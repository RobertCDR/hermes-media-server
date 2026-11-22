using System.Text;
using Hermes.Domain.Enums;
using Hermes.Domain.Ports;
using Hermes.Infrastructure.Media;
using Hermes.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Hermes.Api.Features.Streaming;

public static class StreamEndpoints
{
    public static IEndpointRouteBuilder MapStreamEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints.MapGroup("/api/v1/streams")
            .AllowAnonymous();

        group.MapGet("/{mediaSourceId:guid}/direct", StreamDirectAsync).WithName("StreamDirect");
        group.MapGet("/{mediaSourceId:guid}/video/master.m3u8", StartVideoHlsAsync).WithName("StartVideoHls");
        group.MapGet("/{mediaSourceId:guid}/hls/{sessionId:guid}/{assetName}", GetHlsAssetAsync).WithName("GetHlsAsset");
        group.MapDelete("/{mediaSourceId:guid}/hls/{sessionId:guid}", StopHlsSessionAsync).WithName("StopHlsSession");
        group.MapDelete("/{mediaSourceId:guid}/hls/by-client/{clientSession}", StopClientHlsSessionsAsync).WithName("StopClientHlsSessions");
        group.MapGet("/{targetId:guid}/audio", StreamAudioAsync).WithName("StreamAudio");
        group.MapGet("/{mediaSourceId:guid}/subtitles/{streamIndex:int}.vtt", GetSubtitlesVttAsync).WithName("GetSubtitlesVtt");

