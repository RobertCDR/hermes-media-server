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
using Hermes.Infrastructure.Persistence;
using Hermes.IntegrationTests.Infrastructure;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace Hermes.IntegrationTests.Streaming;

public class StreamingEndpointsTests
{
    [Fact]
    public async Task DirectStream_SupportsHttpRange206_AndRejectsTicketBoundToDifferentMediaSource()
    {
        var tempMediaDir = Path.Combine(Path.GetTempPath(), $"hermes-stream-dir-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempMediaDir);
        var videoFile = Path.Combine(tempMediaDir, "Arrival (2016) - 1080p.mkv");
        var fileBytes = RandomNumberGenerator.GetBytes(256);
        await File.WriteAllBytesAsync(videoFile, fileBytes);

        try
        {
            await using var factory = new PostgresWebApplicationFactory();
            await factory.InitializeAsync();
            using var adminClient = await CreateAuthenticatedAdminClientAsync(factory);

            var lib = await (await adminClient.PostAsJsonAsync(
                "/api/v1/admin/libraries",
                new CreateLibraryRootRequest("Movies", LibraryMediaType.Movies, tempMediaDir, true)))
                .Content.ReadFromJsonAsync<LibraryRootResponse>();
            (await adminClient.PostAsync($"/api/v1/admin/libraries/{lib!.Id}/scan", null)).EnsureSuccessStatusCode();

            var movies = await adminClient.GetFromJsonAsync<List<MovieSummaryDto>>("/api/v1/cinema/movies");
            movies.Should().HaveCount(1);
            var sourceId = movies![0].Sources.Single().Id;

            var ticketDto = await (await adminClient.PostAsJsonAsync(
                "/api/v1/auth/stream-tickets",
                new CreateStreamTicketRequest(sourceId)))
                .Content.ReadFromJsonAsync<StreamTicketResponse>();

            using var anonymousClient = factory.CreateClient();
            using var rangeRequest = new HttpRequestMessage(
                HttpMethod.Get,
                $"/api/v1/streams/{sourceId}/direct?ticket={Uri.EscapeDataString(ticketDto!.Ticket)}");
            rangeRequest.Headers.Range = new RangeHeaderValue(0, 63);

            var rangeResponse = await anonymousClient.SendAsync(rangeRequest);
            rangeResponse.StatusCode.Should().Be(HttpStatusCode.PartialContent);
            var chunk = await rangeResponse.Content.ReadAsByteArrayAsync();
            chunk.Should().Equal(fileBytes[..64]);

            var otherSourceId = Guid.NewGuid();
            var wrongSourceResponse = await anonymousClient.GetAsync(
                $"/api/v1/streams/{otherSourceId}/direct?ticket={Uri.EscapeDataString(ticketDto.Ticket)}");
            wrongSourceResponse.StatusCode.Should().Be(HttpStatusCode.Forbidden);
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
    public async Task VideoHlsEndpoint_Returns429TranscodeSlotsExhausted_WhenConcurrentSlotsAreFull()
    {
        var tempMediaDir = Path.Combine(Path.GetTempPath(), $"hermes-hls-slots-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempMediaDir);
        var videoFile = Path.Combine(tempMediaDir, "Interstellar (2014) - 1080p.mkv");
        await File.WriteAllBytesAsync(videoFile, [0x01, 0x02, 0x03, 0x04]);

        try
        {
            await using var factory = new PostgresWebApplicationFactory();
            await factory.InitializeAsync();
            using var adminClient = await CreateAuthenticatedAdminClientAsync(factory);

            var lib = await (await adminClient.PostAsJsonAsync(
                "/api/v1/admin/libraries",
                new CreateLibraryRootRequest("Movies", LibraryMediaType.Movies, tempMediaDir, true)))
                .Content.ReadFromJsonAsync<LibraryRootResponse>();
            (await adminClient.PostAsync($"/api/v1/admin/libraries/{lib!.Id}/scan", null)).EnsureSuccessStatusCode();

            var movies = await adminClient.GetFromJsonAsync<List<MovieSummaryDto>>("/api/v1/cinema/movies");
            var sourceId = movies![0].Sources.Single().Id;
            var ticket = (await (await adminClient.PostAsJsonAsync(
                "/api/v1/auth/stream-tickets",
                new CreateStreamTicketRequest(sourceId)))
                .Content.ReadFromJsonAsync<StreamTicketResponse>())!.Ticket;
            var encodedTicket = Uri.EscapeDataString(ticket);

            using var anonymousClient = factory.CreateClient();
            var resp1 = await anonymousClient.GetAsync($"/api/v1/streams/{sourceId}/video/master.m3u8?quality=P720&audioStreamIndex=1&startSeconds=0&ticket={encodedTicket}");
            var resp2 = await anonymousClient.GetAsync($"/api/v1/streams/{sourceId}/video/master.m3u8?quality=P480&audioStreamIndex=1&startSeconds=0&ticket={encodedTicket}");
            var resp3 = await anonymousClient.GetAsync($"/api/v1/streams/{sourceId}/video/master.m3u8?quality=P1080&audioStreamIndex=1&startSeconds=0&ticket={encodedTicket}");

            resp1.StatusCode.Should().Be(HttpStatusCode.OK);
            resp2.StatusCode.Should().Be(HttpStatusCode.OK);
            resp3.StatusCode.Should().Be(HttpStatusCode.TooManyRequests);
            (await resp3.Content.ReadAsStringAsync()).Should().Contain("transcode_slots_exhausted");

            var session1Id = resp1.Headers.GetValues("X-Hermes-Transcode-Session").Single();
            var stopResp = await anonymousClient.DeleteAsync($"/api/v1/streams/{sourceId}/hls/{session1Id}?ticket={encodedTicket}");
            stopResp.StatusCode.Should().Be(HttpStatusCode.NoContent);

            var resp4 = await anonymousClient.GetAsync($"/api/v1/streams/{sourceId}/video/master.m3u8?quality=P1080&audioStreamIndex=1&startSeconds=0&ticket={encodedTicket}");
            resp4.StatusCode.Should().Be(HttpStatusCode.OK);
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
    public async Task AudioStream_FallsBackToDirectPlayWithoutUpscaling_WhenSourceBitrateNotAboveTarget()
    {
        var tempMusicDir = Path.Combine(Path.GetTempPath(), $"hermes-music-dir-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempMusicDir);
        var mp3Path = Path.Combine(tempMusicDir, "track128.mp3");
        var mp3Bytes = RandomNumberGenerator.GetBytes(128);
        await File.WriteAllBytesAsync(mp3Path, mp3Bytes);

        try
        {
            await using var factory = new PostgresWebApplicationFactory();
            await factory.InitializeAsync();
            using var adminClient = await CreateAuthenticatedAdminClientAsync(factory);

            Guid songId;
            using (var scope = factory.Services.CreateScope())
            {
                var db = scope.ServiceProvider.GetRequiredService<HermesDbContext>();
                var root = new MediaLibraryRoot("Music", LibraryMediaType.Music, tempMusicDir, true);
                var artist = new Artist("Synth Artist");
                var album = new Album(artist.Id, "Synth Album", 2024);
                var song = new Song(root.Id, artist.Id, album.Id, "Midnight Signal", 1, 1, 180_000, mp3Path, "mp3", 128_000, 44_100, 16, mp3Bytes.Length, DateTimeOffset.UtcNow);

                db.MediaLibraryRoots.Add(root);
                db.Artists.Add(artist);
                db.Albums.Add(album);
                db.Songs.Add(song);
                await db.SaveChangesAsync();
                songId = song.Id;
            }

            var ticket = (await (await adminClient.PostAsJsonAsync(
                "/api/v1/auth/stream-tickets",
                new CreateStreamTicketRequest(songId)))
                .Content.ReadFromJsonAsync<StreamTicketResponse>())!.Ticket;

            using var anonymousClient = factory.CreateClient();
            var response = await anonymousClient.GetAsync(
                $"/api/v1/streams/{songId}/audio?quality=VeryHigh320&ticket={Uri.EscapeDataString(ticket)}");

            response.StatusCode.Should().Be(HttpStatusCode.OK);
            response.Headers.GetValues("X-Hermes-Delivery").Single().Should().Be("DirectPlay");
            (await response.Content.ReadAsByteArrayAsync()).Should().Equal(mp3Bytes);
        }
        finally
        {
            if (Directory.Exists(tempMusicDir))
            {
                Directory.Delete(tempMusicDir, recursive: true);
            }
        }
    }

    [Fact]
    public async Task SubtitlesEndpoint_ConvertsExternalSrtToWebVtt()
    {
        var tempMediaDir = Path.Combine(Path.GetTempPath(), $"hermes-subs-dir-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempMediaDir);
        var videoFile = Path.Combine(tempMediaDir, "Blade Runner 2049 (2017) - 1080p.mkv");
        var srtFile = Path.Combine(tempMediaDir, "Blade Runner 2049 (2017) - 1080p.srt");
        await File.WriteAllBytesAsync(videoFile, [0x01, 0x02]);
        await File.WriteAllTextAsync(srtFile, "1\r\n00:00:01,500 --> 00:00:04,250\r\nCells interlinked.\r\n");

        try
        {
            await using var factory = new PostgresWebApplicationFactory();
            await factory.InitializeAsync();
            using var adminClient = await CreateAuthenticatedAdminClientAsync(factory);

            var lib = await (await adminClient.PostAsJsonAsync(
                "/api/v1/admin/libraries",
                new CreateLibraryRootRequest("Movies", LibraryMediaType.Movies, tempMediaDir, true)))
                .Content.ReadFromJsonAsync<LibraryRootResponse>();
            (await adminClient.PostAsync($"/api/v1/admin/libraries/{lib!.Id}/scan", null)).EnsureSuccessStatusCode();

            var movies = await adminClient.GetFromJsonAsync<List<MovieSummaryDto>>("/api/v1/cinema/movies");
            var sourceId = movies![0].Sources.Single().Id;
            var ticket = (await (await adminClient.PostAsJsonAsync(
                "/api/v1/auth/stream-tickets",
                new CreateStreamTicketRequest(sourceId)))
                .Content.ReadFromJsonAsync<StreamTicketResponse>())!.Ticket;

            using var anonymousClient = factory.CreateClient();
            var vttResponse = await anonymousClient.GetAsync(
                $"/api/v1/streams/{sourceId}/subtitles/0.vtt?ticket={Uri.EscapeDataString(ticket)}");

            vttResponse.StatusCode.Should().Be(HttpStatusCode.OK);
            vttResponse.Content.Headers.ContentType?.MediaType.Should().Be("text/vtt");
            var vtt = await vttResponse.Content.ReadAsStringAsync();
            vtt.Should().StartWith("WEBVTT");
            vtt.Should().Contain("00:00:01.500 --> 00:00:04.250");
            vtt.Should().Contain("Cells interlinked.");
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
    public async Task PutWatchProgress_EnforcesNinetyPercentAutoWatchedInvariant_AndPersistsPerUser()
    {
        var tempMediaDir = Path.Combine(Path.GetTempPath(), $"hermes-prog-dir-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempMediaDir);
        await File.WriteAllBytesAsync(Path.Combine(tempMediaDir, "Solaris (1972) - 1080p.mkv"), [0x01, 0x02]);

        try
        {
            await using var factory = new PostgresWebApplicationFactory();
            await factory.InitializeAsync();
            using var adminClient = await CreateAuthenticatedAdminClientAsync(factory);

            var lib = await (await adminClient.PostAsJsonAsync(
                "/api/v1/admin/libraries",
                new CreateLibraryRootRequest("Movies", LibraryMediaType.Movies, tempMediaDir, true)))
                .Content.ReadFromJsonAsync<LibraryRootResponse>();
            (await adminClient.PostAsync($"/api/v1/admin/libraries/{lib!.Id}/scan", null)).EnsureSuccessStatusCode();

            var movies = await adminClient.GetFromJsonAsync<List<MovieSummaryDto>>("/api/v1/cinema/movies");
            var movieId = movies![0].Id;

            var halfResponse = await adminClient.PutAsJsonAsync(
                "/api/v1/cinema/progress",
                new UpdateWatchProgressRequest(MovieId: movieId, EpisodeId: null, PositionMs: 500_000, DurationMs: 1_000_000));
            halfResponse.StatusCode.Should().Be(HttpStatusCode.OK);
            var halfProgress = await halfResponse.Content.ReadFromJsonAsync<WatchProgressDto>();
            halfProgress!.IsWatched.Should().BeFalse();

            var completedResponse = await adminClient.PutAsJsonAsync(
                "/api/v1/cinema/progress",
                new UpdateWatchProgressRequest(MovieId: movieId, EpisodeId: null, PositionMs: 910_000, DurationMs: 1_000_000));
            completedResponse.StatusCode.Should().Be(HttpStatusCode.OK);
            var completedProgress = await completedResponse.Content.ReadFromJsonAsync<WatchProgressDto>();
            completedProgress!.IsWatched.Should().BeTrue();

            var updatedMovies = await adminClient.GetFromJsonAsync<List<MovieSummaryDto>>("/api/v1/cinema/movies");
            var updatedMovie = updatedMovies!.Single();
            updatedMovie.WatchProgress.Should().NotBeNull();
            updatedMovie.WatchProgress!.IsWatched.Should().BeTrue();
            updatedMovie.WatchProgress.PositionMs.Should().Be(910_000);
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
    public async Task HlsEndpoints_RejectCrossUserAssetReadAndSessionStop_WithoutStoppingOwnerSession()
    {
        var tempMediaDir = Path.Combine(Path.GetTempPath(), $"hermes-hls-idor-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempMediaDir);
        await File.WriteAllBytesAsync(Path.Combine(tempMediaDir, "Dune (2021) - 1080p.mkv"), [0x01, 0x02, 0x03, 0x04]);

        try
        {
            await using var factory = new PostgresWebApplicationFactory();
            await factory.InitializeAsync();
            using var ownerClient = await CreateAuthenticatedAdminClientAsync(factory);

            var lib = await (await ownerClient.PostAsJsonAsync(
                "/api/v1/admin/libraries",
                new CreateLibraryRootRequest("Movies", LibraryMediaType.Movies, tempMediaDir, WatchEnabled: false, FetchMetadata: false)))
                .Content.ReadFromJsonAsync<LibraryRootResponse>();
            (await ownerClient.PostAsync($"/api/v1/admin/libraries/{lib!.Id}/scan", null)).EnsureSuccessStatusCode();

            var movies = await ownerClient.GetFromJsonAsync<List<MovieSummaryDto>>("/api/v1/cinema/movies");
            var sourceId = movies!.Single().Sources.Single().Id;

            // Create second user ("attacker").
            var invite = await (await ownerClient.PostAsJsonAsync("/api/v1/admin/invites", new CreateInviteRequest(1, 24)))
                .Content.ReadFromJsonAsync<InviteResponse>();
            using var attackerClient = factory.CreateClient();
            (await attackerClient.PostAsJsonAsync(
                "/api/v1/auth/register",
                new RegisterRequest("bob", "BobPass!123", invite!.Code))).EnsureSuccessStatusCode();
            var bobLogin = await (await attackerClient.PostAsJsonAsync(
                "/api/v1/auth/login",
                new LoginRequest("bob", "BobPass!123", "bob-pc", "Desktop"))).Content.ReadFromJsonAsync<AuthTokenResponse>();
            attackerClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", bobLogin!.AccessToken);

            var ownerTicket = (await (await ownerClient.PostAsJsonAsync(
                "/api/v1/auth/stream-tickets",
                new CreateStreamTicketRequest(sourceId))).Content.ReadFromJsonAsync<StreamTicketResponse>())!.Ticket;
            var attackerTicket = (await (await attackerClient.PostAsJsonAsync(
                "/api/v1/auth/stream-tickets",
                new CreateStreamTicketRequest(sourceId))).Content.ReadFromJsonAsync<StreamTicketResponse>())!.Ticket;

            using var anonymousClient = factory.CreateClient();
            var startResp = await anonymousClient.GetAsync(
                $"/api/v1/streams/{sourceId}/video/master.m3u8?quality=P720&audioStreamIndex=1&startSeconds=0&ticket={Uri.EscapeDataString(ownerTicket)}");
            startResp.StatusCode.Should().Be(HttpStatusCode.OK);
            startResp.Headers.CacheControl?.NoStore.Should().BeTrue();
            var sessionId = startResp.Headers.GetValues("X-Hermes-Transcode-Session").Single();

            // User B must neither read User A's HLS playlist/segments nor stop User A's session.
            var attackerAssetResp = await anonymousClient.GetAsync(
                $"/api/v1/streams/{sourceId}/hls/{sessionId}/index.m3u8?ticket={Uri.EscapeDataString(attackerTicket)}");
            attackerAssetResp.StatusCode.Should().Be(HttpStatusCode.NotFound);

            var attackerStopResp = await anonymousClient.DeleteAsync(
                $"/api/v1/streams/{sourceId}/hls/{sessionId}?ticket={Uri.EscapeDataString(attackerTicket)}");
            attackerStopResp.StatusCode.Should().Be(HttpStatusCode.NotFound);

            // Owner session remains alive and readable.
            var ownerPlaylistResp = await anonymousClient.GetAsync(
                $"/api/v1/streams/{sourceId}/hls/{sessionId}/index.m3u8?ticket={Uri.EscapeDataString(ownerTicket)}");
            ownerPlaylistResp.StatusCode.Should().Be(HttpStatusCode.OK);
            ownerPlaylistResp.Headers.CacheControl?.NoStore.Should().BeTrue();

            var ownerStopResp = await anonymousClient.DeleteAsync(
                $"/api/v1/streams/{sourceId}/hls/{sessionId}?ticket={Uri.EscapeDataString(ownerTicket)}");
            ownerStopResp.StatusCode.Should().Be(HttpStatusCode.NoContent);
        }
        finally
        {
            if (Directory.Exists(tempMediaDir))
            {
                Directory.Delete(tempMediaDir, recursive: true);
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
