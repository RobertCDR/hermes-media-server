using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using FluentAssertions;
using Hermes.Api.Features.Admin;
using Hermes.Api.Features.Auth;
using Hermes.Api.Features.Cinema;
using Hermes.Api.Features.Setup;
using Hermes.Domain.Entities;
using Hermes.Domain.Enums;
using Hermes.Infrastructure.Media;
using Hermes.Infrastructure.Persistence;
using Hermes.IntegrationTests.Infrastructure;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace Hermes.IntegrationTests.Admin;

public class AdminWatcherAndSettingsTests
{
    [Fact]
    public async Task ServerSettingsEndpoints_UpdateNameLimitsHwAccel_AndReportTotalMediaSize()
    {
        var tempMediaDir = Path.Combine(Path.GetTempPath(), $"hermes-settings-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempMediaDir);
        var movieFile = Path.Combine(tempMediaDir, "Arrival (2016) - 1080p.mkv");
        await File.WriteAllBytesAsync(movieFile, RandomNumberGenerator.GetBytes(2048));

        try
        {
            await using var factory = new PostgresWebApplicationFactory();
            await factory.InitializeAsync();
            using var adminClient = await CreateAuthenticatedAdminClientAsync(factory);

            var libResponse = await adminClient.PostAsJsonAsync(
                "/api/v1/admin/libraries",
                new CreateLibraryRootRequest("Cinema", LibraryMediaType.Movies, tempMediaDir, WatchEnabled: false, FetchMetadata: false));
            libResponse.StatusCode.Should().Be(HttpStatusCode.Created);
            var lib = (await libResponse.Content.ReadFromJsonAsync<LibraryRootResponse>())!;

            (await adminClient.PostAsync($"/api/v1/admin/libraries/{lib.Id}/scan", null)).EnsureSuccessStatusCode();

            var getSettingsResp = await adminClient.GetAsync("/api/v1/admin/settings");
            getSettingsResp.StatusCode.Should().Be(HttpStatusCode.OK);
            var initial = (await getSettingsResp.Content.ReadFromJsonAsync<ServerSettingsResponse>())!;
            initial.ServerName.Should().Be("Hermes Home");
            initial.TranscodingEnabled.Should().BeTrue();
            initial.HardwareAccelerationMode.Should().Be(HardwareAccelerationMode.None);
            initial.TotalMediaSizeBytes.Should().BeGreaterThanOrEqualTo(2048);
            initial.LibraryCount.Should().Be(1);
            initial.TotalMovies.Should().Be(1);

            var updateResp = await adminClient.PutAsJsonAsync(
                "/api/v1/admin/settings",
                new UpdateServerSettingsRequest(
                    ServerName: "Hermes NAS Vault",
                    TranscodingEnabled: false,
                    MaxConcurrentVideoTranscodes: 3,
                    MaxConcurrentAudioTranscodes: 6,
                    MaxRemoteVideoBitrateBps: 15_000_000,
                    HardwareAccelerationMode: HardwareAccelerationMode.Vaapi));
            updateResp.StatusCode.Should().Be(HttpStatusCode.OK);
            var updated = (await updateResp.Content.ReadFromJsonAsync<ServerSettingsResponse>())!;
            updated.ServerName.Should().Be("Hermes NAS Vault");
            updated.TranscodingEnabled.Should().BeFalse();
            updated.MaxConcurrentVideoTranscodes.Should().Be(3);
            updated.MaxConcurrentAudioTranscodes.Should().Be(6);
            updated.MaxRemoteVideoBitrateBps.Should().Be(15_000_000);
            updated.HardwareAccelerationMode.Should().Be(HardwareAccelerationMode.Vaapi);

            var sysInfo = await adminClient.GetFromJsonAsync<Hermes.Api.Features.System.SystemInfoDto>("/api/v1/system/info");
            sysInfo!.ServerName.Should().Be("Hermes NAS Vault");

            var movies = await adminClient.GetFromJsonAsync<List<MovieSummaryDto>>("/api/v1/cinema/movies");
            var sourceId = movies!.Single().Sources.Single().Id;
            var ticket = (await (await adminClient.PostAsJsonAsync(
                "/api/v1/auth/stream-tickets",
                new CreateStreamTicketRequest(sourceId)))
                .Content.ReadFromJsonAsync<StreamTicketResponse>())!.Ticket;

            using var anonymousClient = factory.CreateClient();
            var hlsBlocked = await anonymousClient.GetAsync(
                $"/api/v1/streams/{sourceId}/video/master.m3u8?quality=P720&ticket={Uri.EscapeDataString(ticket)}");
            hlsBlocked.StatusCode.Should().Be(HttpStatusCode.Forbidden);
        }
        finally
        {
            if (Directory.Exists(tempMediaDir))
            {
                Directory.Delete(tempMediaDir, recursive: true);
            }
        }
    }

    [Fact]
    public async Task LibraryAdminEndpoints_SupportEditAndCascadingDeleteForMoviesAndMusic_AndSyncWatcher()
    {
        var tempRoot = Path.Combine(Path.GetTempPath(), $"hermes-lib-crud-{Guid.NewGuid():N}");
        var moviesDir = Path.Combine(tempRoot, "Movies");
        var moviesAltDir = Path.Combine(tempRoot, "MoviesAlt");
        var musicDir = Path.Combine(tempRoot, "Music");
        Directory.CreateDirectory(moviesDir);
        Directory.CreateDirectory(moviesAltDir);
        Directory.CreateDirectory(musicDir);

        await File.WriteAllBytesAsync(Path.Combine(moviesDir, "Interstellar (2014) - 1080p.mkv"), [0x01, 0x02, 0x03, 0x04]);

        try
        {
            await using var factory = new PostgresWebApplicationFactory();
            await factory.InitializeAsync();
            using var adminClient = await CreateAuthenticatedAdminClientAsync(factory);

            var createMoviesResp = await adminClient.PostAsJsonAsync(
                "/api/v1/admin/libraries",
                new CreateLibraryRootRequest("Movies", LibraryMediaType.Movies, moviesDir, WatchEnabled: false, FetchMetadata: false));
            createMoviesResp.StatusCode.Should().Be(HttpStatusCode.Created);
            var moviesLib = (await createMoviesResp.Content.ReadFromJsonAsync<LibraryRootResponse>())!;
            (await adminClient.PostAsync($"/api/v1/admin/libraries/{moviesLib.Id}/scan", null)).EnsureSuccessStatusCode();

            var updateMoviesResp = await adminClient.PutAsJsonAsync(
                $"/api/v1/admin/libraries/{moviesLib.Id}",
                new UpdateLibraryRootRequest("Cinema Vault", moviesAltDir, WatchEnabled: true, FetchMetadata: true));
            updateMoviesResp.StatusCode.Should().Be(HttpStatusCode.OK);
            var updatedMovies = (await updateMoviesResp.Content.ReadFromJsonAsync<LibraryRootResponse>())!;
            updatedMovies.Name.Should().Be("Cinema Vault");
            updatedMovies.RootPath.Should().Be(moviesAltDir);
            updatedMovies.WatchEnabled.Should().BeTrue();
            updatedMovies.FetchMetadata.Should().BeTrue();

            var watcher = factory.Services.GetRequiredService<LibraryWatcherService>();
            watcher.ActiveWatchedLibraryIds.Should().Contain(moviesLib.Id);

            // Seed Music library with Artist -> Album -> Song + PlaylistTrack + LikedSong to exercise cascading delete.
            Guid musicLibId;
            using (var scope = factory.Services.CreateScope())
            {
                var db = scope.ServiceProvider.GetRequiredService<HermesDbContext>();
                var admin = await db.Users.SingleAsync();
                var musicLib = new MediaLibraryRoot("Music", LibraryMediaType.Music, musicDir, watchEnabled: false);
                var artist = new Artist("Test Artist");
                var album = new Album(artist.Id, "Test Album", 2025);
                var song = new Song(
                    musicLib.Id,
                    artist.Id,
                    album.Id,
                    "Track 1",
                    1,
                    1,
                    180_000,
                    Path.Combine(musicDir, "track1.flac"),
                    "flac",
                    900_000,
                    44_100,
                    16,
                    4096,
                    DateTimeOffset.UtcNow);
                var playlist = new Playlist(admin.Id, "Favorites", null, DateTimeOffset.UtcNow);
                var pt = new PlaylistTrack(playlist.Id, song.Id, 0);
                var liked = new LikedSong(admin.Id, song.Id, DateTimeOffset.UtcNow);
                db.MediaLibraryRoots.Add(musicLib);
                db.Artists.Add(artist);
                db.Albums.Add(album);
                db.Songs.Add(song);
                db.Playlists.Add(playlist);
                db.PlaylistTracks.Add(pt);
                db.LikedSongs.Add(liked);
                await db.SaveChangesAsync();
                musicLibId = musicLib.Id;
            }

            // Duplicate RootPath returns 409 Conflict.
            var conflictUpdate = await adminClient.PutAsJsonAsync(
                $"/api/v1/admin/libraries/{musicLibId}",
                new UpdateLibraryRootRequest("Conflict", moviesAltDir, WatchEnabled: false, FetchMetadata: false));
            conflictUpdate.StatusCode.Should().Be(HttpStatusCode.Conflict);

            var deleteMusicResp = await adminClient.DeleteAsync($"/api/v1/admin/libraries/{musicLibId}");
            deleteMusicResp.StatusCode.Should().Be(HttpStatusCode.NoContent);

            var deleteMoviesResp = await adminClient.DeleteAsync($"/api/v1/admin/libraries/{moviesLib.Id}");
            deleteMoviesResp.StatusCode.Should().Be(HttpStatusCode.NoContent);

            watcher.ActiveWatchedLibraryIds.Should().NotContain(moviesLib.Id);

            using (var scope = factory.Services.CreateScope())
            {
                var db = scope.ServiceProvider.GetRequiredService<HermesDbContext>();
                (await db.MediaLibraryRoots.AnyAsync()).Should().BeFalse();
                (await db.Movies.AnyAsync()).Should().BeFalse();
                (await db.Songs.AnyAsync()).Should().BeFalse();
                (await db.PlaylistTracks.AnyAsync()).Should().BeFalse();
                (await db.LikedSongs.AnyAsync()).Should().BeFalse();
            }
        }
        finally
        {
            if (Directory.Exists(tempRoot))
            {
                Directory.Delete(tempRoot, recursive: true);
            }
        }
    }

    private static async Task<HttpClient> CreateAuthenticatedAdminClientAsync(PostgresWebApplicationFactory factory)
    {
        var client = factory.CreateClient();
        await client.PostAsJsonAsync("/api/v1/setup", new SetupRequest("admin", "AdminPass!123", "Hermes Home"));
        var loginResponse = await client.PostAsJsonAsync(
            "/api/v1/auth/login",
            new LoginRequest("admin", "AdminPass!123", "admin-pc", "Desktop"));
        var login = await loginResponse.Content.ReadFromJsonAsync<AuthTokenResponse>();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", login!.AccessToken);
        return client;
    }
}
