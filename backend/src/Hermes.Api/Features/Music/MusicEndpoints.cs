using System.Security.Claims;
using Hermes.Api.Features.System;
using Hermes.Domain.Entities;
using Hermes.Domain.Ports;
using Hermes.Infrastructure.Media;
using Hermes.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Hermes.Api.Features.Music;

public static class MusicEndpoints
{
    public static IEndpointRouteBuilder MapMusicEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var music = endpoints.MapGroup("/api/v1/music")
            .RequireAuthorization();

        music.MapGet("/artists", ListArtistsAsync).WithName("ListArtists");
        music.MapGet("/artists/{id:guid}", GetArtistAsync).WithName("GetArtist");
        music.MapGet("/albums", ListAlbumsAsync).WithName("ListAlbums");
        music.MapGet("/albums/{id:guid}", GetAlbumAsync).WithName("GetAlbum");
        music.MapGet("/songs", ListSongsAsync).WithName("ListSongs");
        music.MapGet("/songs/{id:guid}/lyrics", GetSongLyricsAsync).WithName("GetSongLyrics");
        music.MapGet("/songs/liked", ListLikedSongsAsync).WithName("ListLikedSongs");
        music.MapPost("/songs/{id:guid}/like", ToggleLikeSongAsync).WithName("ToggleLikeSong");
        music.MapGet("/session", GetCurrentPlaybackSessionAsync).WithName("GetPlaybackSession");
        music.MapGet("/devices", GetOnlineDevicesAsync).WithName("GetOnlineDevices");

        endpoints.MapGet("/api/v1/search", SearchLibraryAsync)
            .RequireAuthorization()
            .WithName("UnifiedSearch");

