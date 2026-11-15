using System.Collections.Concurrent;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using FluentAssertions;
using Hermes.Api.Features.Auth;
using Hermes.Api.Features.Cinema;
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

namespace Hermes.IntegrationTests.Realtime;

public class PlaybackHubIntegrationTests
{
    [Fact]
    public async Task MusicCatalog_Search_Playlists_And_LikedSongs_WorkEndToEnd()
    {
        await using var factory = new PostgresWebApplicationFactory();
        await factory.InitializeAsync();

        var (client, _) = await CreateAuthenticatedUserClientAsync(factory, "admin", "AdminPass!123");

        Guid artistId;
        Guid albumId;
        Guid song1Id;
        Guid song2Id;
        Guid movieId;

        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<HermesDbContext>();
            var now = DateTimeOffset.UtcNow;

            var movieLib = new MediaLibraryRoot("Movies", LibraryMediaType.Movies, "/tmp/movies", true);
            var musicLib = new MediaLibraryRoot("Music", LibraryMediaType.Music, "/tmp/music", true);
            db.MediaLibraryRoots.AddRange(movieLib, musicLib);

            var movie = new Movie(movieLib.Id, "Interstellar Odyssey", 2014);
            var series = new TvSeries(movieLib.Id, "Interstellar Chronicles", 2022);
            db.Movies.Add(movie);
            db.TvSeries.Add(series);

            var artist = new Artist("Hans Stellar");
            var album = new Album(artist.Id, "Orbital Horizon", 2014, "art-hash-1");
            artist.Albums.Add(album);

            var song1 = new Song(
                musicLib.Id,
                artist.Id,
                album.Id,
                "Interstellar Cornfield Chase",
                1,
                1,
                126_000,
                "/tmp/music/cornfield.flac",
                "flac",
                1_411_000,
                44_100,
                16,
                25_000_000,
                now);
            var song2 = new Song(
                musicLib.Id,
                artist.Id,
                album.Id,
                "No Time For Caution",
                2,
                1,
                246_000,
                "/tmp/music/caution.flac",
                "flac",
                1_411_000,
                44_100,
                16,
                45_000_000,
                now);

            db.Artists.Add(artist);
            db.Albums.Add(album);
            db.Songs.AddRange(song1, song2);
            await db.SaveChangesAsync();

            artistId = artist.Id;
            albumId = album.Id;
            song1Id = song1.Id;
            song2Id = song2.Id;
            movieId = movie.Id;
        }

        // Artists, albums, songs endpoints
        var artists = await client.GetFromJsonAsync<List<ArtistSummaryDto>>("/api/v1/music/artists");
        artists.Should().ContainSingle(a => a.Id == artistId && a.Name == "Hans Stellar" && a.AlbumCount == 1);

        var albumDetail = await client.GetFromJsonAsync<AlbumDetailDto>($"/api/v1/music/albums/{albumId}");
        albumDetail.Should().NotBeNull();
        albumDetail!.Songs.Select(s => s.Title).Should().ContainInOrder("Interstellar Cornfield Chase", "No Time For Caution");

        var songs = await client.GetFromJsonAsync<List<SongDto>>("/api/v1/music/songs");
        songs.Should().HaveCount(2);

        // Like toggle & liked listing
        var likeResp1 = await client.PostAsync($"/api/v1/music/songs/{song1Id}/like", null);
        likeResp1.StatusCode.Should().Be(HttpStatusCode.OK);
        var liked1 = await likeResp1.Content.ReadFromJsonAsync<LikeToggleResponse>();
        liked1!.IsLiked.Should().BeTrue();

        var likedSongs = await client.GetFromJsonAsync<List<SongDto>>("/api/v1/music/songs/liked");
        likedSongs.Should().ContainSingle(s => s.Id == song1Id && s.IsLiked);

        // Toggle off and back on
        var likeResp2 = await client.PostAsync($"/api/v1/music/songs/{song1Id}/like", null);
        (await likeResp2.Content.ReadFromJsonAsync<LikeToggleResponse>())!.IsLiked.Should().BeFalse();
        (await client.GetFromJsonAsync<List<SongDto>>("/api/v1/music/songs/liked")).Should().BeEmpty();

        // Playlists CRUD + track compaction on delete
        var createPlaylistResp = await client.PostAsJsonAsync(
            "/api/v1/music/playlists",
            new CreatePlaylistRequest("Midnight Sci-Fi", "Instrumental OST"));
        createPlaylistResp.StatusCode.Should().Be(HttpStatusCode.Created);
        var playlist = await createPlaylistResp.Content.ReadFromJsonAsync<PlaylistDetailDto>();
        playlist.Should().NotBeNull();

