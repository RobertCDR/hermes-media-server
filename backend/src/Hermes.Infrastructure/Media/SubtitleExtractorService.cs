using System.Diagnostics;
using System.Text;
using System.Text.RegularExpressions;

namespace Hermes.Infrastructure.Media;

public sealed partial class SubtitleExtractorService
{
    public const int SidecarStreamIndexOffset = 1000;

    private static readonly string[] SidecarExtensions = [".vtt", ".srt", ".ass", ".ssa"];
    private static readonly UTF8Encoding StrictUtf8 = new(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true);
    private static readonly char[] LanguageSeparators = ['.', '-'];

    private static readonly char[] Windows1250HighBytes =
    [
        '\u20AC', '\uFFFD', '\u201A', '\uFFFD', '\u201E', '\u2026', '\u2020', '\u2021',
        '\uFFFD', '\u2030', '\u0160', '\u2039', '\u015A', '\u0164', '\u017D', '\u0179',
        '\uFFFD', '\u2018', '\u2019', '\u201C', '\u201D', '\u2022', '\u2013', '\u2014',
        '\uFFFD', '\u2122', '\u0161', '\u203A', '\u015B', '\u0165', '\u017E', '\u017A',
        '\u00A0', '\u02C7', '\u02D8', '\u0141', '\u00A4', '\u0104', '\u00A6', '\u00A7',
        '\u00A8', '\u00A9', '\u015E', '\u00AB', '\u00AC', '\u00AD', '\u00AE', '\u017B',
        '\u00B0', '\u00B1', '\u02DB', '\u0142', '\u00B4', '\u00B5', '\u00B6', '\u00B7',
        '\u00B8', '\u0105', '\u015F', '\u00BB', '\u013D', '\u02DD', '\u013E', '\u017C',
        '\u0154', '\u00C1', '\u00C2', '\u0102', '\u00C4', '\u0139', '\u0106', '\u00C7',
        '\u010C', '\u00C9', '\u0118', '\u00CB', '\u011A', '\u00CD', '\u00CE', '\u010E',
        '\u0110', '\u0143', '\u0147', '\u00D3', '\u00D4', '\u0150', '\u00D6', '\u00D7',
        '\u0158', '\u016E', '\u00DA', '\u0170', '\u00DC', '\u00DD', '\u0162', '\u00DF',
        '\u0155', '\u00E1', '\u00E2', '\u0103', '\u00E4', '\u013A', '\u0107', '\u00E7',
        '\u010D', '\u00E9', '\u0119', '\u00EB', '\u011B', '\u00ED', '\u00EE', '\u010F',
        '\u0111', '\u0144', '\u0148', '\u00F3', '\u00F4', '\u0151', '\u00F6', '\u00F7',
        '\u0159', '\u016F', '\u00FA', '\u0171', '\u00FC', '\u00FD', '\u0163', '\u02D9'
    ];

    public sealed record DiscoveredSidecarSubtitle(
        int StreamIndex,
        string FilePath,
        string Codec,
        string Language,
        string Title);

    public async Task<string?> ExtractWebVttAsync(string mediaFilePath, int streamIndex, CancellationToken cancellationToken)
    {
        if (!File.Exists(mediaFilePath))
        {
            return null;
        }

        var sidecars = DiscoverSidecarSubtitles(mediaFilePath);
        if (streamIndex >= SidecarStreamIndexOffset && sidecars.Count > 0)
        {
            var matched = sidecars.FirstOrDefault(s => s.StreamIndex == streamIndex) ?? sidecars[0];
            return await ReadAndConvertSidecarAsync(matched.FilePath, cancellationToken);
        }

        var embedded = await TryExtractEmbeddedWithFfmpegAsync(mediaFilePath, streamIndex, cancellationToken);
        if (embedded is not null)
        {
            return embedded;
        }

        if (sidecars.Count > 0)
        {
            return await ReadAndConvertSidecarAsync(sidecars[0].FilePath, cancellationToken);
        }

        return null;
    }

