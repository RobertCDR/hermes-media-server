using System.Diagnostics;
using System.Globalization;
using System.Text.Json;
using Hermes.Domain.Enums;
using Hermes.Domain.Ports;
using Microsoft.Extensions.Logging;

namespace Hermes.Infrastructure.Media;

public sealed class FfprobeMediaProbeService(ILogger<FfprobeMediaProbeService>? logger = null) : IMediaProbeService
{
    public async Task<ProbedMediaInfo?> ProbeAsync(string filePath, CancellationToken cancellationToken)
    {
        if (!File.Exists(filePath))
        {
            return null;
        }

        try
        {
            using var process = new Process
            {
                StartInfo = new ProcessStartInfo
                {
                    FileName = "ffprobe",
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false,
                    CreateNoWindow = true
                }
            };
            process.StartInfo.ArgumentList.Add("-v");
            process.StartInfo.ArgumentList.Add("quiet");
            process.StartInfo.ArgumentList.Add("-print_format");
            process.StartInfo.ArgumentList.Add("json");
            process.StartInfo.ArgumentList.Add("-show_format");
            process.StartInfo.ArgumentList.Add("-show_streams");
            process.StartInfo.ArgumentList.Add(filePath);

            if (process.Start())
            {
                using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
                timeoutCts.CancelAfter(TimeSpan.FromSeconds(10));

                try
                {
                    var stdoutTask = process.StandardOutput.ReadToEndAsync(timeoutCts.Token);
                    var stderrTask = process.StandardError.ReadToEndAsync(timeoutCts.Token);

                    await process.WaitForExitAsync(timeoutCts.Token);
                    var json = await stdoutTask;
                    _ = await stderrTask;

                    if (process.ExitCode == 0 && TryParseFfprobeJson(filePath, json, out var parsed))
                    {
                        return parsed;
                    }
                }
                finally
                {
                    if (!process.HasExited)
                    {
                        try
                        {
                            process.Kill(entireProcessTree: true);
                        }
                        catch
                        {
                            // Best-effort cleanup if process exited concurrently.
                        }
                    }
                }
            }
        }
        catch (Exception ex) when (!cancellationToken.IsCancellationRequested)
        {
            logger?.LogDebug(ex, "ffprobe fell back to filename metadata for {FilePath}.", filePath);
        }

        return BuildFallbackFromFilename(filePath);
    }

    private static bool TryParseFfprobeJson(string filePath, string json, out ProbedMediaInfo info)
    {
        info = null!;
        if (string.IsNullOrWhiteSpace(json))
        {
            return false;
        }

        using var doc = JsonDocument.Parse(json);
        if (!doc.RootElement.TryGetProperty("streams", out var streamsElement) ||
            streamsElement.ValueKind != JsonValueKind.Array ||
            streamsElement.GetArrayLength() == 0)
        {
            return false;
        }

        var streams = new List<ProbedMediaStream>();
        var videoCodec = "unknown";
        var audioCodec = "unknown";
        var width = 0;
        var height = 0;
        var isHdr = false;

        foreach (var stream in streamsElement.EnumerateArray())
        {
            var index = stream.TryGetProperty("index", out var idxProp) ? idxProp.GetInt32() : streams.Count;
            var codecType = stream.TryGetProperty("codec_type", out var typeProp) ? typeProp.GetString() ?? "" : "";
            var codecName = stream.TryGetProperty("codec_name", out var codecProp) ? codecProp.GetString() ?? "unknown" : "unknown";
            var isDefault = stream.TryGetProperty("disposition", out var disp) &&
                            disp.TryGetProperty("default", out var defProp) &&
                            defProp.GetInt32() == 1;

            var lang = "und";
            var title = string.Empty;
            if (stream.TryGetProperty("tags", out var tags))
            {
                if (tags.TryGetProperty("language", out var langProp))
                {
                    lang = langProp.GetString() ?? "und";
                }

                if (tags.TryGetProperty("title", out var titleProp))
                {
                    title = titleProp.GetString() ?? string.Empty;
                }
            }

            switch (codecType)
            {
                case "video":
                    streams.Add(new ProbedMediaStream(index, StreamKind.Video, codecName, lang, title, isDefault));
                    if (videoCodec == "unknown")
                    {
                        videoCodec = codecName;
                        width = stream.TryGetProperty("width", out var wProp) ? wProp.GetInt32() : 1920;
                        height = stream.TryGetProperty("height", out var hProp) ? hProp.GetInt32() : 1080;
                        var transfer = stream.TryGetProperty("color_transfer", out var trProp) ? trProp.GetString() : null;
                        var primaries = stream.TryGetProperty("color_primaries", out var prProp) ? prProp.GetString() : null;
                        isHdr = string.Equals(transfer, "smpte2084", StringComparison.OrdinalIgnoreCase) ||
                                string.Equals(transfer, "arib-std-b67", StringComparison.OrdinalIgnoreCase) ||
                                string.Equals(primaries, "bt2020", StringComparison.OrdinalIgnoreCase);
                    }
                    break;
                case "audio":
                    streams.Add(new ProbedMediaStream(index, StreamKind.Audio, codecName, lang, title, isDefault));
                    if (audioCodec == "unknown")
                    {
                        audioCodec = codecName;
                    }
                    break;
                case "subtitle":
                    streams.Add(new ProbedMediaStream(index, StreamKind.Subtitle, codecName, lang, title, isDefault));
                    break;
            }
        }

        if (streams.Count == 0)
        {
            return false;
        }

        var container = Path.GetExtension(filePath).TrimStart('.').ToLowerInvariant();
        long bitrateBps = 0;
        long durationMs = 0;
        if (doc.RootElement.TryGetProperty("format", out var format))
        {
            if (format.TryGetProperty("bit_rate", out var brProp) &&
                long.TryParse(brProp.GetString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var parsedBr))
            {
                bitrateBps = parsedBr;
            }

            if (format.TryGetProperty("duration", out var durProp) &&
                double.TryParse(durProp.GetString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var parsedSec))
            {
                durationMs = (long)Math.Round(parsedSec * 1000.0);
            }
        }

        info = new ProbedMediaInfo(container, videoCodec, audioCodec, width, height, isHdr, bitrateBps, durationMs, streams);
        return true;
    }

    private static ProbedMediaInfo BuildFallbackFromFilename(string filePath)
    {
        var name = Path.GetFileNameWithoutExtension(filePath);
        var (width, height) = name switch
        {
            _ when name.Contains("2160p", StringComparison.OrdinalIgnoreCase) || name.Contains("4k", StringComparison.OrdinalIgnoreCase) => (3840, 2160),
            _ when name.Contains("720p", StringComparison.OrdinalIgnoreCase) => (1280, 720),
            _ when name.Contains("480p", StringComparison.OrdinalIgnoreCase) => (854, 480),
            _ => (1920, 1080)
        };

        var isHdr = name.Contains("hdr", StringComparison.OrdinalIgnoreCase) ||
                    name.Contains("dovi", StringComparison.OrdinalIgnoreCase) ||
                    name.Contains("dolby vision", StringComparison.OrdinalIgnoreCase);

        var container = Path.GetExtension(filePath).TrimStart('.').ToLowerInvariant();
        if (string.IsNullOrWhiteSpace(container))
        {
            container = "mkv";
        }

        var streams = new List<ProbedMediaStream>
        {
            new(0, StreamKind.Video, "hevc", "und", "Primary Video", true),
            new(1, StreamKind.Audio, "aac", "und", "Primary Audio", true)
        };

        return new ProbedMediaInfo(container, "hevc", "aac", width, height, isHdr, 8_000_000, 0, streams);
    }
}
