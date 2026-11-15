using Hermes.Domain.Ports;

namespace Hermes.Api.Features.Streaming;

public static class ArtworkEndpoints
{
    public static IEndpointRouteBuilder MapArtworkEndpoints(this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet("/api/v1/artwork/{hash}/{variant}", GetArtworkVariant)
            .AllowAnonymous()
            .WithName("GetArtworkVariant");

        return endpoints;
    }

    private static IResult GetArtworkVariant(
        string hash,
        string variant,
        HttpContext httpContext,
        IArtworkStore artworkStore)
    {
        var path = artworkStore.ResolveVariantFilePath(hash, variant);
        if (path is null)
        {
            return Results.NotFound();
        }

        var etag = $"\"{hash}-{variant}\"";
        httpContext.Response.Headers.ETag = etag;
        httpContext.Response.Headers.CacheControl = "public,max-age=31536000,immutable";

        var ifNoneMatch = httpContext.Request.Headers.IfNoneMatch;
        if (ifNoneMatch.Any(value => string.Equals(value, etag, StringComparison.Ordinal) ||
                                     string.Equals(value, "*", StringComparison.Ordinal)))
        {
            return Results.StatusCode(StatusCodes.Status304NotModified);
        }

        return Results.File(path, "image/webp");
    }
}
