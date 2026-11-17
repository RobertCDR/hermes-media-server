using System.Globalization;
using System.Text.RegularExpressions;

namespace Hermes.Infrastructure.Media;

public sealed record SongLyricLine(long? TimestampMs, string Text);

public sealed record SongLyricsResult(bool IsSynced, string Source, IReadOnlyList<SongLyricLine> Lines);

/// <summary>
/// Reads synchronized LRC sidecar files (&lt;song&gt;.lrc) or embedded audio lyric tags read-only.
/// </summary>
public sealed partial class LrcLyricsService
{
    public async Task<SongLyricsResult> ReadLyricsAsync(string songFilePath, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(songFilePath))
        {
            return new SongLyricsResult(false, "none", []);
        }

        var sidecarPath = FindSidecarLrcPath(songFilePath);
        if (sidecarPath is not null)
        {
            var raw = await File.ReadAllTextAsync(sidecarPath, cancellationToken);
            var parsed = ParseLrcText(raw);
            if (parsed.Lines.Count > 0)
            {
                return parsed with { Source = "sidecar" };
            }
        }

        if (File.Exists(songFilePath))
        {
            try
            {
                using var tagFile = TagLib.File.Create(songFilePath, TagLib.ReadStyle.None);
                var embedded = tagFile.Tag.Lyrics;
                if (!string.IsNullOrWhiteSpace(embedded))
                {
                    var parsed = ParseLrcText(embedded);
                    if (parsed.Lines.Count > 0)
                    {
                        return parsed with { Source = "embedded" };
                    }
                }
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                // Corrupt or unreadable tag headers simply fall back to empty lyrics.
            }
        }

        return new SongLyricsResult(false, "none", []);
    }

    public static SongLyricsResult ParseLrcText(string rawText)
    {
        if (string.IsNullOrWhiteSpace(rawText))
        {
            return new SongLyricsResult(false, "none", []);
        }

        var offsetMs = 0L;
        var syncedLines = new List<SongLyricLine>();
        var plainLines = new List<SongLyricLine>();

        using var reader = new StringReader(rawText);
        string? line;
        while ((line = reader.ReadLine()) is not null)
        {
            var trimmed = line.Trim();
            if (trimmed.Length == 0)
            {
                continue;
            }

            var offsetMatch = OffsetRegex().Match(trimmed);
            if (offsetMatch.Success && long.TryParse(offsetMatch.Groups[1].Value, CultureInfo.InvariantCulture, out var parsedOffset))
            {
                offsetMs = parsedOffset;
                continue;
            }

            if (MetadataTagRegex().IsMatch(trimmed))
            {
                continue;
            }

            var matches = TimestampRegex().Matches(trimmed);
            if (matches.Count > 0)
            {
                var lyricText = TimestampRegex().Replace(trimmed, string.Empty).Trim();
                if (lyricText.Length == 0)
                {
                    continue;
                }

                foreach (Match match in matches)
                {
                    var minutes = long.Parse(match.Groups[1].Value, CultureInfo.InvariantCulture);
                    var seconds = long.Parse(match.Groups[2].Value, CultureInfo.InvariantCulture);
                    var millis = 0L;
                    if (match.Groups[3].Success)
                    {
                        var frac = match.Groups[3].Value.PadRight(3, '0')[..3];
                        millis = long.Parse(frac, CultureInfo.InvariantCulture);
                    }

                    var ts = Math.Max(0L, ((minutes * 60L) + seconds) * 1000L + millis - offsetMs);
                    syncedLines.Add(new SongLyricLine(ts, lyricText));
                }
            }
            else
            {
                plainLines.Add(new SongLyricLine(null, trimmed));
            }
        }

        if (syncedLines.Count > 0)
        {
            var ordered = syncedLines.OrderBy(l => l.TimestampMs ?? 0L).ToList();
            return new SongLyricsResult(true, "lrc", ordered);
        }

        if (plainLines.Count > 0)
        {
            return new SongLyricsResult(false, "plain", plainLines);
        }

        return new SongLyricsResult(false, "none", []);
    }

    private static string? FindSidecarLrcPath(string songFilePath)
    {
        var direct = Path.ChangeExtension(songFilePath, ".lrc");
        if (File.Exists(direct))
        {
            return direct;
        }

        var dir = Path.GetDirectoryName(songFilePath);
        if (string.IsNullOrWhiteSpace(dir) || !Directory.Exists(dir))
        {
            return null;
        }

        var targetName = $"{Path.GetFileNameWithoutExtension(songFilePath)}.lrc";
        foreach (var candidate in Directory.EnumerateFiles(dir, "*.lrc", SearchOption.TopDirectoryOnly))
        {
            if (string.Equals(Path.GetFileName(candidate), targetName, StringComparison.OrdinalIgnoreCase))
            {
                return candidate;
            }
        }

        return null;
    }

    [GeneratedRegex(@"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]", RegexOptions.CultureInvariant)]
    private static partial Regex TimestampRegex();

    [GeneratedRegex(@"^\[offset:\s*([+-]?\d+)\s*\]$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex OffsetRegex();

    [GeneratedRegex(@"^\[(ti|ar|al|au|by|length|re|ve):.*\]$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex MetadataTagRegex();
}
