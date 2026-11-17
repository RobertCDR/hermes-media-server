using Hermes.Domain.Enums;
using Hermes.Domain.Ports;
using Hermes.Infrastructure.Media;
using Hermes.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Hermes.Api.Features.Admin;

public static class IdentifyEndpoints
{
    public static IEndpointRouteBuilder MapIdentifyEndpoints(this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPost("/api/v1/admin/media/{id:guid}/identify", IdentifyMediaAsync)
            .RequireAuthorization("AdminOnly")
            .WithName("IdentifyMedia");

        return endpoints;
    }

    private static async Task<IResult> IdentifyMediaAsync(
        Guid id,
        IdentifyMediaRequest request,
        HermesDbContext db,
        ITmdbClient tmdbClient,
        IArtworkStore artworkStore,
        CancellationToken cancellationToken)
    {
        if (request.TmdbId <= 0 || string.IsNullOrWhiteSpace(request.Title))
        {
            return Results.BadRequest(new { error = "invalid_identify_request" });
        }

        var movie = await db.Movies.SingleOrDefaultAsync(m => m.Id == id, cancellationToken);
        if (movie is not null)
        {
            var details = await tmdbClient.GetDetailsAsync(LibraryMediaType.Movies, request.TmdbId, cancellationToken);
            var posterHash = await TryDownloadAndStoreAsync(tmdbClient, artworkStore, details?.PosterPath, cancellationToken)
                ?? movie.ArtworkHash;
            var backdropHash = await TryDownloadAndStoreAsync(tmdbClient, artworkStore, details?.BackdropPath, cancellationToken)
                ?? movie.BackdropHash;

            movie.LockManualMatch(
                request.TmdbId,
                request.Title,
                request.Year ?? details?.Year,
                request.Overview ?? details?.Overview,
                posterHash,
                backdropHash);

            await CinemaMetadataEnricher.EnrichMovieAsync(
                tmdbClient,
                artworkStore,
                movie,
                cancellationToken,
                bypassLock: true);

            await db.SaveChangesAsync(cancellationToken);
            return Results.Ok(new IdentifyMediaResponse(movie.Id, request.TmdbId, movie.Title, movie.Year, movie.IsMetadataLocked));
        }

        var series = await db.TvSeries
            .Include(s => s.Seasons)
            .SingleOrDefaultAsync(s => s.Id == id, cancellationToken);
        if (series is not null)
        {
            var details = await tmdbClient.GetDetailsAsync(LibraryMediaType.Series, request.TmdbId, cancellationToken);
            var posterHash = await TryDownloadAndStoreAsync(tmdbClient, artworkStore, details?.PosterPath, cancellationToken)
                ?? series.ArtworkHash;
            var backdropHash = await TryDownloadAndStoreAsync(tmdbClient, artworkStore, details?.BackdropPath, cancellationToken)
                ?? series.BackdropHash;

            series.LockManualMatch(
                request.TmdbId,
                request.Title,
                request.Year ?? details?.Year,
                request.Overview ?? details?.Overview,
                posterHash,
                backdropHash);

            await CinemaMetadataEnricher.EnrichSeriesAsync(
                tmdbClient,
                artworkStore,
                series,
                cancellationToken,
                bypassLock: true);

            await db.SaveChangesAsync(cancellationToken);
            return Results.Ok(new IdentifyMediaResponse(series.Id, request.TmdbId, series.Title, series.Year, series.IsMetadataLocked));
        }

        return Results.NotFound(new { error = "media_not_found" });
    }

    private static async Task<string?> TryDownloadAndStoreAsync(
        ITmdbClient tmdbClient,
        IArtworkStore artworkStore,
        string? remotePath,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(remotePath))
        {
            return null;
        }

        var bytes = await tmdbClient.DownloadImageBytesAsync(remotePath, cancellationToken);
        return bytes is { Length: > 0 }
            ? await artworkStore.SaveArtworkVariantsAsync(bytes, cancellationToken)
            : null;
    }
}
