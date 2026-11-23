using System.Collections.Concurrent;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using FluentAssertions;
using Hermes.Api.Features.Admin;
using Hermes.Api.Features.Auth;
using Hermes.Api.Features.Music;
using Hermes.Api.Features.Setup;
using Hermes.Domain.Entities;
using Hermes.Domain.Enums;
using Hermes.Infrastructure.Persistence;
using Hermes.IntegrationTests.Infrastructure;
using Microsoft.AspNetCore.Http.Connections;
using Microsoft.AspNetCore.SignalR.Client;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace Hermes.IntegrationTests.Security;

public class SecurityAndCoverageGapsTests
{
    [Fact]
    public async Task NonAdmin_IsForbidden_OnAllAdminEndpoints_AndDeactivatedUserIsRejectedEverywhere()
    {
        await using var factory = new PostgresWebApplicationFactory();
        await factory.InitializeAsync();

        using var anonClient = factory.CreateClient();
        (await anonClient.PostAsJsonAsync("/api/v1/setup", new SetupRequest("admin", "AdminPass!123", "Hermes Home")))
            .StatusCode.Should().Be(HttpStatusCode.Created);

        var adminLogin = await LoginAsync(anonClient, "admin", "AdminPass!123", "admin-pc");
        using var adminClient = factory.CreateClient();
        adminClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", adminLogin.AccessToken);

        var invite = await (await adminClient.PostAsJsonAsync("/api/v1/admin/invites", new CreateInviteRequest(1, 24)))
            .Content.ReadFromJsonAsync<InviteResponse>();
        (await anonClient.PostAsJsonAsync("/api/v1/auth/register", new RegisterRequest("member", "MemberPass!123", invite!.Code)))
            .StatusCode.Should().Be(HttpStatusCode.Created);

        var memberLogin = await LoginAsync(anonClient, "member", "MemberPass!123", "member-phone");
        using var memberClient = factory.CreateClient();
        memberClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", memberLogin.AccessToken);

        // Non-admin receives 403 Forbidden on admin management endpoints
        (await memberClient.GetAsync("/api/v1/admin/libraries")).StatusCode.Should().Be(HttpStatusCode.Forbidden);
        (await memberClient.GetAsync("/api/v1/admin/users")).StatusCode.Should().Be(HttpStatusCode.Forbidden);
        (await memberClient.GetAsync("/api/v1/admin/invites")).StatusCode.Should().Be(HttpStatusCode.Forbidden);
        (await memberClient.GetAsync("/api/v1/admin/settings")).StatusCode.Should().Be(HttpStatusCode.Forbidden);
        (await memberClient.GetAsync("/api/v1/admin/sessions")).StatusCode.Should().Be(HttpStatusCode.Forbidden);

        // Before deactivation, protected endpoints accept member JWT
        (await memberClient.GetAsync("/api/v1/cinema/movies")).StatusCode.Should().Be(HttpStatusCode.OK);

        // Admin deactivates member user
        (await adminClient.DeleteAsync($"/api/v1/admin/users/{memberLogin.UserId}"))
            .StatusCode.Should().Be(HttpStatusCode.NoContent);

        // Deactivated user's JWT is rejected on API endpoints, stream ticket minting, and SignalR /hubs/sync
        (await memberClient.GetAsync("/api/v1/cinema/movies")).StatusCode.Should().Be(HttpStatusCode.Unauthorized);
        (await memberClient.PostAsJsonAsync("/api/v1/auth/stream-tickets", new CreateStreamTicketRequest(Guid.NewGuid())))
            .StatusCode.Should().Be(HttpStatusCode.Unauthorized);

        await using var hubConn = BuildHubConnection(factory, memberLogin.AccessToken, "member-phone");
        Func<Task> connectAct = () => hubConn.StartAsync();
        await connectAct.Should().ThrowAsync<Exception>();
    }

