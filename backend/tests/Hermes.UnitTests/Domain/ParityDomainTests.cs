using FluentAssertions;
using Hermes.Domain.Common;
using Hermes.Domain.Entities;
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
}
