using System.Text.RegularExpressions;
using Hermes.Domain.Entities;
using Hermes.Domain.Enums;
using Hermes.Domain.Ports;
using Hermes.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Hermes.Infrastructure.Media;

public sealed record LibraryScanResult(
    Guid LibraryRootId,
    int FilesDiscovered,
    int SourcesUpserted,
    int SourcesMarkedMissing,
    DateTimeOffset CompletedAtUtc);

public sealed partial class LibraryScannerService(
    HermesDbContext db,
    IMediaProbeService mediaProbeService,
    IAudioMetadataReader audioMetadataReader,
    ITmdbClient tmdbClient,
    IArtworkStore artworkStore,
    TimeProvider timeProvider)
{
    private static readonly HashSet<string> VideoExtensions =
        new([".mkv", ".mp4", ".avi", ".mov", ".m4v", ".webm", ".ts"], StringComparer.OrdinalIgnoreCase);

    private static readonly HashSet<string> AudioExtensions =
        new([".flac", ".mp3", ".m4a", ".ogg", ".wav", ".opus"], StringComparer.OrdinalIgnoreCase);

    private static readonly string[] IgnoredTokens = ["extras", "trailers", "trailer", "sample"];

    public async Task<LibraryScanResult?> ScanLibraryAsync(Guid libraryRootId, CancellationToken cancellationToken)
    {
        var root = await db.MediaLibraryRoots.SingleOrDefaultAsync(r => r.Id == libraryRootId, cancellationToken);
        if (root is null)
        {
            return null;
        }

        if (!Directory.Exists(root.RootPath))
        {
            return new LibraryScanResult(root.Id, 0, 0, 0, timeProvider.GetUtcNow());
        }

        var result = root.MediaType switch
        {
            LibraryMediaType.Movies => await ScanMoviesAsync(root, cancellationToken),
            LibraryMediaType.Series => await ScanSeriesAsync(root, cancellationToken),
            LibraryMediaType.Music => await ScanMusicAsync(root, cancellationToken),
            _ => throw new InvalidOperationException($"Unsupported library type: {root.MediaType}")
        };

        root.MarkScanCompleted(result.CompletedAtUtc);
        await db.SaveChangesAsync(cancellationToken);
        return result;
    }

    private async Task<LibraryScanResult> ScanMoviesAsync(MediaLibraryRoot root, CancellationToken cancellationToken)
    {
        var files = EnumerateSupportedFiles(root.RootPath, VideoExtensions);
        var discoveredSet = new HashSet<string>(files, StringComparer.Ordinal);
        var existingMovies = await db.Movies
            .Where(m => m.LibraryRootId == root.Id)
            .Include(m => m.Sources)
            .ThenInclude(s => s.Streams)
            .ToListAsync(cancellationToken);

        var moviesByKey = new Dictionary<(string Title, int? Year), Movie>();
        var existingSourcesByPath = new Dictionary<string, MediaSource>(StringComparer.Ordinal);
        foreach (var movie in existingMovies)
        {
            moviesByKey.TryAdd((NormalizeKey(movie.Title), movie.Year), movie);
            foreach (var source in movie.Sources)
            {
                existingSourcesByPath[source.FilePath] = source;
            }
        }

        var upserted = 0;
        foreach (var filePath in files)
        {
            var fileInfo = new FileInfo(filePath);
            var lastWriteUtc = new DateTimeOffset(fileInfo.LastWriteTimeUtc, TimeSpan.Zero);

            if (existingSourcesByPath.TryGetValue(filePath, out var existingSource))
            {
                existingSource.UpdateFileFingerprint(fileInfo.Length, lastWriteUtc);
                continue;
            }

            var (title, year, suffixLabel) = ParseMovieFilename(Path.GetFileNameWithoutExtension(filePath));
            var movieKey = (NormalizeKey(title), year);
            if (!moviesByKey.TryGetValue(movieKey, out var movie))
            {
                movie = new Movie(root.Id, title, year);
                db.Movies.Add(movie);
                moviesByKey[movieKey] = movie;
            }

            await TryEnrichMovieFromTmdbAsync(movie, title, year, cancellationToken);

            var probed = await mediaProbeService.ProbeAsync(filePath, cancellationToken);
            if (probed is null)
            {
                continue;
            }

            var sourceLabel = !string.IsNullOrWhiteSpace(suffixLabel)
                ? suffixLabel
                : BuildSourceLabel(probed.Height, probed.IsHdr);

            var source = MediaSource.ForMovie(
                movie.Id,
                filePath,
                sourceLabel,
                probed.Container,
                probed.VideoCodec,
                probed.AudioCodec,
                probed.Width,
                probed.Height,
                probed.IsHdr,
                probed.BitrateBps,
                fileInfo.Length,
                probed.DurationMs);
            source.UpdateFileFingerprint(fileInfo.Length, lastWriteUtc);

            AddProbedStreams(source, probed);
            db.MediaSources.Add(source);
            existingSourcesByPath[filePath] = source;
            upserted++;
        }

        var utcNow = timeProvider.GetUtcNow();
        var markedMissing = 0;
        foreach (var existingSource in existingSourcesByPath.Values)
        {
            if (!discoveredSet.Contains(existingSource.FilePath))
            {
                existingSource.MarkMissing(utcNow);
                markedMissing++;
            }
        }

        return new LibraryScanResult(root.Id, files.Count, upserted, markedMissing, utcNow);
    }

    private async Task<LibraryScanResult> ScanSeriesAsync(MediaLibraryRoot root, CancellationToken cancellationToken)
    {
        var files = EnumerateSupportedFiles(root.RootPath, VideoExtensions);
        var discoveredSet = new HashSet<string>(files, StringComparer.Ordinal);
        var existingSeries = await db.TvSeries
            .Where(s => s.LibraryRootId == root.Id)
            .Include(s => s.Seasons)
            .ThenInclude(sn => sn.Episodes)
            .ThenInclude(ep => ep.Sources)
            .ToListAsync(cancellationToken);

        var seriesByKey = existingSeries.ToDictionary(s => (NormalizeKey(s.Title), s.Year));
        var existingSourcesByPath = existingSeries
            .SelectMany(s => s.Seasons)
            .SelectMany(sn => sn.Episodes)
            .SelectMany(ep => ep.Sources)
            .ToDictionary(src => src.FilePath, StringComparer.Ordinal);

        var upserted = 0;
        foreach (var filePath in files)
        {
            var fileInfo = new FileInfo(filePath);
            var lastWriteUtc = new DateTimeOffset(fileInfo.LastWriteTimeUtc, TimeSpan.Zero);

            if (existingSourcesByPath.TryGetValue(filePath, out var existingSource))
            {
                existingSource.UpdateFileFingerprint(fileInfo.Length, lastWriteUtc);
                continue;
            }

            var (seriesTitle, year, seasonNumber, episodeNumber, suffixLabel) =
                ParseEpisodeFilename(Path.GetFileNameWithoutExtension(filePath));
            var seriesKey = (NormalizeKey(seriesTitle), year);

            if (!seriesByKey.TryGetValue(seriesKey, out var series))
            {
                series = new TvSeries(root.Id, seriesTitle, year);
                db.TvSeries.Add(series);
                seriesByKey[seriesKey] = series;
            }

            var season = series.Seasons.FirstOrDefault(s => s.SeasonNumber == seasonNumber);
            if (season is null)
            {
                season = new TvSeason(series.Id, seasonNumber, $"Season {seasonNumber}");
                series.Seasons.Add(season);
                db.TvSeasons.Add(season);
            }

            var episode = season.Episodes.FirstOrDefault(e => e.EpisodeNumber == episodeNumber);
            if (episode is null)
            {
                episode = new Episode(season.Id, episodeNumber, $"Episode {episodeNumber}");
                season.Episodes.Add(episode);
                db.Episodes.Add(episode);
            }

            var probed = await mediaProbeService.ProbeAsync(filePath, cancellationToken);
            if (probed is null)
            {
                continue;
            }

            var sourceLabel = !string.IsNullOrWhiteSpace(suffixLabel)
                ? suffixLabel
                : BuildSourceLabel(probed.Height, probed.IsHdr);

            var source = MediaSource.ForEpisode(
                episode.Id,
                filePath,
                sourceLabel,
                probed.Container,
                probed.VideoCodec,
                probed.AudioCodec,
                probed.Width,
                probed.Height,
                probed.IsHdr,
                probed.BitrateBps,
                fileInfo.Length,
                probed.DurationMs);
            source.UpdateFileFingerprint(fileInfo.Length, lastWriteUtc);

            AddProbedStreams(source, probed);
            db.MediaSources.Add(source);
            existingSourcesByPath[filePath] = source;
            upserted++;
        }

        var utcNow = timeProvider.GetUtcNow();
        var markedMissing = 0;
        foreach (var existingSource in existingSourcesByPath.Values)
        {
            if (!discoveredSet.Contains(existingSource.FilePath))
            {
                existingSource.MarkMissing(utcNow);
                markedMissing++;
            }
        }

        return new LibraryScanResult(root.Id, files.Count, upserted, markedMissing, utcNow);
    }

    private async Task<LibraryScanResult> ScanMusicAsync(MediaLibraryRoot root, CancellationToken cancellationToken)
    {
        var files = EnumerateSupportedFiles(root.RootPath, AudioExtensions);
        var discoveredSet = new HashSet<string>(files, StringComparer.Ordinal);

        var existingSongs = await db.Songs
            .Where(s => s.LibraryRootId == root.Id)
            .ToListAsync(cancellationToken);
        var songsByPath = existingSongs.ToDictionary(s => s.FilePath, StringComparer.Ordinal);

        var artistsByName = (await db.Artists.Include(a => a.Albums).ToListAsync(cancellationToken))
            .ToDictionary(a => NormalizeKey(a.Name));

        var upserted = 0;
        foreach (var filePath in files)
        {
            if (songsByPath.TryGetValue(filePath, out var existingSong))
            {
                existingSong.MarkPresent();
                continue;
            }

            var meta = audioMetadataReader.ReadMetadata(filePath);
            if (meta is null)
            {
                continue;
            }

            var artistKey = NormalizeKey(meta.ArtistName);
            if (!artistsByName.TryGetValue(artistKey, out var artist))
            {
                artist = new Artist(meta.ArtistName);
                db.Artists.Add(artist);
                artistsByName[artistKey] = artist;
            }

            var album = artist.Albums.FirstOrDefault(
                a => string.Equals(a.Title, meta.AlbumTitle, StringComparison.OrdinalIgnoreCase));
            if (album is null)
            {
                string? artworkHash = null;
                if (meta.EmbeddedArtworkBytes is { Length: > 0 })
                {
                    artworkHash = await artworkStore.SaveArtworkVariantsAsync(meta.EmbeddedArtworkBytes, cancellationToken);
                }

                album = new Album(artist.Id, meta.AlbumTitle, meta.Year, artworkHash);
                artist.Albums.Add(album);
                db.Albums.Add(album);
            }

            var fileInfo = new FileInfo(filePath);
            var lastWriteUtc = new DateTimeOffset(fileInfo.LastWriteTimeUtc, TimeSpan.Zero);
            var song = new Song(
                root.Id,
                artist.Id,
                album.Id,
                meta.Title,
                meta.TrackNumber,
                meta.DiscNumber,
                meta.DurationMs,
                filePath,
                meta.Codec,
                meta.BitrateBps,
                meta.SampleRateHz,
                meta.BitDepth,
                fileInfo.Length,
                lastWriteUtc);

            db.Songs.Add(song);
            songsByPath[filePath] = song;
            upserted++;
        }

        var utcNow = timeProvider.GetUtcNow();
        var markedMissing = 0;
        foreach (var existingSong in songsByPath.Values)
        {
            if (!discoveredSet.Contains(existingSong.FilePath))
            {
                existingSong.MarkMissing(utcNow);
                markedMissing++;
            }
        }

        return new LibraryScanResult(root.Id, files.Count, upserted, markedMissing, utcNow);
    }

    private async Task TryEnrichMovieFromTmdbAsync(
        Movie movie,
        string parsedTitle,
        int? parsedYear,
        CancellationToken cancellationToken)
    {
        if (movie.IsMetadataLocked || movie.TmdbId is not null)
        {
            return;
        }

        var candidates = await tmdbClient.SearchAsync(LibraryMediaType.Movies, parsedTitle, parsedYear, cancellationToken);
        var match = candidates.FirstOrDefault();
        if (match is null)
        {
            return;
        }

        var posterHash = await TryCacheTmdbArtworkAsync(match.PosterPath, cancellationToken);
        var backdropHash = await TryCacheTmdbArtworkAsync(match.BackdropPath, cancellationToken);
        movie.ApplyScannedMetadata(match.Title, match.Year ?? parsedYear, match.Overview, match.TmdbId, posterHash, backdropHash);
    }

    private async Task<string?> TryCacheTmdbArtworkAsync(string? remotePath, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(remotePath))
        {
            return null;
        }

        var bytes = await tmdbClient.DownloadImageBytesAsync(remotePath, cancellationToken);
        return bytes is { Length: > 0 }
            ? await artworkStore.SaveArtworkVariantsAsync(bytes, cancellationToken)
            : null;
    }

    private static List<string> EnumerateSupportedFiles(string rootPath, HashSet<string> extensions)
    {
        return Directory.EnumerateFiles(rootPath, "*", SearchOption.AllDirectories)
            .Where(path => extensions.Contains(Path.GetExtension(path)))
            .Where(path => !ShouldIgnorePath(rootPath, path))
            .OrderBy(path => path, StringComparer.Ordinal)
            .ToList();
    }

    private static bool ShouldIgnorePath(string rootPath, string filePath)
    {
        var relative = Path.GetRelativePath(rootPath, filePath);
        var segments = relative.Split([Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar], StringSplitOptions.RemoveEmptyEntries);
        foreach (var segment in segments)
        {
            var token = Path.GetFileNameWithoutExtension(segment);
            if (IgnoredTokens.Any(ignored => token.Contains(ignored, StringComparison.OrdinalIgnoreCase)))
            {
                return true;
            }
        }

        return false;
    }

    private static void AddProbedStreams(MediaSource source, ProbedMediaInfo probed)
    {
        foreach (var stream in probed.Streams)
        {
            source.Streams.Add(new MediaStream(
                source.Id,
                stream.StreamIndex,
                stream.Kind,
                stream.Codec,
                stream.Language,
                stream.Title,
                stream.IsDefault));
        }
    }

    private static string BuildSourceLabel(int height, bool isHdr) =>
        height switch
        {
            >= 2160 => isHdr ? "2160p HDR" : "2160p",
            >= 1080 => isHdr ? "1080p HDR" : "1080p",
            > 0 => $"{height}p",
            _ => "Source"
        };

    private static string NormalizeKey(string value) =>
        string.Join(' ', value.Split(' ', StringSplitOptions.RemoveEmptyEntries)).ToLowerInvariant();

    private static (string CleanBase, string? SuffixLabel) SplitDashSuffix(string baseName)
    {
        var working = baseName.Trim();
        var dashSplitIndex = working.LastIndexOf(" - ", StringComparison.Ordinal);
        if (dashSplitIndex <= 0)
        {
            return (working, null);
        }

        return (working[..dashSplitIndex].Trim(), working[(dashSplitIndex + 3)..].Trim());
    }

    private static (string Title, int? Year, string? SuffixLabel) ParseMovieFilename(string baseName)
    {
        var (working, suffixLabel) = SplitDashSuffix(baseName);

        var match = MovieParenthesizedYearRegex().Match(working);
        if (!match.Success)
        {
            match = MovieTrailingYearRegex().Match(working);
        }

        if (match.Success)
        {
            var title = match.Groups["title"].Value.Replace('.', ' ').Replace('_', ' ').Trim();
            var year = int.Parse(match.Groups["year"].Value);
            return (title, year, suffixLabel);
        }

        return (working.Replace('.', ' ').Replace('_', ' ').Trim(), null, suffixLabel);
    }

    private static (string SeriesTitle, int? Year, int SeasonNumber, int EpisodeNumber, string? SuffixLabel) ParseEpisodeFilename(string baseName)
    {
        var (working, suffixLabel) = SplitDashSuffix(baseName);

        var match = EpisodePatternRegex().Match(working);
        if (match.Success)
        {
            var rawSeries = match.Groups["series"].Value.Replace('.', ' ').Replace('_', ' ').Trim();
            var (cleanSeries, year, _) = ParseMovieFilename(rawSeries);
            var season = int.Parse(match.Groups["season"].Value);
            var episode = int.Parse(match.Groups["episode"].Value);
            return (cleanSeries, year, season, episode, suffixLabel);
        }

        return (working, null, 1, 1, suffixLabel);
    }

    [GeneratedRegex(@"^(?<title>.+?)\s*[\(\[](?<year>(?:19|20)\d{2})[\)\]](?:\s+.*)?$")]
    private static partial Regex MovieParenthesizedYearRegex();

    [GeneratedRegex(@"^(?<title>.+?)[.\s_-]+(?<year>(?:19|20)\d{2})$")]
    private static partial Regex MovieTrailingYearRegex();

    [GeneratedRegex(@"^(?<series>.+?)[.\s_-]+[Ss](?<season>\d{1,2})[Ee](?<episode>\d{1,3})")]
    private static partial Regex EpisodePatternRegex();
}
