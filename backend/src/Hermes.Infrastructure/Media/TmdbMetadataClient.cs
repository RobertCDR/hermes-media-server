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

        return response.Results
            .Select(r => new TmdbSearchCandidate(
                r.Id,
                r.Title ?? r.Name ?? query,
                TryParseYear(r.ReleaseDate ?? r.FirstAirDate),
                r.Overview,
                r.PosterPath,
                r.BackdropPath))
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
    }
}
