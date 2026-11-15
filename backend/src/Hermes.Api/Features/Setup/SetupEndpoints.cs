using Hermes.Domain.Entities;
using Hermes.Domain.Enums;
using Hermes.Domain.Ports;
using Hermes.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Hermes.Api.Features.Setup;

public static class SetupEndpoints
{
    private const long SetupAdvisoryLockKey = 424242;

    public static IEndpointRouteBuilder MapSetupEndpoints(this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPost("/api/v1/setup", HandleFirstRunSetupAsync)
            .AllowAnonymous()
            .RequireRateLimiting("auth")
            .WithName("FirstRunSetup");

        return endpoints;
    }

    private static async Task<IResult> HandleFirstRunSetupAsync(
        SetupRequest request,
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

        if (string.IsNullOrWhiteSpace(request.ServerName))
        {
            return Results.BadRequest(new { error = "invalid_server_name" });
        }

        await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);
        await db.Database.ExecuteSqlRawAsync(
            $"SELECT pg_advisory_xact_lock({SetupAdvisoryLockKey});",
            cancellationToken);

        if (await db.Users.AnyAsync(cancellationToken))
        {
            return Results.Conflict(new { error = "setup_already_completed" });
        }

        var utcNow = timeProvider.GetUtcNow();
        var passwordHash = passwordHasher.HashPassword(request.Password);
        var admin = User.Create(request.Username, passwordHash, UserRole.Admin, utcNow);
        var settings = ServerSettings.CreateDefault(request.ServerName, utcNow);

        db.Users.Add(admin);
        db.ServerSettings.Add(settings);
        await db.SaveChangesAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);

        return Results.Created(
            $"/api/v1/admin/users/{admin.Id}",
            new SetupResponse(admin.Id, admin.Username, settings.ServerId, settings.ServerName));
    }
}
