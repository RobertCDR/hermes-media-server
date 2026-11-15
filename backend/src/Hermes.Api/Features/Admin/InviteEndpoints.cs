using System.Security.Claims;
using System.Security.Cryptography;
using Hermes.Api.Features.System;
using Hermes.Domain.Entities;
using Hermes.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Hermes.Api.Features.Admin;

public static class InviteEndpoints
{
    public static IEndpointRouteBuilder MapInviteEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints.MapGroup("/api/v1/admin/invites")
            .RequireAuthorization("AdminOnly");

        group.MapPost("", CreateInviteAsync).WithName("CreateInvite");
        group.MapGet("", ListInvitesAsync).WithName("ListInvites");

        return endpoints;
    }

    private static async Task<IResult> CreateInviteAsync(
        CreateInviteRequest request,
        ClaimsPrincipal principal,
        HermesDbContext db,
        TimeProvider timeProvider,
        CancellationToken cancellationToken)
    {
        if (request.MaxUses < 1 || request.ExpiresInHours < 1)
        {
            return Results.BadRequest(new { error = "invalid_invite_parameters" });
        }

        if (!principal.TryGetUserId(out var adminUserId))
        {
            return Results.Unauthorized();
        }

        var utcNow = timeProvider.GetUtcNow();
        var code = $"HRM-{Convert.ToHexString(RandomNumberGenerator.GetBytes(4))}-{Convert.ToHexString(RandomNumberGenerator.GetBytes(4))}";
        var invite = InviteCode.Create(adminUserId, code, request.MaxUses, utcNow.AddHours(request.ExpiresInHours), utcNow);

        db.InviteCodes.Add(invite);
        await db.SaveChangesAsync(cancellationToken);

        return Results.Created(
            $"/api/v1/admin/invites/{invite.Id}",
            new InviteResponse(invite.Id, invite.Code, invite.MaxUses, invite.UsedCount, invite.ExpiresAtUtc, invite.IsRevoked));
    }

    private static async Task<IResult> ListInvitesAsync(
        HermesDbContext db,
        CancellationToken cancellationToken)
    {
        var invites = await db.InviteCodes
            .AsNoTracking()
            .OrderByDescending(i => i.CreatedAtUtc)
            .Select(i => new InviteResponse(i.Id, i.Code, i.MaxUses, i.UsedCount, i.ExpiresAtUtc, i.IsRevoked))
            .ToListAsync(cancellationToken);

        return Results.Ok(invites);
    }
}
