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
        CancellationToken cancellationToken)
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

            _sessions[sessionId] = new ActiveSession(sessionId, userId, mediaSourceId, segmentDir, null);
        }

        try
        {
            Directory.CreateDirectory(segmentDir);
            var process = TryLaunchHlsFfmpeg(sourceFilePath, quality, audioStreamIndex, startSeconds, segmentDir, playlistPath);

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
        CancellationToken cancellationToken)
    {
        if (!File.Exists(sourceFilePath))
        {
            return null;
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

    private static Process? TryLaunchHlsFfmpeg(
        string sourceFilePath,
        VideoQualityPreset quality,
        int audioStreamIndex,
        long startSeconds,
        string segmentDir,
        string playlistPath)
    {
        var maxHeight = quality switch
        {
            VideoQualityPreset.P480 => 480,
            VideoQualityPreset.P720 => 720,
            _ => 1080
        };

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

            process.StartInfo.ArgumentList.Add("-v");
            process.StartInfo.ArgumentList.Add("error");
            if (startSeconds > 0)
            {
                process.StartInfo.ArgumentList.Add("-ss");
                process.StartInfo.ArgumentList.Add(startSeconds.ToString(CultureInfo.InvariantCulture));
            }

            process.StartInfo.ArgumentList.Add("-i");
            process.StartInfo.ArgumentList.Add(sourceFilePath);
            process.StartInfo.ArgumentList.Add("-map");
            process.StartInfo.ArgumentList.Add("0:v:0?");
            process.StartInfo.ArgumentList.Add("-map");
            process.StartInfo.ArgumentList.Add($"0:{Math.Max(0, audioStreamIndex)}?");
            process.StartInfo.ArgumentList.Add("-vf");
            process.StartInfo.ArgumentList.Add($"scale=-2:min({maxHeight}\\,ih)");
            process.StartInfo.ArgumentList.Add("-c:v");
            process.StartInfo.ArgumentList.Add("libx264");
            process.StartInfo.ArgumentList.Add("-preset");
            process.StartInfo.ArgumentList.Add("veryfast");
            process.StartInfo.ArgumentList.Add("-crf");
            process.StartInfo.ArgumentList.Add("22");
            process.StartInfo.ArgumentList.Add("-c:a");
            process.StartInfo.ArgumentList.Add("aac");
            process.StartInfo.ArgumentList.Add("-b:a");
            process.StartInfo.ArgumentList.Add("192k");
            process.StartInfo.ArgumentList.Add("-f");
            process.StartInfo.ArgumentList.Add("hls");
            process.StartInfo.ArgumentList.Add("-hls_time");
            process.StartInfo.ArgumentList.Add("4");
            process.StartInfo.ArgumentList.Add("-hls_list_size");
            process.StartInfo.ArgumentList.Add("0");
            process.StartInfo.ArgumentList.Add("-hls_segment_filename");
            process.StartInfo.ArgumentList.Add(Path.Combine(segmentDir, "seg_%04d.ts"));
            process.StartInfo.ArgumentList.Add(playlistPath);

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

    private sealed record ActiveSession(
        Guid SessionId,
        Guid UserId,
        Guid MediaSourceId,
        string SegmentDirectory,
        Process? Process);
}
