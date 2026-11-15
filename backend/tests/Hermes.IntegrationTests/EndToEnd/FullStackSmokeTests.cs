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
using Hermes.Api.Features.System;
using Hermes.Domain.Enums;
using Hermes.IntegrationTests.Infrastructure;
using Microsoft.AspNetCore.Http.Connections;
using Microsoft.AspNetCore.SignalR.Client;
using Xunit;

namespace Hermes.IntegrationTests.EndToEnd;

public class FullStackSmokeTests
{
    [Fact]
    public async Task FullStackJourney_Setup_Invite_Scan_Stream_Transcode_Search_AndSignalRConnect_Succeeds()
    {
        var tempRoot = Path.Combine(Path.GetTempPath(), $"hermes-e2e-{Guid.NewGuid():N}");
        var moviesDir = Path.Combine(tempRoot, "movies");
        var musicDir = Path.Combine(tempRoot, "music");
        Directory.CreateDirectory(moviesDir);
        Directory.CreateDirectory(musicDir);

        var moviePath = Path.Combine(moviesDir, "Dune Part Two (2024) - 1080p.mp4");
        var srtPath = Path.Combine(moviesDir, "Dune Part Two (2024) - 1080p.srt");
        var songPath = Path.Combine(musicDir, "01 - Midnight City.mp3");

        await GenerateSyntheticMediaFilesAsync(moviePath, srtPath, songPath);

        try
        {
            await using var factory = new PostgresWebApplicationFactory();
            await factory.InitializeAsync();

            using var anonClient = factory.CreateClient();

            // 1. First-run setup check -> setup -> confirmed configured
            var preSetupInfo = await anonClient.GetFromJsonAsync<SystemInfoDto>("/api/v1/system/info");
            preSetupInfo.Should().NotBeNull();
            preSetupInfo!.SetupCompleted.Should().BeFalse();

            var setupResp = await anonClient.PostAsJsonAsync(
                "/api/v1/setup",
                new SetupRequest("admin", "AdminPass!123", "Hermes Cinema & Music"));
            setupResp.StatusCode.Should().Be(HttpStatusCode.Created);

            var postSetupInfo = await anonClient.GetFromJsonAsync<SystemInfoDto>("/api/v1/system/info");
            postSetupInfo!.SetupCompleted.Should().BeTrue();
            postSetupInfo.ServerName.Should().Be("Hermes Cinema & Music");

            // 2. Admin login + invite creation
            var adminLogin = await LoginAsync(anonClient, "admin", "AdminPass!123", "admin-pc", "Admin Workstation");
            using var adminClient = factory.CreateClient();
            adminClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", adminLogin.AccessToken);

            var inviteResp = await adminClient.PostAsJsonAsync(
                "/api/v1/admin/invites",
                new CreateInviteRequest(MaxUses: 1, ExpiresInHours: 24));
            inviteResp.StatusCode.Should().Be(HttpStatusCode.Created);
            var invite = await inviteResp.Content.ReadFromJsonAsync<InviteResponse>();
            invite.Should().NotBeNull();

            // 3. Member registration + multi-device login
            var registerResp = await anonClient.PostAsJsonAsync(
                "/api/v1/auth/register",
                new RegisterRequest("member1", "MemberPass!123", invite!.Code));
            registerResp.StatusCode.Should().Be(HttpStatusCode.Created);

            var memberDesktopAuth = await LoginAsync(anonClient, "member1", "MemberPass!123", "device-desktop", "Windows Desktop");
            var memberPhoneAuth = await LoginAsync(anonClient, "member1", "MemberPass!123", "device-phone", "Android Phone");

            using var memberClient = factory.CreateClient();
            memberClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", memberDesktopAuth.AccessToken);

            // 4. Admin registers & scans Movies + Music libraries
            var moviesLibResp = await adminClient.PostAsJsonAsync(
                "/api/v1/admin/libraries",
                new CreateLibraryRootRequest("Movies", LibraryMediaType.Movies, moviesDir, true));
            moviesLibResp.StatusCode.Should().Be(HttpStatusCode.Created);
            var moviesLib = await moviesLibResp.Content.ReadFromJsonAsync<LibraryRootResponse>();

            var musicLibResp = await adminClient.PostAsJsonAsync(
                "/api/v1/admin/libraries",
                new CreateLibraryRootRequest("Music", LibraryMediaType.Music, musicDir, true));
            musicLibResp.StatusCode.Should().Be(HttpStatusCode.Created);
            var musicLib = await musicLibResp.Content.ReadFromJsonAsync<LibraryRootResponse>();

            (await adminClient.PostAsync($"/api/v1/admin/libraries/{moviesLib!.Id}/scan", null))
                .EnsureSuccessStatusCode();
            (await adminClient.PostAsync($"/api/v1/admin/libraries/{musicLib!.Id}/scan", null))
                .EnsureSuccessStatusCode();

            // 5. Cinema catalog + stream ticket + DirectPlay Range 206 + WebVTT + HLS 480p transcode
            var movies = await memberClient.GetFromJsonAsync<List<MovieSummaryDto>>("/api/v1/cinema/movies");
            movies.Should().ContainSingle(m => m.Title == "Dune Part Two" && m.Year == 2024);
            var movie = movies![0];
            var movieSourceId = movie.Sources.Single().Id;

            var videoTicket = (await (await memberClient.PostAsJsonAsync(
                "/api/v1/auth/stream-tickets",
                new CreateStreamTicketRequest(movieSourceId)))
                .Content.ReadFromJsonAsync<StreamTicketResponse>())!.Ticket;
            var encodedVideoTicket = Uri.EscapeDataString(videoTicket);

            using (var rangeReq = new HttpRequestMessage(
                HttpMethod.Get,
                $"/api/v1/streams/{movieSourceId}/direct?ticket={encodedVideoTicket}"))
            {
                rangeReq.Headers.Range = new RangeHeaderValue(0, 63);
                using var directResp = await anonClient.SendAsync(rangeReq);
                directResp.StatusCode.Should().Be(HttpStatusCode.PartialContent);
                var chunk = await directResp.Content.ReadAsByteArrayAsync();
                chunk.Length.Should().Be(64);
            }

            using (var vttResp = await anonClient.GetAsync(
                $"/api/v1/streams/{movieSourceId}/subtitles/0.vtt?ticket={encodedVideoTicket}"))
            {
                vttResp.StatusCode.Should().Be(HttpStatusCode.OK);
                vttResp.Content.Headers.ContentType?.MediaType.Should().Be("text/vtt");
                var vttText = await vttResp.Content.ReadAsStringAsync();
                vttText.Should().StartWith("WEBVTT");
                vttText.Should().Contain("Long live the fighters.");
            }

            using (var hlsResp = await anonClient.GetAsync(
                $"/api/v1/streams/{movieSourceId}/video/master.m3u8?quality=P480&audioStreamIndex=1&startSeconds=0&ticket={encodedVideoTicket}"))
            {
                hlsResp.StatusCode.Should().Be(HttpStatusCode.OK);
                var playlist = await hlsResp.Content.ReadAsStringAsync();
                playlist.Should().Contain("#EXTM3U");
                var sessionId = hlsResp.Headers.GetValues("X-Hermes-Transcode-Session").Single();

                using var stopResp = await anonClient.DeleteAsync(
                    $"/api/v1/streams/{movieSourceId}/hls/{sessionId}?ticket={encodedVideoTicket}");
                stopResp.StatusCode.Should().Be(HttpStatusCode.NoContent);
            }

            // 6. Music catalog + audio Low64 transcode vs Lossless DirectPlay
            var songs = await memberClient.GetFromJsonAsync<List<SongDto>>("/api/v1/music/songs");
            songs.Should().ContainSingle(s => s.Title == "Midnight City" && s.ArtistName == "M83");
            var songId = songs![0].Id;

            var audioTicket = (await (await memberClient.PostAsJsonAsync(
                "/api/v1/auth/stream-tickets",
                new CreateStreamTicketRequest(songId)))
                .Content.ReadFromJsonAsync<StreamTicketResponse>())!.Ticket;
            var encodedAudioTicket = Uri.EscapeDataString(audioTicket);

            using (var low64Resp = await anonClient.GetAsync(
                $"/api/v1/streams/{songId}/audio?quality=Low64&ticket={encodedAudioTicket}"))
            {
                low64Resp.StatusCode.Should().Be(HttpStatusCode.OK);
                low64Resp.Headers.GetValues("X-Hermes-Delivery").Single().Should().Be("Transcoded");
                (await low64Resp.Content.ReadAsByteArrayAsync()).Should().NotBeEmpty();
            }

            using (var losslessResp = await anonClient.GetAsync(
                $"/api/v1/streams/{songId}/audio?quality=Lossless&ticket={encodedAudioTicket}"))
            {
                losslessResp.StatusCode.Should().Be(HttpStatusCode.OK);
                losslessResp.Headers.GetValues("X-Hermes-Delivery").Single().Should().Be("DirectPlay");
                (await losslessResp.Content.ReadAsByteArrayAsync()).Should().Equal(await File.ReadAllBytesAsync(songPath));
            }

            // 7. Unified pg_trgm/ILIKE search across both worlds
            var duneSearch = await memberClient.GetFromJsonAsync<UnifiedSearchResponse>("/api/v1/search?q=Dune");
            duneSearch!.Movies.Should().ContainSingle(m => m.Id == movie.Id);

            var midnightSearch = await memberClient.GetFromJsonAsync<UnifiedSearchResponse>("/api/v1/search?q=Midnight");
            midnightSearch!.Songs.Should().ContainSingle(s => s.Id == songId);

            // 8. SignalR v2 Connect + WatchProgress 95% auto-watched broadcast + disconnect auto-pause
            var watchProgressTcs = new TaskCompletionSource<WatchProgressUpdatedEvent>(TaskCreationOptions.RunContinuationsAsynchronously);
            var disconnectPausedTcs = new TaskCompletionSource<PlaybackSessionDto>(TaskCreationOptions.RunContinuationsAsynchronously);

            await using var desktopConn = BuildHubConnection(factory, memberDesktopAuth.AccessToken, "device-desktop", "Windows Desktop", "Windows");
            desktopConn.On<WatchProgressUpdatedEvent>("WatchProgressUpdated", wp => watchProgressTcs.TrySetResult(wp));
            desktopConn.On<PlaybackSessionDto>("SessionStateUpdated", session =>
            {
                if (session.Version >= 4 &&
                    session.State == PlaybackState.Paused &&
                    session.ActiveRendererDeviceId is null)
                {
                    disconnectPausedTcs.TrySetResult(session);
                }
            });

            await using var phoneConn = BuildHubConnection(factory, memberPhoneAuth.AccessToken, "device-phone", "Android Phone", "Android");

            await desktopConn.StartAsync();
            await phoneConn.StartAsync();

            var s1 = await desktopConn.InvokeAsync<PlaybackSessionDto>(
                "StartPlayback",
                new StartPlaybackCommand([songId], StartIndex: 0));
            s1.Version.Should().Be(1);
            s1.ActiveRendererDeviceId.Should().Be("device-desktop");
            s1.State.Should().Be(PlaybackState.Playing);

            var s2 = await phoneConn.InvokeAsync<PlaybackSessionDto>(
                "SendTransportCommand",
                new RemoteTransportCommand(PlaybackState.Paused, PositionMs: 1_000));
            s2.Version.Should().Be(2);
            s2.State.Should().Be(PlaybackState.Paused);
            s2.ActiveRendererDeviceId.Should().Be("device-desktop");

            var s3 = await desktopConn.InvokeAsync<PlaybackSessionDto>(
                "TransferOutput",
                new TransferOutputCommand("device-phone"));
            s3.Version.Should().Be(3);
            s3.ActiveRendererDeviceId.Should().Be("device-phone");

            var progressResp = await memberClient.PutAsJsonAsync(
                "/api/v1/cinema/progress",
                new UpdateWatchProgressRequest(MovieId: movie.Id, EpisodeId: null, PositionMs: 950_000, DurationMs: 1_000_000));
            progressResp.StatusCode.Should().Be(HttpStatusCode.OK);
            var progressDto = await progressResp.Content.ReadFromJsonAsync<WatchProgressDto>();
            progressDto!.IsWatched.Should().BeTrue();

            var progressBroadcast = await watchProgressTcs.Task.WaitAsync(TimeSpan.FromSeconds(5));
            progressBroadcast.MovieId.Should().Be(movie.Id);
            progressBroadcast.IsWatched.Should().BeTrue();

            var s3Playing = await desktopConn.InvokeAsync<PlaybackSessionDto>(
                "SendTransportCommand",
                new RemoteTransportCommand(PlaybackState.Playing));
            s3Playing.Version.Should().Be(4);
            s3Playing.ActiveRendererDeviceId.Should().Be("device-phone");

            await phoneConn.StopAsync();
            var autoPaused = await disconnectPausedTcs.Task.WaitAsync(TimeSpan.FromSeconds(5));
            autoPaused.Version.Should().Be(5);
            autoPaused.State.Should().Be(PlaybackState.Paused);
            autoPaused.ActiveRendererDeviceId.Should().BeNull();
        }
        finally
        {
            if (Directory.Exists(tempRoot))
            {
                Directory.Delete(tempRoot, recursive: true);
            }
        }
    }

