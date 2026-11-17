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

public sealed record WatchProgressUpdatedEvent(
    Guid? MovieId,
    Guid? EpisodeId,
    long PositionMs,
    long DurationMs,
    bool IsWatched,
    DateTimeOffset UpdatedAtUtc);

public sealed record CastMemberDto(
    string Name,
    string Role,
    string? ArtworkHash);

public sealed record MovieSummaryDto(
    Guid Id,
    string Title,
    int? Year,
    string? Overview,
    int? TmdbId,
    string? ArtworkHash,
    string? BackdropHash,
    WatchProgressDto? WatchProgress,
    List<MediaSourceDto> Sources,
    DateTimeOffset AddedAtUtc = default,
    double? Rating = null,
    List<string>? Genres = null,
    int? RuntimeMinutes = null,
    bool IsInWatchlist = false,
    List<CastMemberDto>? Cast = null);

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
    List<EpisodeSummaryDto> Episodes,
    int? ExpectedEpisodeCount = null);

public sealed record TvSeriesSummaryDto(
    Guid Id,
    string Title,
    int? Year,
    string? Overview,
    int? TmdbId,
    string? ArtworkHash,
    string? BackdropHash,
    List<TvSeasonDto> Seasons,
    DateTimeOffset AddedAtUtc = default,
    double? Rating = null,
    List<string>? Genres = null,
    bool IsInWatchlist = false,
    List<CastMemberDto>? Cast = null);

public sealed record UpdateWatchProgressRequest(
    Guid? MovieId,
    Guid? EpisodeId,
    long PositionMs,
    long DurationMs,
    bool? MarkWatched = null);

public sealed record UpdateWatchlistRequest(
    Guid? MovieId,
    Guid? TvSeriesId,
    bool InWatchlist);

public sealed record WatchlistResponse(bool InWatchlist);

public sealed record MarkSeriesWatchedRequest(bool Watched);

public sealed record SeriesWatchedResponse(Guid SeriesId, bool Watched, int EpisodesUpdated);

public sealed record CustomListItemDto(
    Guid Id,
    Guid? MovieId,
    Guid? TvSeriesId,
    string MediaKind,
    string Title,
    int? Year,
    string? ArtworkHash,
    double? Rating,
    int Position,
    DateTimeOffset AddedAtUtc);

public sealed record CustomListDto(
    Guid Id,
    string Name,
    string? Description,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset UpdatedAtUtc,
    List<CustomListItemDto> Items);

public sealed record CreateCustomListRequest(string Name, string? Description = null);

public sealed record UpdateCustomListRequest(string Name, string? Description = null);

public sealed record AddCustomListItemRequest(Guid? MovieId, Guid? TvSeriesId);
