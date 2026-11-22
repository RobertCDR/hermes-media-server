using System.Text.Json;
using FluentAssertions;
using Hermes.Domain.Common;
using Hermes.Domain.Entities;
using Hermes.Domain.Enums;
using Xunit;

namespace Hermes.UnitTests.Domain;

public class ParityDomainTests
{
    [Fact]
    public void ArtistCreditParser_ExtractsDeduplicatedCreditsAcrossTagSeparatorsAndFeaturedArtists()
    {
        var credits = ArtistCreditParser.FromPerformerTags(
        [
            "Daft Punk; Pharrell Williams",
            "daft punk",
            "Nile Rodgers feat. Julian Casablancas",
            "AC/DC",
        ]);

        credits.Should().Equal("Daft Punk", "Pharrell Williams", "Nile Rodgers", "Julian Casablancas", "AC/DC");
        ArtistCreditParser.ToDisplayString(credits).Should().Be("Daft Punk, Pharrell Williams, Nile Rodgers, Julian Casablancas, AC/DC");
        ArtistCreditParser.FromPerformerTags(null).Should().BeEmpty();
    }

    [Fact]
    public void ListeningHistoryEntry_ComputesListenThresholdsProportionallyWithBounds()
    {
        ListeningHistoryEntry.GetListenThresholdMs(0).Should().Be(0);
        ListeningHistoryEntry.GetListenThresholdMs(12_000).Should().Be(5_000);
        ListeningHistoryEntry.GetListenThresholdMs(45_000).Should().Be(15_000);
        ListeningHistoryEntry.GetListenThresholdMs(240_000).Should().Be(30_000);

        var entry = new ListeningHistoryEntry(Guid.NewGuid(), Guid.NewGuid(), 42_000, 210_000, "win-1", "Liked Songs", DateTimeOffset.UtcNow);
        entry.PositionMs.Should().Be(42_000);
        entry.ContextLabel.Should().Be("Liked Songs");
    }

    [Fact]
    public void CustomListAndItems_EnforceNonEmptyNamesAndExclusiveTargets()
    {
        var now = DateTimeOffset.UtcNow;
        var list = new CustomList(Guid.NewGuid(), "  Weekend Sci-Fi  ", "Curated epics", now);
        list.Name.Should().Be("Weekend Sci-Fi");

        var movieItem = CustomListItem.ForMovie(list.Id, Guid.NewGuid(), 0, now);
        movieItem.MovieId.Should().NotBeNull();
        movieItem.TvSeriesId.Should().BeNull();

        var seriesItem = CustomListItem.ForSeries(list.Id, Guid.NewGuid(), 1, now);
        seriesItem.TvSeriesId.Should().NotBeNull();
        seriesItem.SetPosition(3);
        seriesItem.Position.Should().Be(3);

        list.UpdateDetails("Modern Classics", null, now.AddMinutes(5));
        list.Name.Should().Be("Modern Classics");
        list.Description.Should().BeNull();
    }

    [Fact]
    public void PlaybackSession_UpdateProgressAndTransferOutput_IncrementVersionAndPreservePosition()
    {
        var now = DateTimeOffset.UtcNow;
        var session = PlaybackSession.CreateForUser(Guid.NewGuid());
        session.StartPlayback("dev-a", "Phone", [Guid.NewGuid()], 0, now);
        var initialVersion = session.Version;

        session.UpdateProgress(45_000, now.AddSeconds(5));
        session.PositionMs.Should().Be(45_000);
        session.Version.Should().Be(initialVersion + 1);

        session.TransferOutput("dev-b", "Windows", now.AddSeconds(6), positionMs: 47_500);
        session.ActiveRendererDeviceId.Should().Be("dev-b");
        session.PositionMs.Should().Be(47_500);
        session.Version.Should().Be(initialVersion + 2);
    }

