using System.Security.Claims;
using Hermes.Api.Features.System;
using Hermes.Domain.Entities;
using Hermes.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Hermes.Api.Features.Cinema;

public static class CinemaEndpoints
{
    public static IEndpointRouteBuilder MapCinemaEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints.MapGroup("/api/v1/cinema")
            .RequireAuthorization();

        group.MapGet("/movies", ListMoviesAsync).WithName("ListMovies");
        group.MapGet("/movies/{id:guid}", GetMovieAsync).WithName("GetMovie");
        group.MapGet("/series", ListSeriesAsync).WithName("ListSeries");

        return endpoints;
    }

    private static async Task<IResult> ListMoviesAsync(
        ClaimsPrincipal principal,
        HermesDbContext db,
        CancellationToken cancellationToken)
    {
        if (!principal.TryGetUserId(out var userId))
        {
            return Results.Unauthorized();
        }

        var movies = await db.Movies
            .AsNoTracking()
            .Include(m => m.Sources)
            .ThenInclude(s => s.Streams)
            .OrderBy(m => m.Title)
            .ToListAsync(cancellationToken);

        var progresses = await db.WatchProgresses
            .AsNoTracking()
            .Where(p => p.UserId == userId && p.MovieId != null)
            .ToDictionaryAsync(p => p.MovieId!.Value, cancellationToken);

        var result = movies
            .Select(m => MapMovie(m, progresses.GetValueOrDefault(m.Id)))
            .ToList();

        return Results.Ok(result);
    }

    private static async Task<IResult> GetMovieAsync(
        Guid id,
        ClaimsPrincipal principal,
        HermesDbContext db,
        CancellationToken cancellationToken)
    {
        if (!principal.TryGetUserId(out var userId))
        {
            return Results.Unauthorized();
        }

        var movie = await db.Movies
            .AsNoTracking()
            .Include(m => m.Sources)
            .ThenInclude(s => s.Streams)
            .SingleOrDefaultAsync(m => m.Id == id, cancellationToken);

        if (movie is null)
        {
            return Results.NotFound(new { error = "movie_not_found" });
        }

        var progress = await db.WatchProgresses
            .AsNoTracking()
            .SingleOrDefaultAsync(p => p.UserId == userId && p.MovieId == id, cancellationToken);

        return Results.Ok(MapMovie(movie, progress));
    }

    private static async Task<IResult> ListSeriesAsync(
        ClaimsPrincipal principal,
        HermesDbContext db,
        CancellationToken cancellationToken)
    {
        if (!principal.TryGetUserId(out var userId))
        {
            return Results.Unauthorized();
        }

        var seriesList = await db.TvSeries
            .AsNoTracking()
            .Include(s => s.Seasons)
            .ThenInclude(sn => sn.Episodes)
            .ThenInclude(ep => ep.Sources)
            .ThenInclude(src => src.Streams)
            .OrderBy(s => s.Title)
            .ToListAsync(cancellationToken);

        var episodeProgresses = await db.WatchProgresses
            .AsNoTracking()
            .Where(p => p.UserId == userId && p.EpisodeId != null)
            .ToDictionaryAsync(p => p.EpisodeId!.Value, cancellationToken);

        var result = seriesList
            .Select(s => new TvSeriesSummaryDto(
                s.Id,
                s.Title,
                s.Year,
                s.Overview,
                s.TmdbId,
                s.ArtworkHash,
                s.BackdropHash,
                s.Seasons
                    .OrderBy(sn => sn.SeasonNumber)
                    .Select(sn => new TvSeasonDto(
                        sn.Id,
                        sn.SeasonNumber,
                        sn.Title,
                        sn.ArtworkHash,
                        sn.Episodes
                            .OrderBy(ep => ep.EpisodeNumber)
                            .Select(ep => new EpisodeSummaryDto(
                                ep.Id,
                                ep.EpisodeNumber,
                                ep.Title,
                                ep.Overview,
                                ep.StillArtworkHash,
                                MapProgress(episodeProgresses.GetValueOrDefault(ep.Id)),
                                MapSources(ep.Sources)))
                            .ToList()))
                    .ToList()))
            .ToList();

        return Results.Ok(result);
    }

    internal static MovieSummaryDto MapMovie(Movie movie, WatchProgress? progress) =>
        new(
            movie.Id,
            movie.Title,
            movie.Year,
            movie.Overview,
            movie.TmdbId,
            movie.ArtworkHash,
            movie.BackdropHash,
            MapProgress(progress),
            MapSources(movie.Sources));

    internal static WatchProgressDto? MapProgress(WatchProgress? progress) =>
        progress is null
            ? null
            : new WatchProgressDto(progress.PositionMs, progress.DurationMs, progress.IsWatched, progress.UpdatedAtUtc);

    internal static List<MediaSourceDto> MapSources(IEnumerable<MediaSource> sources) =>
        sources
            .OrderByDescending(s => s.Height)
            .ThenByDescending(s => s.BitrateBps)
            .Select(s => new MediaSourceDto(
                s.Id,
                s.SourceLabel,
                s.Container,
                s.VideoCodec,
                s.AudioCodec,
                s.Width,
                s.Height,
                s.IsHdr,
                s.BitrateBps,
                s.DurationMs,
                s.MissingSinceUtc is null,
                s.Streams
                    .OrderBy(st => st.StreamIndex)
                    .Select(st => new MediaStreamDto(
                        st.StreamIndex,
                        st.Kind,
                        st.Codec,
                        st.Language,
                        st.Title,
                        st.IsDefault))
                    .ToList()))
            .ToList();
}
