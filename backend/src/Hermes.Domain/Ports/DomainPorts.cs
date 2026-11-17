using Hermes.Domain.Enums;

namespace Hermes.Domain.Ports;

public interface IPasswordHasher
{
    string HashPassword(string password);
    bool VerifyPassword(string password, string passwordHash);
}

public interface ITokenService
{
    string CreateAccessToken(Guid userId, string username, UserRole role);
    string CreateOpaqueRefreshToken();
    string HashToken(string rawToken);
}

public interface IStreamTicketService
{
    string CreateStreamTicket(Guid userId, Guid mediaSourceId, TimeSpan ttl);
    bool TryValidateStreamTicket(string ticket, Guid expectedMediaSourceId, out Guid userId);
}

public sealed record ProbedMediaStream(int StreamIndex, StreamKind Kind, string Codec, string Language, string Title, bool IsDefault);

public sealed record ProbedMediaInfo(
    string Container,
    string VideoCodec,
    string AudioCodec,
    int Width,
    int Height,
    bool IsHdr,
    long BitrateBps,
    long DurationMs,
    IReadOnlyList<ProbedMediaStream> Streams);

public interface IMediaProbeService
{
    Task<ProbedMediaInfo?> ProbeAsync(string filePath, CancellationToken cancellationToken);
}

public sealed record ProbedAudioTrackMetadata(
    string Title,
    string ArtistName,
    string AlbumTitle,
    int? Year,
    int TrackNumber,
    int DiscNumber,
    long DurationMs,
    string Codec,
    long BitrateBps,
    int SampleRateHz,
    int BitDepth,
    byte[]? EmbeddedArtworkBytes);

public interface IAudioMetadataReader
{
    ProbedAudioTrackMetadata? ReadMetadata(string filePath);
}

public sealed record TmdbSearchCandidate(int TmdbId, string Title, int? Year, string? Overview, string? PosterPath, string? BackdropPath);

public sealed record TmdbEpisodeCandidate(int EpisodeNumber, string Title, string? Overview, string? StillPath);

public sealed record TmdbCastCandidate(string Name, string Role, string? ProfilePath);

public sealed record TmdbSeasonCountCandidate(int SeasonNumber, int EpisodeCount);

public sealed record TmdbRichDetails(
    double? Rating,
    int? RuntimeMinutes,
    IReadOnlyList<string> Genres,
    IReadOnlyList<TmdbCastCandidate> Cast,
    IReadOnlyList<TmdbSeasonCountCandidate> Seasons);

public interface ITmdbClient
{
    Task<IReadOnlyList<TmdbSearchCandidate>> SearchAsync(LibraryMediaType mediaType, string query, int? year, CancellationToken cancellationToken);
    Task<TmdbSearchCandidate?> GetDetailsAsync(LibraryMediaType mediaType, int tmdbId, CancellationToken cancellationToken);
    Task<byte[]?> DownloadImageBytesAsync(string remotePath, CancellationToken cancellationToken);
    Task<IReadOnlyList<TmdbEpisodeCandidate>> GetSeasonEpisodesAsync(
        int seriesTmdbId,
        int seasonNumber,
        CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyList<TmdbEpisodeCandidate>>([]);

    Task<TmdbRichDetails?> GetRichDetailsAsync(
        LibraryMediaType mediaType,
        int tmdbId,
        CancellationToken cancellationToken) =>
        Task.FromResult<TmdbRichDetails?>(null);
}

public interface IArtworkStore
{
    Task<string?> SaveArtworkVariantsAsync(byte[] sourceImageBytes, CancellationToken cancellationToken);
    string? ResolveVariantFilePath(string artworkHash, string variant);
}

public sealed record TranscodeSessionLease(Guid SessionId, string PlaylistFilePath, string SegmentDirectory);

public sealed record ActiveTranscodeSessionInfo(
    Guid SessionId,
    Guid UserId,
    Guid MediaSourceId,
    string QualityLabel,
    DateTimeOffset StartedAtUtc);

public interface ITranscodeSessionManager
{
    Task<TranscodeSessionLease?> TryStartVideoHlsSessionAsync(
        Guid userId,
        Guid mediaSourceId,
        string sourceFilePath,
        VideoQualityPreset quality,
        int audioStreamIndex,
        long startSeconds,
        int maxConcurrentSlots,
        CancellationToken cancellationToken,
        HardwareAccelerationMode hardwareAcceleration = HardwareAccelerationMode.None);

    Task StopSessionAsync(Guid sessionId, CancellationToken cancellationToken);
    string? ResolveHlsAssetPath(Guid sessionId, string fileName);
    IReadOnlyList<ActiveTranscodeSessionInfo> GetActiveSessions() => [];
}

public sealed record OnlineDeviceInfo(string DeviceId, string DeviceName, string Platform, DateTimeOffset ConnectedAtUtc);

public interface IDevicePresenceRegistry
{
    void RegisterConnection(Guid userId, string connectionId, OnlineDeviceInfo device);
    (Guid UserId, string DeviceId)? RemoveConnection(string connectionId);
    IReadOnlyList<OnlineDeviceInfo> GetOnlineDevices(Guid userId);
    bool IsDeviceConnected(Guid userId, string deviceId);
}
