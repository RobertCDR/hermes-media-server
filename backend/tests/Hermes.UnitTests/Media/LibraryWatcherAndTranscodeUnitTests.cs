using FluentAssertions;
using Hermes.Domain.Enums;
using Hermes.Infrastructure.Media;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Hermes.UnitTests.Media;

public class LibraryWatcherAndTranscodeUnitTests
{
    [Fact]
    public void ShouldTriggerScan_FiltersUnsupportedExtensionsTempFilesAndHiddenItems()
    {
        LibraryWatcherService.ShouldTriggerScan(LibraryMediaType.Movies, "/media/movies/Dune.mkv").Should().BeTrue();
        LibraryWatcherService.ShouldTriggerScan(LibraryMediaType.Movies, "/media/movies/Dune.srt").Should().BeTrue();
        LibraryWatcherService.ShouldTriggerScan(LibraryMediaType.Movies, "/media/movies/Dune.mkv.part").Should().BeFalse();
        LibraryWatcherService.ShouldTriggerScan(LibraryMediaType.Movies, "/media/movies/Dune.tmp").Should().BeFalse();
        LibraryWatcherService.ShouldTriggerScan(LibraryMediaType.Movies, "/media/movies/.DS_Store").Should().BeFalse();
        LibraryWatcherService.ShouldTriggerScan(LibraryMediaType.Movies, "/media/movies/poster.jpg").Should().BeFalse();

        LibraryWatcherService.ShouldTriggerScan(LibraryMediaType.Series, "/media/tv/Show/Season 01").Should().BeTrue();
        LibraryWatcherService.ShouldTriggerScan(LibraryMediaType.Music, "/media/music/Album/01 - Track.flac").Should().BeTrue();
        LibraryWatcherService.ShouldTriggerScan(LibraryMediaType.Music, "/media/music/Album/video.mkv").Should().BeFalse();
    }

    [Fact]
    public async Task LibraryWatcherService_SyncsDirectories_AndDebouncesBurstEventsIntoSingleChannelWrite()
    {
        var watchedDir = Path.Combine(Path.GetTempPath(), $"hermes-watch-{Guid.NewGuid():N}");
        Directory.CreateDirectory(watchedDir);

        try
        {
            var services = new ServiceCollection();
            await using var provider = services.BuildServiceProvider();
            var scopeFactory = provider.GetRequiredService<IServiceScopeFactory>();
            var channel = new LibraryScanChannel();

            using var watcher = new LibraryWatcherService(
                scopeFactory,
                channel,
                NullLogger<LibraryWatcherService>.Instance,
                debounceDelay: TimeSpan.FromMilliseconds(60),
                syncInterval: TimeSpan.FromMinutes(5));

            var libId = Guid.NewGuid();
            var missingDir = Path.Combine(watchedDir, "does-not-exist");

            watcher.SyncWatchers([
                new LibraryWatcherService.WatchedRootSpec(libId, LibraryMediaType.Movies, watchedDir),
                new LibraryWatcherService.WatchedRootSpec(Guid.NewGuid(), LibraryMediaType.Music, missingDir)
            ]);

            watcher.ActiveWatchedLibraryIds.Should().ContainSingle(id => id == libId);

            // Rapid bursts collapse into a single enqueued scan after debounce.
            watcher.ScheduleDebouncedScan(libId);
            watcher.ScheduleDebouncedScan(libId);
            watcher.ScheduleDebouncedScan(libId);

            using var readCts = new CancellationTokenSource(TimeSpan.FromSeconds(3));
            await using var enumerator = channel.ReadAllAsync(readCts.Token).GetAsyncEnumerator(readCts.Token);
            (await enumerator.MoveNextAsync()).Should().BeTrue();
            enumerator.Current.Should().Be(libId);

            await Task.Delay(120, readCts.Token);
            watcher.SyncWatchers([]);
            watcher.ActiveWatchedLibraryIds.Should().BeEmpty();
        }
        finally
        {
            if (Directory.Exists(watchedDir))
            {
                Directory.Delete(watchedDir, recursive: true);
            }
        }
    }

