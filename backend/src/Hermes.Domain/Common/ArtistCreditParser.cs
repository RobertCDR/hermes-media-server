using System.Text.RegularExpressions;

namespace Hermes.Domain.Common;

public static partial class ArtistCreditParser
{
    private static readonly char[] TagSeparators = [';'];

    [GeneratedRegex(@"\s+(?:feat\.?|ft\.?|featuring)\s+", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex FeaturedSeparatorRegex();

    public static string NormalizeKey(string? artistName) =>
        string.IsNullOrWhiteSpace(artistName)
            ? string.Empty
            : artistName.Trim().ToLowerInvariant();

    public static IReadOnlyList<string> FromPerformerTags(IEnumerable<string>? performerTags)
    {
        if (performerTags is null)
        {
            return [];
        }

        var artists = new List<string>();
        var seen = new HashSet<string>(StringComparer.Ordinal);

        foreach (var performerTag in performerTags)
        {
            if (string.IsNullOrWhiteSpace(performerTag))
            {
                continue;
            }

            foreach (var semicolonChunk in performerTag.Split(
                         TagSeparators,
                         StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            {
                foreach (var rawArtist in FeaturedSeparatorRegex().Split(semicolonChunk))
                {
                    var artist = rawArtist.Trim().TrimEnd(',', ';').Trim();
                    if (artist.Length == 0)
                    {
                        continue;
                    }

                    var normalizedName = NormalizeKey(artist);
                    if (normalizedName.Length == 0 || !seen.Add(normalizedName))
                    {
                        continue;
                    }

                    artists.Add(artist);
                }
            }
        }

        return artists;
    }

    public static IReadOnlyList<string> NormalizeArtistNames(IEnumerable<string>? artistNames)
    {
        if (artistNames is null)
        {
            return [];
        }

        var artists = new List<string>();
        var seen = new HashSet<string>(StringComparer.Ordinal);

        foreach (var artistName in artistNames)
        {
            var artist = artistName?.Trim();
            if (string.IsNullOrEmpty(artist))
            {
                continue;
            }

            var normalizedName = NormalizeKey(artist);
            if (normalizedName.Length == 0 || !seen.Add(normalizedName))
            {
                continue;
            }

            artists.Add(artist);
        }

        return artists;
    }

    public static string ToDisplayString(IEnumerable<string>? artistNames) =>
        string.Join(", ", NormalizeArtistNames(artistNames));
}
