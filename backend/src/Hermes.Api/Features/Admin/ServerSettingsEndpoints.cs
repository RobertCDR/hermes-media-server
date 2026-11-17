using Hermes.Domain.Entities;
using Hermes.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Hermes.Api.Features.Admin;

public static class ServerSettingsEndpoints
{
    public static IEndpointRouteBuilder MapServerSettingsEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints.MapGroup("/api/v1/admin/settings")
            .RequireAuthorization("AdminOnly");

        group.MapGet("", GetServerSettingsAsync).WithName("GetServerSettings");
        group.MapPut("", UpdateServerSettingsAsync).WithName("UpdateServerSettings");

        return endpoints;
    }

    private static async Task<IResult> GetServerSettingsAsync(
        HermesDbContext db,
        TimeProvider timeProvider,
        CancellationToken cancellationToken)
    {
        var settings = await db.ServerSettings.AsNoTracking().FirstOrDefaultAsync(cancellationToken)
            ?? ServerSettings.CreateDefault("Hermes Media Server", timeProvider.GetUtcNow());

        return Results.Ok(await BuildResponseAsync(db, settings, cancellationToken));
    }

    private static async Task<IResult> UpdateServerSettingsAsync(
        UpdateServerSettingsRequest request,
        HermesDbContext db,
        TimeProvider timeProvider,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.ServerName))
        {
            return Results.BadRequest(new { error = "invalid_server_name" });
        }

        if (request.MaxConcurrentVideoTranscodes < 0 ||
            request.MaxConcurrentAudioTranscodes < 0 ||
            request.MaxRemoteVideoBitrateBps is <= 0 ||
            !Enum.IsDefined(request.HardwareAccelerationMode))
        {
            return Results.BadRequest(new { error = "invalid_server_settings" });
        }

        var utcNow = timeProvider.GetUtcNow();
        var settings = await db.ServerSettings.FirstOrDefaultAsync(cancellationToken);
        if (settings is null)
        {
            settings = ServerSettings.CreateDefault(request.ServerName, utcNow);
            db.ServerSettings.Add(settings);
        }

        settings.UpdateSettings(
            request.ServerName,
            request.MaxConcurrentVideoTranscodes,
            request.MaxConcurrentAudioTranscodes,
            request.MaxRemoteVideoBitrateBps,
            request.TranscodingEnabled,
            request.HardwareAccelerationMode,
            utcNow);

        await db.SaveChangesAsync(cancellationToken);

        return Results.Ok(await BuildResponseAsync(db, settings, cancellationToken));
    }

    private static async Task<ServerSettingsResponse> BuildResponseAsync(
        HermesDbContext db,
        ServerSettings settings,
        CancellationToken cancellationToken)
    {
        var libraryCount = await db.MediaLibraryRoots.CountAsync(cancellationToken);
        var totalMovies = await db.Movies.CountAsync(cancellationToken);
        var totalSeries = await db.TvSeries.CountAsync(cancellationToken);
        var totalEpisodes = await db.Episodes.CountAsync(cancellationToken);
        var totalSongs = await db.Songs.CountAsync(s => s.MissingSinceUtc == null, cancellationToken);

        var videoBytes = await db.MediaSources
            .Where(s => s.MissingSinceUtc == null)
            .SumAsync(s => (long?)s.FileSizeBytes, cancellationToken) ?? 0L;
        var musicBytes = await db.Songs
            .Where(s => s.MissingSinceUtc == null)
            .SumAsync(s => (long?)s.FileSizeBytes, cancellationToken) ?? 0L;

        return new ServerSettingsResponse(
            settings.ServerId,
            settings.ServerName,
            settings.TranscodingEnabled,
            settings.MaxConcurrentVideoTranscodes,
            settings.MaxConcurrentAudioTranscodes,
            settings.MaxRemoteVideoBitrateBps,
            settings.HardwareAccelerationMode,
            settings.UpdatedAtUtc,
            videoBytes + musicBytes,
            libraryCount,
            totalMovies,
            totalSeries,
            totalEpisodes,
            totalSongs);
    }
}
