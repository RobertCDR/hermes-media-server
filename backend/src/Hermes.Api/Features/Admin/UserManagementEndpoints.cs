using System.Security.Claims;
using System.Security.Cryptography;
using Hermes.Api.Features.System;
using Hermes.Domain.Enums;
using Hermes.Domain.Ports;
using Hermes.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Hermes.Api.Features.Admin;

public static class UserManagementEndpoints
{
    public static IEndpointRouteBuilder MapUserManagementEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints.MapGroup("/api/v1/admin/users")
            .RequireAuthorization("AdminOnly");

        group.MapGet("", ListUsersAsync).WithName("ListUsers");
        group.MapPost("/{id:guid}/reset-code", IssueResetCodeAsync).WithName("IssueOneTimeResetCode");
        group.MapDelete("/{id:guid}", DeactivateUserAsync).WithName("DeactivateUser");

        return endpoints;
    }

    private static async Task<IResult> ListUsersAsync(
        HermesDbContext db,
        CancellationToken cancellationToken)
    {
        var users = await db.Users
            .AsNoTracking()
            .OrderBy(u => u.CreatedAtUtc)
            .Select(u => new UserSummaryDto(u.Id, u.Username, u.Role.ToString(), u.IsActive, u.CreatedAtUtc))
            .ToListAsync(cancellationToken);

        return Results.Ok(users);
    }

    private static async Task<IResult> IssueResetCodeAsync(
        Guid id,
        HermesDbContext db,
        ITokenService tokenService,
        TimeProvider timeProvider,
        CancellationToken cancellationToken)
    {
        var user = await db.Users.SingleOrDefaultAsync(u => u.Id == id, cancellationToken);
        if (user is null)
        {
            return Results.NotFound(new { error = "user_not_found" });
        }

        var utcNow = timeProvider.GetUtcNow();
        var expiresAt = utcNow.AddMinutes(30);
        var plainResetCode = Convert.ToHexString(RandomNumberGenerator.GetBytes(6));
        user.SetOneTimeResetCode(tokenService.HashToken(plainResetCode), expiresAt);

        await db.SaveChangesAsync(cancellationToken);

        return Results.Ok(new ResetCodeResponse(plainResetCode, expiresAt));
    }

    private static async Task<IResult> DeactivateUserAsync(
        Guid id,
        ClaimsPrincipal principal,
        HermesDbContext db,
        TimeProvider timeProvider,
        CancellationToken cancellationToken)
    {
        if (principal.TryGetUserId(out var currentUserId) && currentUserId == id)
        {
            return Results.BadRequest(new { error = "cannot_deactivate_self" });
        }

        var user = await db.Users
            .Include(u => u.RefreshTokens)
            .SingleOrDefaultAsync(u => u.Id == id, cancellationToken);
        if (user is null)
        {
            return Results.NotFound(new { error = "user_not_found" });
        }

        if (user.Role == UserRole.Admin)
        {
            return Results.BadRequest(new { error = "cannot_deactivate_admin" });
        }

        user.Deactivate(timeProvider.GetUtcNow());
        await db.SaveChangesAsync(cancellationToken);
        return Results.NoContent();
    }
}
