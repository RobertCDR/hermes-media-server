using System.Diagnostics;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using FluentAssertions;
using Hermes.Api.Features.Admin;
using Hermes.Api.Features.Auth;
using Hermes.Api.Features.Cinema;
using Hermes.Api.Features.Music;
using Hermes.Api.Features.Setup;
using Hermes.Domain.Enums;
using Hermes.Infrastructure.Media;
using Hermes.Infrastructure.Persistence;
using Hermes.IntegrationTests.Infrastructure;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace Hermes.IntegrationTests.EndToEnd;

public class ExtendedApiCoverageTests
{
    [Fact]
    public async Task ExtendedEndpoints_Series_CinemaDetails_MusicDetails_Playlists_Identify_AndAdminUsers_Succeed()
    {
        var tempRoot = Path.Combine(Path.GetTempPath(), $"hermes-ext-{Guid.NewGuid():N}");
        var moviesDir = Path.Combine(tempRoot, "movies");
        var seriesDir = Path.Combine(tempRoot, "series");
        var musicDir = Path.Combine(tempRoot, "music");
        var trailersDir = Path.Combine(moviesDir, "Trailers");
        Directory.CreateDirectory(moviesDir);
        Directory.CreateDirectory(trailersDir);
        Directory.CreateDirectory(seriesDir);
        Directory.CreateDirectory(musicDir);

        var moviePath = Path.Combine(moviesDir, "Blade.Runner.1982.mp4");
        var trailerPath = Path.Combine(trailersDir, "Blade.Runner.trailer.mp4");
        var episodePath = Path.Combine(seriesDir, "Severance.2022.S01E01 - 1080p.mp4");
        var song1Path = Path.Combine(musicDir, "01 - Opening.mp3");
        var song2Path = Path.Combine(musicDir, "02 - Closing.mp3");

        await GenerateMediaFixturesAsync(moviePath, trailerPath, episodePath, song1Path, song2Path);

        try
        {
            await using var factory = new PostgresWebApplicationFactory();
            await factory.InitializeAsync();
            using var anonClient = factory.CreateClient();

            // 1. Setup + Admin Login
            var setupResp = await anonClient.PostAsJsonAsync(
                "/api/v1/setup",
                new SetupRequest("admin", "AdminPass!123", "Hermes Extended"));
            setupResp.StatusCode.Should().Be(HttpStatusCode.Created);

            var adminLogin = await LoginAsync(anonClient, "admin", "AdminPass!123", "admin-pc", "Admin PC");
            using var adminClient = factory.CreateClient();
            adminClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", adminLogin.AccessToken);

            // 2. Invite & User management + one-time password reset flow
            var badInvite = await adminClient.PostAsJsonAsync("/api/v1/admin/invites", new CreateInviteRequest(MaxUses: 0, ExpiresInHours: 1));
            badInvite.StatusCode.Should().Be(HttpStatusCode.BadRequest);

            var invite = await (await adminClient.PostAsJsonAsync("/api/v1/admin/invites", new CreateInviteRequest(2, 24)))
                .Content.ReadFromJsonAsync<InviteResponse>();
            var invites = await adminClient.GetFromJsonAsync<List<InviteResponse>>("/api/v1/admin/invites");
            invites.Should().ContainSingle(i => i.Id == invite!.Id);

            var regResp = await anonClient.PostAsJsonAsync("/api/v1/auth/register", new RegisterRequest("bob", "BobPass!123", invite!.Code));
            regResp.StatusCode.Should().Be(HttpStatusCode.Created);
            var regDto = await regResp.Content.ReadFromJsonAsync<RegisterResponse>();

            var users = await adminClient.GetFromJsonAsync<List<UserSummaryDto>>("/api/v1/admin/users");
            users.Should().Contain(u => u.Username == "bob");

            var missingReset = await adminClient.PostAsync($"/api/v1/admin/users/{Guid.NewGuid()}/reset-code", null);
            missingReset.StatusCode.Should().Be(HttpStatusCode.NotFound);

            var resetCodeDto = await (await adminClient.PostAsync($"/api/v1/admin/users/{regDto!.UserId}/reset-code", null))
                .Content.ReadFromJsonAsync<ResetCodeResponse>();
            var resetResp = await anonClient.PostAsJsonAsync(
                "/api/v1/auth/reset-password",
                new ResetPasswordRequest("bob", resetCodeDto!.ResetCode, "BobNewPass!123"));
            resetResp.StatusCode.Should().Be(HttpStatusCode.OK);

            var bobLogin = await LoginAsync(anonClient, "bob", "BobNewPass!123", "bob-phone", "Pixel");
            using var bobClient = factory.CreateClient();
            bobClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", bobLogin.AccessToken);

            // 3. Libraries: validation + scan + queue scan + TV series scan + identify
            (await adminClient.PostAsJsonAsync("/api/v1/admin/libraries", new CreateLibraryRootRequest("", LibraryMediaType.Movies, moviesDir)))
                .StatusCode.Should().Be(HttpStatusCode.BadRequest);

            var moviesLib = await (await adminClient.PostAsJsonAsync(
                "/api/v1/admin/libraries",
                new CreateLibraryRootRequest("Movies", LibraryMediaType.Movies, moviesDir, true)))
                .Content.ReadFromJsonAsync<LibraryRootResponse>();

            // Duplicate root path -> 409 Conflict
            (await adminClient.PostAsJsonAsync(
                "/api/v1/admin/libraries",
                new CreateLibraryRootRequest("Movies Dup", LibraryMediaType.Movies, moviesDir, true)))
                .StatusCode.Should().Be(HttpStatusCode.Conflict);

            var seriesLib = await (await adminClient.PostAsJsonAsync(
                "/api/v1/admin/libraries",
                new CreateLibraryRootRequest("TV Series", LibraryMediaType.Series, seriesDir, true)))
                .Content.ReadFromJsonAsync<LibraryRootResponse>();

            var musicLib = await (await adminClient.PostAsJsonAsync(
                "/api/v1/admin/libraries",
                new CreateLibraryRootRequest("Music", LibraryMediaType.Music, musicDir, true)))
                .Content.ReadFromJsonAsync<LibraryRootResponse>();

            var allLibs = await adminClient.GetFromJsonAsync<List<LibraryRootResponse>>("/api/v1/admin/libraries");
            allLibs.Should().HaveCount(3);

            (await adminClient.PostAsync($"/api/v1/admin/libraries/{moviesLib!.Id}/scan", null)).EnsureSuccessStatusCode();
            (await adminClient.PostAsync($"/api/v1/admin/libraries/{seriesLib!.Id}/scan", null)).EnsureSuccessStatusCode();
            (await adminClient.PostAsync($"/api/v1/admin/libraries/{musicLib!.Id}/scan", null)).EnsureSuccessStatusCode();

            // Rescan once to cover existing source/song fingerprint paths, and queue a background scan
            (await adminClient.PostAsync($"/api/v1/admin/libraries/{moviesLib.Id}/scan", null)).EnsureSuccessStatusCode();
            (await adminClient.PostAsync($"/api/v1/admin/libraries/{seriesLib.Id}/scan", null)).EnsureSuccessStatusCode();
            (await adminClient.PostAsync($"/api/v1/admin/libraries/{musicLib.Id}/scan", null)).EnsureSuccessStatusCode();
            (await adminClient.PostAsync($"/api/v1/admin/libraries/{moviesLib.Id}/scan/queue", null))
                .StatusCode.Should().Be(HttpStatusCode.Accepted);
            (await adminClient.PostAsync($"/api/v1/admin/libraries/{Guid.NewGuid()}/scan/queue", null))
                .StatusCode.Should().Be(HttpStatusCode.NotFound);

            // 4. Cinema Movies, Series, Episodes & Identify
            var movies = await bobClient.GetFromJsonAsync<List<MovieSummaryDto>>("/api/v1/cinema/movies");
            movies.Should().ContainSingle(m => m.Title == "Blade Runner" && m.Year == 1982);
            var movieId = movies![0].Id;

            var movieDetail = await bobClient.GetFromJsonAsync<MovieSummaryDto>($"/api/v1/cinema/movies/{movieId}");
            movieDetail!.Id.Should().Be(movieId);
            (await bobClient.GetAsync($"/api/v1/cinema/movies/{Guid.NewGuid()}")).StatusCode.Should().Be(HttpStatusCode.NotFound);

            var seriesList = await bobClient.GetFromJsonAsync<List<TvSeriesSummaryDto>>("/api/v1/cinema/series");
            seriesList.Should().ContainSingle(s => s.Title == "Severance" && s.Year == 2022);
            var series = seriesList![0];
            var episodeId = series.Seasons.Single().Episodes.Single().Id;

            // Episode watch progress + 400 validation
            (await bobClient.PutAsJsonAsync("/api/v1/cinema/progress", new UpdateWatchProgressRequest(null, null, 100, 1000)))
                .StatusCode.Should().Be(HttpStatusCode.BadRequest);
            (await bobClient.PutAsJsonAsync("/api/v1/cinema/progress", new UpdateWatchProgressRequest(null, Guid.NewGuid(), 100, 1000)))
                .StatusCode.Should().Be(HttpStatusCode.NotFound);
            var epProgressResp = await bobClient.PutAsJsonAsync(
                "/api/v1/cinema/progress",
                new UpdateWatchProgressRequest(null, episodeId, 950, 1000, MarkWatched: true));
            epProgressResp.StatusCode.Should().Be(HttpStatusCode.OK);

            // Watchlist toggle per user (movies & series)
            (await bobClient.PutAsJsonAsync("/api/v1/cinema/watchlist", new UpdateWatchlistRequest(null, null, true)))
                .StatusCode.Should().Be(HttpStatusCode.BadRequest);
            (await bobClient.PutAsJsonAsync("/api/v1/cinema/watchlist", new UpdateWatchlistRequest(Guid.NewGuid(), null, true)))
                .StatusCode.Should().Be(HttpStatusCode.NotFound);
            (await bobClient.PutAsJsonAsync("/api/v1/cinema/watchlist", new UpdateWatchlistRequest(movieId, null, true)))
                .StatusCode.Should().Be(HttpStatusCode.OK);
            (await bobClient.PutAsJsonAsync("/api/v1/cinema/watchlist", new UpdateWatchlistRequest(null, series.Id, true)))
                .StatusCode.Should().Be(HttpStatusCode.OK);

            var bobMovieAfterList = await bobClient.GetFromJsonAsync<MovieSummaryDto>($"/api/v1/cinema/movies/{movieId}");
            bobMovieAfterList!.IsInWatchlist.Should().BeTrue();
            var adminMovies = await adminClient.GetFromJsonAsync<List<MovieSummaryDto>>("/api/v1/cinema/movies");
            adminMovies!.Single(m => m.Id == movieId).IsInWatchlist.Should().BeFalse();

            var bobSeriesAfterList = await bobClient.GetFromJsonAsync<List<TvSeriesSummaryDto>>("/api/v1/cinema/series");
            bobSeriesAfterList!.Single(s => s.Id == series.Id).IsInWatchlist.Should().BeTrue();

            (await bobClient.PutAsJsonAsync("/api/v1/cinema/watchlist", new UpdateWatchlistRequest(movieId, null, false)))
                .StatusCode.Should().Be(HttpStatusCode.OK);
            (await bobClient.GetFromJsonAsync<MovieSummaryDto>($"/api/v1/cinema/movies/{movieId}"))!
                .IsInWatchlist.Should().BeFalse();

            // Mark entire series watched/unwatched
            (await bobClient.PutAsJsonAsync($"/api/v1/cinema/series/{Guid.NewGuid()}/watched", new MarkSeriesWatchedRequest(true)))
                .StatusCode.Should().Be(HttpStatusCode.NotFound);
            var seriesWatchedResp = await bobClient.PutAsJsonAsync(
                $"/api/v1/cinema/series/{series.Id}/watched",
                new MarkSeriesWatchedRequest(true));
            seriesWatchedResp.StatusCode.Should().Be(HttpStatusCode.OK);
            var markedSeries = await seriesWatchedResp.Content.ReadFromJsonAsync<SeriesWatchedResponse>();
            markedSeries!.Watched.Should().BeTrue();
            markedSeries.EpisodesUpdated.Should().Be(1);

            var seriesUnwatchedResp = await bobClient.PutAsJsonAsync(
                $"/api/v1/cinema/series/{series.Id}/watched",
                new MarkSeriesWatchedRequest(false));
            seriesUnwatchedResp.StatusCode.Should().Be(HttpStatusCode.OK);
            var afterUnwatch = await bobClient.GetFromJsonAsync<List<TvSeriesSummaryDto>>("/api/v1/cinema/series");
            afterUnwatch!.Single(s => s.Id == series.Id).Seasons.Single().Episodes.Single().WatchProgress!.IsWatched.Should().BeFalse();

            // Manual Identify for Movie, Series, invalid, and 404
            (await adminClient.PostAsJsonAsync($"/api/v1/admin/media/{movieId}/identify", new IdentifyMediaRequest(0, "", null, null)))
                .StatusCode.Should().Be(HttpStatusCode.BadRequest);
            (await adminClient.PostAsJsonAsync($"/api/v1/admin/media/{Guid.NewGuid()}/identify", new IdentifyMediaRequest(78, "X", null, null)))
                .StatusCode.Should().Be(HttpStatusCode.NotFound);

            var idMovieResp = await adminClient.PostAsJsonAsync(
                $"/api/v1/admin/media/{movieId}/identify",
                new IdentifyMediaRequest(78, "Blade Runner: The Final Cut", 1982, "Locked Sci-Fi"));
            idMovieResp.StatusCode.Should().Be(HttpStatusCode.OK);
            var idSeriesResp = await adminClient.PostAsJsonAsync(
                $"/api/v1/admin/media/{series.Id}/identify",
                new IdentifyMediaRequest(95396, "Severance", 2022, "Lumon Industries"));
            idSeriesResp.StatusCode.Should().Be(HttpStatusCode.OK);

            // 5. Music Artist, Album, Liked toggle, Playlists & Empty Search
            var artists = await bobClient.GetFromJsonAsync<List<ArtistSummaryDto>>("/api/v1/music/artists");
            artists.Should().HaveCountGreaterThanOrEqualTo(1);
            var artistDetail = await bobClient.GetFromJsonAsync<ArtistDetailDto>($"/api/v1/music/artists/{artists![0].Id}");
            artistDetail!.Songs.Should().HaveCount(2);
            (await bobClient.GetAsync($"/api/v1/music/artists/{Guid.NewGuid()}")).StatusCode.Should().Be(HttpStatusCode.NotFound);

            var albums = await bobClient.GetFromJsonAsync<List<AlbumSummaryDto>>("/api/v1/music/albums");
            albums.Should().HaveCountGreaterThanOrEqualTo(1);
            var albumDetail = await bobClient.GetFromJsonAsync<AlbumDetailDto>($"/api/v1/music/albums/{albums![0].Id}");
            albumDetail!.Songs.Should().HaveCount(2);
            (await bobClient.GetAsync($"/api/v1/music/albums/{Guid.NewGuid()}")).StatusCode.Should().Be(HttpStatusCode.NotFound);

            var song1Id = albumDetail.Songs[0].Id;
            var song2Id = albumDetail.Songs[1].Id;

            var likeOn = await (await bobClient.PostAsync($"/api/v1/music/songs/{song1Id}/like", null))
                .Content.ReadFromJsonAsync<LikeToggleResponse>();
            likeOn!.IsLiked.Should().BeTrue();
            var likedList = await bobClient.GetFromJsonAsync<List<SongDto>>("/api/v1/music/songs/liked");
            likedList.Should().ContainSingle(s => s.Id == song1Id);
            var likeOff = await (await bobClient.PostAsync($"/api/v1/music/songs/{song1Id}/like", null))
                .Content.ReadFromJsonAsync<LikeToggleResponse>();
            likeOff!.IsLiked.Should().BeFalse();

            var session = await bobClient.GetFromJsonAsync<PlaybackSessionDto>("/api/v1/music/session");
            session.Should().NotBeNull();
            var devices = await bobClient.GetFromJsonAsync<List<OnlineDeviceDto>>("/api/v1/music/devices");
            devices.Should().NotBeNull();

            // Empty search query + TV Series search hit
            var emptySearch = await bobClient.GetFromJsonAsync<UnifiedSearchResponse>("/api/v1/search?q=");
            emptySearch!.Movies.Should().BeEmpty();
            var tvSearch = await bobClient.GetFromJsonAsync<UnifiedSearchResponse>("/api/v1/search?q=Severance");
            tvSearch!.Series.Should().ContainSingle(s => s.Id == series.Id);

            // Playlists CRUD + shift position when removing track at position 0
            (await bobClient.PostAsJsonAsync("/api/v1/music/playlists/", new CreatePlaylistRequest("   ")))
                .StatusCode.Should().Be(HttpStatusCode.BadRequest);
            var createdPlaylist = await (await bobClient.PostAsJsonAsync(
                "/api/v1/music/playlists/",
                new CreatePlaylistRequest("Late Night", "Synthwave")))
                .Content.ReadFromJsonAsync<PlaylistDetailDto>();

            var listPlaylists = await bobClient.GetFromJsonAsync<List<PlaylistSummaryDto>>("/api/v1/music/playlists/");
            listPlaylists.Should().ContainSingle(p => p.Id == createdPlaylist!.Id);

            await bobClient.PostAsJsonAsync($"/api/v1/music/playlists/{createdPlaylist!.Id}/tracks", new AddPlaylistTrackRequest(song1Id));
            await bobClient.PostAsJsonAsync($"/api/v1/music/playlists/{createdPlaylist.Id}/tracks", new AddPlaylistTrackRequest(song2Id));

            var detailAfterAdd = await bobClient.GetFromJsonAsync<PlaylistDetailDto>($"/api/v1/music/playlists/{createdPlaylist.Id}");
            detailAfterAdd!.Tracks.Should().HaveCount(2);

            var detailAfterDelete = await (await bobClient.DeleteAsync($"/api/v1/music/playlists/{createdPlaylist.Id}/tracks/0"))
                .Content.ReadFromJsonAsync<PlaylistDetailDto>();
            detailAfterDelete!.Tracks.Should().ContainSingle(t => t.Position == 0 && t.Song.Id == song2Id);

            // Rename + Delete playlist + Song lyrics endpoint
            (await bobClient.PutAsJsonAsync($"/api/v1/music/playlists/{createdPlaylist.Id}", new RenamePlaylistRequest("   ")))
                .StatusCode.Should().Be(HttpStatusCode.BadRequest);
            var renamedPlaylist = await (await bobClient.PutAsJsonAsync(
                $"/api/v1/music/playlists/{createdPlaylist.Id}",
                new RenamePlaylistRequest("After Hours")))
                .Content.ReadFromJsonAsync<PlaylistDetailDto>();
            renamedPlaylist!.Name.Should().Be("After Hours");

            var lyricsResp = await bobClient.GetFromJsonAsync<SongLyricsDto>($"/api/v1/music/songs/{song1Id}/lyrics");
            lyricsResp.Should().NotBeNull();
            lyricsResp!.SongId.Should().Be(song1Id);

            (await bobClient.DeleteAsync($"/api/v1/music/playlists/{createdPlaylist.Id}"))
                .StatusCode.Should().Be(HttpStatusCode.NoContent);
            (await bobClient.GetAsync($"/api/v1/music/playlists/{createdPlaylist.Id}"))
                .StatusCode.Should().Be(HttpStatusCode.NotFound);

            // 6. DirectPlay video master.m3u8 + audio bitrate alias checks + missing files scan
            var videoSourceId = movieDetail.Sources.Single().Id;
            var videoTicket = (await (await bobClient.PostAsJsonAsync(
                "/api/v1/auth/stream-tickets",
                new CreateStreamTicketRequest(videoSourceId)))
                .Content.ReadFromJsonAsync<StreamTicketResponse>())!.Ticket;
            var directMaster = await anonClient.GetStringAsync(
                $"/api/v1/streams/{videoSourceId}/video/master.m3u8?quality=direct&ticket={Uri.EscapeDataString(videoTicket)}");
            directMaster.Should().Contain("/direct?ticket=");

            // Remove episode & song files then rescan to cover MarkMissing paths
            File.Delete(episodePath);
            File.Delete(song2Path);
            var missingSeriesScan = await (await adminClient.PostAsync($"/api/v1/admin/libraries/{seriesLib.Id}/scan", null))
                .Content.ReadFromJsonAsync<LibraryScanSummaryDto>();
            missingSeriesScan!.SourcesMarkedMissing.Should().Be(1);

            var missingMusicScan = await (await adminClient.PostAsync($"/api/v1/admin/libraries/{musicLib.Id}/scan", null))
                .Content.ReadFromJsonAsync<LibraryScanSummaryDto>();
            missingMusicScan!.SourcesMarkedMissing.Should().Be(1);

            // Also cover LibraryScanWorker reading once cleanly via service scope
            using var scope = factory.Services.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<HermesDbContext>();
            (await db.MediaLibraryRoots.CountAsync()).Should().Be(3);
            var channel = factory.Services.GetRequiredService<LibraryScanChannel>();
            await channel.EnqueueScanAsync(seriesLib.Id, CancellationToken.None);
        }
        finally
        {
            if (Directory.Exists(tempRoot))
            {
                Directory.Delete(tempRoot, recursive: true);
            }
        }
    }

