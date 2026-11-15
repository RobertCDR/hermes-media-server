using Hermes.Domain.Enums;

namespace Hermes.Api.Features.Admin;

public sealed record CreateLibraryRootRequest(
    string Name,
    LibraryMediaType MediaType,
    string RootPath,
    bool WatchEnabled = true);

public sealed record LibraryRootResponse(
    Guid Id,
    string Name,
    LibraryMediaType MediaType,
    string RootPath,
    bool WatchEnabled,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset? LastScanCompletedAtUtc);

public sealed record LibraryScanSummaryDto(
    Guid LibraryRootId,
    int FilesDiscovered,
    int SourcesUpserted,
    int SourcesMarkedMissing,
    DateTimeOffset CompletedAtUtc);

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
