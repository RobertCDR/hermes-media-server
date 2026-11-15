using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using FluentAssertions;
using Hermes.Api.Features.Admin;
using Hermes.Api.Features.Auth;
using Hermes.Api.Features.Setup;
using Hermes.Domain.Entities;
using Hermes.Domain.Enums;
using Hermes.Domain.Ports;
using Hermes.Infrastructure.Persistence;
using Hermes.IntegrationTests.Infrastructure;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using SkiaSharp;
using Xunit;

namespace Hermes.IntegrationTests.Media;

public class LibraryScannerTests
{
    [Fact]
    public async Task ScanMovieLibrary_GroupsMultipleResolutionsIntoSingleMovie_HandlesMissingAndRestoredFiles_AndRespectsManualIdentifyLock()
    {
        var tempMediaDir = Path.Combine(Path.GetTempPath(), $"hermes-media-{Guid.NewGuid():N}");
        var extrasDir = Path.Combine(tempMediaDir, "Extras");
        Directory.CreateDirectory(extrasDir);

        var file1080 = Path.Combine(tempMediaDir, "Dune Part Two (2024) - 1080p.mkv");
        var file2160 = Path.Combine(tempMediaDir, "Dune Part Two (2024) - 2160p HDR.mkv");
        var trailerFile = Path.Combine(extrasDir, "trailer.mkv");

        await File.WriteAllBytesAsync(file1080, [0x01, 0x02, 0x03, 0x04]);
        await File.WriteAllBytesAsync(file2160, [0x05, 0x06, 0x07, 0x08]);
        await File.WriteAllBytesAsync(trailerFile, [0x09, 0x0A]);

        try
        {
            await using var factory = new PostgresWebApplicationFactory();
            await factory.InitializeAsync();

            using var adminClient = await CreateAuthenticatedAdminClientAsync(factory);

            var createLibResponse = await adminClient.PostAsJsonAsync(
                "/api/v1/admin/libraries",
                new CreateLibraryRootRequest("Cinema", LibraryMediaType.Movies, tempMediaDir, WatchEnabled: true));
            createLibResponse.StatusCode.Should().Be(HttpStatusCode.Created);
            var lib = await createLibResponse.Content.ReadFromJsonAsync<LibraryRootResponse>();
            lib.Should().NotBeNull();

            var scan1Response = await adminClient.PostAsync($"/api/v1/admin/libraries/{lib!.Id}/scan", content: null);
            scan1Response.StatusCode.Should().Be(HttpStatusCode.OK);
            var summary1 = await scan1Response.Content.ReadFromJsonAsync<LibraryScanSummaryDto>();
            summary1.Should().NotBeNull();
            summary1!.SourcesUpserted.Should().Be(2);

            Guid movieId;
            Guid source1080Id;
            using (var scope = factory.Services.CreateScope())
            {
                var db = scope.ServiceProvider.GetRequiredService<HermesDbContext>();
                var movie = await db.Movies.Include(m => m.Sources).SingleAsync();
                movie.Title.Should().Be("Dune Part Two");
                movie.Year.Should().Be(2024);
                movie.Sources.Should().HaveCount(2);

                var s1080 = movie.Sources.Single(s => s.FilePath == file1080);
                var s2160 = movie.Sources.Single(s => s.FilePath == file2160);
                s2160.IsHdr.Should().BeTrue();
                s2160.Height.Should().Be(2160);

                movieId = movie.Id;
                source1080Id = s1080.Id;

                var admin = await db.Users.SingleAsync();
                var progress = WatchProgress.ForMovie(admin.Id, movieId);
                progress.UpdatePosition(600_000, 9_960_000, DateTimeOffset.UtcNow);
                db.WatchProgresses.Add(progress);
                await db.SaveChangesAsync();
            }

            // Missing file resilience (Review Focus #5)
            File.Delete(file1080);
            var scan2Response = await adminClient.PostAsync($"/api/v1/admin/libraries/{lib.Id}/scan", content: null);
            scan2Response.StatusCode.Should().Be(HttpStatusCode.OK);

            using (var scope = factory.Services.CreateScope())
            {
                var db = scope.ServiceProvider.GetRequiredService<HermesDbContext>();
                var movie = await db.Movies.Include(m => m.Sources).SingleAsync(m => m.Id == movieId);
                movie.Sources.Single(s => s.Id == source1080Id).MissingSinceUtc.Should().NotBeNull();
                movie.Sources.Single(s => s.FilePath == file2160).MissingSinceUtc.Should().BeNull();
                var progress = await db.WatchProgresses.SingleAsync(p => p.MovieId == movieId);
                progress.PositionMs.Should().Be(600_000);
            }

            // File restored clears MissingSinceUtc
            await File.WriteAllBytesAsync(file1080, [0x01, 0x02, 0x03, 0x04]);
            var scan3Response = await adminClient.PostAsync($"/api/v1/admin/libraries/{lib.Id}/scan", content: null);
            scan3Response.StatusCode.Should().Be(HttpStatusCode.OK);

            using (var scope = factory.Services.CreateScope())
            {
                var db = scope.ServiceProvider.GetRequiredService<HermesDbContext>();
                var source = await db.MediaSources.SingleAsync(s => s.Id == source1080Id);
                source.MissingSinceUtc.Should().BeNull();
            }

            // Manual Identify locks metadata against future scans
            var identifyResponse = await adminClient.PostAsJsonAsync(
                $"/api/v1/admin/media/{movieId}/identify",
                new IdentifyMediaRequest(693134, "Dune: Part Two - Special Edition", 2024, "Manual curator lock"));
            identifyResponse.StatusCode.Should().Be(HttpStatusCode.OK);

            var scan4Response = await adminClient.PostAsync($"/api/v1/admin/libraries/{lib.Id}/scan", content: null);
            scan4Response.StatusCode.Should().Be(HttpStatusCode.OK);

            using (var scope = factory.Services.CreateScope())
            {
                var db = scope.ServiceProvider.GetRequiredService<HermesDbContext>();
                var movie = await db.Movies.SingleAsync(m => m.Id == movieId);
                movie.IsMetadataLocked.Should().BeTrue();
                movie.TmdbId.Should().Be(693134);
                movie.Title.Should().Be("Dune: Part Two - Special Edition");
                movie.Overview.Should().Be("Manual curator lock");
            }
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
    public async Task SkiaArtworkStore_GeneratesThreeWebpVariants_AndArtworkEndpointSupportsETagAnd304()
    {
        await using var factory = new PostgresWebApplicationFactory();
        await factory.InitializeAsync();

        using var bitmap = new SKBitmap(128, 192);
        using (var canvas = new SKCanvas(bitmap))
        {
            canvas.Clear(SKColors.Crimson);
        }

        using var encoded = SKImage.FromBitmap(bitmap).Encode(SKEncodedImageFormat.Png, 100);
        var pngBytes = encoded.ToArray();

        var artworkStore = factory.Services.GetRequiredService<IArtworkStore>();
        var hash = await artworkStore.SaveArtworkVariantsAsync(pngBytes, CancellationToken.None);
        hash.Should().NotBeNullOrWhiteSpace();

        foreach (var variant in new[] { "thumb_400.webp", "poster_800.webp", "backdrop_1280.webp" })
        {
            var path = artworkStore.ResolveVariantFilePath(hash!, variant);
            path.Should().NotBeNull();
            File.Exists(path).Should().BeTrue();
        }

        using var client = factory.CreateClient();
        var firstResponse = await client.GetAsync($"/api/v1/artwork/{hash}/poster_800.webp");
        firstResponse.StatusCode.Should().Be(HttpStatusCode.OK);
        firstResponse.Content.Headers.ContentType?.MediaType.Should().Be("image/webp");
        var body = await firstResponse.Content.ReadAsByteArrayAsync();
        body.Should().NotBeEmpty();
        firstResponse.Headers.ETag.Should().NotBeNull();

        using var conditionalRequest = new HttpRequestMessage(HttpMethod.Get, $"/api/v1/artwork/{hash}/poster_800.webp");
        conditionalRequest.Headers.IfNoneMatch.Add(firstResponse.Headers.ETag!);
        var secondResponse = await client.SendAsync(conditionalRequest);
        secondResponse.StatusCode.Should().Be(HttpStatusCode.NotModified);
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
