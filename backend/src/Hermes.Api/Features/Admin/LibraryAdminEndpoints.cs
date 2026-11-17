using Hermes.Domain.Entities;
using Hermes.Domain.Enums;
using Hermes.Infrastructure.Media;
using Hermes.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Hermes.Api.Features.Admin;

public static class LibraryAdminEndpoints
{
    public static IEndpointRouteBuilder MapLibraryAdminEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints.MapGroup("/api/v1/admin/libraries")
            .RequireAuthorization("AdminOnly");

        group.MapPost("", CreateLibraryRootAsync).WithName("CreateLibraryRoot");
        group.MapGet("", ListLibraryRootsAsync).WithName("ListLibraryRoots");
        group.MapPut("/{id:guid}", UpdateLibraryRootAsync).WithName("UpdateLibraryRoot");
        group.MapDelete("/{id:guid}", DeleteLibraryRootAsync).WithName("DeleteLibraryRoot");
        group.MapPost("/{id:guid}/scan", ScanLibraryNowAsync).WithName("ScanLibrary");
        group.MapPost("/{id:guid}/scan/queue", QueueLibraryScanAsync).WithName("QueueLibraryScan");

        return endpoints;
    }

    private static async Task<IResult> CreateLibraryRootAsync(
        CreateLibraryRootRequest request,
        HermesDbContext db,
        LibraryScanProgressTracker scanProgress,
        LibraryWatcherService watcherService,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.Name) || string.IsNullOrWhiteSpace(request.RootPath))
        {
            return Results.BadRequest(new { error = "invalid_library_root" });
        }

        var normalizedPath = request.RootPath.Trim();
        if (await db.MediaLibraryRoots.AnyAsync(r => r.RootPath == normalizedPath, cancellationToken))
        {
            return Results.Conflict(new { error = "library_root_already_exists" });
        }

        var root = new MediaLibraryRoot(
            request.Name,
            request.MediaType,
            normalizedPath,
            request.WatchEnabled,
            request.FetchMetadata);
        db.MediaLibraryRoots.Add(root);
        await db.SaveChangesAsync(cancellationToken);

        await watcherService.RefreshWatchersAsync(cancellationToken);

        var dto = await BuildLibraryRootResponseAsync(db, scanProgress, root, cancellationToken);
        return Results.Created($"/api/v1/admin/libraries/{root.Id}", dto);
    }

    private static async Task<IResult> ListLibraryRootsAsync(
        HermesDbContext db,
        LibraryScanProgressTracker scanProgress,
        CancellationToken cancellationToken)
    {
        var roots = await db.MediaLibraryRoots
            .AsNoTracking()
            .OrderBy(r => r.Name)
            .ToListAsync(cancellationToken);

        var responses = new List<LibraryRootResponse>(roots.Count);
        foreach (var r in roots)
        {
            responses.Add(await BuildLibraryRootResponseAsync(db, scanProgress, r, cancellationToken));
        }

        return Results.Ok(responses);
    }

    private static async Task<IResult> UpdateLibraryRootAsync(
        Guid id,
        UpdateLibraryRootRequest request,
        HermesDbContext db,
        LibraryScanProgressTracker scanProgress,
        LibraryWatcherService watcherService,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.Name) || string.IsNullOrWhiteSpace(request.RootPath))
        {
            return Results.BadRequest(new { error = "invalid_library_root" });
        }

        var root = await db.MediaLibraryRoots.SingleOrDefaultAsync(r => r.Id == id, cancellationToken);
        if (root is null)
        {
            return Results.NotFound(new { error = "library_root_not_found" });
        }

        var normalizedPath = request.RootPath.Trim();
        var duplicatePath = await db.MediaLibraryRoots
            .AnyAsync(r => r.Id != id && r.RootPath == normalizedPath, cancellationToken);
        if (duplicatePath)
        {
            return Results.Conflict(new { error = "library_root_already_exists" });
        }

        root.UpdateOptions(request.Name, normalizedPath, request.WatchEnabled, request.FetchMetadata);
        await db.SaveChangesAsync(cancellationToken);

        await watcherService.RefreshWatchersAsync(cancellationToken);

        var dto = await BuildLibraryRootResponseAsync(db, scanProgress, root, cancellationToken);
        return Results.Ok(dto);
    }

    private static async Task<IResult> DeleteLibraryRootAsync(
        Guid id,
        HermesDbContext db,
        LibraryWatcherService watcherService,
        TimeProvider timeProvider,
        CancellationToken cancellationToken)
    {
        var root = await db.MediaLibraryRoots.SingleOrDefaultAsync(r => r.Id == id, cancellationToken);
        if (root is null)
        {
            return Results.NotFound(new { error = "library_root_not_found" });
        }

        await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);

        switch (root.MediaType)
        {
            case LibraryMediaType.Movies:
            {
                var movieIds = await db.Movies
                    .Where(m => m.LibraryRootId == id)
                    .Select(m => m.Id)
                    .ToListAsync(cancellationToken);

                if (movieIds.Count > 0)
                {
                    await db.WatchProgresses
                        .Where(w => w.MovieId != null && movieIds.Contains(w.MovieId.Value))
                        .ExecuteDeleteAsync(cancellationToken);
                    await db.WatchlistItems
                        .Where(w => w.MovieId != null && movieIds.Contains(w.MovieId.Value))
                        .ExecuteDeleteAsync(cancellationToken);
                    await db.Movies
                        .Where(m => m.LibraryRootId == id)
                        .ExecuteDeleteAsync(cancellationToken);
                }
                break;
            }
            case LibraryMediaType.Series:
            {
                var seriesIds = await db.TvSeries
                    .Where(s => s.LibraryRootId == id)
                    .Select(s => s.Id)
                    .ToListAsync(cancellationToken);

                if (seriesIds.Count > 0)
                {
                    var episodeIds = await db.Episodes
                        .Where(e => seriesIds.Contains(e.TvSeason.TvSeriesId))
                        .Select(e => e.Id)
                        .ToListAsync(cancellationToken);

                    if (episodeIds.Count > 0)
                    {
                        await db.WatchProgresses
                            .Where(w => w.EpisodeId != null && episodeIds.Contains(w.EpisodeId.Value))
                            .ExecuteDeleteAsync(cancellationToken);
                    }

                    await db.WatchlistItems
                        .Where(w => w.TvSeriesId != null && seriesIds.Contains(w.TvSeriesId.Value))
                        .ExecuteDeleteAsync(cancellationToken);
                    await db.TvSeries
                        .Where(s => s.LibraryRootId == id)
                        .ExecuteDeleteAsync(cancellationToken);
                }
                break;
            }
            case LibraryMediaType.Music:
            {
                var songIds = await db.Songs
                    .Where(s => s.LibraryRootId == id)
                    .Select(s => s.Id)
                    .ToListAsync(cancellationToken);

                if (songIds.Count > 0)
                {
                    var removedSongSet = songIds.ToHashSet();
                    var activeSessions = await db.PlaybackSessions.ToListAsync(cancellationToken);
                    var utcNow = timeProvider.GetUtcNow();
                    foreach (var session in activeSessions)
                    {
                        if (!session.QueueSongIds.Any(removedSongSet.Contains))
                        {
                            continue;
                        }

                        var remainingQueue = session.QueueSongIds
                            .Where(q => !removedSongSet.Contains(q))
                            .ToArray();
                        session.StartPlayback(
                            session.ActiveRendererDeviceId ?? "server",
                            session.ActiveRendererDeviceName ?? "Server",
                            remainingQueue,
                            0,
                            utcNow);
                    }

                    await db.SaveChangesAsync(cancellationToken);

                    await db.LikedSongs
                        .Where(l => songIds.Contains(l.SongId))
                        .ExecuteDeleteAsync(cancellationToken);
                    await db.PlaylistTracks
                        .Where(t => songIds.Contains(t.SongId))
                        .ExecuteDeleteAsync(cancellationToken);
                    await db.Songs
                        .Where(s => s.LibraryRootId == id)
                        .ExecuteDeleteAsync(cancellationToken);
                    await db.Albums
                        .Where(a => !db.Songs.Any(s => s.AlbumId == a.Id))
                        .ExecuteDeleteAsync(cancellationToken);
                    await db.Artists
                        .Where(a => !db.Songs.Any(s => s.ArtistId == a.Id) && !db.Albums.Any(al => al.ArtistId == a.Id))
                        .ExecuteDeleteAsync(cancellationToken);
                }
                break;
            }
        }

        await db.MediaLibraryRoots
            .Where(r => r.Id == id)
            .ExecuteDeleteAsync(cancellationToken);

        await transaction.CommitAsync(cancellationToken);

        await watcherService.RefreshWatchersAsync(cancellationToken);
        return Results.NoContent();
    }

    internal static async Task<(int ItemCount, long TotalSizeBytes)> ComputeLibraryStatsAsync(
        HermesDbContext db,
        Guid libraryRootId,
        LibraryMediaType mediaType,
        CancellationToken cancellationToken)
    {
        return mediaType switch
        {
            LibraryMediaType.Movies => (
                await db.Movies.CountAsync(m => m.LibraryRootId == libraryRootId, cancellationToken),
                await db.MediaSources
                    .Where(s => s.Movie != null && s.Movie.LibraryRootId == libraryRootId && s.MissingSinceUtc == null)
                    .SumAsync(s => (long?)s.FileSizeBytes, cancellationToken) ?? 0L),
            LibraryMediaType.Series => (
                await db.TvSeries.CountAsync(s => s.LibraryRootId == libraryRootId, cancellationToken),
                await db.MediaSources
                    .Where(s => s.Episode != null && s.Episode.TvSeason.TvSeries.LibraryRootId == libraryRootId && s.MissingSinceUtc == null)
                    .SumAsync(s => (long?)s.FileSizeBytes, cancellationToken) ?? 0L),
            _ => (
                await db.Songs.CountAsync(s => s.LibraryRootId == libraryRootId && s.MissingSinceUtc == null, cancellationToken),
                await db.Songs
                    .Where(s => s.LibraryRootId == libraryRootId && s.MissingSinceUtc == null)
                    .SumAsync(s => (long?)s.FileSizeBytes, cancellationToken) ?? 0L),
        };
    }

    private static async Task<LibraryRootResponse> BuildLibraryRootResponseAsync(
        HermesDbContext db,
        LibraryScanProgressTracker scanProgress,
        MediaLibraryRoot root,
        CancellationToken cancellationToken)
    {
        var (count, bytes) = await ComputeLibraryStatsAsync(db, root.Id, root.MediaType, cancellationToken);
        var live = scanProgress.GetProgress(root.Id);

        return new LibraryRootResponse(
            root.Id,
            root.Name,
            root.MediaType,
            root.RootPath,
            root.WatchEnabled,
            root.CreatedAtUtc,
            root.LastScanCompletedAtUtc,
            count,
            bytes,
            live?.IsScanning ?? false,
            live?.ProcessedFiles ?? 0,
            live?.TotalFiles ?? 0,
            root.FetchMetadata);
    }

    private static async Task<IResult> ScanLibraryNowAsync(
        Guid id,
        LibraryScannerService scanner,
        CancellationToken cancellationToken)
    {
        var result = await scanner.ScanLibraryAsync(id, cancellationToken);
        if (result is null)
        {
            return Results.NotFound(new { error = "library_root_not_found" });
        }

        return Results.Ok(new LibraryScanSummaryDto(
            result.LibraryRootId,
            result.FilesDiscovered,
            result.SourcesUpserted,
            result.SourcesMarkedMissing,
            result.CompletedAtUtc));
    }

    private static async Task<IResult> QueueLibraryScanAsync(
        Guid id,
        HermesDbContext db,
        LibraryScanChannel scanChannel,
        CancellationToken cancellationToken)
    {
        if (!await db.MediaLibraryRoots.AnyAsync(r => r.Id == id, cancellationToken))
        {
            return Results.NotFound(new { error = "library_root_not_found" });
        }

        await scanChannel.EnqueueScanAsync(id, cancellationToken);
        return Results.Accepted($"/api/v1/admin/libraries/{id}");
    }
}
