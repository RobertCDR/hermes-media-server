using System.Text.RegularExpressions;
using Hermes.Domain.Common;
using Hermes.Domain.Entities;
using Hermes.Domain.Enums;
using Hermes.Domain.Ports;
using Hermes.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

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
    TimeProvider timeProvider,
    LibraryScanProgressTracker? scanProgress = null,
    ILogger<LibraryScannerService>? logger = null)
{
    private static readonly HashSet<string> VideoExtensions =
        new([".mkv", ".mp4", ".avi", ".mov", ".m4v", ".webm", ".ts"], StringComparer.OrdinalIgnoreCase);

    private static readonly HashSet<string> AudioExtensions =
        new([".flac", ".mp3", ".m4a", ".ogg", ".wav", ".opus"], StringComparer.OrdinalIgnoreCase);

    private static readonly HashSet<string> SubtitleExtensions =
        new([".srt", ".vtt", ".ass", ".ssa", ".sub"], StringComparer.OrdinalIgnoreCase);

    internal static bool IsSupportedMediaFileExtension(LibraryMediaType mediaType, string extensionOrPath)
    {
        var ext = extensionOrPath.StartsWith('.') ? extensionOrPath : Path.GetExtension(extensionOrPath);
        if (string.IsNullOrEmpty(ext))
        {
            return false;
        }

        return mediaType switch
        {
            LibraryMediaType.Movies or LibraryMediaType.Series => VideoExtensions.Contains(ext) || SubtitleExtensions.Contains(ext),
            LibraryMediaType.Music => AudioExtensions.Contains(ext),
            _ => false
        };
    }

    private static readonly HashSet<string> IgnoredFolderSegments =
        new(["extras", "featurettes", "behind the scenes", "deleted scenes", "trailers", "trailer", "samples", "sample"], StringComparer.OrdinalIgnoreCase);

    private static readonly string[] IgnoredFileSuffixes = ["-trailer", ".trailer", "_trailer", " trailer", "-sample", ".sample", "_sample", " sample"];

    public async Task<LibraryScanResult?> ScanLibraryAsync(Guid libraryRootId, CancellationToken cancellationToken)
    {
        using var scanLock = scanProgress is null
            ? null
            : await scanProgress.AcquireScanLockAsync(libraryRootId, cancellationToken);

        var root = await db.MediaLibraryRoots.SingleOrDefaultAsync(r => r.Id == libraryRootId, cancellationToken);
        if (root is null)
        {
            return null;
        }

        if (!Directory.Exists(root.RootPath))
        {
            return new LibraryScanResult(root.Id, 0, 0, 0, timeProvider.GetUtcNow());
        }

        try
        {
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
        finally
        {
            scanProgress?.Complete(root.Id);
        }
    }

    private async Task<LibraryScanResult> ScanMoviesAsync(MediaLibraryRoot root, CancellationToken cancellationToken)
    {
        var files = EnumerateSupportedFiles(root.RootPath, VideoExtensions);
        scanProgress?.BeginScan(root.Id, files.Count, timeProvider.GetUtcNow());
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
            scanProgress?.Advance(root.Id);
            try
            {
                var fileInfo = new FileInfo(filePath);
                if (!fileInfo.Exists)
                {
                    continue;
                }

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

                if (root.FetchMetadata)
                {
                    await TryEnrichMovieFromTmdbAsync(movie, title, year, cancellationToken);
                }

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
            catch (Exception ex) when (ex is FileNotFoundException or DirectoryNotFoundException or IOException or UnauthorizedAccessException)
            {
                logger?.LogWarning(ex, "Skipped unreadable or vanished movie file {FilePath}.", filePath);
            }
        }

        if (root.FetchMetadata)
        {
            foreach (var movie in moviesByKey.Values)
            {
                if (movie.TmdbId is not null && movie.GenresCsv is null && movie.Rating is null)
                {
                    await CinemaMetadataEnricher.EnrichMovieAsync(tmdbClient, artworkStore, movie, cancellationToken);
                }
            }
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
        scanProgress?.BeginScan(root.Id, files.Count, timeProvider.GetUtcNow());
        var discoveredSet = new HashSet<string>(files, StringComparer.Ordinal);
        var existingSeries = await db.TvSeries
            .Where(s => s.LibraryRootId == root.Id)
            .Include(s => s.Seasons)
            .ThenInclude(sn => sn.Episodes)
            .ThenInclude(ep => ep.Sources)
            .ToListAsync(cancellationToken);

        var seriesByKey = new Dictionary<(string, int?), TvSeries>();
        var existingSourcesByPath = new Dictionary<string, MediaSource>(StringComparer.Ordinal);
        foreach (var s in existingSeries)
        {
            seriesByKey.TryAdd((NormalizeKey(s.Title), s.Year), s);
            foreach (var sn in s.Seasons)
            {
                foreach (var ep in sn.Episodes)
                {
                    foreach (var src in ep.Sources)
                    {
                        existingSourcesByPath.TryAdd(src.FilePath, src);
                    }
                }
            }
        }

        var upserted = 0;
        foreach (var filePath in files)
        {
            scanProgress?.Advance(root.Id);
            try
            {
                var fileInfo = new FileInfo(filePath);
                if (!fileInfo.Exists)
                {
                    continue;
                }

                var lastWriteUtc = new DateTimeOffset(fileInfo.LastWriteTimeUtc, TimeSpan.Zero);

                if (existingSourcesByPath.TryGetValue(filePath, out var existingSource))
                {
                    existingSource.UpdateFileFingerprint(fileInfo.Length, lastWriteUtc);
                    continue;
                }

                var (seriesTitle, year, seasonNumber, episodeNumber, suffixLabel) =
                    ParseEpisodeWithFolderContext(root.RootPath, filePath);
                var seriesKey = (NormalizeKey(seriesTitle), year);

                if (!seriesByKey.TryGetValue(seriesKey, out var series))
                {
                    series = new TvSeries(root.Id, seriesTitle, year);
                    db.TvSeries.Add(series);
                    seriesByKey[seriesKey] = series;
                }

                if (root.FetchMetadata)
                {
                    await TryEnrichSeriesFromTmdbAsync(series, seriesTitle, year, cancellationToken);
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
            catch (Exception ex) when (ex is FileNotFoundException or DirectoryNotFoundException or IOException or UnauthorizedAccessException)
            {
                logger?.LogWarning(ex, "Skipped unreadable or vanished series file {FilePath}.", filePath);
            }
        }

        if (root.FetchMetadata)
        {
            foreach (var series in seriesByKey.Values)
            {
                await TryEnrichSeriesFromTmdbAsync(series, series.Title, series.Year, cancellationToken);
                if (series.TmdbId is int seriesTmdbId)
                {
                    if ((series.GenresCsv is null && series.Rating is null) ||
                        series.Seasons.Any(sn => sn.ExpectedEpisodeCount is null))
                    {
                        await CinemaMetadataEnricher.EnrichSeriesAsync(tmdbClient, artworkStore, series, cancellationToken);
                    }
                    await TryEnrichSeriesEpisodesFromTmdbAsync(series, seriesTmdbId, cancellationToken);
                }
            }
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
        scanProgress?.BeginScan(root.Id, files.Count, timeProvider.GetUtcNow());
        var discoveredSet = new HashSet<string>(files, StringComparer.Ordinal);

        var existingSongs = await db.Songs
            .Include(s => s.SongArtists)
            .Where(s => s.LibraryRootId == root.Id)
            .ToListAsync(cancellationToken);
        var songsByPath = new Dictionary<string, Song>(StringComparer.Ordinal);
        foreach (var existing in existingSongs)
        {
            songsByPath.TryAdd(existing.FilePath, existing);
        }

        var artistsByName = new Dictionary<string, Artist>();
        foreach (var existingArtist in await db.Artists.Include(a => a.Albums).ToListAsync(cancellationToken))
        {
            artistsByName.TryAdd(NormalizeKey(existingArtist.Name), existingArtist);
        }

        var upserted = 0;
        foreach (var filePath in files)
        {
            scanProgress?.Advance(root.Id);
            try
            {
                if (songsByPath.TryGetValue(filePath, out var existingSong))
                {
                    var existingInfo = new FileInfo(filePath);
                    if (!existingInfo.Exists)
                    {
                        continue;
                    }

                    var existingWriteUtc = new DateTimeOffset(existingInfo.LastWriteTimeUtc, TimeSpan.Zero);
                    existingSong.UpdateFileFingerprint(existingInfo.Length, existingWriteUtc);
                    if (existingSong.SongArtists.Count == 0)
                    {
                        var refreshedMeta = audioMetadataReader.ReadMetadata(filePath);
                        if (refreshedMeta is not null)
                        {
                            var refreshedCredits = ResolveArtistCredits(refreshedMeta);
                            var creditArtists = EnsureArtistsExist(artistsByName, refreshedCredits);
                            for (var pos = 0; pos < creditArtists.Count; pos++)
                            {
                                var sa = new SongArtist(existingSong.Id, creditArtists[pos].Id, pos);
                                existingSong.SongArtists.Add(sa);
                                db.SongArtists.Add(sa);
                            }
                        }
                        else
                        {
                            var fallbackSa = new SongArtist(existingSong.Id, existingSong.ArtistId, 0);
                            existingSong.SongArtists.Add(fallbackSa);
                            db.SongArtists.Add(fallbackSa);
                        }
                    }
                    continue;
                }

                var meta = audioMetadataReader.ReadMetadata(filePath);
                if (meta is null)
                {
                    continue;
                }

                var creditNames = ResolveArtistCredits(meta);
                var creditedArtists = EnsureArtistsExist(artistsByName, creditNames);
                var artist = creditedArtists[0];

                var album = artist.Albums.FirstOrDefault(
                    a => string.Equals(a.Title, meta.AlbumTitle, StringComparison.OrdinalIgnoreCase));
                if (album is null)
                {
                    string? artworkHash = null;
                    if (meta.EmbeddedArtworkBytes is { Length: > 0 })
                    {
                        try
                        {
                            artworkHash = await artworkStore.SaveArtworkVariantsAsync(meta.EmbeddedArtworkBytes, cancellationToken);
                        }
                        catch (Exception) when (!cancellationToken.IsCancellationRequested)
                        {
                            artworkHash = null;
                        }
                    }

                    album = new Album(artist.Id, meta.AlbumTitle, meta.Year, artworkHash);
                    artist.Albums.Add(album);
                    db.Albums.Add(album);
                }

                var fileInfo = new FileInfo(filePath);
                if (!fileInfo.Exists)
                {
                    continue;
                }

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
                for (var pos = 0; pos < creditedArtists.Count; pos++)
                {
                    var link = new SongArtist(song.Id, creditedArtists[pos].Id, pos);
                    song.SongArtists.Add(link);
                    db.SongArtists.Add(link);
                }

                songsByPath[filePath] = song;
                upserted++;
            }
            catch (Exception ex) when (ex is FileNotFoundException or DirectoryNotFoundException or IOException or UnauthorizedAccessException)
            {
                logger?.LogWarning(ex, "Skipped unreadable or vanished audio file {FilePath}.", filePath);
            }
        }

        List<Artist> EnsureArtistsExist(Dictionary<string, Artist> lookup, IReadOnlyList<string> names)
        {
            var resolved = new List<Artist>(names.Count);
            foreach (var name in names)
            {
                var key = NormalizeKey(name);
                if (!lookup.TryGetValue(key, out var found))
                {
                    found = new Artist(name);
                    db.Artists.Add(found);
                    lookup[key] = found;
                }
                resolved.Add(found);
            }
            return resolved;
        }

        static IReadOnlyList<string> ResolveArtistCredits(ProbedAudioTrackMetadata meta)
        {
            var raw = meta.ArtistCredits is { Count: > 0 }
                ? meta.ArtistCredits
                : ArtistCreditParser.FromPerformerTags([meta.ArtistName]);
            var normalized = ArtistCreditParser.NormalizeArtistNames(raw);
            return normalized.Count > 0 ? normalized : ["Unknown Artist"];
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

        var enriched = await TryFetchTmdbEnrichmentAsync(LibraryMediaType.Movies, parsedTitle, parsedYear, cancellationToken);
        if (enriched is not null)
        {
            var (match, posterHash, backdropHash) = enriched.Value;
            movie.ApplyScannedMetadata(match.Title, match.Year ?? parsedYear, match.Overview, match.TmdbId, posterHash, backdropHash);
            await CinemaMetadataEnricher.EnrichMovieAsync(tmdbClient, artworkStore, movie, cancellationToken);
        }
    }

    private async Task TryEnrichSeriesFromTmdbAsync(
        TvSeries series,
        string parsedTitle,
        int? parsedYear,
        CancellationToken cancellationToken)
    {
        if (series.IsMetadataLocked || series.TmdbId is not null)
        {
            return;
        }

        var enriched = await TryFetchTmdbEnrichmentAsync(LibraryMediaType.Series, parsedTitle, parsedYear, cancellationToken);
        if (enriched is not null)
        {
            var (match, posterHash, backdropHash) = enriched.Value;
            series.ApplyScannedMetadata(match.Title, match.Year ?? parsedYear, match.Overview, match.TmdbId, posterHash, backdropHash);
            await CinemaMetadataEnricher.EnrichSeriesAsync(tmdbClient, artworkStore, series, cancellationToken);
        }
    }

    private async Task TryEnrichSeriesEpisodesFromTmdbAsync(
        TvSeries series,
        int seriesTmdbId,
        CancellationToken cancellationToken)
    {
        foreach (var season in series.Seasons)
        {
            if (season.Episodes.Count == 0 || season.Episodes.All(e => !string.IsNullOrWhiteSpace(e.Overview)))
            {
                continue;
            }

            try
            {
                var remoteEpisodes = await tmdbClient.GetSeasonEpisodesAsync(seriesTmdbId, season.SeasonNumber, cancellationToken);
                if (remoteEpisodes.Count == 0)
                {
                    continue;
                }

                var byNumber = remoteEpisodes.ToDictionary(e => e.EpisodeNumber);
                foreach (var episode in season.Episodes)
                {
                    if (!byNumber.TryGetValue(episode.EpisodeNumber, out var remote) || episode.IsMetadataLocked)
                    {
                        continue;
                    }

                    string? stillHash = episode.StillArtworkHash;
                    if (string.IsNullOrWhiteSpace(stillHash))
                    {
                        stillHash = await TryCacheTmdbArtworkAsync(remote.StillPath, cancellationToken);
                    }

                    episode.ApplyScannedMetadata(remote.Title, remote.Overview, stillHash);
                }
            }
            catch (Exception) when (!cancellationToken.IsCancellationRequested)
            {
                // Transient TMDb season lookup errors must not abort the library scan.
            }
        }
    }

    private async Task<(TmdbSearchCandidate Match, string? PosterHash, string? BackdropHash)?> TryFetchTmdbEnrichmentAsync(
        LibraryMediaType mediaType,
        string parsedTitle,
        int? parsedYear,
        CancellationToken cancellationToken)
    {
        try
        {
            var candidates = await tmdbClient.SearchAsync(mediaType, parsedTitle, parsedYear, cancellationToken);
            var match = candidates.FirstOrDefault(
                    c => string.Equals(c.Title.Trim(), parsedTitle.Trim(), StringComparison.OrdinalIgnoreCase))
                ?? candidates.FirstOrDefault();
            if (match is null)
            {
                return null;
            }

            var posterHash = await TryCacheTmdbArtworkAsync(match.PosterPath, cancellationToken);
            var backdropHash = await TryCacheTmdbArtworkAsync(match.BackdropPath, cancellationToken);
            return (match, posterHash, backdropHash);
        }
        catch (Exception) when (!cancellationToken.IsCancellationRequested)
        {
            return null;
        }
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
        var options = new EnumerationOptions
        {
            RecurseSubdirectories = true,
            IgnoreInaccessible = true,
            ReturnSpecialDirectories = false
        };

        return Directory.EnumerateFiles(rootPath, "*", options)
            .Where(path => extensions.Contains(Path.GetExtension(path)))
            .Where(path => !ShouldIgnorePath(rootPath, path))
            .OrderBy(path => path, StringComparer.Ordinal)
            .ToList();
    }

    internal static bool ShouldIgnorePath(string rootPath, string filePath)
    {
        var relative = Path.GetRelativePath(rootPath, filePath);
        var segments = relative.Split([Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar], StringSplitOptions.RemoveEmptyEntries);
        for (var i = 0; i < segments.Length; i++)
        {
            var isFileSegment = i == segments.Length - 1;
            var segment = segments[i];
            if (!isFileSegment)
            {
                if (IgnoredFolderSegments.Contains(segment.Trim()))
                {
                    return true;
                }

                continue;
            }

            var stem = Path.GetFileNameWithoutExtension(segment).Trim();
            if (IgnoredFolderSegments.Contains(stem) ||
                IgnoredFileSuffixes.Any(suffix => stem.EndsWith(suffix, StringComparison.OrdinalIgnoreCase)))
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

    private static (string SeriesTitle, int? Year, int SeasonNumber, int EpisodeNumber, string? SuffixLabel) ParseEpisodeWithFolderContext(
        string rootPath,
        string filePath)
    {
        var (parsedSeries, parsedYear, season, episode, suffixLabel) =
            ParseEpisodeFilename(Path.GetFileNameWithoutExtension(filePath));

        var relative = Path.GetRelativePath(rootPath, filePath);
        var parts = relative.Split([Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar], StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length <= 1)
        {
            return (parsedSeries, parsedYear, season, episode, suffixLabel);
        }

        // Inspect parent directories bottom-up (skipping Season XX / Specials folders)
        for (var i = parts.Length - 2; i >= 0; i--)
        {
            var folderName = parts[i].Trim();
            if (SeasonFolderRegex().IsMatch(folderName))
            {
                continue;
            }

            var (folderTitle, folderYear, _) = ParseMovieFilename(folderName);
            if (!string.IsNullOrWhiteSpace(folderTitle))
            {
                var finalTitle = string.IsNullOrWhiteSpace(parsedSeries) ? folderTitle : parsedSeries;
                var finalYear = parsedYear ?? folderYear;
                return (finalTitle, finalYear, season, episode, suffixLabel);
            }
        }

        var fallbackTitle = string.IsNullOrWhiteSpace(parsedSeries) ? "Unknown Series" : parsedSeries;
        return (fallbackTitle, parsedYear, season, episode, suffixLabel);
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

        var bareMatch = BareEpisodePatternRegex().Match(working);
        if (bareMatch.Success)
        {
            var season = int.Parse(bareMatch.Groups["season"].Value);
            var episode = int.Parse(bareMatch.Groups["episode"].Value);
            return (string.Empty, null, season, episode, suffixLabel);
        }

        return (working, null, 1, 1, suffixLabel);
    }

    [GeneratedRegex(@"^(?<title>.+?)\s*[\(\[](?<year>(?:19|20)\d{2})[\)\]](?:\s+.*)?$")]
    private static partial Regex MovieParenthesizedYearRegex();

    [GeneratedRegex(@"^(?<title>.+?)[.\s_-]+(?<year>(?:19|20)\d{2})(?:[.\s_-]+.*)?$")]
    private static partial Regex MovieTrailingYearRegex();

    [GeneratedRegex(@"^(?<series>.+?)[.\s_-]+[Ss](?<season>\d{1,2})[Ee](?<episode>\d{1,3})")]
    private static partial Regex EpisodePatternRegex();

    [GeneratedRegex(@"^[Ss](?<season>\d{1,2})[Ee](?<episode>\d{1,3})\b")]
    private static partial Regex BareEpisodePatternRegex();

    [GeneratedRegex(@"^(?:Season\s*\d+|Specials|S\d{1,2})$", RegexOptions.IgnoreCase)]
    private static partial Regex SeasonFolderRegex();
}
