using System.Reflection;

namespace Hermes.Api.Features.System;

public static class SystemEndpoints
{
    private static readonly Guid EphemeralFallbackServerId = Guid.NewGuid();

    public static IEndpointRouteBuilder MapSystemEndpoints(this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet("/health/live", () => Results.Ok(new { status = "Healthy" }))
            .AllowAnonymous()
            .WithName("HealthLive");

        endpoints.MapGet("/api/v1/system/info", (IConfiguration configuration) =>
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

                var version = typeof(SystemEndpoints).Assembly
                    .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?
                    .InformationalVersion?
                    .Split('+')[0]
                    ?? "1.0.0";

                return Results.Ok(new SystemInfoDto(
                    ServerId: serverId,
                    ServerName: serverName,
                    Version: version,
                    SetupCompleted: false));
            })
            .AllowAnonymous()
            .WithName("GetSystemInfo");

        return endpoints;
    }
}