    private static async Task GenerateSyntheticMediaFilesAsync(string moviePath, string srtPath, string songPath)
    {
        await RunFfmpegAsync([
            "-y", "-v", "error",
            "-f", "lavfi", "-i", "testsrc=duration=2:size=640x360:rate=24",
            "-f", "lavfi", "-i", "sine=frequency=880:duration=2",
            "-c:v", "libx264", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-b:a", "128k",
            moviePath
        ]);

        await File.WriteAllTextAsync(
            srtPath,
            "1\r\n00:00:00,500 --> 00:00:01,800\r\nLong live the fighters.\r\n");

        await RunFfmpegAsync([
            "-y", "-v", "error",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=2",
            "-c:a", "libmp3lame", "-b:a", "192k",
            "-id3v2_version", "3",
            "-metadata", "title=Midnight City",
            "-metadata", "artist=M83",
            "-metadata", "album=Hurry Up",
            "-metadata", "track=1/10",
            "-metadata", "date=2011",
            songPath
        ]);
    }

    private static async Task RunFfmpegAsync(IReadOnlyList<string> args)
    {
        using var process = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = "ffmpeg",
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            }
        };

        foreach (var arg in args)
        {
            process.StartInfo.ArgumentList.Add(arg);
        }

        process.Start().Should().BeTrue("ffmpeg must be available on PATH to generate synthetic test media");
        var stderr = await process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();
        process.ExitCode.Should().Be(0, $"ffmpeg failed: {stderr}");
    }

    private static HubConnection BuildHubConnection(
        PostgresWebApplicationFactory factory,
        string accessToken,
        string deviceId,
        string deviceName,
        string platform)
    {
        var url = $"{factory.Server.BaseAddress}hubs/sync" +
            $"?deviceId={Uri.EscapeDataString(deviceId)}" +
            $"&deviceName={Uri.EscapeDataString(deviceName)}" +
            $"&platform={Uri.EscapeDataString(platform)}";

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
        string deviceId,
        string deviceName)
    {
        var response = await client.PostAsJsonAsync(
            "/api/v1/auth/login",
            new LoginRequest(username, password, deviceId, deviceName));
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var auth = await response.Content.ReadFromJsonAsync<AuthTokenResponse>();
        auth.Should().NotBeNull();
        return auth!;
    }
}
