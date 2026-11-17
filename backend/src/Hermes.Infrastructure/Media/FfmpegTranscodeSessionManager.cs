using System.Diagnostics;
using System.Globalization;
using System.Text;
using Hermes.Domain.Enums;
using Hermes.Domain.Ports;

namespace Hermes.Infrastructure.Media;

public sealed class FfmpegTranscodeSessionManager : ITranscodeSessionManager, IAsyncDisposable, IDisposable
{
    private readonly string _transcodeRoot;
    private readonly Lock _gate = new();
    private readonly Dictionary<Guid, ActiveSession> _sessions = [];
    private int _activeAudioTranscodes;

    public FfmpegTranscodeSessionManager(string transcodeRootDirectory)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(transcodeRootDirectory);
        _transcodeRoot = Path.GetFullPath(transcodeRootDirectory);
    }

    public async Task<TranscodeSessionLease?> TryStartVideoHlsSessionAsync(
        Guid userId,
        Guid mediaSourceId,
        string sourceFilePath,
        VideoQualityPreset quality,
        int audioStreamIndex,
        long startSeconds,
        int maxConcurrentSlots,
        CancellationToken cancellationToken,
        HardwareAccelerationMode hardwareAcceleration = HardwareAccelerationMode.None)
    {
        if (maxConcurrentSlots <= 0 || !File.Exists(sourceFilePath))
        {
            return null;
        }

        var sessionId = Guid.NewGuid();
        var segmentDir = Path.Combine(_transcodeRoot, sessionId.ToString("N"));
        var playlistPath = Path.Combine(segmentDir, "index.m3u8");

        lock (_gate)
        {
            if (_sessions.Count >= maxConcurrentSlots)
            {
                return null;
            }

            _sessions[sessionId] = new ActiveSession(
                sessionId,
                userId,
                mediaSourceId,
                segmentDir,
                quality.ToString(),
                DateTimeOffset.UtcNow,
                null);
        }

        try
        {
            Directory.CreateDirectory(segmentDir);
            var process = TryLaunchHlsFfmpeg(sourceFilePath, quality, audioStreamIndex, startSeconds, segmentDir, playlistPath, hardwareAcceleration);

            lock (_gate)
            {
                if (_sessions.TryGetValue(sessionId, out var current))
                {
                    _sessions[sessionId] = current with { Process = process };
                }
            }

            for (var i = 0; i < 10 && !File.Exists(playlistPath); i++)
            {
                if (process is null || process.HasExited)
                {
                    break;
                }

                await Task.Delay(35, cancellationToken);
            }

            if (!File.Exists(playlistPath))
            {
                await File.WriteAllTextAsync(
                    playlistPath,
                    "#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:4\n#EXT-X-MEDIA-SEQUENCE:0\n#EXT-X-ENDLIST\n",
                    Encoding.UTF8,
                    cancellationToken);
            }

            return new TranscodeSessionLease(sessionId, playlistPath, segmentDir);
        }
        catch
        {
            await StopSessionAsync(sessionId, CancellationToken.None);
            throw;
        }
    }

    public Task StopSessionAsync(Guid sessionId, CancellationToken cancellationToken)
    {
        ActiveSession? removed;
        lock (_gate)
        {
            _sessions.Remove(sessionId, out removed);
        }

        if (removed is not null)
        {
            CleanupSessionResources(removed);
        }

        return Task.CompletedTask;
    }

    public string? ResolveHlsAssetPath(Guid sessionId, string fileName)
    {
        if (string.IsNullOrWhiteSpace(fileName) || Path.GetFileName(fileName) != fileName)
        {
            return null;
        }

        var ext = Path.GetExtension(fileName);
        if (!string.Equals(ext, ".m3u8", StringComparison.OrdinalIgnoreCase) &&
            !string.Equals(ext, ".ts", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        string? segmentDir;
        lock (_gate)
        {
            segmentDir = _sessions.TryGetValue(sessionId, out var session) ? session.SegmentDirectory : null;
        }

        if (segmentDir is null)
        {
            return null;
        }

        var path = Path.Combine(segmentDir, fileName);
        return File.Exists(path) ? path : null;
    }

    public async Task<byte[]?> TryTranscodeAudioToMp3Async(
        string sourceFilePath,
        long targetBitrateBps,
        CancellationToken cancellationToken,
        int maxConcurrentAudioSlots = 4)
    {
        if (maxConcurrentAudioSlots <= 0 || !File.Exists(sourceFilePath))
        {
            return null;
        }

        lock (_gate)
        {
            if (_activeAudioTranscodes >= maxConcurrentAudioSlots)
            {
                return null;
            }

            _activeAudioTranscodes++;
        }

        var kbps = Math.Clamp((int)Math.Round(targetBitrateBps / 1000.0), 32, 320);

        try
        {
            using var process = new Process
            {
                StartInfo = new ProcessStartInfo
                {
                    FileName = "ffmpeg",
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false,
                    CreateNoWindow = true
                }
            };

            process.StartInfo.ArgumentList.Add("-v");
            process.StartInfo.ArgumentList.Add("error");
            process.StartInfo.ArgumentList.Add("-i");
            process.StartInfo.ArgumentList.Add(sourceFilePath);
            process.StartInfo.ArgumentList.Add("-vn");
            process.StartInfo.ArgumentList.Add("-c:a");
            process.StartInfo.ArgumentList.Add("libmp3lame");
            process.StartInfo.ArgumentList.Add("-b:a");
            process.StartInfo.ArgumentList.Add($"{kbps}k");
            process.StartInfo.ArgumentList.Add("-f");
            process.StartInfo.ArgumentList.Add("mp3");
            process.StartInfo.ArgumentList.Add("pipe:1");

            if (!process.Start())
            {
                return null;
            }

            await using var memoryStream = new MemoryStream();
            var copyTask = process.StandardOutput.BaseStream.CopyToAsync(memoryStream, cancellationToken);
            var stderrTask = process.StandardError.ReadToEndAsync(cancellationToken);

            await process.WaitForExitAsync(cancellationToken);
            await copyTask;
            _ = await stderrTask;

            return process.ExitCode == 0 && memoryStream.Length > 0 ? memoryStream.ToArray() : null;
        }
        catch (Exception) when (!cancellationToken.IsCancellationRequested)
        {
            return null;
        }
        finally
        {
            lock (_gate)
            {
                _activeAudioTranscodes = Math.Max(0, _activeAudioTranscodes - 1);
            }
        }
    }

    public ValueTask DisposeAsync()
    {
        Dispose();
        return ValueTask.CompletedTask;
    }

    public void Dispose()
    {
        List<ActiveSession> remaining;
        lock (_gate)
        {
            remaining = [.. _sessions.Values];
            _sessions.Clear();
        }

        foreach (var session in remaining)
        {
            CleanupSessionResources(session);
        }
    }

    public static IReadOnlyList<string> BuildVideoHlsArguments(
        string sourceFilePath,
        VideoQualityPreset quality,
        int audioStreamIndex,
        long startSeconds,
        string segmentDir,
        string playlistPath,
        HardwareAccelerationMode hardwareAcceleration)
    {
        var maxHeight = quality switch
        {
            VideoQualityPreset.P480 => 480,
            VideoQualityPreset.P720 => 720,
            _ => 1080
        };

        var args = new List<string>(32)
        {
            "-v",
            "error"
        };

        switch (hardwareAcceleration)
        {
            case HardwareAccelerationMode.Auto:
                args.Add("-hwaccel");
                args.Add("auto");
                break;
            case HardwareAccelerationMode.Nvenc:
                args.Add("-hwaccel");
                args.Add("cuda");
                break;
            case HardwareAccelerationMode.Vaapi:
                args.Add("-hwaccel");
                args.Add("vaapi");
                args.Add("-vaapi_device");
                args.Add("/dev/dri/renderD128");
                break;
            case HardwareAccelerationMode.Qsv:
                args.Add("-hwaccel");
                args.Add("qsv");
                break;
            case HardwareAccelerationMode.VideoToolbox:
                args.Add("-hwaccel");
                args.Add("videotoolbox");
                break;
        }

        if (startSeconds > 0)
        {
            args.Add("-ss");
            args.Add(startSeconds.ToString(CultureInfo.InvariantCulture));
        }

        args.Add("-i");
        args.Add(sourceFilePath);
        args.Add("-map");
        args.Add("0:v:0?");
        args.Add("-map");
        args.Add($"0:{Math.Max(0, audioStreamIndex)}?");

        if (hardwareAcceleration == HardwareAccelerationMode.Vaapi)
        {
            args.Add("-vf");
            args.Add($"format=nv12|vaapi,hwupload,scale_vaapi=-2:min({maxHeight}\\,ih)");
            args.Add("-c:v");
            args.Add("h264_vaapi");
        }
        else
        {
            args.Add("-vf");
            args.Add($"scale=-2:min({maxHeight}\\,ih)");
            switch (hardwareAcceleration)
            {
                case HardwareAccelerationMode.Nvenc:
                    args.Add("-c:v");
                    args.Add("h264_nvenc");
                    args.Add("-preset");
                    args.Add("p4");
                    args.Add("-cq");
                    args.Add("23");
                    break;
                case HardwareAccelerationMode.Qsv:
                    args.Add("-c:v");
                    args.Add("h264_qsv");
                    break;
                case HardwareAccelerationMode.VideoToolbox:
                    args.Add("-c:v");
                    args.Add("h264_videotoolbox");
                    break;
                default:
                    args.Add("-c:v");
                    args.Add("libx264");
                    args.Add("-preset");
                    args.Add("veryfast");
                    args.Add("-crf");
                    args.Add("22");
                    break;
            }
        }

        args.Add("-c:a");
        args.Add("aac");
        args.Add("-b:a");
        args.Add("192k");
        args.Add("-f");
        args.Add("hls");
        args.Add("-hls_time");
        args.Add("4");
        args.Add("-hls_list_size");
        args.Add("0");
        args.Add("-hls_segment_filename");
        args.Add(Path.Combine(segmentDir, "seg_%04d.ts"));
        args.Add(playlistPath);
        return args;
    }

    private static Process? TryLaunchHlsFfmpeg(
        string sourceFilePath,
        VideoQualityPreset quality,
        int audioStreamIndex,
        long startSeconds,
        string segmentDir,
        string playlistPath,
        HardwareAccelerationMode hardwareAcceleration)
    {
        try
        {
            var process = new Process
            {
                StartInfo = new ProcessStartInfo
                {
                    FileName = "ffmpeg",
                    RedirectStandardError = true,
                    RedirectStandardOutput = true,
                    UseShellExecute = false,
                    CreateNoWindow = true
                }
            };

            foreach (var arg in BuildVideoHlsArguments(
                         sourceFilePath,
                         quality,
                         audioStreamIndex,
                         startSeconds,
                         segmentDir,
                         playlistPath,
                         hardwareAcceleration))
            {
                process.StartInfo.ArgumentList.Add(arg);
            }

            if (!process.Start())
            {
                process.Dispose();
                return null;
            }

            return process;
        }
        catch
        {
            return null;
        }
    }

    private static void CleanupSessionResources(ActiveSession session)
    {
        if (session.Process is not null)
        {
            try
            {
                if (!session.Process.HasExited)
                {
                    session.Process.Kill(entireProcessTree: true);
                }
            }
            catch
            {
                // Process may have exited concurrently.
            }
            finally
            {
                session.Process.Dispose();
            }
        }

        if (Directory.Exists(session.SegmentDirectory))
        {
            try
            {
                Directory.Delete(session.SegmentDirectory, recursive: true);
            }
            catch
            {
                // Best-effort cleanup of temp transcode directory.
            }
        }
    }

    public IReadOnlyList<ActiveTranscodeSessionInfo> GetActiveSessions()
    {
        lock (_gate)
        {
            return _sessions.Values
                .Select(s => new ActiveTranscodeSessionInfo(
                    s.SessionId,
                    s.UserId,
                    s.MediaSourceId,
                    s.QualityLabel,
                    s.StartedAtUtc))
                .ToList();
        }
    }

    private sealed record ActiveSession(
        Guid SessionId,
        Guid UserId,
        Guid MediaSourceId,
        string SegmentDirectory,
        string QualityLabel,
        DateTimeOffset StartedAtUtc,
        Process? Process);
}
