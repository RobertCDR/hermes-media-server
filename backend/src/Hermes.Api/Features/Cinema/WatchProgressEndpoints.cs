using System.Security.Claims;
using Hermes.Api.Features.System;
using Hermes.Domain.Entities;
using Hermes.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Hermes.Api.Features.Cinema;

public static class WatchProgressEndpoints
{
    public static IEndpointRouteBuilder MapWatchProgressEndpoints(this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPut("/api/v1/cinema/progress", UpdateWatchProgressAsync)
            .RequireAuthorization()
            .WithName("UpdateWatchProgress");

        return endpoints;
    }

    private static async Task<IResult> UpdateWatchProgressAsync(
        UpdateWatchProgressRequest request,
        ClaimsPrincipal principal,
        HermesDbContext db,
        TimeProvider timeProvider,
        CancellationToken cancellationToken)
    {
        if (!principal.TryGetUserId(out var userId))
        {
            return Results.Unauthorized();
        }

        if ((request.MovieId is null) == (request.EpisodeId is null))
        {
            return Results.BadRequest(new { error = "specify_movie_or_episode" });
        }

        WatchProgress? progress;
        if (request.MovieId is { } movieId)
        {
            if (!await db.Movies.AnyAsync(m => m.Id == movieId, cancellationToken))
            {
                return Results.NotFound(new { error = "movie_not_found" });
            }

            progress = await db.WatchProgresses.SingleOrDefaultAsync(
                p => p.UserId == userId && p.MovieId == movieId,
                cancellationToken);
            if (progress is null)
            {
                progress = WatchProgress.ForMovie(userId, movieId);
                db.WatchProgresses.Add(progress);
            }
        }
        else
        {
            var episodeId = request.EpisodeId!.Value;
            if (!await db.Episodes.AnyAsync(e => e.Id == episodeId, cancellationToken))
            {
                return Results.NotFound(new { error = "episode_not_found" });
            }

            progress = await db.WatchProgresses.SingleOrDefaultAsync(
                p => p.UserId == userId && p.EpisodeId == episodeId,
                cancellationToken);
            if (progress is null)
            {
                progress = WatchProgress.ForEpisode(userId, episodeId);
                db.WatchProgresses.Add(progress);
            }
        }

        var utcNow = timeProvider.GetUtcNow();
        progress.UpdatePosition(request.PositionMs, request.DurationMs, utcNow);
        if (request.MarkWatched is { } watched)
        {
            progress.SetWatched(watched, utcNow);
        }

        await db.SaveChangesAsync(cancellationToken);

        return Results.Ok(CinemaEndpoints.MapProgress(progress));
    }
}
