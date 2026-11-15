using Hermes.Domain.Entities;
using Hermes.Infrastructure.Media;
using Hermes.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Hermes.Api.Features.Admin;

public static class LibraryAdminEndpoints
{
    public static IEndpointRouteBuilder MapLibraryAdminEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints.MapGroup("/api/v1/admin/libraries")
            .RequireAuthorization("AdminOnly");

        group.MapPost("", CreateLibraryRootAsync).WithName("CreateLibraryRoot");
        group.MapGet("", ListLibraryRootsAsync).WithName("ListLibraryRoots");
        group.MapPost("/{id:guid}/scan", ScanLibraryNowAsync).WithName("ScanLibrary");
        group.MapPost("/{id:guid}/scan/queue", QueueLibraryScanAsync).WithName("QueueLibraryScan");

        return endpoints;
    }

    private static async Task<IResult> CreateLibraryRootAsync(
        CreateLibraryRootRequest request,
        HermesDbContext db,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.Name) || string.IsNullOrWhiteSpace(request.RootPath))
        {
            return Results.BadRequest(new { error = "invalid_library_root" });
        }

        var normalizedPath = request.RootPath.Trim();
        if (await db.MediaLibraryRoots.AnyAsync(r => r.RootPath == normalizedPath, cancellationToken))
        {
            return Results.Conflict(new { error = "library_root_already_exists" });
        }

        var root = new MediaLibraryRoot(request.Name, request.MediaType, normalizedPath, request.WatchEnabled);
        db.MediaLibraryRoots.Add(root);
        await db.SaveChangesAsync(cancellationToken);

        return Results.Created(
            $"/api/v1/admin/libraries/{root.Id}",
            new LibraryRootResponse(
                root.Id,
                root.Name,
                root.MediaType,
                root.RootPath,
                root.WatchEnabled,
                root.CreatedAtUtc,
                root.LastScanCompletedAtUtc));
    }

    private static async Task<IResult> ListLibraryRootsAsync(
        HermesDbContext db,
        CancellationToken cancellationToken)
    {
        var roots = await db.MediaLibraryRoots
            .AsNoTracking()
            .OrderBy(r => r.Name)
            .Select(r => new LibraryRootResponse(
                r.Id,
                r.Name,
                r.MediaType,
                r.RootPath,
                r.WatchEnabled,
                r.CreatedAtUtc,
                r.LastScanCompletedAtUtc))
            .ToListAsync(cancellationToken);

        return Results.Ok(roots);
    }

    private static async Task<IResult> ScanLibraryNowAsync(
        Guid id,
        LibraryScannerService scanner,
        CancellationToken cancellationToken)
    {
        var result = await scanner.ScanLibraryAsync(id, cancellationToken);
        if (result is null)
        {
            return Results.NotFound(new { error = "library_root_not_found" });
        }

        return Results.Ok(new LibraryScanSummaryDto(
            result.LibraryRootId,
            result.FilesDiscovered,
            result.SourcesUpserted,
            result.SourcesMarkedMissing,
            result.CompletedAtUtc));
    }

    private static async Task<IResult> QueueLibraryScanAsync(
        Guid id,
        HermesDbContext db,
        LibraryScanChannel scanChannel,
        CancellationToken cancellationToken)
    {
        if (!await db.MediaLibraryRoots.AnyAsync(r => r.Id == id, cancellationToken))
        {
            return Results.NotFound(new { error = "library_root_not_found" });
        }

        await scanChannel.EnqueueScanAsync(id, cancellationToken);
        return Results.Accepted($"/api/v1/admin/libraries/{id}");
    }
}
