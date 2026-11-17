using System.Security.Claims;
using Hermes.Api.Features.System;
using Hermes.Api.Hubs;
using Hermes.Domain.Entities;
using Hermes.Infrastructure.Media;
using Hermes.Infrastructure.Persistence;
using Microsoft.AspNetCore.SignalR;
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
        group.MapPut("/watchlist", UpdateWatchlistAsync).WithName("UpdateWatchlist");
        group.MapPut("/series/{id:guid}/watched", MarkSeriesWatchedAsync).WithName("MarkSeriesWatched");

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

        var watchlistIds = (await db.WatchlistItems
            .AsNoTracking()
            .Where(w => w.UserId == userId && w.MovieId != null)
            .Select(w => w.MovieId!.Value)
            .ToListAsync(cancellationToken))
            .ToHashSet();

        var result = movies
            .Select(m => MapMovie(m, progresses.GetValueOrDefault(m.Id), watchlistIds.Contains(m.Id)))
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

        var inWatchlist = await db.WatchlistItems
            .AsNoTracking()
            .AnyAsync(w => w.UserId == userId && w.MovieId == id, cancellationToken);

        return Results.Ok(MapMovie(movie, progress, inWatchlist));
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

        var watchlistIds = (await db.WatchlistItems
            .AsNoTracking()
            .Where(w => w.UserId == userId && w.TvSeriesId != null)
            .Select(w => w.TvSeriesId!.Value)
            .ToListAsync(cancellationToken))
            .ToHashSet();

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
                            .ToList(),
                        sn.ExpectedEpisodeCount))
                    .ToList(),
                s.AddedAtUtc,
                s.Rating,
                CinemaMetadataEnricher.ParseGenresCsv(s.GenresCsv),
                watchlistIds.Contains(s.Id),
                CinemaMetadataEnricher.DeserializeCastJson(s.CastJson)
                    .Select(c => new CastMemberDto(c.Name, c.Role, c.ArtworkHash))
                    .ToList()))
            .ToList();

        return Results.Ok(result);
    }

    private static async Task<IResult> UpdateWatchlistAsync(
        UpdateWatchlistRequest request,
        ClaimsPrincipal principal,
        HermesDbContext db,
        TimeProvider timeProvider,
        CancellationToken cancellationToken)
    {
        if (!principal.TryGetUserId(out var userId))
        {
            return Results.Unauthorized();
        }

        if ((request.MovieId is null) == (request.TvSeriesId is null))
        {
            return Results.BadRequest(new { error = "specify_movie_or_series" });
        }

        var utcNow = timeProvider.GetUtcNow();
        if (request.MovieId is { } movieId)
        {
            if (!await db.Movies.AnyAsync(m => m.Id == movieId, cancellationToken))
            {
                return Results.NotFound(new { error = "movie_not_found" });
            }

            var existing = await db.WatchlistItems.SingleOrDefaultAsync(
                w => w.UserId == userId && w.MovieId == movieId,
                cancellationToken);

            if (request.InWatchlist && existing is null)
            {
                db.WatchlistItems.Add(WatchlistItem.ForMovie(userId, movieId, utcNow));
                await db.SaveChangesAsync(cancellationToken);
            }
            else if (!request.InWatchlist && existing is not null)
            {
                db.WatchlistItems.Remove(existing);
                await db.SaveChangesAsync(cancellationToken);
            }

            return Results.Ok(new WatchlistResponse(request.InWatchlist));
        }

        var seriesId = request.TvSeriesId!.Value;
        if (!await db.TvSeries.AnyAsync(s => s.Id == seriesId, cancellationToken))
        {
            return Results.NotFound(new { error = "series_not_found" });
        }

        var existingSeries = await db.WatchlistItems.SingleOrDefaultAsync(
            w => w.UserId == userId && w.TvSeriesId == seriesId,
            cancellationToken);

        if (request.InWatchlist && existingSeries is null)
        {
            db.WatchlistItems.Add(WatchlistItem.ForSeries(userId, seriesId, utcNow));
            await db.SaveChangesAsync(cancellationToken);
        }
        else if (!request.InWatchlist && existingSeries is not null)
        {
            db.WatchlistItems.Remove(existingSeries);
            await db.SaveChangesAsync(cancellationToken);
        }

        return Results.Ok(new WatchlistResponse(request.InWatchlist));
    }

    private static async Task<IResult> MarkSeriesWatchedAsync(
        Guid id,
        MarkSeriesWatchedRequest request,
        ClaimsPrincipal principal,
        HermesDbContext db,
        IHubContext<PlaybackSyncHub> hubContext,
        TimeProvider timeProvider,
        CancellationToken cancellationToken)
    {
        if (!principal.TryGetUserId(out var userId))
        {
            return Results.Unauthorized();
        }

        var series = await db.TvSeries
            .AsNoTracking()
            .Include(s => s.Seasons)
            .ThenInclude(sn => sn.Episodes)
            .ThenInclude(ep => ep.Sources)
            .SingleOrDefaultAsync(s => s.Id == id, cancellationToken);

        if (series is null)
        {
            return Results.NotFound(new { error = "series_not_found" });
        }

        var episodes = series.Seasons
            .SelectMany(sn => sn.Episodes)
            .ToList();
        var episodeIds = episodes.Select(e => e.Id).ToList();

        var existingProgress = await db.WatchProgresses
            .Where(p => p.UserId == userId && p.EpisodeId != null && episodeIds.Contains(p.EpisodeId.Value))
            .ToDictionaryAsync(p => p.EpisodeId!.Value, cancellationToken);

        var utcNow = timeProvider.GetUtcNow();
        var updatedEvents = new List<WatchProgressUpdatedEvent>(episodes.Count);

        foreach (var episode in episodes)
        {
            var durationMs = episode.Sources.MaxBy(s => s.Height)?.DurationMs ?? 0;
            if (!existingProgress.TryGetValue(episode.Id, out var progress))
            {
                if (!request.Watched)
                {
                    continue;
                }

                progress = WatchProgress.ForEpisode(userId, episode.Id);
                db.WatchProgresses.Add(progress);
            }

            if (request.Watched)
            {
                progress.UpdatePosition(durationMs, durationMs, utcNow);
                progress.SetWatched(true, utcNow);
            }
            else
            {
                progress.UpdatePosition(0, durationMs, utcNow);
                progress.SetWatched(false, utcNow);
            }

            updatedEvents.Add(new WatchProgressUpdatedEvent(
                null,
                episode.Id,
                progress.PositionMs,
                progress.DurationMs,
                progress.IsWatched,
                progress.UpdatedAtUtc));
        }

        await db.SaveChangesAsync(cancellationToken);

        foreach (var evt in updatedEvents)
        {
            await hubContext.Clients
                .Group(PlaybackSyncHub.UserGroupName(userId))
                .SendAsync("WatchProgressUpdated", evt, cancellationToken);
        }

        return Results.Ok(new SeriesWatchedResponse(id, request.Watched, updatedEvents.Count));
    }

    internal static MovieSummaryDto MapMovie(Movie movie, WatchProgress? progress, bool isInWatchlist = false) =>
        new(
            movie.Id,
            movie.Title,
            movie.Year,
            movie.Overview,
            movie.TmdbId,
            movie.ArtworkHash,
            movie.BackdropHash,
            MapProgress(progress),
            MapSources(movie.Sources),
            movie.AddedAtUtc,
            movie.Rating,
            CinemaMetadataEnricher.ParseGenresCsv(movie.GenresCsv),
            movie.RuntimeMinutes,
            isInWatchlist,
            CinemaMetadataEnricher.DeserializeCastJson(movie.CastJson)
                .Select(c => new CastMemberDto(c.Name, c.Role, c.ArtworkHash))
                .ToList());

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