    [Fact]
    public void BuildVideoHlsArguments_ConfiguresExpectedHardwareAccelerationFlags()
    {
        var noneArgs = FfmpegTranscodeSessionManager.BuildVideoHlsArguments(
            "movie.mkv", VideoQualityPreset.P720, 1, 0, "/tmp/seg", "/tmp/seg/index.m3u8", HardwareAccelerationMode.None);
        noneArgs.Should().NotContain("-hwaccel");
        noneArgs.Should().Contain("libx264");

        var autoArgs = FfmpegTranscodeSessionManager.BuildVideoHlsArguments(
            "movie.mkv", VideoQualityPreset.P720, 1, 30, "/tmp/seg", "/tmp/seg/index.m3u8", HardwareAccelerationMode.Auto);
        autoArgs.Should().ContainInOrder("-hwaccel", "auto");
        autoArgs.Should().ContainInOrder("-ss", "30");
        autoArgs.Should().Contain("libx264");

        var nvencArgs = FfmpegTranscodeSessionManager.BuildVideoHlsArguments(
            "movie.mkv", VideoQualityPreset.P1080, 1, 0, "/tmp/seg", "/tmp/seg/index.m3u8", HardwareAccelerationMode.Nvenc);
        nvencArgs.Should().ContainInOrder("-hwaccel", "cuda");
        nvencArgs.Should().Contain("h264_nvenc");

        var vaapiArgs = FfmpegTranscodeSessionManager.BuildVideoHlsArguments(
            "movie.mkv", VideoQualityPreset.P480, 1, 0, "/tmp/seg", "/tmp/seg/index.m3u8", HardwareAccelerationMode.Vaapi);
        vaapiArgs.Should().ContainInOrder("-hwaccel", "vaapi");
        vaapiArgs.Should().Contain("h264_vaapi");

        var qsvArgs = FfmpegTranscodeSessionManager.BuildVideoHlsArguments(
            "movie.mkv", VideoQualityPreset.P720, 1, 0, "/tmp/seg", "/tmp/seg/index.m3u8", HardwareAccelerationMode.Qsv);
        qsvArgs.Should().ContainInOrder("-hwaccel", "qsv");
        qsvArgs.Should().Contain("h264_qsv");

        var vtArgs = FfmpegTranscodeSessionManager.BuildVideoHlsArguments(
            "movie.mkv", VideoQualityPreset.P720, 1, 0, "/tmp/seg", "/tmp/seg/index.m3u8", HardwareAccelerationMode.VideoToolbox);
        vtArgs.Should().ContainInOrder("-hwaccel", "videotoolbox");
        vtArgs.Should().Contain("h264_videotoolbox");
    }

    [Fact]
    public async Task TryTranscodeAudioToMp3_RejectsWhenZeroAudioSlotsAllowed()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"hermes-aud-slot-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        var fakeAudio = Path.Combine(tempDir, "song.flac");
        await File.WriteAllBytesAsync(fakeAudio, [0x66, 0x4C, 0x61, 0x43]);

