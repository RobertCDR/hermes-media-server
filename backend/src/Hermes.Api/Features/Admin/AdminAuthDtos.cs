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
