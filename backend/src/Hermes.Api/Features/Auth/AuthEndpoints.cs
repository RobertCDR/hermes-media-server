using System.Data.Common;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Hermes.Api.Features.System;
using Hermes.Domain.Entities;
using Hermes.Domain.Enums;
using Hermes.Domain.Ports;
using Hermes.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Hermes.Api.Features.Auth;

public static class AuthEndpoints
{
    internal const int MaxPasswordLength = 256;
    private static readonly TimeSpan RefreshTokenTtl = TimeSpan.FromDays(30);
    private static readonly TimeSpan StreamTicketTtl = TimeSpan.FromHours(6);

    public static IEndpointRouteBuilder MapAuthEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints.MapGroup("/api/v1/auth")
            .RequireRateLimiting("auth");

        group.MapPost("/register", RegisterAsync).AllowAnonymous().WithName("Register");
        group.MapPost("/login", LoginAsync).AllowAnonymous().WithName("Login");
        group.MapPost("/refresh", RefreshAsync).AllowAnonymous().WithName("RefreshToken");
        group.MapPost("/reset-password", ResetPasswordAsync).AllowAnonymous().WithName("ResetPassword");
        group.MapPost("/change-password", ChangePasswordAsync).RequireAuthorization().WithName("ChangePassword");
        group.MapPost("/stream-tickets", CreateStreamTicketAsync).RequireAuthorization().WithName("CreateStreamTicket");
        group.MapGet("/me/preferences", GetAccountPreferencesAsync).RequireAuthorization().WithName("GetAccountPreferences");
        group.MapPut("/me/preferences", UpdateAccountPreferencesAsync).RequireAuthorization().WithName("UpdateAccountPreferences");

