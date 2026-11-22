using System.ComponentModel.DataAnnotations.Schema;
using Hermes.Domain.Enums;

namespace Hermes.Domain.Entities;

public sealed class Artist
{
    private Artist()
    {
        Name = string.Empty;
    }

    public Artist(string name, string? artworkHash = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        Id = Guid.NewGuid();
        Name = name.Trim();
        ArtworkHash = artworkHash;
    }

    public Guid Id { get; private set; }
    public string Name { get; private set; }
    public string? ArtworkHash { get; private set; }

    public ICollection<Album> Albums { get; } = [];
    public ICollection<Song> Songs { get; } = [];
    public ICollection<SongArtist> SongArtists { get; } = [];
}

public sealed class Album
{
    private Album()
    {
        Title = string.Empty;
    }

    public Album(Guid artistId, string title, int? year = null, string? artworkHash = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(title);
        Id = Guid.NewGuid();
        ArtistId = artistId;
        Title = title.Trim();
        Year = year;
        ArtworkHash = artworkHash;
    }

    public Guid Id { get; private set; }
    public Guid ArtistId { get; private set; }
    public string Title { get; private set; }
    public int? Year { get; private set; }
    public string? ArtworkHash { get; private set; }

    public Artist Artist { get; private set; } = null!;
    public ICollection<Song> Songs { get; } = [];
}

public sealed class Song
{
    private Song()
    {
        Title = string.Empty;
        FilePath = string.Empty;
        Codec = string.Empty;
    }

    public Song(
        Guid libraryRootId,
        Guid artistId,
        Guid albumId,
        string title,
        int trackNumber,
        int discNumber,
        long durationMs,
        string filePath,
        string codec,
        long bitrateBps,
        int sampleRateHz,
        int bitDepth,
        long fileSizeBytes,
        DateTimeOffset fileLastWriteUtc)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(title);
        ArgumentException.ThrowIfNullOrWhiteSpace(filePath);

        Id = Guid.NewGuid();
        LibraryRootId = libraryRootId;
        ArtistId = artistId;
        AlbumId = albumId;
        Title = title.Trim();
        TrackNumber = trackNumber;
        DiscNumber = discNumber;
        DurationMs = durationMs;
        FilePath = filePath.Trim();
        Codec = codec;
        BitrateBps = bitrateBps;
        SampleRateHz = sampleRateHz;
        BitDepth = bitDepth;
        FileSizeBytes = fileSizeBytes;
        FileLastWriteUtc = fileLastWriteUtc;
    }

    public Guid Id { get; private set; }
    public Guid LibraryRootId { get; private set; }
    public Guid ArtistId { get; private set; }
    public Guid AlbumId { get; private set; }
    public string Title { get; private set; }
    public int TrackNumber { get; private set; }
    public int DiscNumber { get; private set; }
    public long DurationMs { get; private set; }
    public string FilePath { get; private set; }
    public string Codec { get; private set; }
    public long BitrateBps { get; private set; }
    public int SampleRateHz { get; private set; }
    public int BitDepth { get; private set; }
    public long FileSizeBytes { get; private set; }
    public DateTimeOffset FileLastWriteUtc { get; private set; }
    public DateTimeOffset? MissingSinceUtc { get; private set; }

    public Artist Artist { get; private set; } = null!;
    public Album Album { get; private set; } = null!;
    public ICollection<SongArtist> SongArtists { get; } = [];

    public void MarkMissing(DateTimeOffset utcNow) => MissingSinceUtc ??= utcNow;

    public void UpdateFileFingerprint(long fileSizeBytes, DateTimeOffset fileLastWriteUtc)
    {
        FileSizeBytes = fileSizeBytes;
        FileLastWriteUtc = fileLastWriteUtc;
        MissingSinceUtc = null;
    }
}

public sealed class Playlist
{
    private Playlist()
    {
        Name = string.Empty;
    }

    public Playlist(Guid ownerUserId, string name, string? description, DateTimeOffset utcNow)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(name);

