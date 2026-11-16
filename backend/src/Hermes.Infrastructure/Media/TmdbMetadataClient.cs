using System.Net.Http.Json;
using System.Text.Json.Serialization;
using Hermes.Domain.Enums;
using Hermes.Domain.Ports;
using Microsoft.Extensions.Configuration;

namespace Hermes.Infrastructure.Media;

public sealed class TmdbMetadataClient(HttpClient httpClient, IConfiguration configuration) : ITmdbClient
{
    private const string ImageBaseUrl = "https://image.tmdb.org/t/p/original";

    public async Task<IReadOnlyList<TmdbSearchCandidate>> SearchAsync(
        LibraryMediaType mediaType,
        string query,
        int? year,
        CancellationToken cancellationToken)
    {
        var apiKey = configuration["Hermes:TmdbApiKey"];
        if (string.IsNullOrWhiteSpace(apiKey) || string.IsNullOrWhiteSpace(query))
        {
            return [];
        }

        var segment = mediaType == LibraryMediaType.Series ? "tv" : "movie";
        var encodedQuery = Uri.EscapeDataString(query);
        var yearParam = year is not null
            ? (mediaType == LibraryMediaType.Series ? $"&first_air_date_year={year}" : $"&year={year}")
            : string.Empty;

        var url = $"https://api.themoviedb.org/3/search/{segment}?api_key={Uri.EscapeDataString(apiKey)}&query={encodedQuery}{yearParam}";
        var response = await httpClient.GetFromJsonAsync<TmdbSearchResponse>(url, cancellationToken);
        if (response?.Results is null)
        {
            return [];
        }

        var normalizedQuery = query.Trim();

        return response.Results
            .Select(r =>
            {
                var candidateTitle = r.Title ?? r.Name ?? query;
                var candidateYear = TryParseYear(r.ReleaseDate ?? r.FirstAirDate);
                var exactMatch =
                    string.Equals(r.Title?.Trim(), normalizedQuery, StringComparison.OrdinalIgnoreCase) ||
                    string.Equals(r.Name?.Trim(), normalizedQuery, StringComparison.OrdinalIgnoreCase) ||
                    string.Equals(r.OriginalTitle?.Trim(), normalizedQuery, StringComparison.OrdinalIgnoreCase) ||
                    string.Equals(r.OriginalName?.Trim(), normalizedQuery, StringComparison.OrdinalIgnoreCase);
                var exactYearMatch = year is not null && candidateYear == year;
                return new
                {
                    Candidate = new TmdbSearchCandidate(
                        r.Id,
                        candidateTitle,
                        candidateYear,
                        r.Overview,
                        r.PosterPath,
                        r.BackdropPath),
                    ExactMatch = exactMatch,
                    ExactYearMatch = exactYearMatch,
                    r.VoteCount,
                    r.Popularity,
                };
            })
            .OrderByDescending(x => x.ExactMatch)
            .ThenByDescending(x => x.ExactYearMatch)
            .ThenByDescending(x => x.VoteCount)
            .ThenByDescending(x => x.Popularity)
            .Select(x => x.Candidate)
            .ToList();
    }

    public async Task<TmdbSearchCandidate?> GetDetailsAsync(
        LibraryMediaType mediaType,
        int tmdbId,
        CancellationToken cancellationToken)
    {
        var apiKey = configuration["Hermes:TmdbApiKey"];
        if (string.IsNullOrWhiteSpace(apiKey))
        {
            return null;
        }

        var segment = mediaType == LibraryMediaType.Series ? "tv" : "movie";
        var url = $"https://api.themoviedb.org/3/{segment}/{tmdbId}?api_key={Uri.EscapeDataString(apiKey)}";
        var item = await httpClient.GetFromJsonAsync<TmdbResultItem>(url, cancellationToken);
        if (item is null)
        {
            return null;
        }

        return new TmdbSearchCandidate(
            item.Id,
            item.Title ?? item.Name ?? string.Empty,
            TryParseYear(item.ReleaseDate ?? item.FirstAirDate),
            item.Overview,
            item.PosterPath,
            item.BackdropPath);
    }

    public async Task<byte[]?> DownloadImageBytesAsync(string remotePath, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(remotePath))
        {
            return null;
        }

        var fullUrl = remotePath.StartsWith("http", StringComparison.OrdinalIgnoreCase)
            ? remotePath
            : $"{ImageBaseUrl}{remotePath}";

        using var response = await httpClient.GetAsync(fullUrl, cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            return null;
        }

        return await response.Content.ReadAsByteArrayAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<TmdbEpisodeCandidate>> GetSeasonEpisodesAsync(
        int seriesTmdbId,
        int seasonNumber,
        CancellationToken cancellationToken)
    {
        var apiKey = configuration["Hermes:TmdbApiKey"];
        if (string.IsNullOrWhiteSpace(apiKey) || seriesTmdbId <= 0 || seasonNumber < 0)
        {
            return [];
        }

        var url = $"https://api.themoviedb.org/3/tv/{seriesTmdbId}/season/{seasonNumber}?api_key={Uri.EscapeDataString(apiKey)}";
        var season = await httpClient.GetFromJsonAsync<TmdbSeasonResponse>(url, cancellationToken);
        if (season?.Episodes is null)
        {
            return [];
        }

        return season.Episodes
            .Select(e => new TmdbEpisodeCandidate(
                e.EpisodeNumber,
                e.Name ?? $"Episode {e.EpisodeNumber}",
                e.Overview,
                e.StillPath))
            .ToList();
    }

    private static int? TryParseYear(string? dateText)
    {
        if (!string.IsNullOrWhiteSpace(dateText) &&
            dateText.Length >= 4 &&
            int.TryParse(dateText[..4], out var parsedYear))
        {
            return parsedYear;
        }

        return null;
    }

    private sealed class TmdbSearchResponse
    {
        [JsonPropertyName("results")]
        public List<TmdbResultItem>? Results { get; init; }
    }

    private sealed class TmdbResultItem
    {
        [JsonPropertyName("id")]
        public int Id { get; init; }

        [JsonPropertyName("title")]
        public string? Title { get; init; }

        [JsonPropertyName("name")]
        public string? Name { get; init; }

        [JsonPropertyName("original_title")]
        public string? OriginalTitle { get; init; }

        [JsonPropertyName("original_name")]
        public string? OriginalName { get; init; }

        [JsonPropertyName("overview")]
        public string? Overview { get; init; }

        [JsonPropertyName("release_date")]
        public string? ReleaseDate { get; init; }

        [JsonPropertyName("first_air_date")]
        public string? FirstAirDate { get; init; }

        [JsonPropertyName("poster_path")]
        public string? PosterPath { get; init; }

        [JsonPropertyName("backdrop_path")]
        public string? BackdropPath { get; init; }

        [JsonPropertyName("vote_count")]
        public int VoteCount { get; init; }

        [JsonPropertyName("popularity")]
        public double Popularity { get; init; }
    }

    private sealed class TmdbSeasonResponse
    {
        [JsonPropertyName("episodes")]
        public List<TmdbEpisodeItem>? Episodes { get; init; }
    }

    private sealed class TmdbEpisodeItem
    {
        [JsonPropertyName("episode_number")]
        public int EpisodeNumber { get; init; }

        [JsonPropertyName("name")]
        public string? Name { get; init; }

        [JsonPropertyName("overview")]
        public string? Overview { get; init; }

        [JsonPropertyName("still_path")]
        public string? StillPath { get; init; }
    }
}
