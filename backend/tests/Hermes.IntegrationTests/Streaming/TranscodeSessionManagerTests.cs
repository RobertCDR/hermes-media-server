using FluentAssertions;
using Hermes.Domain.Enums;
using Hermes.Infrastructure.Media;
using Xunit;

namespace Hermes.IntegrationTests.Streaming;

public class TranscodeSessionManagerTests
{
    [Fact]
    public async Task TryStartVideoHlsSession_EnforcesMaxConcurrentSlots_AndCleansUpTempDirectoryOnStop()
    {
        var transcodeRoot = Path.Combine(Path.GetTempPath(), $"hermes-slots-{Guid.NewGuid():N}");
        var dummyMediaFile = Path.Combine(transcodeRoot, "source.mkv");
        Directory.CreateDirectory(transcodeRoot);
        await File.WriteAllBytesAsync(dummyMediaFile, [0x1A, 0x45, 0xDF, 0xA3]);

        await using var manager = new FfmpegTranscodeSessionManager(transcodeRoot);
        try
        {
            var userId = Guid.NewGuid();
            var sourceId = Guid.NewGuid();

            var lease1 = await manager.TryStartVideoHlsSessionAsync(
                userId, sourceId, dummyMediaFile, VideoQualityPreset.P720, 1, 0, maxConcurrentSlots: 2, CancellationToken.None);
            var lease2 = await manager.TryStartVideoHlsSessionAsync(
                userId, sourceId, dummyMediaFile, VideoQualityPreset.P480, 1, 0, maxConcurrentSlots: 2, CancellationToken.None);
            var lease3 = await manager.TryStartVideoHlsSessionAsync(
                userId, sourceId, dummyMediaFile, VideoQualityPreset.P1080, 1, 0, maxConcurrentSlots: 2, CancellationToken.None);

            lease1.Should().NotBeNull();
            lease2.Should().NotBeNull();
            lease3.Should().BeNull();
            Directory.Exists(lease1!.SegmentDirectory).Should().BeTrue();
            File.Exists(lease1.PlaylistFilePath).Should().BeTrue();

            await manager.StopSessionAsync(lease1.SessionId, CancellationToken.None);
            Directory.Exists(lease1.SegmentDirectory).Should().BeFalse();

            var lease4 = await manager.TryStartVideoHlsSessionAsync(
                userId, sourceId, dummyMediaFile, VideoQualityPreset.P1080, 1, 0, maxConcurrentSlots: 2, CancellationToken.None);
            lease4.Should().NotBeNull();
        }
        finally
        {
            if (Directory.Exists(transcodeRoot))
            {
                Directory.Delete(transcodeRoot, recursive: true);
            }
        }
    }
}
