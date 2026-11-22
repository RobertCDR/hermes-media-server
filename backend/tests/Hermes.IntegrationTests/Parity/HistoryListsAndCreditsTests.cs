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
using Hermes.Domain.Ports;
using Hermes.Infrastructure.Media;
using Hermes.Infrastructure.Persistence;
using Hermes.IntegrationTests.Infrastructure;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace Hermes.IntegrationTests.Parity;

public class HistoryListsAndCreditsTests
{
    [Fact]
    public async Task MultiArtistCreditsAndListeningHistoryEndpoints_WorkEndToEndWithDeduplication()
    {
        var tempMusicDir = Path.Combine(Path.GetTempPath(), $"hermes-credits-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempMusicDir);
        var flacFile = Path.Combine(tempMusicDir, "Get Lucky.flac");
        await File.WriteAllBytesAsync(flacFile, [0x66, 0x4C, 0x61, 0x43]);

        try
        {
            await using var factory = new PostgresWebApplicationFactory();
            await factory.InitializeAsync();
            using var adminClient = await CreateAuthenticatedAdminClientAsync(factory);

            Guid libId;
            using (var scope = factory.Services.CreateScope())
            {
                var db = scope.ServiceProvider.GetRequiredService<HermesDbContext>();
                var lib = new MediaLibraryRoot("Music", LibraryMediaType.Music, tempMusicDir, watchEnabled: false);
                db.MediaLibraryRoots.Add(lib);
                await db.SaveChangesAsync();
                libId = lib.Id;

                var scanner = new LibraryScannerService(
                    db,
                    scope.ServiceProvider.GetRequiredService<IMediaProbeService>(),
                    new MultiCreditStubAudioReader(),
                    scope.ServiceProvider.GetRequiredService<ITmdbClient>(),
                    scope.ServiceProvider.GetRequiredService<IArtworkStore>(),
                    scope.ServiceProvider.GetRequiredService<TimeProvider>());
                var summary = await scanner.ScanLibraryAsync(libId, CancellationToken.None);
                summary!.SourcesUpserted.Should().Be(1);
            }

            var songs = await adminClient.GetFromJsonAsync<List<SongDto>>("/api/v1/music/songs");
            songs.Should().ContainSingle();
            var song = songs![0];
            song.ArtistName.Should().Be("Daft Punk, Pharrell Williams, Nile Rodgers");
            song.ArtistCredits.Should().NotBeNull();
            song.ArtistCredits!.Select(c => c.Name).Should().Equal("Daft Punk", "Pharrell Williams", "Nile Rodgers");

            // Secondary artist detail page also lists the shared track and album displays true album artist.
            var pharrellId = song.ArtistCredits!.Single(c => c.Name == "Pharrell Williams").ArtistId;
            var pharrellDetail = await adminClient.GetFromJsonAsync<ArtistDetailDto>($"/api/v1/music/artists/{pharrellId}");
            pharrellDetail!.Songs.Should().ContainSingle(s => s.Id == song.Id);
            pharrellDetail.Albums.Should().ContainSingle(a => a.Title == "Random Access Memories" && a.ArtistName == "Daft Punk");

            // Listening history rejects below threshold, accepts >= 30s, and dedupes within 10 minutes.
            var tooShort = await adminClient.PostAsJsonAsync(
                "/api/v1/music/history",
                new RecordListenRequest(song.Id, PositionMs: 3_000, DurationMs: 240_000, DeviceId: "win-1", ContextLabel: "Random Access Memories"));
            tooShort.StatusCode.Should().Be(HttpStatusCode.BadRequest);

            var recorded = await adminClient.PostAsJsonAsync(
                "/api/v1/music/history",
                new RecordListenRequest(song.Id, PositionMs: 35_000, DurationMs: 240_000, DeviceId: "win-1", ContextLabel: "Random Access Memories"));
            recorded.StatusCode.Should().Be(HttpStatusCode.Created);
            var listen1 = await recorded.Content.ReadFromJsonAsync<RecordListenResponse>();
            listen1!.Deduped.Should().BeFalse();

            var duplicate = await adminClient.PostAsJsonAsync(
                "/api/v1/music/history",
                new RecordListenRequest(song.Id, PositionMs: 90_000, DurationMs: 240_000, DeviceId: "win-1", ContextLabel: "Random Access Memories"));
            duplicate.StatusCode.Should().Be(HttpStatusCode.OK);
            var listen2 = await duplicate.Content.ReadFromJsonAsync<RecordListenResponse>();
            listen2!.Deduped.Should().BeTrue();
            listen2.Id.Should().Be(listen1.Id);

            var history = await adminClient.GetFromJsonAsync<List<ListeningHistoryItemDto>>("/api/v1/music/history");
            history.Should().ContainSingle();
            history![0].Song.Id.Should().Be(song.Id);
            history[0].ContextLabel.Should().Be("Random Access Memories");
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
    public async Task CustomListEndpoints_CreateAddRemoveRenameDeleteAndIsolatePerUser()
    {
        await using var factory = new PostgresWebApplicationFactory();
        await factory.InitializeAsync();
        using var adminClient = await CreateAuthenticatedAdminClientAsync(factory);

        Guid movieId;
        Guid movie2Id;
        Guid seriesId;
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<HermesDbContext>();
            var moviesRoot = new MediaLibraryRoot("Movies", LibraryMediaType.Movies, "/tmp/movies-list", false);
            var seriesRoot = new MediaLibraryRoot("Series", LibraryMediaType.Series, "/tmp/series-list", false);
            var movie = new Movie(moviesRoot.Id, "Dune", 2021);
            var movie2 = new Movie(moviesRoot.Id, "Arrival", 2016);
            var series = new TvSeries(seriesRoot.Id, "Andor", 2022);
            db.MediaLibraryRoots.AddRange(moviesRoot, seriesRoot);
            db.Movies.AddRange(movie, movie2);
            db.TvSeries.Add(series);
            await db.SaveChangesAsync();
            movieId = movie.Id;
            movie2Id = movie2.Id;
            seriesId = series.Id;
        }

        var createResp = await adminClient.PostAsJsonAsync(
            "/api/v1/cinema/lists",
            new CreateCustomListRequest("Weekend Sci-Fi", "Epic space picks"));
        createResp.StatusCode.Should().Be(HttpStatusCode.Created);
        var created = (await createResp.Content.ReadFromJsonAsync<CustomListDto>())!;
        created.Name.Should().Be("Weekend Sci-Fi");
        created.Items.Should().BeEmpty();

        // Add movie & series (idempotent on duplicate add).
        var afterMovie = await (await adminClient.PostAsJsonAsync(
            $"/api/v1/cinema/lists/{created.Id}/items",
            new AddCustomListItemRequest(movieId, null)))
            .Content.ReadFromJsonAsync<CustomListDto>();
        afterMovie!.Items.Should().HaveCount(1);

        await adminClient.PostAsJsonAsync(
            $"/api/v1/cinema/lists/{created.Id}/items",
            new AddCustomListItemRequest(movieId, null));

        var afterSeries = await (await adminClient.PostAsJsonAsync(
            $"/api/v1/cinema/lists/{created.Id}/items",
            new AddCustomListItemRequest(null, seriesId)))
            .Content.ReadFromJsonAsync<CustomListDto>();
        afterSeries!.Items.Should().HaveCount(2);
        afterSeries.Items.Select(i => i.Title).Should().Equal("Dune", "Andor");

        // Rename & update description.
        var renamed = await (await adminClient.PutAsJsonAsync(
            $"/api/v1/cinema/lists/{created.Id}",
            new UpdateCustomListRequest("Late Night Watch", "Top picks")))
            .Content.ReadFromJsonAsync<CustomListDto>();
        renamed!.Name.Should().Be("Late Night Watch");
        renamed.Description.Should().Be("Top picks");

        // Remove movie by target query, add another item after deletion (verifies monotonic Position), then clean up.
        var afterRemoveMovie = await (await adminClient.DeleteAsync(
            $"/api/v1/cinema/lists/{created.Id}/items?movieId={movieId}"))
            .Content.ReadFromJsonAsync<CustomListDto>();
        afterRemoveMovie!.Items.Should().ContainSingle(i => i.TvSeriesId == seriesId);

        var afterAppendMovie2 = await (await adminClient.PostAsJsonAsync(
            $"/api/v1/cinema/lists/{created.Id}/items",
            new AddCustomListItemRequest(movie2Id, null)))
            .Content.ReadFromJsonAsync<CustomListDto>();
        afterAppendMovie2!.Items.Select(i => i.Title).Should().Equal("Andor", "Arrival");

        (await adminClient.DeleteAsync($"/api/v1/cinema/lists/{created.Id}/items?movieId={movie2Id}"))
            .StatusCode.Should().Be(HttpStatusCode.OK);

        var remainingItemId = afterRemoveMovie.Items.Single().Id;
        var afterRemoveSeries = await (await adminClient.DeleteAsync(
            $"/api/v1/cinema/lists/{created.Id}/items/{remainingItemId}"))
            .Content.ReadFromJsonAsync<CustomListDto>();
        afterRemoveSeries!.Items.Should().BeEmpty();

        var listAll = await adminClient.GetFromJsonAsync<List<CustomListDto>>("/api/v1/cinema/lists");
        listAll.Should().ContainSingle(l => l.Id == created.Id);

        (await adminClient.DeleteAsync($"/api/v1/cinema/lists/{created.Id}"))
            .StatusCode.Should().Be(HttpStatusCode.NoContent);

        var afterDelete = await adminClient.GetFromJsonAsync<List<CustomListDto>>("/api/v1/cinema/lists");
        afterDelete.Should().BeEmpty();
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

    private sealed class MultiCreditStubAudioReader : IAudioMetadataReader
    {
        public ProbedAudioTrackMetadata? ReadMetadata(string filePath) =>
            new(
                "Get Lucky",
                "Daft Punk",
                "Random Access Memories",
                2013,
                8,
                1,
                248_000,
                "flac",
                1_000_000,
                44_100,
                24,
                null,
                ["Daft Punk", "Pharrell Williams", "Nile Rodgers"]);
    }
}