        Id = Guid.NewGuid();
        OwnerUserId = ownerUserId;
        Name = name.Trim();
        Description = description;
        CreatedAtUtc = utcNow;
        UpdatedAtUtc = utcNow;
    }

    public Guid Id { get; private set; }
    public Guid OwnerUserId { get; private set; }
    public string Name { get; private set; }
    public string? Description { get; private set; }
    public DateTimeOffset CreatedAtUtc { get; private set; }
    public DateTimeOffset UpdatedAtUtc { get; private set; }

    public ICollection<PlaylistTrack> Tracks { get; } = [];

    public void Rename(string name, DateTimeOffset utcNow)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        Name = name.Trim();
        UpdatedAtUtc = utcNow;
    }

    public void UpdateDescription(string? description, DateTimeOffset utcNow)
    {
        Description = string.IsNullOrWhiteSpace(description) ? null : description.Trim();
        UpdatedAtUtc = utcNow;
    }

    public void Touch(DateTimeOffset utcNow) => UpdatedAtUtc = utcNow;
}

public sealed class PlaylistTrack
{
    private PlaylistTrack()
    {
    }

    public PlaylistTrack(Guid playlistId, Guid songId, int position)
    {
        Id = Guid.NewGuid();
        PlaylistId = playlistId;
        SongId = songId;
        Position = position;
    }

    public Guid Id { get; private set; }
    public Guid PlaylistId { get; private set; }
    public Guid SongId { get; private set; }
    public int Position { get; private set; }

    public Playlist Playlist { get; private set; } = null!;
    public Song Song { get; private set; } = null!;
}

public sealed class LikedSong
{
    private LikedSong()
    {
    }

    public LikedSong(Guid userId, Guid songId, DateTimeOffset likedAtUtc)
    {
        UserId = userId;
        SongId = songId;
        LikedAtUtc = likedAtUtc;
    }

    public Guid UserId { get; private set; }
    public Guid SongId { get; private set; }
    public DateTimeOffset LikedAtUtc { get; private set; }
}

public sealed class PlaybackSession
{
    private PlaybackSession()
    {
    }

    private PlaybackSession(Guid id, Guid userId, DateTimeOffset utcNow)
    {
        Id = id;
        UserId = userId;
        State = PlaybackState.Stopped;
        RepeatMode = RepeatMode.Off;
        Volume = 1.0;
        UpdatedAtUtc = utcNow;
    }

    public Guid Id { get; private set; }
    public Guid UserId { get; private set; }
    public long Version { get; private set; }
    public string? ActiveRendererDeviceId { get; private set; }
    public string? ActiveRendererDeviceName { get; private set; }
    public PlaybackState State { get; private set; }
    public RepeatMode RepeatMode { get; private set; }
    public bool Shuffle { get; private set; }
    public double Volume { get; private set; }
    public int CurrentIndex { get; private set; }
    public long PositionMs { get; private set; }
    public DateTimeOffset UpdatedAtUtc { get; private set; }

    public Guid[] QueueSongIds { get; private set; } = [];

    [NotMapped]
    public Guid? CurrentSongId =>
        CurrentIndex >= 0 && CurrentIndex < QueueSongIds.Length
            ? QueueSongIds[CurrentIndex]
            : null;

    public static PlaybackSession CreateForUser(Guid userId) =>
        new(Guid.NewGuid(), userId, DateTimeOffset.UtcNow);

    public void StartPlayback(string deviceId, string deviceName, IReadOnlyList<Guid> queueSongIds, int startIndex, DateTimeOffset utcNow)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(deviceId);
        ArgumentException.ThrowIfNullOrWhiteSpace(deviceName);

