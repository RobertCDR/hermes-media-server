using Hermes.Domain.Enums;

namespace Hermes.Domain.Ports;

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

public sealed record TmdbSearchCandidate(int TmdbId, string Title, int? Year, string? Overview, string? PosterPath, string? BackdropPath);

public interface ITmdbClient
{
    Task<IReadOnlyList<TmdbSearchCandidate>> SearchAsync(LibraryMediaType mediaType, string query, int? year, CancellationToken cancellationToken);
    Task<TmdbSearchCandidate?> GetDetailsAsync(LibraryMediaType mediaType, int tmdbId, CancellationToken cancellationToken);
    Task<byte[]?> DownloadImageBytesAsync(string remotePath, CancellationToken cancellationToken);
}

public interface IArtworkStore
{
    Task<string?> SaveArtworkVariantsAsync(byte[] sourceImageBytes, CancellationToken cancellationToken);
    string? ResolveVariantFilePath(string artworkHash, string variant);
}

public sealed record TranscodeSessionLease(Guid SessionId, string PlaylistFilePath, string SegmentDirectory);

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
        CancellationToken cancellationToken);

    Task StopSessionAsync(Guid sessionId, CancellationToken cancellationToken);
    string? ResolveHlsAssetPath(Guid sessionId, string fileName);
}

public sealed record OnlineDeviceInfo(string DeviceId, string DeviceName, string Platform, DateTimeOffset ConnectedAtUtc);

public interface IDevicePresenceRegistry
{
    void RegisterConnection(Guid userId, string connectionId, OnlineDeviceInfo device);
    (Guid UserId, string DeviceId)? RemoveConnection(string connectionId);
    IReadOnlyList<OnlineDeviceInfo> GetOnlineDevices(Guid userId);
    bool IsDeviceConnected(Guid userId, string deviceId);
}