    private static async Task GenerateMediaFixturesAsync(
        string moviePath,
        string trailerPath,
        string episodePath,
        string song1Path,
        string song2Path)
    {
        await RunFfmpegAsync([
            "-y", "-v", "error",
            "-f", "lavfi", "-i", "testsrc=duration=1:size=320x180:rate=24",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=1",
            "-c:v", "libx264", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-b:a", "96k",
            moviePath
        ]);

        File.Copy(moviePath, trailerPath);
        File.Copy(moviePath, episodePath);

        await RunFfmpegAsync([
            "-y", "-v", "error",
            "-f", "lavfi", "-i", "sine=frequency=523:duration=1",
            "-c:a", "libmp3lame", "-b:a", "192k",
            "-metadata", "title=Opening",
            "-metadata", "artist=Kavinsky",
            "-metadata", "album=OutRun",
            "-metadata", "track=1",
            song1Path
        ]);

        await RunFfmpegAsync([
            "-y", "-v", "error",
            "-f", "lavfi", "-i", "sine=frequency=659:duration=1",
            "-c:a", "libmp3lame", "-b:a", "192k",
            "-metadata", "title=Closing",
            "-metadata", "artist=Kavinsky",
            "-metadata", "album=OutRun",
            "-metadata", "track=2",
            song2Path
        ]);
    }

    private static async Task RunFfmpegAsync(string[] arguments)
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
        foreach (var arg in arguments)
        {
            process.StartInfo.ArgumentList.Add(arg);
        }

        process.Start();
        var err = await process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();
        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException($"ffmpeg exited with code {process.ExitCode}: {err}");
        }
    }

    private static async Task<AuthTokenResponse> LoginAsync(
        HttpClient client,
        string username,
        string password,
        string deviceId,
        string deviceName)
    {
        var response = await client.PostAsJsonAsync(
            "/api/v1/auth/login",
            new LoginRequest(username, password, deviceId, deviceName));
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        return (await response.Content.ReadFromJsonAsync<AuthTokenResponse>())!;
    }
}
