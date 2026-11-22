using System.Collections.Concurrent;
using System.Diagnostics;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using Hermes.Domain.Enums;
using Hermes.Domain.Ports;

namespace Hermes.Infrastructure.Media;

public sealed class FfmpegTranscodeSessionManager : ITranscodeSessionManager, IAsyncDisposable, IDisposable
{
    private static readonly TimeSpan IdleSessionTimeout = TimeSpan.FromMinutes(15);
    private static readonly TimeSpan AudioTranscodeTimeout = TimeSpan.FromMinutes(2);
    private const long MaxAudioCacheBytes = 512L * 1024 * 1024;

    internal delegate Process? HlsProcessLauncher(
        string sourceFilePath,
        VideoQualityPreset quality,
        int audioStreamIndex,
        long startSeconds,
        string segmentDir,
        string playlistPath,
        HardwareAccelerationMode hardwareAcceleration);

    private readonly string _transcodeRoot;
    private readonly string _audioCacheDirectory;
    private readonly HlsProcessLauncher _launchHlsProcess;
    private readonly bool _usesCustomLauncher;
    private readonly Lock _gate = new();
    private readonly Dictionary<Guid, ActiveSession> _sessions = [];
    private readonly ConcurrentDictionary<string, SemaphoreSlim> _audioCacheLocks = new(StringComparer.Ordinal);
    private int _activeAudioTranscodes;

    public FfmpegTranscodeSessionManager(string transcodeRootDirectory)
        : this(transcodeRootDirectory, null)
    {
    }

