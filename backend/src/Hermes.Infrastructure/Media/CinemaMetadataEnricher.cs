using System.Text.Json;
using Hermes.Domain.Entities;
using Hermes.Domain.Enums;
using Hermes.Domain.Ports;

namespace Hermes.Infrastructure.Media;

public sealed record CastMemberRecord(string Name, string Role, string? ArtworkHash);

public static class CinemaMetadataEnricher
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public static async Task EnrichMovieAsync(
        ITmdbClient tmdbClient,
        IArtworkStore artworkStore,
        Movie movie,
        CancellationToken cancellationToken,
        bool bypassLock = false)
    {
        if (movie.TmdbId is not int tmdbId || (movie.IsMetadataLocked && !bypassLock))
        {
            return;
        }

        try
        {
            var details = await tmdbClient.GetRichDetailsAsync(LibraryMediaType.Movies, tmdbId, cancellationToken);
            if (details is null)
            {
                return;
            }

            var castJson = await BuildCastJsonAsync(tmdbClient, artworkStore, details.Cast, cancellationToken);
            movie.ApplyRichMetadata(
                details.Rating,
                details.Genres,
                details.RuntimeMinutes,
                castJson,
                bypassLock: bypassLock);
        }
        catch (Exception) when (!cancellationToken.IsCancellationRequested)
        {
            // Transient TMDB detail failures must never fail scanning or manual identification.
        }
    }

    public static async Task EnrichSeriesAsync(
        ITmdbClient tmdbClient,
        IArtworkStore artworkStore,
        TvSeries series,
        CancellationToken cancellationToken,
        bool bypassLock = false)
    {
        if (series.TmdbId is not int tmdbId || (series.IsMetadataLocked && !bypassLock))
        {
            return;
        }

        try
        {
            var details = await tmdbClient.GetRichDetailsAsync(LibraryMediaType.Series, tmdbId, cancellationToken);
            if (details is null)
            {
                return;
            }

            var castJson = await BuildCastJsonAsync(tmdbClient, artworkStore, details.Cast, cancellationToken);
            series.ApplyRichMetadata(
                details.Rating,
                details.Genres,
                castJson,
                bypassLock: bypassLock);

            if (details.Seasons.Count > 0)
            {
                var expectedByNumber = details.Seasons.ToDictionary(s => s.SeasonNumber, s => s.EpisodeCount);
                foreach (var season in series.Seasons)
                {
                    if (expectedByNumber.TryGetValue(season.SeasonNumber, out var count))
                    {
                        season.SetExpectedEpisodeCount(count);
                    }
                }
            }
        }
        catch (Exception) when (!cancellationToken.IsCancellationRequested)
        {
            // Transient TMDB detail failures must never fail scanning or manual identification.
        }
    }

    public static List<CastMemberRecord> DeserializeCastJson(string? castJson)
    {
        if (string.IsNullOrWhiteSpace(castJson))
        {
            return [];
        }

        try
        {
            return JsonSerializer.Deserialize<List<CastMemberRecord>>(castJson, JsonOptions) ?? [];
        }
        catch (JsonException)
        {
            return [];
        }
    }

    public static List<string> ParseGenresCsv(string? genresCsv)
    {
        if (string.IsNullOrWhiteSpace(genresCsv))
        {
            return [];
        }

        return genresCsv
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    private static async Task<string?> BuildCastJsonAsync(
        ITmdbClient tmdbClient,
        IArtworkStore artworkStore,
        IReadOnlyList<TmdbCastCandidate> cast,
        CancellationToken cancellationToken)
    {
        if (cast.Count == 0)
        {
            return null;
        }

        var entries = new List<CastMemberRecord>(cast.Count);
        foreach (var member in cast.Take(8))
        {
            string? artworkHash = null;
            if (entries.Count < 6 && !string.IsNullOrWhiteSpace(member.ProfilePath))
            {
                try
                {
                    artworkHash = await tmdbClient.DownloadAndStoreArtworkAsync(artworkStore, member.ProfilePath, cancellationToken);
                }
                catch (Exception) when (!cancellationToken.IsCancellationRequested)
                {
                    artworkHash = null;
                }
            }

            entries.Add(new CastMemberRecord(member.Name, member.Role, artworkHash));
        }

        return JsonSerializer.Serialize(entries, JsonOptions);
    }
}
