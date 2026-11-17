using FluentAssertions;
using Hermes.Domain.Entities;
using Hermes.Domain.Enums;
using Hermes.Domain.Ports;
using Hermes.Infrastructure.Realtime;
using Hermes.Infrastructure.Security;
using Xunit;

namespace Hermes.UnitTests.Domain;

public class CinemaAndIdentityDomainTests
{
    [Fact]
    public void TvSeriesSeasonEpisodeAndMediaSource_EnforceInvariantsAndMetadataLocks()
    {
        var now = DateTimeOffset.UtcNow;
        var root = new MediaLibraryRoot("TV Shows", LibraryMediaType.Series, "/media/tv", true);
        root.MarkScanCompleted(now);
        root.LastScanCompletedAtUtc.Should().Be(now);

        var series = new TvSeries(root.Id, "Severance", 2022);
        series.ApplyScannedMetadata("Severance", 2022, "Macrodata Refinement", 95396, "art", "bg");
        series.TmdbId.Should().Be(95396);

        series.LockManualMatch(95396, "Severance (Locked)", 2022, "Locked Overview", "art2", "bg2");
        series.IsMetadataLocked.Should().BeTrue();
        series.ApplyScannedMetadata("Wrong", 1999, "Overwritten", 1, "bad", "bad");
        series.ApplyRichMetadata(9.9, ["Ignored"], """[{"name":"Bad"}]""");
        series.Title.Should().Be("Severance (Locked)");
        series.GenresCsv.Should().BeNull();

        series.ApplyRichMetadata(8.74, ["Drama", "Sci-Fi", "Drama"], """[{"name":"Adam Scott","role":"Mark Scout"}]""", bypassLock: true);
        series.Rating.Should().Be(8.7);
        series.GenresCsv.Should().Be("Drama, Sci-Fi");
        series.CastJson.Should().Contain("Adam Scott");

        var season = new TvSeason(series.Id, 1, "Season 1", "s1art");
        season.SetExpectedEpisodeCount(9);
        season.ExpectedEpisodeCount.Should().Be(9);
        season.SetExpectedEpisodeCount(0);
        season.ExpectedEpisodeCount.Should().BeNull();

        var movie = new Movie(root.Id, "Dark City", 1998);
        movie.ApplyRichMetadata(7.6, ["Mystery", "Sci-Fi"], 100, """[{"name":"Rufus Sewell","role":"John Murdoch"}]""");
        movie.Rating.Should().Be(7.6);
        movie.GenresCsv.Should().Be("Mystery, Sci-Fi");
        movie.RuntimeMinutes.Should().Be(100);

        var watchlistMovie = WatchlistItem.ForMovie(Guid.NewGuid(), movie.Id, now);
        watchlistMovie.MovieId.Should().Be(movie.Id);
        watchlistMovie.TvSeriesId.Should().BeNull();

        var watchlistSeries = WatchlistItem.ForSeries(watchlistMovie.UserId, series.Id, now);
        watchlistSeries.TvSeriesId.Should().Be(series.Id);
        watchlistSeries.MovieId.Should().BeNull();
        var episode = new Episode(season.Id, 1, "Good News About Hell", "Pilot", "ep1still");
        season.Episodes.Add(episode);
        series.Seasons.Add(season);

        var epSource = MediaSource.ForEpisode(episode.Id, "/media/tv/S01E01.mkv", "1080p", "mkv", "h264", "aac", 1920, 1080, false, 5_000_000, 1_500_000_000, 3_400_000);
        epSource.EpisodeId.Should().Be(episode.Id);
        epSource.MovieId.Should().BeNull();
        epSource.UpdateFileFingerprint(1_600_000_000, now.AddMinutes(5));
        epSource.FileSizeBytes.Should().Be(1_600_000_000);

        var stream = new MediaStream(epSource.Id, 2, StreamKind.Subtitle, "subrip", "", "English", true);
        stream.Language.Should().Be("und");
        stream.IsDefault.Should().BeTrue();

        var epProgress = WatchProgress.ForEpisode(Guid.NewGuid(), episode.Id);
        epProgress.UpdatePosition(5_000_000, 1_000_000, now);
        epProgress.PositionMs.Should().Be(1_000_000);
        epProgress.IsWatched.Should().BeTrue();
        epProgress.SetWatched(false, now.AddMinutes(1));
        epProgress.IsWatched.Should().BeFalse();
        epProgress.SetWatched(true, now.AddMinutes(2));
        epProgress.PositionMs.Should().Be(1_000_000);

        var actInvalidProgress = () => WatchProgress.ForEpisode(Guid.NewGuid(), episode.Id);
        actInvalidProgress.Should().NotThrow();
    }