        (await client.PostAsJsonAsync($"/api/v1/music/playlists/{playlist!.Id}/tracks", new AddPlaylistTrackRequest(song1Id)))
            .StatusCode.Should().Be(HttpStatusCode.OK);
        (await client.PostAsJsonAsync($"/api/v1/music/playlists/{playlist.Id}/tracks", new AddPlaylistTrackRequest(song2Id)))
            .StatusCode.Should().Be(HttpStatusCode.OK);

        var playlistAfterAdd = await client.GetFromJsonAsync<PlaylistDetailDto>($"/api/v1/music/playlists/{playlist.Id}");
        playlistAfterAdd!.Tracks.Should().HaveCount(2);
        playlistAfterAdd.Tracks.Select(t => (t.Position, t.Song.Id)).Should().ContainInOrder((0, song1Id), (1, song2Id));

        var removeResp = await client.DeleteAsync($"/api/v1/music/playlists/{playlist.Id}/tracks/0");
        removeResp.StatusCode.Should().Be(HttpStatusCode.OK);
        var playlistAfterDelete = await removeResp.Content.ReadFromJsonAsync<PlaylistDetailDto>();
        playlistAfterDelete!.Tracks.Should().ContainSingle(t => t.Position == 0 && t.Song.Id == song2Id);

