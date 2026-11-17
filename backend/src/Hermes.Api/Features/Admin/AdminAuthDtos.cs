namespace Hermes.Api.Features.Admin;

public sealed record CreateInviteRequest(int MaxUses = 1, int ExpiresInHours = 24);

public sealed record InviteResponse(
    Guid Id,
    string Code,
    int MaxUses,
    int UsedCount,
    DateTimeOffset ExpiresAtUtc,
    bool IsRevoked);

public sealed record ResetCodeResponse(string ResetCode, DateTimeOffset ExpiresAtUtc);

public sealed record UserSummaryDto(
    Guid Id,
    string Username,
    string Role,
    bool IsActive,
    DateTimeOffset CreatedAtUtc);

public sealed record ActiveStreamSessionDto(
    string SessionId,
    string Kind,
    Guid UserId,
    string Username,
    string DeviceName,
    string Title,
    string Subtitle,
    double Progress,
    string Mode,
    string Bitrate,
    bool IsPaused,
    bool CanStop,
    string? ArtworkHash = null);
