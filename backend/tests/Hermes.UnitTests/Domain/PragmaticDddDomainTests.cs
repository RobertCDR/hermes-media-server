using System.Reflection;
using FluentAssertions;
using Hermes.Domain.Entities;
using Hermes.Domain.Enums;
using Xunit;

namespace Hermes.UnitTests.Domain;

public class PragmaticDddDomainTests
{
    [Fact]
    public void WatchProgress_UpdatePosition_MarksWatchedAtNinetyPercent_AndClampsNegativePosition()
    {
        var now = DateTimeOffset.UtcNow;
        var progress = WatchProgress.ForMovie(Guid.NewGuid(), Guid.NewGuid());

        progress.UpdatePosition(-500, 1_000_000, now);
        progress.PositionMs.Should().Be(0);
        progress.IsWatched.Should().BeFalse();

        progress.UpdatePosition(890_000, 1_000_000, now.AddMinutes(10));
        progress.PositionMs.Should().Be(890_000);
        progress.IsWatched.Should().BeFalse();

        progress.UpdatePosition(900_000, 1_000_000, now.AddMinutes(11));
        progress.IsWatched.Should().BeTrue();
    }

    [Fact]
    public void PlaybackSession_RemoteTransportKeepsActiveRenderer_UntilExplicitTransferOutput_AndPausesOnRendererDisconnect()
    {
        var now = DateTimeOffset.UtcNow;
        var song1 = Guid.NewGuid();
        var song2 = Guid.NewGuid();
        var session = PlaybackSession.CreateForUser(Guid.NewGuid());

        session.StartPlayback("win-pc", "Windows Desktop", [song1, song2], 0, now);
        session.Version.Should().Be(1);
        session.ActiveRendererDeviceId.Should().Be("win-pc");
        session.State.Should().Be(PlaybackState.Playing);

        // Device B sends transport command -> ActiveRenderer stays on Device A
        session.ApplyRemoteTransport(PlaybackState.Playing, currentIndex: 1, positionMs: 0, now.AddSeconds(5));
        session.Version.Should().Be(2);
        session.ActiveRendererDeviceId.Should().Be("win-pc");
        session.CurrentSongId.Should().Be(song2);

        // Explicit handoff to Device B
        session.TransferOutput("android-1", "Pixel Phone", now.AddSeconds(10));
        session.Version.Should().Be(3);
        session.ActiveRendererDeviceId.Should().Be("android-1");

        // Disconnecting an inactive device leaves playback running
        session.HandleDeviceDisconnected("win-pc", now.AddSeconds(15)).Should().BeFalse();
        session.State.Should().Be(PlaybackState.Playing);
        session.Version.Should().Be(3);

        // Disconnecting the active renderer auto-pauses and clears active renderer
        session.HandleDeviceDisconnected("android-1", now.AddSeconds(20)).Should().BeTrue();
        session.Version.Should().Be(4);
        session.State.Should().Be(PlaybackState.Paused);
        session.ActiveRendererDeviceId.Should().BeNull();
    }

    [Fact]
    public void InviteCode_TryRedeem_EnforcesMaxUsesExpirationAndRevocation()
    {
        var now = DateTimeOffset.UtcNow;
        var invite = InviteCode.Create(Guid.NewGuid(), "HERMES-2026", maxUses: 1, now.AddDays(1), now);

        invite.TryRedeem(now.AddHours(1)).Should().BeTrue();
        invite.TryRedeem(now.AddHours(2)).Should().BeFalse();

        var expired = InviteCode.Create(Guid.NewGuid(), "EXPIRED", maxUses: 5, now.AddMinutes(10), now);
        expired.TryRedeem(now.AddMinutes(11)).Should().BeFalse();

        var revoked = InviteCode.Create(Guid.NewGuid(), "REVOKED", maxUses: 5, now.AddDays(1), now);
        revoked.Revoke();
        revoked.TryRedeem(now.AddMinutes(1)).Should().BeFalse();
    }

    [Fact]
    public void Movie_LockManualMatch_PreventsSubsequentScannerOverwrite_AndMediaSourceTracksMissingSince()
    {
        var now = DateTimeOffset.UtcNow;
        var movie = new Movie(Guid.NewGuid(), "Wrong Guess", 2001);

        movie.LockManualMatch(27205, "Inception", 2010, "Dream heist", "art1", "bg1");
        movie.IsMetadataLocked.Should().BeTrue();
        movie.TmdbId.Should().Be(27205);

        movie.ApplyScannedMetadata("Wrong Guess Again", 1999, "Overwritten", 999, "other", "other2");
        movie.Title.Should().Be("Inception");
        movie.Year.Should().Be(2010);
        movie.ArtworkHash.Should().Be("art1");

        var source = MediaSource.ForMovie(movie.Id, "/media/Inception.2010.1080p.mkv", "1080p HEVC", "mkv", "hevc", "aac", 1920, 1080, false, 8_000_000, 4_200_000_000, 8_880_000);
        source.MarkMissing(now);
        source.MissingSinceUtc.Should().Be(now);

        source.MarkPresent();
        source.MissingSinceUtc.Should().BeNull();
    }

    [Fact]
    public void DomainEntities_ContainZeroByteArrayColumns()
    {
        var entityTypes = typeof(Hermes.Domain.AssemblyReference).Assembly
            .GetTypes()
            .Where(t => t.Namespace == "Hermes.Domain.Entities" && t.IsClass);

        var byteArrayProperties = entityTypes
            .SelectMany(t => t.GetProperties(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance))
            .Where(p => p.PropertyType == typeof(byte[]))
            .Select(p => $"{p.DeclaringType!.Name}.{p.Name}")
            .ToList();

        byteArrayProperties.Should().BeEmpty();
    }
}