    [Fact]
    public async Task AdminStopSession_PlaybackReportProgress_AndFeaturedArtistCredits_WorkEndToEnd()
    {
        await using var factory = new PostgresWebApplicationFactory();
        await factory.InitializeAsync();

        using var anonClient = factory.CreateClient();
        (await anonClient.PostAsJsonAsync("/api/v1/setup", new SetupRequest("admin", "AdminPass!123", "Hermes Home")))
            .StatusCode.Should().Be(HttpStatusCode.Created);
        var login = await LoginAsync(anonClient, "admin", "AdminPass!123", "desktop-pc");

        using var adminClient = factory.CreateClient();
        adminClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", login.AccessToken);

        Guid featuredArtistId;
        Guid songId;
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<HermesDbContext>();
            var musicLib = new MediaLibraryRoot("Music", LibraryMediaType.Music, "/tmp/music-gap", false);
            var primaryArtist = new Artist("Daft Punk");
            var featuredArtist = new Artist("Pharrell Williams");
            var album = new Album(primaryArtist.Id, "RAM", 2013, null);
            var song = new Song(
                musicLib.Id,
                primaryArtist.Id,
                album.Id,
                "Get Lucky",
                8,
                1,
                248_000,
                "/tmp/music-gap/get-lucky.flac",
                "flac",
                1_000_000,
                44_100,
                24,
                10_000_000,
                DateTimeOffset.UtcNow);
            db.MediaLibraryRoots.Add(musicLib);
            db.Artists.AddRange(primaryArtist, featuredArtist);
            db.Albums.Add(album);
            db.Songs.Add(song);
            db.SongArtists.AddRange(
                new SongArtist(song.Id, primaryArtist.Id, 0),
                new SongArtist(song.Id, featuredArtist.Id, 1));
            await db.SaveChangesAsync();

            featuredArtistId = featuredArtist.Id;
            songId = song.Id;
        }

        // Featured artist page includes collaborator track via SongArtists join
        var featuredDetail = await adminClient.GetFromJsonAsync<ArtistDetailDto>($"/api/v1/music/artists/{featuredArtistId}");
        featuredDetail.Should().NotBeNull();
        featuredDetail!.Name.Should().Be("Pharrell Williams");
        featuredDetail.Songs.Should().ContainSingle(s => s.Id == songId && s.Title == "Get Lucky");

        await using var hubConn = BuildHubConnection(factory, login.AccessToken, "desktop-pc");
        var stoppedTcs = new TaskCompletionSource<PlaybackSessionDto>(TaskCreationOptions.RunContinuationsAsynchronously);
        var updates = new ConcurrentQueue<PlaybackSessionDto>();
        hubConn.On<PlaybackSessionDto>("SessionStateUpdated", dto =>
        {
            updates.Enqueue(dto);
            if (dto.State == PlaybackState.Stopped && dto.Version >= 2)
            {
                stoppedTcs.TrySetResult(dto);
            }
        });
        await hubConn.StartAsync();

        var started = await hubConn.InvokeAsync<PlaybackSessionDto>(
            "StartPlayback",
            new StartPlaybackCommand([songId], 0));
        started.State.Should().Be(PlaybackState.Playing);

        // Hub.ReportProgress updates live PositionMs
        await hubConn.InvokeAsync("ReportProgress", new ProgressHeartbeatCommand(42_500));
        var polledSession = await adminClient.GetFromJsonAsync<PlaybackSessionDto>("/api/v1/music/session");
        polledSession.Should().NotBeNull();
        polledSession!.PositionMs.Should().Be(42_500);

        // Admin stops music session -> persists Stopped and broadcasts SessionStateUpdated over SignalR
        var stopResp = await adminClient.DeleteAsync($"/api/v1/admin/sessions/music:{started.SessionId}");
        stopResp.StatusCode.Should().Be(HttpStatusCode.NoContent);

        var broadcastStopped = await stoppedTcs.Task.WaitAsync(TimeSpan.FromSeconds(5));
        broadcastStopped.State.Should().Be(PlaybackState.Stopped);

        var afterStop = await adminClient.GetFromJsonAsync<PlaybackSessionDto>("/api/v1/music/session");
        afterStop!.State.Should().Be(PlaybackState.Stopped);
    }

    private static HubConnection BuildHubConnection(
        PostgresWebApplicationFactory factory,
        string accessToken,
        string deviceId)
    {
        var url = $"{factory.Server.BaseAddress}hubs/sync" +
            $"?deviceId={Uri.EscapeDataString(deviceId)}" +
            "&deviceName=TestDevice&platform=Windows";

        return new HubConnectionBuilder()
            .WithUrl(url, options =>
            {
                options.HttpMessageHandlerFactory = _ => factory.Server.CreateHandler();
                options.WebSocketFactory = async (context, cancellationToken) =>
                    await factory.Server.CreateWebSocketClient().ConnectAsync(context.Uri, cancellationToken);
                options.Transports = HttpTransportType.WebSockets | HttpTransportType.ServerSentEvents | HttpTransportType.LongPolling;
                options.AccessTokenProvider = () => Task.FromResult<string?>(accessToken);
            })
            .Build();
    }

    private static async Task<AuthTokenResponse> LoginAsync(
        HttpClient client,
        string username,
        string password,
        string deviceId)
    {
        var resp = await client.PostAsJsonAsync("/api/v1/auth/login", new LoginRequest(username, password, deviceId, "Desktop"));
        resp.StatusCode.Should().Be(HttpStatusCode.OK);
        return (await resp.Content.ReadFromJsonAsync<AuthTokenResponse>())!;
    }
}