    [Fact]
    public void UserAndServerSettings_EnforceSecurityLimitsAndThemeUpdates()
    {
        var now = DateTimeOffset.UtcNow;
        var user = User.Create("alice", "hash1", UserRole.Member, now);
        var refresh = RefreshToken.Create(user.Id, "dev-1", "Desktop", "tokHash", now.AddDays(30), now);
        user.RefreshTokens.Add(refresh);

        user.SetOneTimeResetCode("resetHash", now.AddMinutes(30));
        user.OneTimeResetCodeHash.Should().Be("resetHash");

        user.UpdateThemePreferences(ThemeSurfacePreset.OledBlack, "#10B981");
        user.PreferredSurfacePreset.Should().Be(ThemeSurfacePreset.OledBlack);
        user.PreferredAccentHex.Should().Be("#10B981");

        user.AutoplayNextEpisode.Should().BeTrue();
        user.NormalizeVolume.Should().BeFalse();
        user.MatchTitleColors.Should().BeTrue();
        user.SubtitleSize.Should().Be("medium");
        user.SubtitleBackground.Should().Be("shadow");

        user.UpdateAccountPreferences(false, true, false, "XL", "Box");
        user.AutoplayNextEpisode.Should().BeFalse();
        user.NormalizeVolume.Should().BeTrue();
        user.MatchTitleColors.Should().BeFalse();
        user.SubtitleSize.Should().Be("xl");
        user.SubtitleBackground.Should().Be("box");

        var badSubSize = () => user.UpdateAccountPreferences(true, false, true, "huge", "shadow");
        badSubSize.Should().Throw<ArgumentException>();

        var badSubBg = () => user.UpdateAccountPreferences(true, false, true, "large", "neon");
        badSubBg.Should().Throw<ArgumentException>();

        user.ChangePassword("hash2", now.AddMinutes(5));
        user.OneTimeResetCodeHash.Should().BeNull();
        refresh.IsActive(now.AddMinutes(6)).Should().BeFalse();

        user.Deactivate(now.AddMinutes(10));
        user.IsActive.Should().BeFalse();

        var settings = ServerSettings.CreateDefault("Hermes", now);
        settings.HardwareAccelerationMode.Should().Be(HardwareAccelerationMode.None);
        settings.UpdateTranscodeLimits(4, 6, 20_000_000, true, now.AddMinutes(1));
        settings.MaxConcurrentVideoTranscodes.Should().Be(4);
        settings.MaxConcurrentAudioTranscodes.Should().Be(6);
        settings.MaxRemoteVideoBitrateBps.Should().Be(20_000_000);

        settings.UpdateSettings("Hermes NAS", 3, 5, null, false, HardwareAccelerationMode.Vaapi, now.AddMinutes(2));
        settings.ServerName.Should().Be("Hermes NAS");
        settings.TranscodingEnabled.Should().BeFalse();
        settings.HardwareAccelerationMode.Should().Be(HardwareAccelerationMode.Vaapi);

        var badSettings = () => settings.UpdateTranscodeLimits(2, 2, 0, true, now);
        badSettings.Should().Throw<ArgumentOutOfRangeException>();

        var library = new MediaLibraryRoot("Movies", LibraryMediaType.Movies, "/media/movies", watchEnabled: true);
        library.FetchMetadata.Should().BeTrue();
        library.UpdateOptions("Cinema 4K", "/mnt/cinema", watchEnabled: false, fetchMetadata: false);
        library.Name.Should().Be("Cinema 4K");
        library.RootPath.Should().Be("/mnt/cinema");
        library.WatchEnabled.Should().BeFalse();
        library.FetchMetadata.Should().BeFalse();
    }

