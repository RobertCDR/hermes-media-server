using System.Security.Claims;
using Hermes.Api.Features.System;
using Hermes.Domain.Entities;
using Hermes.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Hermes.Api.Features.Music;

public static class PlaylistEndpoints
{
    public static IEndpointRouteBuilder MapPlaylistEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var playlists = endpoints.MapGroup("/api/v1/music/playlists")
            .RequireAuthorization();

        playlists.MapGet("/", ListPlaylistsAsync).WithName("ListPlaylists");
        playlists.MapGet("/{id:guid}", GetPlaylistAsync).WithName("GetPlaylist");
        playlists.MapPost("/", CreatePlaylistAsync).WithName("CreatePlaylist");
        playlists.MapPut("/{id:guid}", RenamePlaylistAsync).WithName("RenamePlaylist");
        playlists.MapDelete("/{id:guid}", DeletePlaylistAsync).WithName("DeletePlaylist");
        playlists.MapPost("/{id:guid}/tracks", AddTrackAsync).WithName("AddPlaylistTrack");
        playlists.MapDelete("/{id:guid}/tracks/{position:int}", RemoveTrackAsync).WithName("RemovePlaylistTrack");

        return endpoints;
    }

    private static async Task<IResult> ListPlaylistsAsync(
        ClaimsPrincipal principal,
        HermesDbContext db,
        CancellationToken cancellationToken)
    {
        if (!principal.TryGetUserId(out var userId))
        {
            return Results.Unauthorized();
        }

        var items = await db.Playlists
            .AsNoTracking()
            .Where(p => p.OwnerUserId == userId)
            .OrderByDescending(p => p.UpdatedAtUtc)
            .Select(p => new PlaylistSummaryDto(
                p.Id,
                p.Name,
                p.Description,
                p.Tracks.Count,
                p.CreatedAtUtc,
                p.UpdatedAtUtc))
            .ToListAsync(cancellationToken);

        return Results.Ok(items);
    }

    private static async Task<IResult> GetPlaylistAsync(
        Guid id,
        ClaimsPrincipal principal,
        HermesDbContext db,
        CancellationToken cancellationToken)
    {
        if (!principal.TryGetUserId(out var userId))
        {
            return Results.Unauthorized();
        }

        var detail = await LoadPlaylistDetailAsync(db, id, userId, cancellationToken);
        return detail is null
            ? Results.NotFound(new { error = "playlist_not_found" })
            : Results.Ok(detail);
    }

    private static async Task<IResult> CreatePlaylistAsync(
        CreatePlaylistRequest request,
        ClaimsPrincipal principal,
        HermesDbContext db,
        TimeProvider timeProvider,
        CancellationToken cancellationToken)
    {
        if (!principal.TryGetUserId(out var userId))
        {
            return Results.Unauthorized();
        }

        var name = request.Name?.Trim() ?? string.Empty;
        if (name.Length == 0)
        {
            return Results.BadRequest(new { error = "playlist_name_required" });
        }

        var playlist = new Playlist(userId, name, request.Description?.Trim(), timeProvider.GetUtcNow());
        db.Playlists.Add(playlist);
        await db.SaveChangesAsync(cancellationToken);

        var detail = new PlaylistDetailDto(
            playlist.Id,
            playlist.Name,
            playlist.Description,
            playlist.CreatedAtUtc,
            playlist.UpdatedAtUtc,
            []);

        return Results.Created($"/api/v1/music/playlists/{playlist.Id}", detail);
    }

    private static async Task<IResult> RenamePlaylistAsync(
        Guid id,
        RenamePlaylistRequest request,
        ClaimsPrincipal principal,
        HermesDbContext db,
        TimeProvider timeProvider,
        CancellationToken cancellationToken)
    {
        if (!principal.TryGetUserId(out var userId))
        {
            return Results.Unauthorized();
        }

        var name = request.Name?.Trim() ?? string.Empty;
        if (name.Length == 0)
        {
            return Results.BadRequest(new { error = "playlist_name_required" });
        }

        var playlist = await db.Playlists
            .SingleOrDefaultAsync(p => p.Id == id && p.OwnerUserId == userId, cancellationToken);
        if (playlist is null)
        {
            return Results.NotFound(new { error = "playlist_not_found" });
        }

        var utcNow = timeProvider.GetUtcNow();
        playlist.Rename(name, utcNow);
        if (request.Description is not null)
        {
            playlist.UpdateDescription(request.Description, utcNow);
        }

        await db.SaveChangesAsync(cancellationToken);

        var detail = await LoadPlaylistDetailAsync(db, id, userId, cancellationToken);
        return Results.Ok(detail);
    }

    private static async Task<IResult> DeletePlaylistAsync(
        Guid id,
        ClaimsPrincipal principal,
        HermesDbContext db,
        CancellationToken cancellationToken)
    {
        if (!principal.TryGetUserId(out var userId))
        {
            return Results.Unauthorized();
        }

        var playlist = await db.Playlists
            .SingleOrDefaultAsync(p => p.Id == id && p.OwnerUserId == userId, cancellationToken);
        if (playlist is null)
        {
            return Results.NotFound(new { error = "playlist_not_found" });
        }

        db.Playlists.Remove(playlist);
        await db.SaveChangesAsync(cancellationToken);
        return Results.NoContent();
    }

    private static async Task<IResult> AddTrackAsync(
        Guid id,
        AddPlaylistTrackRequest request,
        ClaimsPrincipal principal,
        HermesDbContext db,
        CancellationToken cancellationToken)
    {
        if (!principal.TryGetUserId(out var userId))
        {
            return Results.Unauthorized();
        }

        var playlist = await db.Playlists
            .SingleOrDefaultAsync(p => p.Id == id && p.OwnerUserId == userId, cancellationToken);
        if (playlist is null)
        {
            return Results.NotFound(new { error = "playlist_not_found" });
        }

        if (!await db.Songs.AnyAsync(s => s.Id == request.SongId, cancellationToken))
        {
            return Results.NotFound(new { error = "song_not_found" });
        }

        var existingMaxPosition = await db.PlaylistTracks
            .Where(t => t.PlaylistId == id)
            .Select(t => (int?)t.Position)
            .MaxAsync(cancellationToken);

        var nextPosition = existingMaxPosition.HasValue ? existingMaxPosition.Value + 1 : 0;
        db.PlaylistTracks.Add(new PlaylistTrack(id, request.SongId, nextPosition));
        await db.SaveChangesAsync(cancellationToken);

        var detail = await LoadPlaylistDetailAsync(db, id, userId, cancellationToken);
        return Results.Ok(detail);
    }

    private static async Task<IResult> RemoveTrackAsync(
        Guid id,
        int position,
        ClaimsPrincipal principal,
        HermesDbContext db,
        CancellationToken cancellationToken)
    {
        if (!principal.TryGetUserId(out var userId))
        {
            return Results.Unauthorized();
        }

        var playlistExists = await db.Playlists
            .AnyAsync(p => p.Id == id && p.OwnerUserId == userId, cancellationToken);
        if (!playlistExists)
        {
            return Results.NotFound(new { error = "playlist_not_found" });
        }

        var affected = await db.PlaylistTracks
            .Where(t => t.PlaylistId == id && t.Position >= position)
            .OrderBy(t => t.Position)
            .ToListAsync(cancellationToken);

        var target = affected.FirstOrDefault(t => t.Position == position);
        if (target is null)
        {
            return Results.NotFound(new { error = "playlist_track_not_found" });
        }

        await using var tx = await db.Database.BeginTransactionAsync(cancellationToken);
        db.PlaylistTracks.RemoveRange(affected);
        await db.SaveChangesAsync(cancellationToken);

        var shifted = affected
            .Where(t => t.Position > position)
            .Select(t => new PlaylistTrack(id, t.SongId, t.Position - 1))
            .ToList();

        if (shifted.Count > 0)
        {
            db.PlaylistTracks.AddRange(shifted);
            await db.SaveChangesAsync(cancellationToken);
        }

        await tx.CommitAsync(cancellationToken);

        var detail = await LoadPlaylistDetailAsync(db, id, userId, cancellationToken);
        return Results.Ok(detail);
    }

    private static async Task<PlaylistDetailDto?> LoadPlaylistDetailAsync(
        HermesDbContext db,
        Guid playlistId,
        Guid userId,
        CancellationToken cancellationToken)
    {
        var playlist = await db.Playlists
            .AsNoTracking()
            .SingleOrDefaultAsync(p => p.Id == playlistId && p.OwnerUserId == userId, cancellationToken);
        if (playlist is null)
        {
            return null;
        }

        var tracks = await db.PlaylistTracks
            .AsNoTracking()
            .Include(t => t.Song)
            .ThenInclude(s => s.Artist)
            .Include(t => t.Song)
            .ThenInclude(s => s.Album)
            .Include(t => t.Song)
            .ThenInclude(s => s.SongArtists)
            .ThenInclude(sa => sa.Artist)
            .Where(t => t.PlaylistId == playlistId)
            .OrderBy(t => t.Position)
            .ToListAsync(cancellationToken);

        var likedSet = await MusicEndpoints.LoadLikedSongIdsAsync(db, userId, cancellationToken);

        var trackDtos = tracks
            .Select(t => new PlaylistTrackDto(t.Position, MusicEndpoints.MapSong(t.Song, likedSet.Contains(t.SongId))))
            .ToList();

        return new PlaylistDetailDto(
            playlist.Id,
            playlist.Name,
            playlist.Description,
            playlist.CreatedAtUtc,
            playlist.UpdatedAtUtc,
            trackDtos);
    }
}