    internal FfmpegTranscodeSessionManager(
        string transcodeRootDirectory,
        HlsProcessLauncher? launchHlsProcess)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(transcodeRootDirectory);
        _transcodeRoot = Path.GetFullPath(transcodeRootDirectory);
        _audioCacheDirectory = Path.Combine(_transcodeRoot, "audio-cache");
        _usesCustomLauncher = launchHlsProcess is not null;
        _launchHlsProcess = launchHlsProcess ?? TryLaunchHlsFfmpeg;
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
        HardwareAccelerationMode hardwareAcceleration = HardwareAccelerationMode.None,
        string? clientSession = null)
    {
        if (maxConcurrentSlots <= 0 || !File.Exists(sourceFilePath))
        {
            return null;
        }

        var normalizedClientSession = string.IsNullOrWhiteSpace(clientSession) ? null : clientSession.Trim();
        var sessionId = Guid.NewGuid();
        var segmentDir = Path.Combine(_transcodeRoot, sessionId.ToString("N"));
        var playlistPath = Path.Combine(segmentDir, "index.m3u8");
        var now = DateTimeOffset.UtcNow;
        var evictedSessions = new List<ActiveSession>();

        lock (_gate)
        {
            foreach (var existing in _sessions.Values)
            {
                if (existing.UserId == userId &&
                    existing.MediaSourceId == mediaSourceId &&
                    existing.Quality == quality &&
                    existing.AudioStreamIndex == audioStreamIndex &&
                    existing.StartSeconds == startSeconds &&
                    string.Equals(existing.ClientSession, normalizedClientSession, StringComparison.Ordinal) &&
                    IsReusableSession(existing, now))
                {
                    var existingPlaylist = Path.Combine(existing.SegmentDirectory, "index.m3u8");
                    if (File.Exists(existingPlaylist))
                    {
                        _sessions[existing.SessionId] = existing with { LastAccessedUtc = now };
                        return new TranscodeSessionLease(
                            existing.SessionId,
                            existingPlaylist,
                            existing.SegmentDirectory);
                    }
                }
            }

            foreach (var existing in _sessions.Values)
            {
                var sameClientPrior = normalizedClientSession is not null &&
                                      existing.UserId == userId &&
                                      string.Equals(existing.ClientSession, normalizedClientSession, StringComparison.Ordinal);
                var staleExited = (existing.Process is null || HasExitedSafe(existing.Process)) &&
                                  (now - existing.LastAccessedUtc) > TimeSpan.FromMinutes(2);
                var staleIdle = (now - existing.LastAccessedUtc) > IdleSessionTimeout;
                if (sameClientPrior || staleExited || staleIdle)
                {
                    evictedSessions.Add(existing);
                }
            }

            foreach (var evicted in evictedSessions)
            {
                _sessions.Remove(evicted.SessionId);
            }

            if (_sessions.Count >= maxConcurrentSlots)
            {
                goto SlotsExhausted;
            }

            _sessions[sessionId] = new ActiveSession(
                sessionId,
                userId,
                mediaSourceId,
                quality,
                audioStreamIndex,
                startSeconds,
                normalizedClientSession,
                segmentDir,
                quality.ToString(),
                now,
                now,
                null);
        }

        CleanupSessions(evictedSessions);
        goto LaunchSession;

        SlotsExhausted:
        CleanupSessions(evictedSessions);
        return null;

        LaunchSession:

        try
        {
            Directory.CreateDirectory(segmentDir);
            var process = _launchHlsProcess(sourceFilePath, quality, audioStreamIndex, startSeconds, segmentDir, playlistPath, hardwareAcceleration);

            var stoppedConcurrently = false;
            lock (_gate)
            {
                if (_sessions.TryGetValue(sessionId, out var current))
                {
                    _sessions[sessionId] = current with { Process = process };
                }
                else
                {
                    stoppedConcurrently = true;
                }
            }

            if (stoppedConcurrently)
            {
                KillAndDisposeProcess(process);
                return null;
            }

            for (var i = 0; i < 80; i++)
            {
                if (File.Exists(playlistPath) && Directory.EnumerateFiles(segmentDir, "*.ts").Any())
                {
                    break;
                }

                if (process is null || process.HasExited)
                {
                    break;
                }

                await Task.Delay(100, cancellationToken);
            }

            if ((process is null || process.HasExited) &&
                !File.Exists(playlistPath) &&
                hardwareAcceleration != HardwareAccelerationMode.None)
            {
                KillAndDisposeProcess(process);
                process = _launchHlsProcess(
                    sourceFilePath,
                    quality,
                    audioStreamIndex,
                    startSeconds,
                    segmentDir,
                    playlistPath,
                    HardwareAccelerationMode.None);

                stoppedConcurrently = false;
                lock (_gate)
                {
                    if (_sessions.TryGetValue(sessionId, out var current))
                    {
                        _sessions[sessionId] = current with { Process = process };
                    }
                    else
                    {
                        stoppedConcurrently = true;
                    }
                }

                if (stoppedConcurrently)
                {
                    KillAndDisposeProcess(process);
                    return null;
                }

                for (var i = 0; i < 80; i++)
                {
                    if (File.Exists(playlistPath) && Directory.EnumerateFiles(segmentDir, "*.ts").Any())
                    {
                        break;
                    }

                    if (process is null || process.HasExited)
                    {
                        break;
                    }

                    await Task.Delay(100, cancellationToken);
                }
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

    public Task<bool> TryStopUserSessionAsync(
        Guid sessionId,
        Guid userId,
        Guid mediaSourceId,
        CancellationToken cancellationToken)
    {
        ActiveSession? removed = null;
        lock (_gate)
        {
            if (_sessions.TryGetValue(sessionId, out var existing) &&
                existing.UserId == userId &&
                existing.MediaSourceId == mediaSourceId)
            {
                _sessions.Remove(sessionId, out removed);
            }
        }

        if (removed is null)
        {
            return Task.FromResult(false);
        }

        CleanupSessionResources(removed);
        return Task.FromResult(true);
    }

    public Task StopSessionsForMediaSourcesAsync(IReadOnlyCollection<Guid> mediaSourceIds, CancellationToken cancellationToken)
    {
        if (mediaSourceIds.Count == 0)
        {
            return Task.CompletedTask;
        }

        var idSet = mediaSourceIds.ToHashSet();
        List<ActiveSession> toStop;
        lock (_gate)
        {
            toStop = _sessions.Values.Where(s => idSet.Contains(s.MediaSourceId)).ToList();
            foreach (var session in toStop)
            {
                _sessions.Remove(session.SessionId);
            }
        }

        CleanupSessions(toStop);
        return Task.CompletedTask;
    }

    public Task StopClientSessionsAsync(Guid userId, string clientSession, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(clientSession))
        {
            return Task.CompletedTask;
        }

        var normalized = clientSession.Trim();
        List<ActiveSession> toStop;
        lock (_gate)
        {
            toStop = _sessions.Values
                .Where(s => s.UserId == userId && string.Equals(s.ClientSession, normalized, StringComparison.Ordinal))
                .ToList();
            foreach (var session in toStop)
            {
                _sessions.Remove(session.SessionId);
            }
        }

        CleanupSessions(toStop);

        return Task.CompletedTask;
    }

    public string? ResolveHlsAssetPath(Guid sessionId, string fileName) =>
        ResolveHlsAssetPathInternal(sessionId, fileName, expectedUserId: null, expectedMediaSourceId: null);

    public string? ResolveHlsAssetPath(Guid sessionId, string fileName, Guid expectedUserId, Guid expectedMediaSourceId) =>
        ResolveHlsAssetPathInternal(sessionId, fileName, expectedUserId, expectedMediaSourceId);

    private string? ResolveHlsAssetPathInternal(
        Guid sessionId,
        string fileName,
        Guid? expectedUserId,
        Guid? expectedMediaSourceId)
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

        string? segmentDir = null;
        lock (_gate)
        {
            if (_sessions.TryGetValue(sessionId, out var session))
            {
                if (expectedUserId is Guid uId && session.UserId != uId)
                {
                    return null;
                }

                if (expectedMediaSourceId is Guid msId && session.MediaSourceId != msId)
                {
                    return null;
                }

                _sessions[sessionId] = session with { LastAccessedUtc = DateTimeOffset.UtcNow };
                segmentDir = session.SegmentDirectory;
            }
        }

        if (segmentDir is null)
        {
            return null;
        }

        var path = Path.Combine(segmentDir, fileName);
        return File.Exists(path) ? path : null;
    }

    public async Task<string?> TryTranscodeAudioToMp3FileAsync(
        string sourceFilePath,
        long targetBitrateBps,
        CancellationToken cancellationToken,
        int maxConcurrentAudioSlots = 4)
    {
        if (!File.Exists(sourceFilePath))
        {
            return null;
        }

        var kbps = Math.Clamp((int)Math.Round(targetBitrateBps / 1000.0), 32, 320);
        var fileInfo = new FileInfo(sourceFilePath);
        var keyInput = $"{Path.GetFullPath(sourceFilePath)}|{fileInfo.LastWriteTimeUtc.Ticks}|{fileInfo.Length}|{kbps}";
        var cacheKey = Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(keyInput)));
        var cachePath = Path.Combine(_audioCacheDirectory, $"{cacheKey}.mp3");

        if (File.Exists(cachePath))
        {
            TryTouchFileUtc(cachePath);
            return cachePath;
        }

        if (maxConcurrentAudioSlots <= 0)
        {
            return null;
        }

        var keyLock = _audioCacheLocks.GetOrAdd(cacheKey, _ => new SemaphoreSlim(1, 1));
        await keyLock.WaitAsync(cancellationToken);
        try
        {
            if (File.Exists(cachePath))
            {
                TryTouchFileUtc(cachePath);
                return cachePath;
            }

            lock (_gate)
            {
                if (_activeAudioTranscodes >= maxConcurrentAudioSlots)
                {
                    return null;
                }

                _activeAudioTranscodes++;
            }

            try
            {
                Directory.CreateDirectory(_audioCacheDirectory);
                var tempPath = Path.Combine(_audioCacheDirectory, $"{cacheKey}.{Guid.NewGuid():N}.tmp");

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
                    process.StartInfo.ArgumentList.Add("-y");
                    process.StartInfo.ArgumentList.Add(tempPath);

                    if (!process.Start())
                    {
                        return null;
                    }

                    using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
                    timeoutCts.CancelAfter(AudioTranscodeTimeout);

                    try
                    {
                        var stdoutDrain = process.StandardOutput.BaseStream.CopyToAsync(Stream.Null, timeoutCts.Token);
                        var stderrDrain = process.StandardError.BaseStream.CopyToAsync(Stream.Null, timeoutCts.Token);

                        await process.WaitForExitAsync(timeoutCts.Token);
                        await Task.WhenAll(stdoutDrain, stderrDrain);

                        if (process.ExitCode == 0 && File.Exists(tempPath) && new FileInfo(tempPath).Length > 0)
                        {
                            File.Move(tempPath, cachePath, overwrite: true);
                            PruneAudioCacheIfNeeded();
                            return cachePath;
                        }

                        TryDeleteFile(tempPath);
                        return null;
                    }
                    finally
                    {
                        if (!HasExitedSafe(process))
                        {
                            try
                            {
                                process.Kill(entireProcessTree: true);
                            }
                            catch
                            {
                                // Process exited concurrently.
                            }
                        }
                    }
                }
                catch (Exception) when (!cancellationToken.IsCancellationRequested)
                {
                    TryDeleteFile(tempPath);
                    return null;
                }
                catch
                {
                    TryDeleteFile(tempPath);
                    throw;
                }
            }
            finally
            {
                lock (_gate)
                {
                    _activeAudioTranscodes = Math.Max(0, _activeAudioTranscodes - 1);
                }
            }
        }
        finally
        {
            keyLock.Release();
        }
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

            using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeoutCts.CancelAfter(AudioTranscodeTimeout);

            try
            {
                await using var memoryStream = new MemoryStream();
                var copyTask = process.StandardOutput.BaseStream.CopyToAsync(memoryStream, timeoutCts.Token);
                var stderrTask = process.StandardError.BaseStream.CopyToAsync(Stream.Null, timeoutCts.Token);

                await process.WaitForExitAsync(timeoutCts.Token);
                await Task.WhenAll(copyTask, stderrTask);

                return process.ExitCode == 0 && memoryStream.Length > 0 ? memoryStream.ToArray() : null;
            }
            finally
            {
                if (!HasExitedSafe(process))
                {
                    try
                    {
                        process.Kill(entireProcessTree: true);
                    }
                    catch
                    {
                        // Process exited concurrently.
                    }
                }
            }
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
            args.Add("-pix_fmt");
            args.Add("yuv420p");
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
                    args.Add("-sc_threshold");
                    args.Add("0");
                    break;
            }
        }

        args.Add("-force_key_frames");
        args.Add("expr:gte(t,n_forced*2)");
        args.Add("-c:a");
        args.Add("aac");
        args.Add("-ac");
        args.Add("2");
        args.Add("-b:a");
        args.Add("192k");
        args.Add("-f");
        args.Add("hls");
        args.Add("-hls_init_time");
        args.Add("2");
        args.Add("-hls_time");
        args.Add("4");
        args.Add("-hls_list_size");
        args.Add("0");
        args.Add("-hls_flags");
        args.Add("temp_file+independent_segments");
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

            _ = Task.Run(async () =>
            {
                try
                {
                    await process.StandardError.BaseStream.CopyToAsync(Stream.Null);
                }
                catch
                {
                    // Process disposed or exited.
                }
            });

            _ = Task.Run(async () =>
            {
                try
                {
                    await process.StandardOutput.BaseStream.CopyToAsync(Stream.Null);
                }
                catch
                {
                    // Process disposed or exited.
                }
            });

            return process;
        }
        catch
        {
            return null;
        }
    }

    private static void CleanupSessions(IEnumerable<ActiveSession> sessions)
    {
        foreach (var session in sessions)
        {
            CleanupSessionResources(session);
        }
    }

    private static void KillAndDisposeProcess(Process? process)
    {
        if (process is null)
        {
            return;
        }

        try
        {
            if (!HasExitedSafe(process))
            {
                process.Kill(entireProcessTree: true);
            }
        }
        catch
        {
            // Process may have exited concurrently.
        }
        finally
        {
            process.Dispose();
        }
    }

    private static void CleanupSessionResources(ActiveSession session)
    {
        KillAndDisposeProcess(session.Process);

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
        var now = DateTimeOffset.UtcNow;
        List<ActiveSession> expired;
        List<ActiveTranscodeSessionInfo> result;

        lock (_gate)
        {
            expired = _sessions.Values
                .Where(s => (now - s.LastAccessedUtc) > IdleSessionTimeout)
                .ToList();
            foreach (var session in expired)
            {
                _sessions.Remove(session.SessionId);
            }

            result = _sessions.Values
                .Select(s => new ActiveTranscodeSessionInfo(
                    s.SessionId,
                    s.UserId,
                    s.MediaSourceId,
                    s.QualityLabel,
                    s.StartedAtUtc))
                .ToList();
        }

        CleanupSessions(expired);
        return result;
    }

    private static bool HasExitedSafe(Process process)
    {
        try
        {
            return process.HasExited;
        }
        catch
        {
            return true;
        }
    }

    private bool IsReusableSession(ActiveSession session, DateTimeOffset now)
    {
        if (!_usesCustomLauncher && session.Process is null)
        {
            return false;
        }

        if (session.Process is not null && !HasExitedSafe(session.Process))
        {
            return true;
        }

        if (session.Process is not null)
        {
            try
            {
                if (session.Process.ExitCode != 0)
                {
                    return false;
                }
            }
            catch
            {
                return false;
            }
        }

        return (now - session.StartedAtUtc) < TimeSpan.FromSeconds(15);
    }

    private void PruneAudioCacheIfNeeded()
    {
        try
        {
            if (!Directory.Exists(_audioCacheDirectory))
            {
                return;
            }

            var files = new DirectoryInfo(_audioCacheDirectory)
                .GetFiles("*.mp3")
                .OrderBy(f => f.LastWriteTimeUtc)
                .ToList();

            var totalBytes = files.Sum(f => f.Length);
            foreach (var file in files)
            {
                if (totalBytes <= MaxAudioCacheBytes)
                {
                    break;
                }

                try
                {
                    var len = file.Length;
                    file.Delete();
                    totalBytes -= len;
                }
                catch
                {
                    // File might currently be streamed by an active HTTP response.
                }
            }
        }
        catch
        {
            // Best-effort cache pruning.
        }
    }

    private static void TryTouchFileUtc(string path)
    {
        try
        {
            File.SetLastWriteTimeUtc(path, DateTime.UtcNow);
        }
        catch
        {
            // Best-effort LRU timestamp refresh.
        }
    }

    private static void TryDeleteFile(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch
        {
            // Best-effort cleanup of incomplete temp audio file.
        }
    }

    private sealed record ActiveSession(
        Guid SessionId,
        Guid UserId,
        Guid MediaSourceId,
        VideoQualityPreset Quality,
        int AudioStreamIndex,
        long StartSeconds,
        string? ClientSession,
        string SegmentDirectory,
        string QualityLabel,
        DateTimeOffset StartedAtUtc,
        DateTimeOffset LastAccessedUtc,
        Process? Process);
}
