using FluentAssertions;
using Hermes.Domain.Entities;
using Hermes.Domain.Enums;
using Hermes.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Testcontainers.PostgreSql;
using Xunit;

namespace Hermes.IntegrationTests.Persistence;

public class PostgresSchemaMigrationTests
{
    [Fact]
    public async Task MigrateAsync_CreatesSchemaWithPgTrgm_AndSupportsMultipleMediaSourcesPerMovieWithSharedWatchProgress()
    {
        await using var container = new PostgreSqlBuilder("postgres:17-alpine").Build();
        await container.StartAsync();

        var options = new DbContextOptionsBuilder<HermesDbContext>()
            .UseNpgsql(container.GetConnectionString())
            .Options;

        await using var db = new HermesDbContext(options);
        await db.Database.MigrateAsync();

        var root = new MediaLibraryRoot("Cinema", LibraryMediaType.Movies, "/media/movies", watchEnabled: true);
        var admin = User.Create("admin", "hashed-password", UserRole.Admin, DateTimeOffset.UtcNow);
        var movie = new Movie(root.Id, "Dune: Part Two", 2024);
        movie.ApplyScannedMetadata("Dune: Part Two", 2024, "Sci-fi epic", 693134, "hash_poster", "hash_bg");

        var source1080 = MediaSource.ForMovie(movie.Id, "/media/movies/dune2-1080p.mkv", "1080p HEVC", "mkv", "hevc", "aac", 1920, 1080, false, 8_000_000, 4_000_000_000, 9_960_000);
        source1080.Streams.Add(new MediaStream(source1080.Id, 0, StreamKind.Video, "hevc", "und", "HEVC Main10", true));
        source1080.Streams.Add(new MediaStream(source1080.Id, 1, StreamKind.Audio, "aac", "eng", "English AAC 5.1", true));

        var source4k = MediaSource.ForMovie(movie.Id, "/media/movies/dune2-4k-hdr.mkv", "4K HDR", "mkv", "hevc", "eac3", 3840, 2160, true, 25_000_000, 14_000_000_000, 9_960_000);
        var progress = WatchProgress.ForMovie(admin.Id, movie.Id);
        progress.UpdatePosition(1_200_000, 9_960_000, DateTimeOffset.UtcNow);

        db.MediaLibraryRoots.Add(root);
        db.Users.Add(admin);
        db.Movies.Add(movie);
        db.MediaSources.AddRange(source1080, source4k);
        db.WatchProgresses.Add(progress);
        await db.SaveChangesAsync();

        var loaded = await db.Movies
            .Include(m => m.Sources)
            .ThenInclude(s => s.Streams)
            .SingleAsync(m => m.Id == movie.Id);

        loaded.Sources.Should().HaveCount(2);
        loaded.Sources.Single(s => s.Id == source1080.Id).Streams.Should().HaveCount(2);

        var loadedProgress = await db.WatchProgresses.SingleAsync(p => p.UserId == admin.Id && p.MovieId == movie.Id);
        loadedProgress.PositionMs.Should().Be(1_200_000);

        var trgmInstalled = await db.Database
            .SqlQueryRaw<string>("SELECT extname AS \"Value\" FROM pg_extension WHERE extname = 'pg_trgm'")
            .SingleOrDefaultAsync();
        trgmInstalled.Should().Be("pg_trgm");
    }
}
