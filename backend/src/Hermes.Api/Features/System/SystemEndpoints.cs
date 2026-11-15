using System.Reflection;
using Hermes.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Hermes.Api.Features.System;

public static class SystemEndpoints
{
    private static readonly Guid EphemeralFallbackServerId = Guid.NewGuid();

    public static IEndpointRouteBuilder MapSystemEndpoints(this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet("/health/live", () => Results.Ok(new { status = "Healthy" }))
            .AllowAnonymous()
            .WithName("HealthLive");

        endpoints.MapGet("/api/v1/system/info", HandleGetSystemInfoAsync)
            .AllowAnonymous()
            .WithName("GetSystemInfo");

        return endpoints;
    }

    private static async Task<IResult> HandleGetSystemInfoAsync(
        HermesDbContext db,
        IConfiguration configuration,
        CancellationToken cancellationToken)
    {
        var configuredId = configuration["Hermes:ServerId"];
        var serverId = Guid.TryParse(configuredId, out var parsed)
            ? parsed
            : EphemeralFallbackServerId;

        var serverName = configuration["Hermes:ServerName"];
        if (string.IsNullOrWhiteSpace(serverName))
        {
            serverName = "Hermes Media Server";
        }

        var setupCompleted = false;

        try
        {
            if (await db.Database.CanConnectAsync(cancellationToken))
            {
                setupCompleted = await db.Users.AnyAsync(cancellationToken);
                var settings = await db.ServerSettings.AsNoTracking().FirstOrDefaultAsync(cancellationToken);
                if (settings is not null)
                {
                    serverId = settings.ServerId;
                    serverName = settings.ServerName;
                }
            }
        }
        catch (Exception) when (!cancellationToken.IsCancellationRequested)
        {
            // Fallback to unconfigured startup defaults when Postgres is not reachable yet.
        }

        var version = typeof(SystemEndpoints).Assembly
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?
            .InformationalVersion?
            .Split('+')[0]
            ?? "1.0.0";

        return Results.Ok(new SystemInfoDto(
            ServerId: serverId,
            ServerName: serverName,
            Version: version,
            SetupCompleted: setupCompleted));
    }
}
