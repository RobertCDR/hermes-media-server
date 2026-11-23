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
        endpoints.MapGet("/api/v1/admin/media/unmatched", ListUnmatchedMediaAsync)
            .RequireAuthorization("AdminOnly")
            .WithName("ListUnmatchedMedia");
        endpoints.MapGet("/api/v1/admin/media/tmdb-search", SearchTmdbAsync)
            .RequireAuthorization("AdminOnly")
            .WithName("SearchAdminTmdb");

        return endpoints;
    }

    private static async Task<IResult> ListUnmatchedMediaAsync(
        HermesDbContext db,
        CancellationToken cancellationToken)
    {
        var libraryNames = await db.MediaLibraryRoots
            .AsNoTracking()
            .ToDictionaryAsync(r => r.Id, r => r.Name, cancellationToken);

        var unmatchedMovies = await db.Movies
            .AsNoTracking()
            .Where(m => m.TmdbId == null)
            .Include(m => m.Sources)
            .OrderBy(m => m.Title)
            .ToListAsync(cancellationToken);

        var unmatchedSeries = await db.TvSeries
            .AsNoTracking()
            .Where(s => s.TmdbId == null)
            .Include(s => s.Seasons)
            .ThenInclude(sn => sn.Episodes)
            .ThenInclude(ep => ep.Sources)
            .OrderBy(s => s.Title)
            .ToListAsync(cancellationToken);

        var results = new List<UnmatchedMediaDto>(unmatchedMovies.Count + unmatchedSeries.Count);

        foreach (var movie in unmatchedMovies)
        {
            var libName = libraryNames.GetValueOrDefault(movie.LibraryRootId, "Movies");
            var path = movie.Sources.FirstOrDefault()?.FilePath ?? movie.Title;
            results.Add(new UnmatchedMediaDto(
                movie.Id,
                LibraryMediaType.Movies,
                movie.Title,
                movie.Year,
                libName,
                path));
        }

        foreach (var series in unmatchedSeries)
        {
            var libName = libraryNames.GetValueOrDefault(series.LibraryRootId, "TV Shows");
            var path = series.Seasons
                .SelectMany(sn => sn.Episodes)
                .SelectMany(ep => ep.Sources)
                .Select(src => src.FilePath)
                .FirstOrDefault() ?? series.Title;
            results.Add(new UnmatchedMediaDto(
                series.Id,
                LibraryMediaType.Series,
                series.Title,
                series.Year,
                libName,
                path));
        }

        return Results.Ok(results);
    }

    private static async Task<IResult> SearchTmdbAsync(
        string? query,
        LibraryMediaType mediaType,
        ITmdbClient tmdbClient,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(query))
        {
            return Results.Ok(Array.Empty<TmdbCandidateDto>());
        }

        var kind = mediaType == LibraryMediaType.Series
            ? LibraryMediaType.Series
            : LibraryMediaType.Movies;
        try
        {
            var candidates = await tmdbClient.SearchAsync(kind, query.Trim(), null, cancellationToken);
            return Results.Ok(
                candidates
                    .Select(c => new TmdbCandidateDto(c.TmdbId, c.Title, c.Year, c.Overview))
                    .ToList());
        }
        catch (HttpRequestException)
        {
            return Results.Problem(
                "TMDb metadata service is temporarily unavailable.",
                statusCode: StatusCodes.Status502BadGateway);
        }
        catch (TaskCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return Results.Problem(
                "TMDb metadata request timed out.",
                statusCode: StatusCodes.Status502BadGateway);
        }
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

        try
        {
            var movie = await db.Movies.SingleOrDefaultAsync(m => m.Id == id, cancellationToken);
            if (movie is not null)
            {
                var details = await tmdbClient.GetDetailsAsync(LibraryMediaType.Movies, request.TmdbId, cancellationToken);
                var posterHash = await tmdbClient.DownloadAndStoreArtworkAsync(artworkStore, details?.PosterPath, cancellationToken)
                    ?? movie.ArtworkHash;
                var backdropHash = await tmdbClient.DownloadAndStoreArtworkAsync(artworkStore, details?.BackdropPath, cancellationToken)
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
                var posterHash = await tmdbClient.DownloadAndStoreArtworkAsync(artworkStore, details?.PosterPath, cancellationToken)
                    ?? series.ArtworkHash;
                var backdropHash = await tmdbClient.DownloadAndStoreArtworkAsync(artworkStore, details?.BackdropPath, cancellationToken)
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
        }
        catch (HttpRequestException)
        {
            return Results.Problem(
                "TMDb metadata service is temporarily unavailable.",
                statusCode: StatusCodes.Status502BadGateway);
        }
        catch (TaskCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return Results.Problem(
                "TMDb metadata request timed out.",
                statusCode: StatusCodes.Status502BadGateway);
        }

        return Results.NotFound(new { error = "media_not_found" });
    }
}
