namespace Hermes.Api.Features.Auth;

public sealed record RegisterRequest(string Username, string Password, string InviteCode);

public sealed record RegisterResponse(Guid UserId, string Username);

public sealed record LoginRequest(string Username, string Password, string DeviceId, string DeviceName);

public sealed record RefreshTokenRequest(string DeviceId, string RefreshToken);

public sealed record AuthTokenResponse(
    string AccessToken,
    string RefreshToken,
    Guid UserId,
    string Username,
    string Role);

public sealed record ChangePasswordRequest(string CurrentPassword, string NewPassword);

public sealed record ResetPasswordRequest(string Username, string ResetCode, string NewPassword);

public sealed record CreateStreamTicketRequest(Guid MediaSourceId);

public sealed record StreamTicketResponse(string Ticket, DateTimeOffset ExpiresAtUtc);