        try
        {
            await using var manager = new FfmpegTranscodeSessionManager(tempDir);
            var result = await manager.TryTranscodeAudioToMp3Async(
                fakeAudio,
                160_000,
                CancellationToken.None,
                maxConcurrentAudioSlots: 0);
            result.Should().BeNull();
        }
        finally
        {
            if (Directory.Exists(tempDir))
            {
                Directory.Delete(tempDir, recursive: true);
            }
        }
    }

    [Fact]
    public async Task TryStartVideoHlsSessionAsync_ReusesIdenticalSession_AndEvictsPriorUserSessionOnQualityChange()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"hermes-hls-evict-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        var fakeVideo = Path.Combine(tempDir, "movie.mkv");
        await File.WriteAllBytesAsync(fakeVideo, [0x1A, 0x45, 0xDF, 0xA3]);

        try
        {
            await using var manager = new FfmpegTranscodeSessionManager(
                tempDir,
                (_, _, _, _, segmentDir, playlistPath, _) =>
                {
                    File.WriteAllText(
                        Path.Combine(segmentDir, "seg_0000.ts"),
                        "ts");
                    File.WriteAllText(
                        playlistPath,
                        "#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:2\n#EXTINF:2.0,\nseg_0000.ts\n");
                    return null;
                });
            var userId = Guid.NewGuid();
            var sourceId = Guid.NewGuid();

            var first = await manager.TryStartVideoHlsSessionAsync(
                userId,
                sourceId,
                fakeVideo,
                VideoQualityPreset.P720,
                audioStreamIndex: 1,
                startSeconds: 0,
                maxConcurrentSlots: 1,
                CancellationToken.None,
                clientSession: "player-tab-1");
            first.Should().NotBeNull();

            // Double probe with exact same parameters reuses existing lease cleanly without exhausting slots.
            var reused = await manager.TryStartVideoHlsSessionAsync(
                userId,
                sourceId,
                fakeVideo,
                VideoQualityPreset.P720,
                audioStreamIndex: 1,
                startSeconds: 0,
                maxConcurrentSlots: 1,
                CancellationToken.None,
                clientSession: "player-tab-1");
            reused.Should().NotBeNull();
            reused!.SessionId.Should().Be(first!.SessionId);

            // Switching quality for same player clientSession evicts the previous slot even when maxConcurrentSlots is 1.
            var switched = await manager.TryStartVideoHlsSessionAsync(
                userId,
                sourceId,
                fakeVideo,
                VideoQualityPreset.P480,
                audioStreamIndex: 1,
                startSeconds: 12,
                maxConcurrentSlots: 1,
                CancellationToken.None,
                clientSession: "player-tab-1");
            switched.Should().NotBeNull();
            switched!.SessionId.Should().NotBe(first.SessionId);
            manager.GetActiveSessions().Should().ContainSingle(s => s.SessionId == switched.SessionId);

            await manager.StopClientSessionsAsync(userId, "player-tab-1", CancellationToken.None);
            manager.GetActiveSessions().Should().BeEmpty();
        }
        finally
        {
            if (Directory.Exists(tempDir))
            {
                Directory.Delete(tempDir, recursive: true);
            }
        }
    }

    [Fact]
    public async Task LibraryScanWorker_SurvivesThrowingScan_AndContinuesProcessingNextRoot()
    {
        var channel = new LibraryScanChannel();
        var secondProcessed = new TaskCompletionSource<Guid>(TaskCreationOptions.RunContinuationsAsynchronously);
        var scopeFactory = new ThrowingThenSignalingScopeFactory(secondProcessed);
        using var worker = new LibraryScanWorker(channel, scopeFactory, NullLogger<LibraryScanWorker>.Instance);

        var root1 = Guid.NewGuid();
        var root2 = Guid.NewGuid();
        await channel.EnqueueScanAsync(root1, CancellationToken.None);
        await channel.EnqueueScanAsync(root2, CancellationToken.None);

        await worker.StartAsync(CancellationToken.None);
        var completed = await Task.WhenAny(secondProcessed.Task, Task.Delay(TimeSpan.FromSeconds(5)));
        completed.Should().Be(secondProcessed.Task);
        await worker.StopAsync(CancellationToken.None);
    }

    [Fact]
    public async Task LibraryWatcherService_ConcurrentBurstAndDispose_DoesNotThrow()
    {
        var services = new ServiceCollection();
        await using var provider = services.BuildServiceProvider();
        var scopeFactory = provider.GetRequiredService<IServiceScopeFactory>();
        var channel = new LibraryScanChannel();
        var watcher = new LibraryWatcherService(
            scopeFactory,
            channel,
            NullLogger<LibraryWatcherService>.Instance,
            debounceDelay: TimeSpan.FromMilliseconds(15),
            syncInterval: TimeSpan.FromMinutes(5));

        var libId = Guid.NewGuid();
        var scheduleTasks = Enumerable.Range(0, 20).Select(_ => Task.Run(async () =>
        {
            for (var i = 0; i < 15; i++)
            {
                watcher.ScheduleDebouncedScan(libId);
                await Task.Delay(2);
            }
        }));

        await Task.Delay(20);
        watcher.Dispose();
        await Task.WhenAll(scheduleTasks);
    }

    [Fact]
    public void LibraryScannerService_ShouldIgnorePath_DoesNotIgnoreTrailerTitle_ButIgnoresExtrasAndTrailerSuffix()
    {
        var root = Path.Combine(Path.GetTempPath(), "hermes-ignore-test");

        LibraryScannerService.ShouldIgnorePath(
            root,
            Path.Combine(root, "Trailer Park Boys (2001)", "Season 01", "S01E01.mkv")).Should().BeFalse();
        LibraryScannerService.ShouldIgnorePath(
            root,
            Path.Combine(root, "The Sampler Movie (2020)", "The Sampler Movie (2020) - 1080p.mkv")).Should().BeFalse();

        LibraryScannerService.ShouldIgnorePath(
            root,
            Path.Combine(root, "Dune (2021)", "Extras", "trailer.mkv")).Should().BeTrue();
        LibraryScannerService.ShouldIgnorePath(
            root,
            Path.Combine(root, "Dune (2021)", "Dune (2021)-trailer.mkv")).Should().BeTrue();
        LibraryScannerService.ShouldIgnorePath(
            root,
            Path.Combine(root, "Dune (2021)", "sample.mkv")).Should().BeTrue();
    }

    private sealed class ThrowingThenSignalingScopeFactory(TaskCompletionSource<Guid> secondProcessed) : IServiceScopeFactory
    {
        private int _calls;

        public IServiceScope CreateScope()
        {
            var callNumber = Interlocked.Increment(ref _calls);
            if (callNumber == 1)
            {
                throw new InvalidOperationException("Simulated library scan crash.");
            }

            secondProcessed.TrySetResult(Guid.NewGuid());
            throw new InvalidOperationException("Stop before resolving scoped DbContext in unit test.");
        }
    }
}
