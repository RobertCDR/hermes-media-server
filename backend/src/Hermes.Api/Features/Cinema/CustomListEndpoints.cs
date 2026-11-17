using System.Security.Claims;
using Hermes.Api.Features.System;
using Hermes.Domain.Entities;
using Hermes.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Hermes.Api.Features.Cinema;

public static class CustomListEndpoints
{
    public static IEndpointRouteBuilder MapCustomListEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints.MapGroup("/api/v1/cinema/lists")
            .RequireAuthorization();

        group.MapGet("", ListCustomListsAsync).WithName("ListCustomLists");
        group.MapPost("", CreateCustomListAsync).WithName("CreateCustomList");
        group.MapPut("/{id:guid}", UpdateCustomListAsync).WithName("UpdateCustomList");
        group.MapDelete("/{id:guid}", DeleteCustomListAsync).WithName("DeleteCustomList");
        group.MapPost("/{id:guid}/items", AddItemToCustomListAsync).WithName("AddCustomListItem");
        group.MapDelete("/{id:guid}/items/{itemId:guid}", RemoveItemByIdAsync).WithName("RemoveCustomListItemById");
        group.MapDelete("/{id:guid}/items", RemoveItemByTargetAsync).WithName("RemoveCustomListItemByTarget");

        return endpoints;
    }

    private static async Task<IResult> ListCustomListsAsync(
        ClaimsPrincipal principal,
        HermesDbContext db,
        CancellationToken cancellationToken)
    {
        if (!principal.TryGetUserId(out var userId))
        {
            return Results.Unauthorized();
        }

        var lists = await db.CustomLists
            .AsNoTracking()
            .Where(l => l.OwnerUserId == userId)
            .Include(l => l.Items)
            .ThenInclude(i => i.Movie)
            .Include(l => l.Items)
            .ThenInclude(i => i.TvSeries)
            .OrderByDescending(l => l.UpdatedAtUtc)
            .ToListAsync(cancellationToken);

        return Results.Ok(lists.Select(MapCustomList).ToList());
    }

    private static async Task<IResult> CreateCustomListAsync(
        CreateCustomListRequest request,
        ClaimsPrincipal principal,
        HermesDbContext db,
        TimeProvider timeProvider,
        CancellationToken cancellationToken)
    {
        if (!principal.TryGetUserId(out var userId))
        {
            return Results.Unauthorized();
        }

        var name = request.Name?.Trim() ?? string.Empty;
        if (name.Length == 0)
        {
            return Results.BadRequest(new { error = "custom_list_name_required" });
        }

        var list = new CustomList(userId, name, request.Description, timeProvider.GetUtcNow());
        db.CustomLists.Add(list);
        await db.SaveChangesAsync(cancellationToken);

        return Results.Created($"/api/v1/cinema/lists/{list.Id}", MapCustomList(list));
    }

    private static async Task<IResult> UpdateCustomListAsync(
        Guid id,
        UpdateCustomListRequest request,
        ClaimsPrincipal principal,
        HermesDbContext db,
        TimeProvider timeProvider,
        CancellationToken cancellationToken)
    {
        if (!principal.TryGetUserId(out var userId))
        {
            return Results.Unauthorized();
        }

        var name = request.Name?.Trim() ?? string.Empty;
        if (name.Length == 0)
        {
            return Results.BadRequest(new { error = "custom_list_name_required" });
        }

        var list = await db.CustomLists
            .Include(l => l.Items)
            .ThenInclude(i => i.Movie)
            .Include(l => l.Items)
            .ThenInclude(i => i.TvSeries)
            .SingleOrDefaultAsync(l => l.Id == id && l.OwnerUserId == userId, cancellationToken);

        if (list is null)
        {
            return Results.NotFound(new { error = "custom_list_not_found" });
        }

        list.UpdateDetails(name, request.Description, timeProvider.GetUtcNow());
        await db.SaveChangesAsync(cancellationToken);

        return Results.Ok(MapCustomList(list));
    }

    private static async Task<IResult> DeleteCustomListAsync(
        Guid id,
        ClaimsPrincipal principal,
        HermesDbContext db,
        CancellationToken cancellationToken)
    {
        if (!principal.TryGetUserId(out var userId))
        {
            return Results.Unauthorized();
        }

        var deleted = await db.CustomLists
            .Where(l => l.Id == id && l.OwnerUserId == userId)
            .ExecuteDeleteAsync(cancellationToken);

        return deleted == 0
            ? Results.NotFound(new { error = "custom_list_not_found" })
            : Results.NoContent();
    }

    private static async Task<IResult> AddItemToCustomListAsync(
        Guid id,
        AddCustomListItemRequest request,
        ClaimsPrincipal principal,
        HermesDbContext db,
        TimeProvider timeProvider,
        CancellationToken cancellationToken)
    {
        if (!principal.TryGetUserId(out var userId))
        {
            return Results.Unauthorized();
        }

        if ((request.MovieId is null) == (request.TvSeriesId is null))
        {
            return Results.BadRequest(new { error = "invalid_custom_list_target" });
        }

        var list = await db.CustomLists
            .Include(l => l.Items)
            .SingleOrDefaultAsync(l => l.Id == id && l.OwnerUserId == userId, cancellationToken);
        if (list is null)
        {
            return Results.NotFound(new { error = "custom_list_not_found" });
        }

        var utcNow = timeProvider.GetUtcNow();

        if (request.MovieId is Guid movieId)
        {
            if (!await db.Movies.AnyAsync(m => m.Id == movieId, cancellationToken))
            {
                return Results.NotFound(new { error = "movie_not_found" });
            }

            if (!list.Items.Any(i => i.MovieId == movieId))
            {
                var nextPos = list.Items.Count;
                var item = CustomListItem.ForMovie(list.Id, movieId, nextPos, utcNow);
                db.CustomListItems.Add(item);
                list.Touch(utcNow);
                await db.SaveChangesAsync(cancellationToken);
            }
        }
        else if (request.TvSeriesId is Guid seriesId)
        {
            if (!await db.TvSeries.AnyAsync(s => s.Id == seriesId, cancellationToken))
            {
                return Results.NotFound(new { error = "series_not_found" });
            }

            if (!list.Items.Any(i => i.TvSeriesId == seriesId))
            {
                var nextPos = list.Items.Count;
                var item = CustomListItem.ForSeries(list.Id, seriesId, nextPos, utcNow);
                db.CustomListItems.Add(item);
                list.Touch(utcNow);
                await db.SaveChangesAsync(cancellationToken);
            }
        }

        var refreshed = await LoadCustomListAsync(db, id, userId, cancellationToken);
        return Results.Ok(refreshed!);
    }

    private static async Task<IResult> RemoveItemByIdAsync(
        Guid id,
        Guid itemId,
        ClaimsPrincipal principal,
        HermesDbContext db,
        TimeProvider timeProvider,
        CancellationToken cancellationToken)
    {
        if (!principal.TryGetUserId(out var userId))
        {
            return Results.Unauthorized();
        }

        var list = await db.CustomLists
            .SingleOrDefaultAsync(l => l.Id == id && l.OwnerUserId == userId, cancellationToken);
        if (list is null)
        {
            return Results.NotFound(new { error = "custom_list_not_found" });
        }

        var deleted = await db.CustomListItems
            .Where(i => i.CustomListId == id && i.Id == itemId)
            .ExecuteDeleteAsync(cancellationToken);
        if (deleted > 0)
        {
            list.Touch(timeProvider.GetUtcNow());
            await db.SaveChangesAsync(cancellationToken);
        }

        var refreshed = await LoadCustomListAsync(db, id, userId, cancellationToken);
        return Results.Ok(refreshed!);
    }

    private static async Task<IResult> RemoveItemByTargetAsync(
        Guid id,
        Guid? movieId,
        Guid? seriesId,
        ClaimsPrincipal principal,
        HermesDbContext db,
        TimeProvider timeProvider,
        CancellationToken cancellationToken)
    {
        if (!principal.TryGetUserId(out var userId))
        {
            return Results.Unauthorized();
        }

        if ((movieId is null) == (seriesId is null))
        {
            return Results.BadRequest(new { error = "invalid_custom_list_target" });
        }

        var list = await db.CustomLists
            .SingleOrDefaultAsync(l => l.Id == id && l.OwnerUserId == userId, cancellationToken);
        if (list is null)
        {
            return Results.NotFound(new { error = "custom_list_not_found" });
        }

        var deleted = await db.CustomListItems
            .Where(i => i.CustomListId == id &&
                        ((movieId != null && i.MovieId == movieId) ||
                         (seriesId != null && i.TvSeriesId == seriesId)))
            .ExecuteDeleteAsync(cancellationToken);
        if (deleted > 0)
        {
            list.Touch(timeProvider.GetUtcNow());
            await db.SaveChangesAsync(cancellationToken);
        }

        var refreshed = await LoadCustomListAsync(db, id, userId, cancellationToken);
        return Results.Ok(refreshed!);
    }

    private static async Task<CustomListDto?> LoadCustomListAsync(
        HermesDbContext db,
        Guid listId,
        Guid userId,
        CancellationToken cancellationToken)
    {
        var list = await db.CustomLists
            .AsNoTracking()
            .Include(l => l.Items)
            .ThenInclude(i => i.Movie)
            .Include(l => l.Items)
            .ThenInclude(i => i.TvSeries)
            .SingleOrDefaultAsync(l => l.Id == listId && l.OwnerUserId == userId, cancellationToken);

        return list is null ? null : MapCustomList(list);
    }

    private static CustomListDto MapCustomList(CustomList list)
    {
        var items = list.Items
            .OrderBy(i => i.Position)
            .ThenBy(i => i.AddedAtUtc)
            .Select(i => i.Movie is not null
                ? new CustomListItemDto(
                    i.Id,
                    i.MovieId,
                    null,
                    "movie",
                    i.Movie.Title,
                    i.Movie.Year,
                    i.Movie.ArtworkHash,
                    i.Movie.Rating,
                    i.Position,
                    i.AddedAtUtc)
                : i.TvSeries is not null
                    ? new CustomListItemDto(
                        i.Id,
                        null,
                        i.TvSeriesId,
                        "series",
                        i.TvSeries.Title,
                        i.TvSeries.Year,
                        i.TvSeries.ArtworkHash,
                        i.TvSeries.Rating,
                        i.Position,
                        i.AddedAtUtc)
                    : null)
            .Where(x => x is not null)
            .Select(x => x!)
            .ToList();

        return new CustomListDto(
            list.Id,
            list.Name,
            list.Description,
            list.CreatedAtUtc,
            list.UpdatedAtUtc,
            items);
    }
}