    public static IReadOnlyList<DiscoveredSidecarSubtitle> DiscoverSidecarSubtitles(string mediaFilePath)
    {
        var dir = Path.GetDirectoryName(mediaFilePath);
        if (string.IsNullOrEmpty(dir) || !Directory.Exists(dir))
        {
            return [];
        }

        var baseName = Path.GetFileNameWithoutExtension(mediaFilePath);
        var candidateFiles = new List<string>();

        foreach (var path in Directory.EnumerateFiles(dir, "*.*", SearchOption.TopDirectoryOnly)
                     .OrderBy(p => p, StringComparer.OrdinalIgnoreCase))
        {
            var ext = Path.GetExtension(path);
            if (!SidecarExtensions.Contains(ext, StringComparer.OrdinalIgnoreCase))
            {
                continue;
            }

            var subBase = Path.GetFileNameWithoutExtension(path);
            if (IsMatchingSidecarBaseName(baseName, subBase))
            {
                candidateFiles.Add(path);
            }
        }

        var results = new List<DiscoveredSidecarSubtitle>(candidateFiles.Count);
        for (var i = 0; i < candidateFiles.Count; i++)
        {
            var path = candidateFiles[i];
            var ext = Path.GetExtension(path).TrimStart('.').ToLowerInvariant();
            var lang = InferSubtitleLanguage(path, baseName);
            var title = $"External {ext.ToUpperInvariant()}";
            results.Add(new DiscoveredSidecarSubtitle(
                SidecarStreamIndexOffset + i,
                path,
                ext,
                lang,
                title));
        }

        return results;
    }

    public static string DecodeSubtitleBytes(ReadOnlySpan<byte> bytes)
    {
        if (bytes.Length == 0)
        {
            return string.Empty;
        }

        if (bytes.Length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF)
        {
            return NormalizeRomanianDiacritics(Encoding.UTF8.GetString(bytes[3..]));
        }

        if (bytes.Length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE)
        {
            return NormalizeRomanianDiacritics(Encoding.Unicode.GetString(bytes[2..]));
        }

        if (bytes.Length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF)
        {
            return NormalizeRomanianDiacritics(Encoding.BigEndianUnicode.GetString(bytes[2..]));
        }

        try
        {
            return NormalizeRomanianDiacritics(StrictUtf8.GetString(bytes));
        }
        catch (DecoderFallbackException)
        {
            var chars = new char[bytes.Length];
            for (var i = 0; i < bytes.Length; i++)
            {
                var b = bytes[i];
                chars[i] = b < 0x80 ? (char)b : Windows1250HighBytes[b - 0x80];
            }

            return NormalizeRomanianDiacritics(new string(chars));
        }
    }

    public static string NormalizeRomanianDiacritics(string text)
    {
        if (string.IsNullOrEmpty(text))
        {
            return text;
        }

        return text
            .Replace('\u015F', '\u0219')
            .Replace('\u015E', '\u0218')
            .Replace('\u0163', '\u021B')
            .Replace('\u0162', '\u021A');
    }

    private static async Task<string?> ReadAndConvertSidecarAsync(string sidecarPath, CancellationToken cancellationToken)
    {
        var rawBytes = await File.ReadAllBytesAsync(sidecarPath, cancellationToken);
        var rawContent = DecodeSubtitleBytes(rawBytes);
        var ext = Path.GetExtension(sidecarPath).ToLowerInvariant();
        return ext switch
        {
            ".vtt" => EnsureWebVttHeader(rawContent),
            ".srt" => ConvertSrtToWebVtt(rawContent),
            ".ass" or ".ssa" => ConvertAssToWebVtt(rawContent),
            _ => null
        };
    }