        return endpoints;
    }

    private static async Task<IResult> StreamDirectAsync(
        Guid mediaSourceId,
        string? ticket,
        IStreamTicketService ticketService,
        HermesDbContext db,
        CancellationToken cancellationToken)
    {
        if (!TryAuthorizeTicket(ticketService, ticket, mediaSourceId, out _))
        {
            return Results.StatusCode(StatusCodes.Status403Forbidden);
        }

        var source = await db.MediaSources.AsNoTracking()
            .SingleOrDefaultAsync(s => s.Id == mediaSourceId, cancellationToken);
        if (source is null || !File.Exists(source.FilePath))
        {
            return Results.NotFound(new { error = "media_source_not_found" });
        }

        return Results.File(source.FilePath, GetVideoMimeType(source.Container), enableRangeProcessing: true);
    }

    private static async Task<IResult> StartVideoHlsAsync(
        Guid mediaSourceId,
        string? quality,
        string? ticket,
        HttpContext httpContext,
        IStreamTicketService ticketService,
        HermesDbContext db,
        ITranscodeSessionManager transcodeManager,
        CancellationToken cancellationToken,
        int audioStreamIndex = 1,
        long startSeconds = 0,
        string? clientSession = null)
    {
        if (!TryAuthorizeTicket(ticketService, ticket, mediaSourceId, out var userId))
        {
            return Results.StatusCode(StatusCodes.Status403Forbidden);
        }

        var source = await db.MediaSources.AsNoTracking()
            .SingleOrDefaultAsync(s => s.Id == mediaSourceId, cancellationToken);
        if (source is null || !File.Exists(source.FilePath))
        {
            return Results.NotFound(new { error = "media_source_not_found" });
        }

        var preset = ParseVideoQuality(quality);
        if (preset == VideoQualityPreset.DirectPlay)
        {
            httpContext.Response.Headers.CacheControl = "no-store";
            var directManifest = $"#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH={Math.Max(1_000_000, source.BitrateBps)}\n/api/v1/streams/{mediaSourceId}/direct?ticket={Uri.EscapeDataString(ticket!)}\n";
            return Results.Text(directManifest, "application/vnd.apple.mpegurl", Encoding.UTF8);
        }

        var settings = await db.ServerSettings.AsNoTracking().FirstOrDefaultAsync(cancellationToken);
        if (settings is { TranscodingEnabled: false })
        {
            return Results.StatusCode(StatusCodes.Status403Forbidden);
        }

        var maxSlots = settings?.MaxConcurrentVideoTranscodes ?? 2;
        var hardwareAcceleration = settings?.HardwareAccelerationMode ?? HardwareAccelerationMode.None;
        var lease = await transcodeManager.TryStartVideoHlsSessionAsync(
            userId,
            mediaSourceId,
            source.FilePath,
            preset,
            audioStreamIndex,
            startSeconds,
            maxSlots,
            cancellationToken,
            hardwareAcceleration,
            clientSession);

        if (lease is null)
        {
            return Results.Json(
                new { error = "transcode_slots_exhausted" },
                statusCode: StatusCodes.Status429TooManyRequests);
        }

        httpContext.Response.Headers["X-Hermes-Transcode-Session"] = lease.SessionId.ToString("N");
        httpContext.Response.Headers.CacheControl = "no-store";
        var bandwidth = preset switch
        {
            VideoQualityPreset.P480 => 1_500_000,
            VideoQualityPreset.P720 => 4_000_000,
            _ => 8_000_000
        };
        var resolution = preset switch
        {
            VideoQualityPreset.P480 => "854x480",
            VideoQualityPreset.P720 => "1280x720",
            _ => "1920x1080"
        };

        var playlistUrl = $"/api/v1/streams/{mediaSourceId}/hls/{lease.SessionId:N}/index.m3u8?ticket={Uri.EscapeDataString(ticket!)}";
        var master = $"#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH={bandwidth},RESOLUTION={resolution}\n{playlistUrl}\n";
        return Results.Text(master, "application/vnd.apple.mpegurl", Encoding.UTF8);
    }

    private static async Task<IResult> GetHlsAssetAsync(
        Guid mediaSourceId,
        Guid sessionId,
        string assetName,
        string? ticket,
        HttpContext httpContext,
        IStreamTicketService ticketService,
        ITranscodeSessionManager transcodeManager,
        CancellationToken cancellationToken)
    {
        if (!TryAuthorizeTicket(ticketService, ticket, mediaSourceId, out var userId))
        {
            return Results.StatusCode(StatusCodes.Status403Forbidden);
        }

        var assetPath = transcodeManager.ResolveHlsAssetPath(sessionId, assetName, userId, mediaSourceId);
        if (assetPath is null)
        {
            return Results.NotFound();
        }

        if (assetName.EndsWith(".m3u8", StringComparison.OrdinalIgnoreCase))
        {
            httpContext.Response.Headers.CacheControl = "no-store";
            var rawPlaylist = await File.ReadAllTextAsync(assetPath, cancellationToken);
            var encodedTicket = Uri.EscapeDataString(ticket!);
            var rewritten = new StringBuilder();
            foreach (var rawLine in rawPlaylist.Split('\n'))
            {
                var line = rawLine.TrimEnd('\r');
                if (line.Length > 0 && !line.StartsWith('#') && !line.Contains("ticket=", StringComparison.Ordinal))
                {
                    var separator = line.Contains('?') ? '&' : '?';
                    rewritten.AppendLine($"{line}{separator}ticket={encodedTicket}");
                }
                else
                {
                    rewritten.AppendLine(line);
                }
            }

            return Results.Text(rewritten.ToString(), "application/vnd.apple.mpegurl", Encoding.UTF8);
        }

        return Results.File(assetPath, "video/mp2t");
    }

    private static async Task<IResult> StopHlsSessionAsync(
        Guid mediaSourceId,
        Guid sessionId,
        string? ticket,
        IStreamTicketService ticketService,
        ITranscodeSessionManager transcodeManager,
        CancellationToken cancellationToken)
    {
        if (!TryAuthorizeTicket(ticketService, ticket, mediaSourceId, out var userId))
        {
            return Results.StatusCode(StatusCodes.Status403Forbidden);
        }

        var stopped = await transcodeManager.TryStopUserSessionAsync(sessionId, userId, mediaSourceId, cancellationToken);
        return stopped
            ? Results.NoContent()
            : Results.NotFound(new { error = "transcode_session_not_found" });
    }

    private static async Task<IResult> StopClientHlsSessionsAsync(
        Guid mediaSourceId,
        string clientSession,
        string? ticket,
        IStreamTicketService ticketService,
        ITranscodeSessionManager transcodeManager,
        CancellationToken cancellationToken)
    {
        if (!TryAuthorizeTicket(ticketService, ticket, mediaSourceId, out var userId))
        {
            return Results.StatusCode(StatusCodes.Status403Forbidden);
        }

        await transcodeManager.StopClientSessionsAsync(userId, clientSession, cancellationToken);
        return Results.NoContent();
    }

    private static async Task<IResult> StreamAudioAsync(
        Guid targetId,
        string? quality,
        string? ticket,
        HttpContext httpContext,
        IStreamTicketService ticketService,
        HermesDbContext db,
        FfmpegTranscodeSessionManager sessionManager,
        CancellationToken cancellationToken)
    {
        if (!TryAuthorizeTicket(ticketService, ticket, targetId, out _))
        {
            return Results.StatusCode(StatusCodes.Status403Forbidden);
        }

        var song = await db.Songs.AsNoTracking().SingleOrDefaultAsync(s => s.Id == targetId, cancellationToken);
        string? filePath = song?.FilePath;
        var sourceCodec = song?.Codec ?? "mp3";
        var sourceBitrate = song?.BitrateBps ?? 0;

        if (song is null)
        {
            var source = await db.MediaSources.AsNoTracking().SingleOrDefaultAsync(s => s.Id == targetId, cancellationToken);
            filePath = source?.FilePath;
            sourceCodec = source?.AudioCodec ?? "aac";
            sourceBitrate = source?.BitrateBps ?? 0;
        }

        if (string.IsNullOrEmpty(filePath) || !File.Exists(filePath))
        {
            return Results.NotFound(new { error = "audio_source_not_found" });
        }

        var settings = await db.ServerSettings.AsNoTracking().FirstOrDefaultAsync(cancellationToken);
        var preset = ParseAudioQuality(quality);
        var targetBitrateBps = GetTargetAudioBitrateBps(preset);

        // Enforce strict no-upscale invariant and transcode policy: Lossless, disabled transcoding, or source <= target plays directly.
        if (preset == AudioQualityPreset.Lossless ||
            settings is { TranscodingEnabled: false } ||
            (sourceBitrate > 0 && sourceBitrate <= targetBitrateBps))
        {
            httpContext.Response.Headers["X-Hermes-Delivery"] = "DirectPlay";
            return Results.File(filePath, GetAudioMimeType(sourceCodec), enableRangeProcessing: true);
        }

        var maxAudioSlots = settings?.MaxConcurrentAudioTranscodes ?? 4;
        var transcodedFilePath = await sessionManager.TryTranscodeAudioToMp3FileAsync(
            filePath,
            targetBitrateBps,
            cancellationToken,
            maxAudioSlots);
        if (!string.IsNullOrEmpty(transcodedFilePath) && File.Exists(transcodedFilePath))
        {
            httpContext.Response.Headers["X-Hermes-Delivery"] = "Transcoded";
            return Results.File(transcodedFilePath, "audio/mpeg", enableRangeProcessing: true);
        }

        httpContext.Response.Headers["X-Hermes-Delivery"] = "DirectPlay";
        return Results.File(filePath, GetAudioMimeType(sourceCodec), enableRangeProcessing: true);
    }

    private static async Task<IResult> GetSubtitlesVttAsync(
        Guid mediaSourceId,
        int streamIndex,
        string? ticket,
        IStreamTicketService ticketService,
        HermesDbContext db,
        SubtitleExtractorService subtitleExtractor,
        CancellationToken cancellationToken)
    {
        if (!TryAuthorizeTicket(ticketService, ticket, mediaSourceId, out _))
        {
            return Results.StatusCode(StatusCodes.Status403Forbidden);
        }

        var source = await db.MediaSources.AsNoTracking()
            .SingleOrDefaultAsync(s => s.Id == mediaSourceId, cancellationToken);
        if (source is null || !File.Exists(source.FilePath))
        {
            return Results.NotFound(new { error = "media_source_not_found" });
        }

        var vtt = await subtitleExtractor.ExtractWebVttAsync(source.FilePath, streamIndex, cancellationToken);
        return vtt is null
            ? Results.NotFound(new { error = "subtitle_not_found" })
            : Results.Text(vtt, "text/vtt", Encoding.UTF8);
    }

    private static bool TryAuthorizeTicket(
        IStreamTicketService ticketService,
        string? ticket,
        Guid expectedTargetId,
        out Guid userId)
    {
        userId = Guid.Empty;
        return !string.IsNullOrWhiteSpace(ticket) &&
               ticketService.TryValidateStreamTicket(ticket, expectedTargetId, out userId);
    }

    private static VideoQualityPreset ParseVideoQuality(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw))
        {
            return VideoQualityPreset.P720;
        }

        if (Enum.TryParse<VideoQualityPreset>(raw.Trim(), ignoreCase: true, out var parsed) &&
            Enum.IsDefined(parsed))
        {
            return parsed;
        }

        return raw.Trim().ToLowerInvariant() switch
        {
            "direct" or "directplay" => VideoQualityPreset.DirectPlay,
            "1080p" => VideoQualityPreset.P1080,
            "720p" => VideoQualityPreset.P720,
            "480p" => VideoQualityPreset.P480,
            _ => VideoQualityPreset.P720
        };
    }

    private static AudioQualityPreset ParseAudioQuality(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw))
        {
            return AudioQualityPreset.High160;
        }

        if (Enum.TryParse<AudioQualityPreset>(raw.Trim(), ignoreCase: true, out var parsed) &&
            Enum.IsDefined(parsed))
        {
            return parsed;
        }

        return raw.Trim().ToLowerInvariant() switch
        {
            "lossless" => AudioQualityPreset.Lossless,
            "veryhigh" or "very_high" or "320" => AudioQualityPreset.VeryHigh320,
            "high" or "160" => AudioQualityPreset.High160,
            "medium" or "96" => AudioQualityPreset.Medium96,
            "low" or "64" => AudioQualityPreset.Low64,
            _ => AudioQualityPreset.High160
        };
    }

    private static long GetTargetAudioBitrateBps(AudioQualityPreset preset) => preset switch
    {
        AudioQualityPreset.Lossless => long.MaxValue,
        AudioQualityPreset.VeryHigh320 => 320_000,
        AudioQualityPreset.High160 => 160_000,
        AudioQualityPreset.Medium96 => 96_000,
        AudioQualityPreset.Low64 => 64_000,
        _ => 160_000
    };

    private static string GetVideoMimeType(string container) => container.ToLowerInvariant() switch
    {
        "mp4" or "m4v" => "video/mp4",
        "webm" => "video/webm",
        "mkv" => "video/x-matroska",
        _ => "application/octet-stream"
    };

    private static string GetAudioMimeType(string codec) => codec.ToLowerInvariant() switch
    {
        "flac" => "audio/flac",
        "mp3" => "audio/mpeg",
        "m4a" or "aac" => "audio/mp4",
        "ogg" or "opus" => "audio/ogg",
        "wav" => "audio/wav",
        _ => "application/octet-stream"
    };
}
