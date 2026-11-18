using Hermes.Domain.Enums;

namespace Hermes.Api.Features.Music;

public sealed record ArtistSummaryDto(
    Guid Id,
    string Name,
    string? ArtworkHash,
    int AlbumCount);

public sealed record AlbumSummaryDto(
    Guid Id,
    Guid ArtistId,
    string ArtistName,
    string Title,
    int? Year,
    string? ArtworkHash,
    int SongCount);

public sealed record SongArtistCreditDto(Guid ArtistId, string Name);

public sealed record SongDto(
    Guid Id,
    Guid ArtistId,
    string ArtistName,
    Guid AlbumId,
    string AlbumTitle,
    string Title,
    int TrackNumber,
    int DiscNumber,
    long DurationMs,
    string Codec,
    long BitrateBps,
    int SampleRateHz,
    int BitDepth,
    string? ArtworkHash,
    bool IsLiked,
    bool IsMissing,
    DateTimeOffset FileLastWriteUtc = default,
    IReadOnlyList<SongArtistCreditDto>? ArtistCredits = null);

public sealed record AlbumDetailDto(
    Guid Id,
    Guid ArtistId,
    string ArtistName,
    string Title,
    int? Year,
    string? ArtworkHash,
    IReadOnlyList<SongDto> Songs);

public sealed record ArtistDetailDto(
    Guid Id,
    string Name,
    string? ArtworkHash,
    IReadOnlyList<AlbumSummaryDto> Albums,
    IReadOnlyList<SongDto> Songs);

public sealed record LikeToggleResponse(Guid SongId, bool IsLiked);

public sealed record PlaylistTrackDto(int Position, SongDto Song);

public sealed record PlaylistSummaryDto(
    Guid Id,
    string Name,
    string? Description,
    int TrackCount,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset UpdatedAtUtc);

public sealed record PlaylistDetailDto(
    Guid Id,
    string Name,
    string? Description,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset UpdatedAtUtc,
    IReadOnlyList<PlaylistTrackDto> Tracks);

public sealed record CreatePlaylistRequest(string Name, string? Description = null);

public sealed record RenamePlaylistRequest(string Name, string? Description = null);

public sealed record AddPlaylistTrackRequest(Guid SongId);

public sealed record SongLyricLineDto(long? TimestampMs, string Text);

public sealed record SongLyricsDto(Guid SongId, bool IsSynced, string Source, IReadOnlyList<SongLyricLineDto> Lines);

public sealed record UnifiedSearchMovieHit(Guid Id, string Title, int? Year, string? ArtworkHash);

public sealed record UnifiedSearchSeriesHit(Guid Id, string Title, int? Year, string? ArtworkHash);

public sealed record UnifiedSearchResponse(
    string Query,
    IReadOnlyList<UnifiedSearchMovieHit> Movies,
    IReadOnlyList<UnifiedSearchSeriesHit> Series,
    IReadOnlyList<ArtistSummaryDto> Artists,
    IReadOnlyList<AlbumSummaryDto> Albums,
    IReadOnlyList<SongDto> Songs);

public sealed record PlaybackSessionDto(
    Guid SessionId,
    Guid UserId,
    long Version,
    string? ActiveRendererDeviceId,
    string? ActiveRendererDeviceName,
    PlaybackState State,
    RepeatMode RepeatMode,
    bool Shuffle,
    double Volume,
    int CurrentIndex,
    Guid? CurrentSongId,
    long PositionMs,
    IReadOnlyList<Guid> QueueSongIds,
    DateTimeOffset UpdatedAtUtc);

public sealed record OnlineDeviceDto(
    string DeviceId,
    string DeviceName,
    string Platform,
    DateTimeOffset ConnectedAtUtc);

public sealed record StartPlaybackCommand(IReadOnlyList<Guid> QueueSongIds, int StartIndex = 0);

public sealed record RemoteTransportCommand(
    PlaybackState State,
    int? CurrentIndex = null,
    long? PositionMs = null,
    RepeatMode? RepeatMode = null,
    bool? Shuffle = null,
    double? Volume = null);

public sealed record TransferOutputCommand(string TargetDeviceId, long? PositionMs = null);

public sealed record ProgressHeartbeatCommand(long PositionMs);

public sealed record RecordListenRequest(
    Guid SongId,
    long PositionMs,
    long DurationMs,
    string? DeviceId = null,
    string? ContextLabel = null,
    DateTimeOffset? ListenedAtUtc = null);

public sealed record RecordListenResponse(
    Guid Id,
    Guid SongId,
    DateTimeOffset ListenedAtUtc,
    bool Deduped);

public sealed record ListeningHistoryItemDto(
    Guid Id,
    DateTimeOffset ListenedAtUtc,
    string? DeviceId,
    string? ContextLabel,
    SongDto Song);