    private static bool IsMatchingSidecarBaseName(string mediaBaseName, string subBaseName)
    {
        if (subBaseName.Equals(mediaBaseName, StringComparison.OrdinalIgnoreCase) ||
            subBaseName.StartsWith(mediaBaseName + ".", StringComparison.OrdinalIgnoreCase) ||
            subBaseName.StartsWith(mediaBaseName + "-", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        var stem = TrimLanguageSuffix(subBaseName);
        return stem.Length >= 8 &&
               mediaBaseName.StartsWith(stem, StringComparison.OrdinalIgnoreCase);
    }

    private static string TrimLanguageSuffix(string name)
    {
        foreach (var sep in LanguageSeparators)
        {
            var idx = name.LastIndexOf(sep);
            if (idx > 0 && name.Length - idx - 1 is >= 2 and <= 3)
            {
                return name[..idx];
            }
        }

        return name;
    }

    private static string InferSubtitleLanguage(string path, string mediaBaseName)
    {
        var subBase = Path.GetFileNameWithoutExtension(path);
        string? tag = null;
        if (subBase.Length > mediaBaseName.Length &&
            (subBase[mediaBaseName.Length] == '.' || subBase[mediaBaseName.Length] == '-'))
        {
            tag = subBase[(mediaBaseName.Length + 1)..].Trim().ToLowerInvariant();
        }
        else
        {
            var dotIdx = subBase.LastIndexOfAny(['.', '-']);
            if (dotIdx > 0 && subBase.Length - dotIdx - 1 is >= 2 and <= 3)
            {
                tag = subBase[(dotIdx + 1)..].Trim().ToLowerInvariant();
            }
        }

        var fromTag = tag switch
        {
            "en" or "eng" or "english" => "eng",
            "ro" or "rum" or "ron" or "rom" or "romanian" => "rum",
            "fr" or "fre" or "fra" => "fre",
            "es" or "spa" => "spa",
            "de" or "ger" or "deu" => "ger",
            "it" or "ita" => "ita",
            "hu" or "hun" => "hun",
            _ => null
        };
        if (fromTag is not null)
        {
            return fromTag;
        }

        try
        {
            using var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            var sampleLen = (int)Math.Min(2048, fs.Length);
            var buf = new byte[sampleLen];
            var read = fs.Read(buf, 0, sampleLen);
            var sample = DecodeSubtitleBytes(buf.AsSpan(0, read));
            if (sample.IndexOfAny(['ă', 'Ă', 'î', 'Î', 'ș', 'Ș', 'ț', 'Ț']) >= 0)
            {
                return "rum";
            }
        }
        catch
        {
            // Ignore unreadable sample headers.
        }

        return "und";
    }

    public static string ConvertSrtToWebVtt(string srtContent)
    {
        var normalized = srtContent.Replace("\r\n", "\n").Replace('\r', '\n');
        var lines = normalized.Split('\n');
        var output = new StringBuilder();
        output.AppendLine("WEBVTT");
        output.AppendLine();

        for (var i = 0; i < lines.Length; i++)
        {
            var line = lines[i];
            var trimmed = line.Trim();

            if (SrtIndexRegex().IsMatch(trimmed) &&
                i + 1 < lines.Length &&
                SrtTimestampRegex().IsMatch(lines[i + 1]))
            {
                continue;
            }

            if (SrtTimestampRegex().IsMatch(line))
            {
                output.AppendLine(SrtCommaRegex().Replace(line, "$1.$2"));
            }
            else
            {
                output.AppendLine(line);
            }
        }

        return output.ToString();
    }

    public static string ConvertAssToWebVtt(string assContent)
    {
        var normalized = assContent.Replace("\r\n", "\n").Replace('\r', '\n');
        var lines = normalized.Split('\n');
        var output = new StringBuilder();
        output.AppendLine("WEBVTT");
        output.AppendLine();

        var inEvents = false;
        var startIdx = 1;
        var endIdx = 2;
        var textIdx = 9;
        var fieldCount = 10;

        foreach (var rawLine in lines)
        {
            var line = rawLine.Trim();
            if (line.StartsWith("[", StringComparison.Ordinal))
            {
                inEvents = line.Equals("[Events]", StringComparison.OrdinalIgnoreCase);
                continue;
            }

            if (!inEvents)
            {
                continue;
            }

            if (line.StartsWith("Format:", StringComparison.OrdinalIgnoreCase))
            {
                var cols = line["Format:".Length..].Split(',').Select(c => c.Trim()).ToArray();
                fieldCount = cols.Length;
                startIdx = Array.FindIndex(cols, c => c.Equals("Start", StringComparison.OrdinalIgnoreCase));
                endIdx = Array.FindIndex(cols, c => c.Equals("End", StringComparison.OrdinalIgnoreCase));
                textIdx = Array.FindIndex(cols, c => c.Equals("Text", StringComparison.OrdinalIgnoreCase));
                continue;
            }

            if (!line.StartsWith("Dialogue:", StringComparison.OrdinalIgnoreCase) || startIdx < 0 || endIdx < 0 || textIdx < 0)
            {
                continue;
            }

            var parts = line["Dialogue:".Length..].Split(',', fieldCount);
            if (parts.Length <= Math.Max(startIdx, Math.Max(endIdx, textIdx)))
            {
                continue;
            }

            var startVtt = FormatAssTimestamp(parts[startIdx].Trim());
            var endVtt = FormatAssTimestamp(parts[endIdx].Trim());
            var text = AssOverrideTagRegex().Replace(parts[textIdx], string.Empty)
                .Replace(@"\N", "\n", StringComparison.Ordinal)
                .Replace(@"\n", "\n", StringComparison.Ordinal)
                .Trim();

            if (!string.IsNullOrWhiteSpace(text))
            {
                output.AppendLine($"{startVtt} --> {endVtt}");
                output.AppendLine(text);
                output.AppendLine();
            }
        }

        return output.ToString();
    }

    private static string EnsureWebVttHeader(string content) =>
        content.TrimStart().StartsWith("WEBVTT", StringComparison.Ordinal)
            ? content
            : $"WEBVTT\n\n{content}";

    private static string FormatAssTimestamp(string assTime)
    {
        var split = assTime.Split(':');
        if (split.Length != 3)
        {
            return assTime;
        }

        var hours = split[0].PadLeft(2, '0');
        var minutes = split[1].PadLeft(2, '0');
        var secParts = split[2].Split('.');
        var seconds = secParts[0].PadLeft(2, '0');
        var ms = secParts.Length > 1 ? secParts[1].PadRight(3, '0')[..3] : "000";
        return $"{hours}:{minutes}:{seconds}.{ms}";
    }

    private static async Task<string?> TryExtractEmbeddedWithFfmpegAsync(
        string mediaFilePath,
        int streamIndex,
        CancellationToken cancellationToken)
    {
        try
        {
            using var process = new Process
            {
                StartInfo = new ProcessStartInfo
                {
                    FileName = "ffmpeg",
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    StandardOutputEncoding = Encoding.UTF8,
                    UseShellExecute = false,
                    CreateNoWindow = true
                }
            };

            process.StartInfo.ArgumentList.Add("-v");
            process.StartInfo.ArgumentList.Add("error");
            process.StartInfo.ArgumentList.Add("-i");
            process.StartInfo.ArgumentList.Add(mediaFilePath);
            process.StartInfo.ArgumentList.Add("-map");
            process.StartInfo.ArgumentList.Add($"0:{Math.Max(0, streamIndex)}");
            process.StartInfo.ArgumentList.Add("-f");
            process.StartInfo.ArgumentList.Add("webvtt");
            process.StartInfo.ArgumentList.Add("pipe:1");

            if (!process.Start())
            {
                return null;
            }

            var vtt = await process.StandardOutput.ReadToEndAsync(cancellationToken);
            _ = await process.StandardError.ReadToEndAsync(cancellationToken);
            await process.WaitForExitAsync(cancellationToken);

            return process.ExitCode == 0 && !string.IsNullOrWhiteSpace(vtt)
                ? EnsureWebVttHeader(NormalizeRomanianDiacritics(vtt))
                : null;
        }
        catch (Exception) when (!cancellationToken.IsCancellationRequested)
        {
            return null;
        }
    }

    [GeneratedRegex(@"^\d+$")]
    private static partial Regex SrtIndexRegex();

    [GeneratedRegex(@"\d{2}:\d{2}:\d{2},\d{3}\s+-->\s+\d{2}:\d{2}:\d{2},\d{3}")]
    private static partial Regex SrtTimestampRegex();

    [GeneratedRegex(@"(\d{2}:\d{2}:\d{2}),(\d{3})")]
    private static partial Regex SrtCommaRegex();

    [GeneratedRegex(@"\{[^}]*\}")]
    private static partial Regex AssOverrideTagRegex();
}
