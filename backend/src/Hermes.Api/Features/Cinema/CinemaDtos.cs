using Hermes.Domain.Enums;

namespace Hermes.Api.Features.Cinema;

public sealed record MediaStreamDto(
    int StreamIndex,
    StreamKind Kind,
    string Codec,
    string Language,
    string Title,
    bool IsDefault);

public sealed record MediaSourceDto(
    Guid Id,
    string SourceLabel,
    string Container,
    string VideoCodec,
    string AudioCodec,
    int Width,
    int Height,
    bool IsHdr,
    long BitrateBps,
    long DurationMs,
    bool IsAvailable,
    List<MediaStreamDto> Streams);

public sealed record WatchProgressDto(
    long PositionMs,
    long DurationMs,
    bool IsWatched,
    DateTimeOffset UpdatedAtUtc);

public sealed record MovieSummaryDto(
    Guid Id,
    string Title,
    int? Year,
    string? Overview,
    int? TmdbId,
    string? ArtworkHash,
    string? BackdropHash,
    WatchProgressDto? WatchProgress,
    List<MediaSourceDto> Sources);

public sealed record EpisodeSummaryDto(
    Guid Id,
    int EpisodeNumber,
    string Title,
    string? Overview,
    string? StillArtworkHash,
    WatchProgressDto? WatchProgress,
    List<MediaSourceDto> Sources);

public sealed record TvSeasonDto(
    Guid Id,
    int SeasonNumber,
    string Title,
    string? ArtworkHash,
    List<EpisodeSummaryDto> Episodes);

public sealed record TvSeriesSummaryDto(
    Guid Id,
    string Title,
    int? Year,
    string? Overview,
    int? TmdbId,
    string? ArtworkHash,
    string? BackdropHash,
    List<TvSeasonDto> Seasons);

public sealed record UpdateWatchProgressRequest(
    Guid? MovieId,
    Guid? EpisodeId,
    long PositionMs,
    long DurationMs,
    bool? MarkWatched = null);
