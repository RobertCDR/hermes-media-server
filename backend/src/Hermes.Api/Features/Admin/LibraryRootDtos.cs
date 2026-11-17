using Hermes.Domain.Enums;

namespace Hermes.Api.Features.Admin;

public sealed record CreateLibraryRootRequest(
    string Name,
    LibraryMediaType MediaType,
    string RootPath,
    bool WatchEnabled = true,
    bool FetchMetadata = true);

public sealed record UpdateLibraryRootRequest(
    string Name,
    string RootPath,
    bool WatchEnabled = true,
    bool FetchMetadata = true);

public sealed record LibraryRootResponse(
    Guid Id,
    string Name,
    LibraryMediaType MediaType,
    string RootPath,
    bool WatchEnabled,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset? LastScanCompletedAtUtc,
    int ItemCount = 0,
    long TotalSizeBytes = 0,
    bool IsScanning = false,
    int ScanProcessedFiles = 0,
    int ScanTotalFiles = 0,
    bool FetchMetadata = true);

public sealed record ServerSettingsResponse(
    Guid ServerId,
    string ServerName,
    bool TranscodingEnabled,
    int MaxConcurrentVideoTranscodes,
    int MaxConcurrentAudioTranscodes,
    int? MaxRemoteVideoBitrateBps,
    HardwareAccelerationMode HardwareAccelerationMode,
    DateTimeOffset UpdatedAtUtc,
    long TotalMediaSizeBytes,
    int LibraryCount,
    int TotalMovies,
    int TotalSeries,
    int TotalEpisodes,
    int TotalSongs);

public sealed record UpdateServerSettingsRequest(
    string ServerName,
    bool TranscodingEnabled,
    int MaxConcurrentVideoTranscodes,
    int MaxConcurrentAudioTranscodes,
    int? MaxRemoteVideoBitrateBps,
    HardwareAccelerationMode HardwareAccelerationMode);

public sealed record LibraryScanSummaryDto(
    Guid LibraryRootId,
    int FilesDiscovered,
    int SourcesUpserted,
    int SourcesMarkedMissing,
    DateTimeOffset CompletedAtUtc);

public sealed record UnmatchedMediaDto(
    Guid Id,
    LibraryMediaType MediaType,
    string Title,
    int? Year,
    string LibraryName,
    string FilePath);

public sealed record TmdbCandidateDto(
    int TmdbId,
    string Title,
    int? Year,
    string? Overview);

public sealed record IdentifyMediaRequest(
    int TmdbId,
    string Title,
    int? Year,
    string? Overview);

public sealed record IdentifyMediaResponse(
    Guid Id,
    int TmdbId,
    string Title,
    int? Year,
    bool IsMetadataLocked);