        QueueSongIds = [.. queueSongIds];
        CurrentIndex = queueSongIds.Count == 0 ? 0 : Math.Clamp(startIndex, 0, queueSongIds.Count - 1);
        PositionMs = 0;
        ActiveRendererDeviceId = deviceId;
        ActiveRendererDeviceName = deviceName;
        State = queueSongIds.Count > 0 ? PlaybackState.Playing : PlaybackState.Stopped;
        Version++;
        UpdatedAtUtc = utcNow;
    }

    public void ApplyRemoteTransport(
        PlaybackState state,
        int? currentIndex,
        long? positionMs,
        DateTimeOffset utcNow,
        RepeatMode? repeatMode = null,
        bool? shuffle = null,
        double? volume = null,
        IReadOnlyList<Guid>? queueSongIds = null,
        string? callerDeviceId = null,
        string? callerDeviceName = null)
    {
        if (queueSongIds is { Count: > 0 })
        {
            QueueSongIds = [.. queueSongIds];
        }

        State = state;
        if (currentIndex is int idx && QueueSongIds.Length > 0)
        {
            CurrentIndex = Math.Clamp(idx, 0, QueueSongIds.Length - 1);
        }
        else if (QueueSongIds.Length > 0)
        {
            CurrentIndex = Math.Clamp(CurrentIndex, 0, QueueSongIds.Length - 1);
        }

        if (ActiveRendererDeviceId is null &&
            state == PlaybackState.Playing &&
            !string.IsNullOrWhiteSpace(callerDeviceId))
        {
            ActiveRendererDeviceId = callerDeviceId;
            ActiveRendererDeviceName = string.IsNullOrWhiteSpace(callerDeviceName)
                ? "Hermes Client"
                : callerDeviceName;
        }

        if (positionMs is long pos)
        {
            PositionMs = Math.Max(0, pos);
        }

        if (repeatMode is RepeatMode rm)
        {
            RepeatMode = rm;
        }

        if (shuffle is bool sh)
        {
            Shuffle = sh;
        }

        if (volume is double vol)
        {
            Volume = Math.Clamp(vol, 0.0, 1.0);
        }

        Version++;
        UpdatedAtUtc = utcNow;
    }

    public void TransferOutput(string targetDeviceId, string targetDeviceName, DateTimeOffset utcNow, long? positionMs = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(targetDeviceId);
        ArgumentException.ThrowIfNullOrWhiteSpace(targetDeviceName);

        ActiveRendererDeviceId = targetDeviceId;
        ActiveRendererDeviceName = targetDeviceName;
        if (positionMs is long pos)
        {
            PositionMs = Math.Max(0, pos);
        }

        Version++;
        UpdatedAtUtc = utcNow;
    }

    public void UpdateProgress(long positionMs, DateTimeOffset utcNow)
    {
        PositionMs = Math.Max(0, positionMs);
        Version++;
        UpdatedAtUtc = utcNow;
    }

    public bool HandleDeviceDisconnected(string disconnectedDeviceId, DateTimeOffset utcNow)
    {
        if (!string.Equals(ActiveRendererDeviceId, disconnectedDeviceId, StringComparison.Ordinal))
        {
            return false;
        }

        ActiveRendererDeviceId = null;
        ActiveRendererDeviceName = null;
        if (State == PlaybackState.Playing)
        {
            State = PlaybackState.Paused;
        }

        Version++;
        UpdatedAtUtc = utcNow;
        return true;
    }
}

public sealed class SongArtist
{
    private SongArtist()
    {
    }

    public SongArtist(Guid songId, Guid artistId, int position)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(position, 0);
        SongId = songId;
        ArtistId = artistId;
        Position = position;
    }

    public Guid SongId { get; private set; }
    public Guid ArtistId { get; private set; }
    public int Position { get; private set; }

    public Song Song { get; private set; } = null!;
    public Artist Artist { get; private set; } = null!;
}

public sealed class ListeningHistoryEntry
{
    public static readonly TimeSpan DuplicateWindow = TimeSpan.FromMinutes(10);

    private ListeningHistoryEntry()
    {
    }

    public ListeningHistoryEntry(
        Guid userId,
        Guid songId,
        long positionMs,
        long durationMs,
        string? deviceId,
        string? contextLabel,
        DateTimeOffset listenedAtUtc)
    {
        Id = Guid.NewGuid();
        UserId = userId;
        SongId = songId;
        PositionMs = Math.Max(0, positionMs);
        DurationMs = Math.Max(0, durationMs);
        DeviceId = string.IsNullOrWhiteSpace(deviceId) ? null : deviceId.Trim()[..Math.Min(deviceId.Trim().Length, 128)];
        ContextLabel = string.IsNullOrWhiteSpace(contextLabel) ? null : contextLabel.Trim()[..Math.Min(contextLabel.Trim().Length, 256)];
        ListenedAtUtc = listenedAtUtc;
    }

    public Guid Id { get; private set; }
    public Guid UserId { get; private set; }
    public Guid SongId { get; private set; }
    public long PositionMs { get; private set; }
    public long DurationMs { get; private set; }
    public string? DeviceId { get; private set; }
    public string? ContextLabel { get; private set; }
    public DateTimeOffset ListenedAtUtc { get; private set; }

    public Song Song { get; private set; } = null!;

    public static long GetListenThresholdMs(long durationMs)
    {
        if (durationMs <= 0)
        {
            return 0;
        }

        return Math.Min(30_000L, Math.Max(5_000L, durationMs / 3));
    }
}
