using System.Diagnostics;
using System.Text;
using System.Text.RegularExpressions;

namespace Hermes.Infrastructure.Media;

public sealed partial class SubtitleExtractorService
{
    private static readonly string[] SidecarExtensions = [".vtt", ".srt", ".ass", ".ssa"];

    public async Task<string?> ExtractWebVttAsync(string mediaFilePath, int streamIndex, CancellationToken cancellationToken)
    {
        if (!File.Exists(mediaFilePath))
        {
            return null;
        }

        var sidecarPath = FindSidecarSubtitle(mediaFilePath);
        if (sidecarPath is not null)
        {
            var rawContent = await File.ReadAllTextAsync(sidecarPath, cancellationToken);
            var ext = Path.GetExtension(sidecarPath).ToLowerInvariant();
            return ext switch
            {
                ".vtt" => EnsureWebVttHeader(rawContent),
                ".srt" => ConvertSrtToWebVtt(rawContent),
                ".ass" or ".ssa" => ConvertAssToWebVtt(rawContent),
                _ => null
            };
        }

        return await TryExtractEmbeddedWithFfmpegAsync(mediaFilePath, streamIndex, cancellationToken);
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

    private static string? FindSidecarSubtitle(string mediaFilePath)
    {
        var dir = Path.GetDirectoryName(mediaFilePath);
        if (string.IsNullOrEmpty(dir) || !Directory.Exists(dir))
        {
            return null;
        }

        var baseName = Path.GetFileNameWithoutExtension(mediaFilePath);
        foreach (var ext in SidecarExtensions)
        {
            var exact = Path.Combine(dir, baseName + ext);
            if (File.Exists(exact))
            {
                return exact;
            }
        }

        return Directory.EnumerateFiles(dir, $"{baseName}.*", SearchOption.TopDirectoryOnly)
            .FirstOrDefault(path => SidecarExtensions.Contains(Path.GetExtension(path), StringComparer.OrdinalIgnoreCase));
    }

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

            return process.ExitCode == 0 && !string.IsNullOrWhiteSpace(vtt) ? EnsureWebVttHeader(vtt) : null;
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