        return endpoints;
    }

    private static async Task<IResult> RegisterAsync(
        RegisterRequest request,
        HermesDbContext db,
        IPasswordHasher passwordHasher,
        TimeProvider timeProvider,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.Username) || request.Username.Trim().Length < 2)
        {
            return Results.BadRequest(new { error = "invalid_username" });
        }

        if (string.IsNullOrWhiteSpace(request.Password) || request.Password.Length < 8)
        {
            return Results.BadRequest(new { error = "password_too_short" });
        }

        if (request.Password.Length > MaxPasswordLength)
        {
            return Results.BadRequest(new { error = "password_too_long" });
        }

        if (string.IsNullOrWhiteSpace(request.InviteCode))
        {
            return Results.BadRequest(new { error = "invalid_invite_code" });
        }

        var normalizedUsername = request.Username.Trim();
        var lowerUsername = normalizedUsername.ToLowerInvariant();
        if (normalizedUsername.Length > 64)
        {
            return Results.BadRequest(new { error = "invalid_username" });
        }

        var normalizedCode = request.InviteCode.Trim();
        var utcNow = timeProvider.GetUtcNow();

        await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);

        if (await db.Users.AnyAsync(u => u.Username.ToLower() == lowerUsername, cancellationToken))
        {
            return Results.Conflict(new { error = "username_already_exists" });
        }

        var redeemedInvites = await db.InviteCodes
            .Where(i => i.Code == normalizedCode && !i.IsRevoked && i.ExpiresAtUtc > utcNow && i.UsedCount < i.MaxUses)
            .ExecuteUpdateAsync(
                setters => setters.SetProperty(i => i.UsedCount, i => i.UsedCount + 1),
                cancellationToken);
        if (redeemedInvites == 0)
        {
            return Results.BadRequest(new { error = "invalid_or_expired_invite" });
        }

        var user = User.Create(normalizedUsername, passwordHasher.HashPassword(request.Password), UserRole.Member, utcNow);
        db.Users.Add(user);

        try
        {
            await db.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateException ex) when ((ex.InnerException as DbException)?.SqlState == "23505")
        {
            await transaction.RollbackAsync(cancellationToken);
            return Results.Conflict(new { error = "username_already_exists" });
        }

        await transaction.CommitAsync(cancellationToken);
        return Results.Created($"/api/v1/admin/users/{user.Id}", new RegisterResponse(user.Id, user.Username));
    }

    private static async Task<IResult> LoginAsync(
        LoginRequest request,
        HermesDbContext db,
        IPasswordHasher passwordHasher,
        ITokenService tokenService,
        TimeProvider timeProvider,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.Username) ||
            string.IsNullOrWhiteSpace(request.Password) ||
            string.IsNullOrWhiteSpace(request.DeviceId) ||
            string.IsNullOrWhiteSpace(request.DeviceName))
        {
            return Results.BadRequest(new { error = "invalid_login_request" });
        }

        if (request.Password.Length > MaxPasswordLength)
        {
            return Results.Unauthorized();
        }

        var lowerUsername = request.Username.Trim().ToLowerInvariant();
        var user = await db.Users.SingleOrDefaultAsync(u => u.Username.ToLower() == lowerUsername, cancellationToken);
        if (user is null || !user.IsActive || !passwordHasher.VerifyPassword(request.Password, user.PasswordHash))
        {
            return Results.Unauthorized();
        }

        var utcNow = timeProvider.GetUtcNow();
        var normalizedDeviceId = request.DeviceId.Trim();
        var normalizedDeviceName = request.DeviceName.Trim();

        var existingDeviceTokens = await db.RefreshTokens
            .Where(t => t.UserId == user.Id && t.DeviceId == normalizedDeviceId && t.RevokedAtUtc == null)
            .ToListAsync(cancellationToken);

        foreach (var oldToken in existingDeviceTokens)
        {
            oldToken.Revoke(utcNow);
        }

        var response = await IssueDeviceSessionAsync(
            db,
            tokenService,
            user,
            normalizedDeviceId,
            normalizedDeviceName,
            utcNow,
            cancellationToken);

        return Results.Ok(response);
    }

    private static async Task<IResult> RefreshAsync(
        RefreshTokenRequest request,
        HermesDbContext db,
        ITokenService tokenService,
        TimeProvider timeProvider,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.DeviceId) || string.IsNullOrWhiteSpace(request.RefreshToken))
        {
            return Results.Unauthorized();
        }

        var tokenHash = tokenService.HashToken(request.RefreshToken);
        var existing = await db.RefreshTokens
            .AsNoTracking()
            .Include(t => t.User)
            .SingleOrDefaultAsync(t => t.TokenHash == tokenHash, cancellationToken);

        var utcNow = timeProvider.GetUtcNow();
        var normalizedDeviceId = request.DeviceId.Trim();
        if (existing is null ||
            existing.DeviceId != normalizedDeviceId ||
            !existing.IsActive(utcNow) ||
            !existing.User.IsActive)
        {
            return Results.Unauthorized();
        }

        await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);

        var revokedCount = await db.RefreshTokens
            .Where(t => t.Id == existing.Id && t.RevokedAtUtc == null && t.ExpiresAtUtc > utcNow)
            .ExecuteUpdateAsync(
                setters => setters.SetProperty(t => t.RevokedAtUtc, utcNow),
                cancellationToken);
        if (revokedCount == 0)
        {
            return Results.Unauthorized();
        }

        var response = await IssueDeviceSessionAsync(
            db,
            tokenService,
            existing.User,
            existing.DeviceId,
            existing.DeviceName,
            utcNow,
            cancellationToken);

        await transaction.CommitAsync(cancellationToken);
        return Results.Ok(response);
    }

    private static async Task<IResult> ChangePasswordAsync(
        ChangePasswordRequest request,
        ClaimsPrincipal principal,
        HermesDbContext db,
        IPasswordHasher passwordHasher,
        TimeProvider timeProvider,
        CancellationToken cancellationToken)
    {
        if (!principal.TryGetUserId(out var userId))
        {
            return Results.Unauthorized();
        }

        if (string.IsNullOrWhiteSpace(request.NewPassword) || request.NewPassword.Length < 8)
        {
            return Results.BadRequest(new { error = "password_too_short" });
        }

        if (request.NewPassword.Length > MaxPasswordLength || request.CurrentPassword.Length > MaxPasswordLength)
        {
            return Results.BadRequest(new { error = "password_too_long" });
        }

        var user = await db.Users
            .Include(u => u.RefreshTokens)
            .SingleOrDefaultAsync(u => u.Id == userId, cancellationToken);

        if (user is null || !user.IsActive)
        {
            return Results.Unauthorized();
        }

        if (!passwordHasher.VerifyPassword(request.CurrentPassword, user.PasswordHash))
        {
            return Results.BadRequest(new { error = "invalid_current_password" });
        }

        var utcNow = timeProvider.GetUtcNow();
        user.ChangePassword(passwordHasher.HashPassword(request.NewPassword), utcNow);
        await db.SaveChangesAsync(cancellationToken);

        return Results.Ok(new { changed = true });
    }

    private static async Task<IResult> ResetPasswordAsync(
        ResetPasswordRequest request,
        HermesDbContext db,
        IPasswordHasher passwordHasher,
        ITokenService tokenService,
        TimeProvider timeProvider,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.Username) ||
            string.IsNullOrWhiteSpace(request.ResetCode) ||
            string.IsNullOrWhiteSpace(request.NewPassword) ||
            request.NewPassword.Length < 8 ||
            request.NewPassword.Length > MaxPasswordLength)
        {
            return Results.BadRequest(new { error = "invalid_reset_request" });
        }

        var lowerUsername = request.Username.Trim().ToLowerInvariant();
        var user = await db.Users
            .Include(u => u.RefreshTokens)
            .SingleOrDefaultAsync(u => u.Username.ToLower() == lowerUsername, cancellationToken);

        var utcNow = timeProvider.GetUtcNow();
        if (user is null ||
            !user.IsActive ||
            string.IsNullOrEmpty(user.OneTimeResetCodeHash) ||
            user.OneTimeResetExpiresAtUtc is not { } expiresAt ||
            utcNow >= expiresAt)
        {
            return Results.BadRequest(new { error = "invalid_or_expired_reset_code" });
        }

        var providedBytes = Encoding.UTF8.GetBytes(tokenService.HashToken(request.ResetCode.Trim()));
        var expectedBytes = Encoding.UTF8.GetBytes(user.OneTimeResetCodeHash);
        if (providedBytes.Length != expectedBytes.Length ||
            !CryptographicOperations.FixedTimeEquals(providedBytes, expectedBytes))
        {
            return Results.BadRequest(new { error = "invalid_or_expired_reset_code" });
        }

        user.ChangePassword(passwordHasher.HashPassword(request.NewPassword), utcNow);
        await db.SaveChangesAsync(cancellationToken);

        return Results.Ok(new { reset = true });
    }

    private static async Task<IResult> CreateStreamTicketAsync(
        CreateStreamTicketRequest request,
        ClaimsPrincipal principal,
        HermesDbContext db,
        IStreamTicketService streamTicketService,
        TimeProvider timeProvider,
        CancellationToken cancellationToken)
    {
        if (!principal.TryGetUserId(out var userId))
        {
            return Results.Unauthorized();
        }

        var isActive = await db.Users
            .AsNoTracking()
            .AnyAsync(u => u.Id == userId && u.IsActive, cancellationToken);
        if (!isActive)
        {
            return Results.Unauthorized();
        }

        if (request.MediaSourceId == Guid.Empty)
        {
            return Results.BadRequest(new { error = "invalid_media_source_id" });
        }

        var ticket = streamTicketService.CreateStreamTicket(userId, request.MediaSourceId, StreamTicketTtl);
        return Results.Ok(new StreamTicketResponse(ticket, timeProvider.GetUtcNow().Add(StreamTicketTtl)));
    }

    private static async Task<IResult> GetAccountPreferencesAsync(
        ClaimsPrincipal principal,
        HermesDbContext db,
        CancellationToken cancellationToken)
    {
        if (!principal.TryGetUserId(out var userId))
        {
            return Results.Unauthorized();
        }

        var user = await db.Users
            .AsNoTracking()
            .SingleOrDefaultAsync(u => u.Id == userId, cancellationToken);

        if (user is null || !user.IsActive)
        {
            return Results.Unauthorized();
        }

        return Results.Ok(ToPreferencesDto(user));
    }

    private static async Task<IResult> UpdateAccountPreferencesAsync(
        UpdateAccountPreferencesRequest request,
        ClaimsPrincipal principal,
        HermesDbContext db,
        CancellationToken cancellationToken)
    {
        if (!principal.TryGetUserId(out var userId))
        {
            return Results.Unauthorized();
        }

        var user = await db.Users
            .SingleOrDefaultAsync(u => u.Id == userId, cancellationToken);

        if (user is null || !user.IsActive)
        {
            return Results.Unauthorized();
        }

        try
        {
            user.UpdateAccountPreferences(
                request.AutoplayNextEpisode,
                request.NormalizeVolume,
                request.MatchTitleColors,
                request.SubtitleSize,
                request.SubtitleBackground);
        }
        catch (ArgumentException)
        {
            return Results.BadRequest(new { error = "invalid_account_preferences" });
        }

        await db.SaveChangesAsync(cancellationToken);
        return Results.Ok(ToPreferencesDto(user));
    }

    private static AccountPreferencesDto ToPreferencesDto(User user) =>
        new(
            user.AutoplayNextEpisode,
            user.NormalizeVolume,
            user.MatchTitleColors,
            user.SubtitleSize,
            user.SubtitleBackground);

    private static async Task<AuthTokenResponse> IssueDeviceSessionAsync(
        HermesDbContext db,
        ITokenService tokenService,
        User user,
        string deviceId,
        string deviceName,
        DateTimeOffset utcNow,
        CancellationToken cancellationToken)
    {
        var rawRefreshToken = tokenService.CreateOpaqueRefreshToken();
        var refreshEntity = RefreshToken.Create(
            user.Id,
            deviceId,
            deviceName,
            tokenService.HashToken(rawRefreshToken),
            utcNow.Add(RefreshTokenTtl),
            utcNow);

        db.RefreshTokens.Add(refreshEntity);
        await db.SaveChangesAsync(cancellationToken);

        var accessToken = tokenService.CreateAccessToken(user.Id, user.Username, user.Role);
        return new AuthTokenResponse(accessToken, rawRefreshToken, user.Id, user.Username, user.Role.ToString());
    }
}