    [Fact]
    public void SecurityAndPresenceAdapters_RejectMalformedInputs()
    {
        var hasher = new PasswordHasherAdapter();
        var hash = hasher.HashPassword("StrongPass!123");
        hasher.VerifyPassword("StrongPass!123", hash).Should().BeTrue();
        hasher.VerifyPassword("", hash).Should().BeFalse();
        hasher.VerifyPassword("StrongPass!123", "bad$format").Should().BeFalse();
        hasher.VerifyPassword("StrongPass!123", "pbkdf2-sha256$0$abc$def").Should().BeFalse();
        hasher.VerifyPassword("StrongPass!123", "pbkdf2-sha256$10$notbase64!$def").Should().BeFalse();
        hasher.VerifyPassword("StrongPass!123", $"pbkdf2-sha256$10${Convert.ToBase64String(new byte[16])}$notbase64!").Should().BeFalse();

        var actShortSecret = () => new HmacStreamTicketService("too-short");
        actShortSecret.Should().Throw<ArgumentException>();

        var tickets = new HmacStreamTicketService("0123456789abcdef0123456789abcdef");
        var sourceId = Guid.NewGuid();
        var validTicket = tickets.CreateStreamTicket(Guid.NewGuid(), sourceId, TimeSpan.FromMinutes(10));
        tickets.TryValidateStreamTicket(validTicket, sourceId, out _).Should().BeTrue();
        tickets.TryValidateStreamTicket("", sourceId, out _).Should().BeFalse();
        tickets.TryValidateStreamTicket("onlyonepart", sourceId, out _).Should().BeFalse();
        tickets.TryValidateStreamTicket("bad.sig!", sourceId, out _).Should().BeFalse();
        tickets.TryValidateStreamTicket(validTicket, Guid.NewGuid(), out _).Should().BeFalse();

        var registry = new InMemoryDevicePresenceRegistry();
        var userId = Guid.NewGuid();
        registry.RegisterConnection(userId, "c1", new OnlineDeviceInfo("d1", "Phone", "Android", DateTimeOffset.UtcNow));
        registry.RegisterConnection(userId, "c2", new OnlineDeviceInfo("d1", "Phone", "Android", DateTimeOffset.UtcNow));
        registry.IsDeviceConnected(userId, "d1").Should().BeTrue();
        registry.GetOnlineDevices(userId).Should().HaveCount(1);
        registry.RemoveConnection("c1").Should().NotBeNull();
        registry.IsDeviceConnected(userId, "d1").Should().BeTrue();
        registry.RemoveConnection("c2").Should().NotBeNull();
        registry.IsDeviceConnected(userId, "d1").Should().BeFalse();
        registry.RemoveConnection("unknown").Should().BeNull();
    }

    [Fact]
    public void Playlist_Rename_And_UpdateDescription_ShouldTrimAndUpdateTimestamp()
    {
        var t0 = DateTimeOffset.Parse("2026-11-16T10:00:00Z");
        var t1 = DateTimeOffset.Parse("2026-11-17T12:00:00Z");
        var playlist = new Playlist(Guid.NewGuid(), "Initial Mix", "Original notes", t0);

        playlist.Rename("  Late Night Synth  ", t1);
        playlist.Name.Should().Be("Late Night Synth");
        playlist.Description.Should().Be("Original notes");
        playlist.UpdatedAtUtc.Should().Be(t1);

        var t2 = t1.AddMinutes(5);
        playlist.UpdateDescription("   ", t2);
        playlist.Description.Should().BeNull();
        playlist.UpdatedAtUtc.Should().Be(t2);

        var invalidRename = () => playlist.Rename("   ", t2);
        invalidRename.Should().Throw<ArgumentException>();
    }
}