    [Fact]
    public void PlaybackSession_ApplyRemoteTransport_ReplacesShuffledQueueAtomically_AndClaimsNullRendererOnPlay()
    {
        var now = DateTimeOffset.UtcNow;
        var s1 = Guid.NewGuid();
        var s2 = Guid.NewGuid();
        var s3 = Guid.NewGuid();
        var session = PlaybackSession.CreateForUser(Guid.NewGuid());
        session.StartPlayback("dev-pc", "Windows PC", [s1, s2, s3], 0, now);

        session.ApplyRemoteTransport(
            PlaybackState.Playing,
            currentIndex: 0,
            positionMs: 12_000,
            now.AddSeconds(5),
            shuffle: true,
            queueSongIds: [s2, s3, s1]);

        session.Shuffle.Should().BeTrue();
        session.QueueSongIds.Should().Equal(s2, s3, s1);
        session.CurrentIndex.Should().Be(0);
        session.CurrentSongId.Should().Be(s2);
        session.PositionMs.Should().Be(12_000);
        session.ActiveRendererDeviceId.Should().Be("dev-pc");

        session.HandleDeviceDisconnected("dev-pc", now.AddSeconds(10)).Should().BeTrue();
        session.ActiveRendererDeviceId.Should().BeNull();

        session.ApplyRemoteTransport(
            PlaybackState.Playing,
            currentIndex: null,
            positionMs: null,
            now.AddSeconds(12),
            callerDeviceId: "dev-phone",
            callerDeviceName: "Honor Phone");

        session.ActiveRendererDeviceId.Should().Be("dev-phone");
        session.ActiveRendererDeviceName.Should().Be("Honor Phone");
        session.State.Should().Be(PlaybackState.Playing);
    }

    [Fact]
    public void PlaybackSession_ApplyRemoteTransport_IgnoresNonFiniteVolume_AndValidatesEnums()
    {
        var now = DateTimeOffset.UtcNow;
        var session = PlaybackSession.CreateForUser(Guid.NewGuid());
        session.StartPlayback("dev-pc", "Windows PC", [Guid.NewGuid()], 0, now);

        session.ApplyRemoteTransport(
            PlaybackState.Playing,
            currentIndex: 0,
            positionMs: 1_000,
            now.AddSeconds(1),
            volume: 0.65);

        session.ApplyRemoteTransport(
            PlaybackState.Playing,
            currentIndex: 0,
            positionMs: 2_000,
            now.AddSeconds(2),
            volume: double.NaN);

        session.ApplyRemoteTransport(
            PlaybackState.Playing,
            currentIndex: 0,
            positionMs: 3_000,
            now.AddSeconds(3),
            volume: double.PositiveInfinity);

        session.Volume.Should().Be(0.65);
        var serialize = () => JsonSerializer.Serialize(session);
        serialize.Should().NotThrow();

        var badState = () => session.ApplyRemoteTransport((PlaybackState)99, 0, 0, now.AddSeconds(4));
        badState.Should().Throw<ArgumentOutOfRangeException>();

        var badRepeat = () => session.ApplyRemoteTransport(PlaybackState.Playing, 0, 0, now.AddSeconds(4), repeatMode: (RepeatMode)99);
        badRepeat.Should().Throw<ArgumentOutOfRangeException>();
    }

    [Fact]
    public void PlaybackSession_RemoveSongsFromQueue_PreservesPausedState_AndStopsWhenEmptied()
    {
        var now = DateTimeOffset.UtcNow;
        var s1 = Guid.NewGuid();
        var s2 = Guid.NewGuid();
        var s3 = Guid.NewGuid();
        var session = PlaybackSession.CreateForUser(Guid.NewGuid());
        session.StartPlayback("dev-pc", "Windows PC", [s1, s2, s3], 1, now);
        session.ApplyRemoteTransport(PlaybackState.Paused, 1, 15_000, now.AddSeconds(2));

        // Remove first song while paused: keeps s2 active & preserves Paused state + PositionMs.
        session.RemoveSongsFromQueue(new HashSet<Guid> { s1 }, now.AddSeconds(3)).Should().BeTrue();
        session.State.Should().Be(PlaybackState.Paused);
        session.QueueSongIds.Should().Equal(s2, s3);
        session.CurrentIndex.Should().Be(0);
        session.CurrentSongId.Should().Be(s2);
        session.PositionMs.Should().Be(15_000);

        // Remove current song while paused: falls back to remaining track, stays Paused (never forces Playing).
        session.RemoveSongsFromQueue(new HashSet<Guid> { s2 }, now.AddSeconds(4)).Should().BeTrue();
        session.State.Should().Be(PlaybackState.Paused);
        session.QueueSongIds.Should().Equal(s3);
        session.CurrentSongId.Should().Be(s3);
        session.PositionMs.Should().Be(0);

        // Removing final song transitions cleanly to Stopped.
        session.RemoveSongsFromQueue(new HashSet<Guid> { s3 }, now.AddSeconds(5)).Should().BeTrue();
        session.State.Should().Be(PlaybackState.Stopped);
        session.QueueSongIds.Should().BeEmpty();
        session.CurrentSongId.Should().BeNull();
    }
}