        return endpoints;
    }

    private static async Task<IResult> ListArtistsAsync(HermesDbContext db, CancellationToken cancellationToken)
    {
        var artists = await db.Artists
            .AsNoTracking()
            .OrderBy(a => a.Name)
            .Select(a => new ArtistSummaryDto(a.Id, a.Name, a.ArtworkHash, a.Albums.Count))
            .ToListAsync(cancellationToken);

        return Results.Ok(artists);
    }

    private static async Task<IResult> GetArtistAsync(
        Guid id,
        ClaimsPrincipal principal,
        HermesDbContext db,
        CancellationToken cancellationToken)
    {
        if (!principal.TryGetUserId(out var userId))
        {
            return Results.Unauthorized();
        }

        var artist = await db.Artists
            .AsNoTracking()
            .Include(a => a.Albums)
            .SingleOrDefaultAsync(a => a.Id == id, cancellationToken);

        if (artist is null)
        {
            return Results.NotFound(new { error = "artist_not_found" });
        }

        var songs = await db.Songs
            .AsNoTracking()
            .Include(s => s.Artist)
            .Include(s => s.Album)
            .Where(s => s.ArtistId == id)
            .OrderBy(s => s.Album.Title)
            .ThenBy(s => s.DiscNumber)
            .ThenBy(s => s.TrackNumber)
            .ThenBy(s => s.Title)
            .ToListAsync(cancellationToken);

        var likedSet = await LoadLikedSongIdsAsync(db, userId, cancellationToken);

        var albumDtos = artist.Albums
            .OrderBy(a => a.Year ?? int.MaxValue)
            .ThenBy(a => a.Title)
            .Select(a => new AlbumSummaryDto(
                a.Id,
                artist.Id,
                artist.Name,
                a.Title,
                a.Year,
                a.ArtworkHash,
                songs.Count(s => s.AlbumId == a.Id)))
            .ToList();

        return Results.Ok(new ArtistDetailDto(
            artist.Id,
            artist.Name,
            artist.ArtworkHash,
            albumDtos,
            songs.Select(s => MapSong(s, likedSet.Contains(s.Id))).ToList()));
    }

    private static async Task<IResult> ListAlbumsAsync(HermesDbContext db, CancellationToken cancellationToken)
    {
        var albums = await db.Albums
            .AsNoTracking()
            .Include(a => a.Artist)
            .OrderBy(a => a.Title)
            .Select(a => new AlbumSummaryDto(
                a.Id,
                a.ArtistId,
                a.Artist.Name,
                a.Title,
                a.Year,
                a.ArtworkHash,
                a.Songs.Count))
            .ToListAsync(cancellationToken);

        return Results.Ok(albums);
    }

    private static async Task<IResult> GetAlbumAsync(
        Guid id,
        ClaimsPrincipal principal,
        HermesDbContext db,
        CancellationToken cancellationToken)
    {
        if (!principal.TryGetUserId(out var userId))
        {
            return Results.Unauthorized();
        }

        var album = await db.Albums
            .AsNoTracking()
            .Include(a => a.Artist)
            .SingleOrDefaultAsync(a => a.Id == id, cancellationToken);

        if (album is null)
        {
            return Results.NotFound(new { error = "album_not_found" });
        }

        var songs = await db.Songs
            .AsNoTracking()
            .Include(s => s.Artist)
            .Include(s => s.Album)
            .Where(s => s.AlbumId == id)
            .OrderBy(s => s.DiscNumber)
            .ThenBy(s => s.TrackNumber)
            .ThenBy(s => s.Title)
            .ToListAsync(cancellationToken);

        var likedSet = await LoadLikedSongIdsAsync(db, userId, cancellationToken);

        return Results.Ok(new AlbumDetailDto(
            album.Id,
            album.ArtistId,
            album.Artist.Name,
            album.Title,
            album.Year,
            album.ArtworkHash,
            songs.Select(s => MapSong(s, likedSet.Contains(s.Id))).ToList()));
    }

    private static async Task<IResult> ListSongsAsync(
        ClaimsPrincipal principal,
        HermesDbContext db,
        CancellationToken cancellationToken)
    {
        if (!principal.TryGetUserId(out var userId))
        {
            return Results.Unauthorized();
        }

        var songs = await db.Songs
            .AsNoTracking()
            .Include(s => s.Artist)
            .Include(s => s.Album)
            .OrderBy(s => s.Artist.Name)
            .ThenBy(s => s.Album.Title)
            .ThenBy(s => s.DiscNumber)
            .ThenBy(s => s.TrackNumber)
            .ThenBy(s => s.Title)
            .ToListAsync(cancellationToken);

        var likedSet = await LoadLikedSongIdsAsync(db, userId, cancellationToken);
        return Results.Ok(songs.Select(s => MapSong(s, likedSet.Contains(s.Id))).ToList());
    }

    private static async Task<IResult> ListLikedSongsAsync(
        ClaimsPrincipal principal,
        HermesDbContext db,
        CancellationToken cancellationToken)
    {
        if (!principal.TryGetUserId(out var userId))
        {
            return Results.Unauthorized();
        }

        var likedRows = await db.LikedSongs
            .AsNoTracking()
            .Where(l => l.UserId == userId)
            .OrderByDescending(l => l.LikedAtUtc)
            .Join(
                db.Songs.AsNoTracking().Include(s => s.Artist).Include(s => s.Album),
                l => l.SongId,
                s => s.Id,
                (_, s) => s)
            .ToListAsync(cancellationToken);

        return Results.Ok(likedRows.Select(s => MapSong(s, isLiked: true)).ToList());
    }

    private static async Task<IResult> ToggleLikeSongAsync(
        Guid id,
        ClaimsPrincipal principal,
        HermesDbContext db,
        TimeProvider timeProvider,
        CancellationToken cancellationToken)
    {
        if (!principal.TryGetUserId(out var userId))
        {
            return Results.Unauthorized();
        }

        if (!await db.Songs.AnyAsync(s => s.Id == id, cancellationToken))
        {
            return Results.NotFound(new { error = "song_not_found" });
        }

        var existing = await db.LikedSongs
            .SingleOrDefaultAsync(l => l.UserId == userId && l.SongId == id, cancellationToken);

        bool isLiked;
        if (existing is not null)
        {
            db.LikedSongs.Remove(existing);
            isLiked = false;
        }
        else
        {
            db.LikedSongs.Add(new LikedSong(userId, id, timeProvider.GetUtcNow()));
            isLiked = true;
        }

        await db.SaveChangesAsync(cancellationToken);
        return Results.Ok(new LikeToggleResponse(id, isLiked));
    }

    private static async Task<IResult> GetCurrentPlaybackSessionAsync(
        ClaimsPrincipal principal,
        PlaybackConnectService connectService,
        CancellationToken cancellationToken)
    {
        if (!principal.TryGetUserId(out var userId))
        {
            return Results.Unauthorized();
        }

        var session = await connectService.GetOrCreateSessionAsync(userId, cancellationToken);
        return Results.Ok(session);
    }

    private static IResult GetOnlineDevicesAsync(
        ClaimsPrincipal principal,
        IDevicePresenceRegistry presenceRegistry)
    {
        if (!principal.TryGetUserId(out var userId))
        {
            return Results.Unauthorized();
        }

        var devices = presenceRegistry.GetOnlineDevices(userId)
            .Select(d => new OnlineDeviceDto(d.DeviceId, d.DeviceName, d.Platform, d.ConnectedAtUtc))
            .ToList();

        return Results.Ok(devices);
    }

    private static async Task<IResult> SearchLibraryAsync(
        string? q,
        ClaimsPrincipal principal,
        HermesDbContext db,
        CancellationToken cancellationToken)
    {
        if (!principal.TryGetUserId(out var userId))
        {
            return Results.Unauthorized();
        }

        var trimmed = q?.Trim() ?? string.Empty;
        if (trimmed.Length == 0)
        {
            return Results.Ok(new UnifiedSearchResponse(trimmed, [], [], [], [], []));
        }

        var pattern = $"%{EscapeLikePattern(trimmed)}%";

        // Native PostgreSQL pg_trgm-backed ILIKE queries executed strictly sequentially on HermesDbContext.
        var movies = await db.Movies
            .AsNoTracking()
            .Where(m => EF.Functions.ILike(m.Title, pattern, "\\"))
            .OrderBy(m => m.Title)
            .Take(25)
            .Select(m => new UnifiedSearchMovieHit(m.Id, m.Title, m.Year, m.ArtworkHash))
            .ToListAsync(cancellationToken);

        var series = await db.TvSeries
            .AsNoTracking()
            .Where(s => EF.Functions.ILike(s.Title, pattern, "\\"))
            .OrderBy(s => s.Title)
            .Take(25)
            .Select(s => new UnifiedSearchSeriesHit(s.Id, s.Title, s.Year, s.ArtworkHash))
            .ToListAsync(cancellationToken);

        var artists = await db.Artists
            .AsNoTracking()
            .Where(a => EF.Functions.ILike(a.Name, pattern, "\\"))
            .OrderBy(a => a.Name)
            .Take(25)
            .Select(a => new ArtistSummaryDto(a.Id, a.Name, a.ArtworkHash, a.Albums.Count))
            .ToListAsync(cancellationToken);

        var albums = await db.Albums
            .AsNoTracking()
            .Include(a => a.Artist)
            .Where(a => EF.Functions.ILike(a.Title, pattern, "\\"))
            .OrderBy(a => a.Title)
            .Take(25)
            .Select(a => new AlbumSummaryDto(a.Id, a.ArtistId, a.Artist.Name, a.Title, a.Year, a.ArtworkHash, a.Songs.Count))
            .ToListAsync(cancellationToken);

        var songs = await db.Songs
            .AsNoTracking()
            .Include(s => s.Artist)
            .Include(s => s.Album)
            .Where(s => EF.Functions.ILike(s.Title, pattern, "\\"))
            .OrderBy(s => s.Title)
            .Take(25)
            .ToListAsync(cancellationToken);

        var likedSet = await LoadLikedSongIdsAsync(db, userId, cancellationToken);

        return Results.Ok(new UnifiedSearchResponse(
            trimmed,
            movies,
            series,
            artists,
            albums,
            songs.Select(s => MapSong(s, likedSet.Contains(s.Id))).ToList()));
    }

    internal static async Task<HashSet<Guid>> LoadLikedSongIdsAsync(
        HermesDbContext db,
        Guid userId,
        CancellationToken cancellationToken)
    {
        var ids = await db.LikedSongs
            .AsNoTracking()
            .Where(l => l.UserId == userId)
            .Select(l => l.SongId)
            .ToListAsync(cancellationToken);

        return [.. ids];
    }

    internal static SongDto MapSong(Song song, bool isLiked) =>
        new(
            song.Id,
            song.ArtistId,
            song.Artist.Name,
            song.AlbumId,
            song.Album.Title,
            song.Title,
            song.TrackNumber,
            song.DiscNumber,
            song.DurationMs,
            song.Codec,
            song.BitrateBps,
            song.SampleRateHz,
            song.BitDepth,
            song.Album.ArtworkHash,
            isLiked,
            song.MissingSinceUtc is not null,
            song.FileLastWriteUtc);

    private static async Task<IResult> GetSongLyricsAsync(
        Guid id,
        HermesDbContext db,
        LrcLyricsService lyricsService,
        CancellationToken cancellationToken)
    {
        var song = await db.Songs
            .AsNoTracking()
            .Where(s => s.Id == id)
            .Select(s => new { s.Id, s.FilePath })
            .SingleOrDefaultAsync(cancellationToken);

        if (song is null)
        {
            return Results.NotFound(new { error = "song_not_found" });
        }

        var result = await lyricsService.ReadLyricsAsync(song.FilePath, cancellationToken);
        return Results.Ok(new SongLyricsDto(
            song.Id,
            result.IsSynced,
            result.Source,
            result.Lines.Select(l => new SongLyricLineDto(l.TimestampMs, l.Text)).ToList()));
    }

    private static string EscapeLikePattern(string input) =>
        input.Replace("\\", "\\\\", StringComparison.Ordinal)
             .Replace("%", "\\%", StringComparison.Ordinal)
             .Replace("_", "\\_", StringComparison.Ordinal);
}
