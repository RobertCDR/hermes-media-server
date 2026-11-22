using Hermes.Api.Features.Music;
using Hermes.Api.Hubs;
using Hermes.Domain.Enums;
using Hermes.Domain.Ports;
using Hermes.Infrastructure.Persistence;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;

namespace Hermes.Api.Features.Admin;

public static class AdminSessionEndpoints
{
    public static IEndpointRouteBuilder MapAdminSessionEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints.MapGroup("/api/v1/admin/sessions")
            .RequireAuthorization("AdminOnly");

        group.MapGet("", ListActiveSessionsAsync).WithName("ListAdminActiveSessions");
        group.MapDelete("/{id}", StopSessionAsync).WithName("StopAdminSession");

        return endpoints;
    }

    private static async Task<IResult> ListActiveSessionsAsync(
        HermesDbContext db,
        ITranscodeSessionManager transcodeManager,
        CancellationToken cancellationToken)
    {
        var results = new List<ActiveStreamSessionDto>();

        var users = await db.Users
            .AsNoTracking()
            .ToDictionaryAsync(u => u.Id, u => u.Username, cancellationToken);

        var transcodes = transcodeManager.GetActiveSessions();
        if (transcodes.Count > 0)
        {
            var sourceIds = transcodes.Select(t => t.MediaSourceId).Distinct().ToList();
            var sources = await db.MediaSources
                .AsNoTracking()
                .Where(s => sourceIds.Contains(s.Id))
                .Include(s => s.Movie)
                .Include(s => s.Episode)
                .ThenInclude(e => e!.TvSeason)
                .ThenInclude(sn => sn.TvSeries)
                .ToDictionaryAsync(s => s.Id, cancellationToken);

            foreach (var tr in transcodes)
            {
                sources.TryGetValue(tr.MediaSourceId, out var src);
                var title = src?.Movie?.Title
                    ?? src?.Episode?.TvSeason.TvSeries.Title
                    ?? "Video Stream";
                var subtitle = src?.Episode is not null
                    ? $"S{src.Episode.TvSeason.SeasonNumber:D2}E{src.Episode.EpisodeNumber:D2} • {src.Episode.Title}"
                    : (src?.Movie?.Year?.ToString() ?? src?.SourceLabel ?? "Video");
                var artHash = src?.Movie?.BackdropHash
                    ?? src?.Movie?.ArtworkHash
                    ?? src?.Episode?.TvSeason.TvSeries.BackdropHash
                    ?? src?.Episode?.TvSeason.TvSeries.ArtworkHash;
                var bitrateMbps = Math.Max(1, Math.Round((src?.BitrateBps ?? 8_000_000) / 1_000_000.0, 1));

                results.Add(new ActiveStreamSessionDto(
                    $"transcode:{tr.SessionId}",
                    "video",
                    tr.UserId,
                    users.GetValueOrDefault(tr.UserId, "Member"),
                    "Web / Player",
                    title,
                    subtitle,
                    0.0,
                    $"Converting to {tr.QualityLabel}",
                    $"{bitrateMbps} Mbps",
                    false,
                    true,
                    artHash));
            }
        }

        var playbackSessions = (await db.PlaybackSessions
            .AsNoTracking()
            .Where(p => p.State != PlaybackState.Stopped)
            .OrderByDescending(p => p.UpdatedAtUtc)
            .ToListAsync(cancellationToken))
            .Where(p => p.CurrentSongId != null)
            .ToList();

        if (playbackSessions.Count > 0)
        {
            var songIds = playbackSessions
                .Where(p => p.CurrentSongId.HasValue)
                .Select(p => p.CurrentSongId!.Value)
                .Distinct()
                .ToList();

            var songs = await db.Songs
                .AsNoTracking()
                .Where(s => songIds.Contains(s.Id))
                .Include(s => s.Artist)
                .Include(s => s.Album)
                .ToDictionaryAsync(s => s.Id, cancellationToken);

            foreach (var p in playbackSessions)
            {
                if (p.CurrentSongId is not Guid songId || !songs.TryGetValue(songId, out var song))
                {
                    continue;
                }

                var ratio = song.DurationMs > 0
                    ? Math.Clamp((double)p.PositionMs / song.DurationMs, 0.0, 1.0)
                    : 0.0;
                var kbps = song.BitrateBps > 0 ? song.BitrateBps / 1000 : 320;

                results.Add(new ActiveStreamSessionDto(
                    $"music:{p.Id}",
                    "music",
                    p.UserId,
                    users.GetValueOrDefault(p.UserId, "Member"),
                    p.ActiveRendererDeviceName ?? "Hermes Client",
                    song.Title,
                    song.Artist.Name,
                    ratio,
                    $"Direct Play • {song.Codec.ToUpperInvariant()}",
                    $"{kbps} kbps",
                    p.State == PlaybackState.Paused,
                    true,
                    song.Album.ArtworkHash));
            }
        }

        return Results.Ok(results);
    }

    private static async Task<IResult> StopSessionAsync(
        string id,
        HermesDbContext db,
        ITranscodeSessionManager transcodeManager,
        PlaybackSessionLockProvider lockProvider,
        IHubContext<PlaybackSyncHub> hubContext,
        TimeProvider timeProvider,
        CancellationToken cancellationToken)
    {
        if (id.StartsWith("transcode:", StringComparison.OrdinalIgnoreCase) &&
            Guid.TryParse(id.AsSpan("transcode:".Length), out var transcodeId))
        {
            await transcodeManager.StopSessionAsync(transcodeId, cancellationToken);
            return Results.NoContent();
        }

        if (id.StartsWith("music:", StringComparison.OrdinalIgnoreCase) &&
            Guid.TryParse(id.AsSpan("music:".Length), out var sessionId))
        {
            var ownerUserId = await db.PlaybackSessions
                .AsNoTracking()
                .Where(p => p.Id == sessionId)
                .Select(p => (Guid?)p.UserId)
                .SingleOrDefaultAsync(cancellationToken);
            if (ownerUserId is null)
            {
                return Results.NotFound(new { error = "session_not_found" });
            }

            PlaybackSessionDto dto;
            var gate = lockProvider.GetLock(ownerUserId.Value);
            await gate.WaitAsync(cancellationToken);
            try
            {
                var session = await db.PlaybackSessions.SingleOrDefaultAsync(p => p.Id == sessionId, cancellationToken);
                if (session is null)
                {
                    return Results.NotFound(new { error = "session_not_found" });
                }

                session.ForceStop(timeProvider.GetUtcNow());
                await db.SaveChangesAsync(cancellationToken);
                dto = PlaybackConnectService.MapSession(session);
            }
            finally
            {
                gate.Release();
            }

            await hubContext.Clients
                .Group(PlaybackSyncHub.UserGroupName(dto.UserId))
                .SendAsync("SessionStateUpdated", dto, cancellationToken);

            return Results.NoContent();
        }

        return Results.NotFound(new { error = "session_not_found" });
    }
}