        // Unified native SQL pg_trgm/ILike search across Movies, TvSeries, Artists, Albums, Songs
        var searchResp = await client.GetFromJsonAsync<UnifiedSearchResponse>("/api/v1/search?q=interstellar");
        searchResp.Should().NotBeNull();
        searchResp!.Movies.Should().ContainSingle(m => m.Id == movieId);
        searchResp.Series.Should().ContainSingle(s => s.Title == "Interstellar Chronicles");
        searchResp.Songs.Should().ContainSingle(s => s.Id == song1Id);
    }

    [Fact]
    public async Task SignalR_ConnectSync_MonotonicVersion_RemoteControlPreservesRenderer_TransferOutput_AndAutoPausesOnRendererDisconnect()
    {
        await using var factory = new PostgresWebApplicationFactory();
        await factory.InitializeAsync();

        var (client, accessToken) = await CreateAuthenticatedUserClientAsync(factory, "admin", "AdminPass!123");

        Guid song1Id;
        Guid song2Id;
        Guid movieId;

        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<HermesDbContext>();
            var now = DateTimeOffset.UtcNow;

            var movieLib = new MediaLibraryRoot("Movies", LibraryMediaType.Movies, "/tmp/movies2", true);
            var musicLib = new MediaLibraryRoot("Music", LibraryMediaType.Music, "/tmp/music2", true);
            db.MediaLibraryRoots.AddRange(movieLib, musicLib);

            var movie = new Movie(movieLib.Id, "Solaris", 1972);
            db.Movies.Add(movie);

            var artist = new Artist("M83");
            var album = new Album(artist.Id, "Hurry Up", 2011);
            artist.Albums.Add(album);

            var song1 = new Song(musicLib.Id, artist.Id, album.Id, "Intro", 1, 1, 320_000, "/tmp/m83-1.flac", "flac", 1_400_000, 44_100, 16, 30_000_000, now);
            var song2 = new Song(musicLib.Id, artist.Id, album.Id, "Midnight City", 2, 1, 244_000, "/tmp/m83-2.flac", "flac", 1_400_000, 44_100, 16, 28_000_000, now);
            db.Artists.Add(artist);
            db.Albums.Add(album);
            db.Songs.AddRange(song1, song2);
            await db.SaveChangesAsync();

            song1Id = song1.Id;
            song2Id = song2.Id;
            movieId = movie.Id;
        }

        var desktopUpdates = new ConcurrentQueue<PlaybackSessionDto>();
        var phoneUpdates = new ConcurrentQueue<PlaybackSessionDto>();
        var desktopDevicesUpdates = new ConcurrentQueue<List<OnlineDeviceDto>>();
        var watchProgressTcs = new TaskCompletionSource<WatchProgressUpdatedEvent>(TaskCreationOptions.RunContinuationsAsynchronously);
        var disconnectPausedTcs = new TaskCompletionSource<PlaybackSessionDto>(TaskCreationOptions.RunContinuationsAsynchronously);

        await using var desktopConn = BuildHubConnection(factory, accessToken, "device-desktop", "Workstation PC", "Windows");
        desktopConn.On<PlaybackSessionDto>("SessionStateUpdated", dto =>
        {
            desktopUpdates.Enqueue(dto);
            if (dto.Version == 5 && dto.State == PlaybackState.Paused && dto.ActiveRendererDeviceId is null)
            {
                disconnectPausedTcs.TrySetResult(dto);
            }
        });
        desktopConn.On<List<OnlineDeviceDto>>("DevicesUpdated", devices => desktopDevicesUpdates.Enqueue(devices));
        desktopConn.On<WatchProgressUpdatedEvent>("WatchProgressUpdated", wp => watchProgressTcs.TrySetResult(wp));

        await using var phoneConn = BuildHubConnection(factory, accessToken, "device-phone", "Pixel 9", "Android");
        phoneConn.On<PlaybackSessionDto>("SessionStateUpdated", dto => phoneUpdates.Enqueue(dto));

        await desktopConn.StartAsync();
        await phoneConn.StartAsync();

        var onlineDevices = await desktopConn.InvokeAsync<List<OnlineDeviceDto>>("GetOnlineDevices");
        onlineDevices.Select(d => d.DeviceId).Should().BeEquivalentTo(["device-desktop", "device-phone"]);

        // 1. Desktop starts playback -> Version = 1, ActiveRenderer = device-desktop
        var s1 = await desktopConn.InvokeAsync<PlaybackSessionDto>(
            "StartPlayback",
            new StartPlaybackCommand([song1Id, song2Id], StartIndex: 0));
        s1.Version.Should().Be(1);
        s1.ActiveRendererDeviceId.Should().Be("device-desktop");
        s1.State.Should().Be(PlaybackState.Playing);
        s1.CurrentSongId.Should().Be(song1Id);

        // 2. Phone sends remote transport command -> Version = 2, ActiveRenderer stays device-desktop
        var s2 = await phoneConn.InvokeAsync<PlaybackSessionDto>(
            "SendTransportCommand",
            new RemoteTransportCommand(PlaybackState.Paused, CurrentIndex: 1, PositionMs: 45_000));
        s2.Version.Should().Be(2);
        s2.State.Should().Be(PlaybackState.Paused);
        s2.CurrentSongId.Should().Be(song2Id);
        s2.PositionMs.Should().Be(45_000);
        s2.ActiveRendererDeviceId.Should().Be("device-desktop");

        // 3. Explicit TransferOutput to device-phone -> Version = 3
        var s3 = await desktopConn.InvokeAsync<PlaybackSessionDto>(
            "TransferOutput",
            new TransferOutputCommand("device-phone"));
        s3.Version.Should().Be(3);
        s3.ActiveRendererDeviceId.Should().Be("device-phone");

        // 4. Resume playing while device-phone is active renderer -> Version = 4
        var s4 = await desktopConn.InvokeAsync<PlaybackSessionDto>(
            "SendTransportCommand",
            new RemoteTransportCommand(PlaybackState.Playing));
        s4.Version.Should().Be(4);
        s4.State.Should().Be(PlaybackState.Playing);
        s4.ActiveRendererDeviceId.Should().Be("device-phone");

        // 5. WatchProgress endpoint broadcasts real-time update to user SignalR group
        var wpResp = await client.PutAsJsonAsync(
            "/api/v1/cinema/progress",
            new UpdateWatchProgressRequest(MovieId: movieId, EpisodeId: null, PositionMs: 120_000, DurationMs: 600_000));
        wpResp.StatusCode.Should().Be(HttpStatusCode.OK);
        var broadcastedWp = await watchProgressTcs.Task.WaitAsync(TimeSpan.FromSeconds(5));
        broadcastedWp.MovieId.Should().Be(movieId);
        broadcastedWp.PositionMs.Should().Be(120_000);

        // 6. Disconnecting active renderer (device-phone) auto-pauses session -> Version = 5, ActiveRenderer = null
        await phoneConn.StopAsync();
        var s5 = await disconnectPausedTcs.Task.WaitAsync(TimeSpan.FromSeconds(5));
        s5.Version.Should().Be(5);
        s5.State.Should().Be(PlaybackState.Paused);
        s5.ActiveRendererDeviceId.Should().BeNull();

        var remainingDevices = await desktopConn.InvokeAsync<List<OnlineDeviceDto>>("GetOnlineDevices");
        remainingDevices.Should().ContainSingle(d => d.DeviceId == "device-desktop");

        phoneUpdates.Should().NotBeEmpty();
        desktopUpdates.Select(u => u.Version).Should().ContainInOrder(1, 2, 3, 4, 5);
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

    private static async Task<(HttpClient Client, string AccessToken)> CreateAuthenticatedUserClientAsync(
        PostgresWebApplicationFactory factory,
        string username,
        string password)
    {
        var client = factory.CreateClient();
        await client.PostAsJsonAsync("/api/v1/setup", new SetupRequest(username, password, "Hermes Home"));
        var loginResp = await client.PostAsJsonAsync(
            "/api/v1/auth/login",
            new LoginRequest(username, password, "init-device", "Desktop"));
        var auth = await loginResp.Content.ReadFromJsonAsync<AuthTokenResponse>();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", auth!.AccessToken);
        return (client, auth.AccessToken);
    }
}
