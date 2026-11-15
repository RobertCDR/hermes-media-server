using Hermes.Domain.Enums;

namespace Hermes.Domain.Entities;

public sealed class MediaLibraryRoot
{
    private MediaLibraryRoot()
    {
        Name = string.Empty;
        RootPath = string.Empty;
    }

    public MediaLibraryRoot(string name, LibraryMediaType mediaType, string rootPath, bool watchEnabled)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        ArgumentException.ThrowIfNullOrWhiteSpace(rootPath);

        Id = Guid.NewGuid();
        Name = name.Trim();
        MediaType = mediaType;
        RootPath = rootPath.Trim();
        WatchEnabled = watchEnabled;
        CreatedAtUtc = DateTimeOffset.UtcNow;
    }

    public Guid Id { get; private set; }
    public string Name { get; private set; }
    public LibraryMediaType MediaType { get; private set; }
    public string RootPath { get; private set; }
    public bool WatchEnabled { get; private set; }
    public DateTimeOffset CreatedAtUtc { get; private set; }
    public DateTimeOffset? LastScanCompletedAtUtc { get; private set; }

    public void MarkScanCompleted(DateTimeOffset utcNow) => LastScanCompletedAtUtc = utcNow;
}

public sealed class Movie
{
    private Movie()
    {
        Title = string.Empty;
    }

    public Movie(Guid libraryRootId, string title, int? year)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(title);

        Id = Guid.NewGuid();
        LibraryRootId = libraryRootId;
        Title = title.Trim();
        Year = year;
        AddedAtUtc = DateTimeOffset.UtcNow;
    }

    public Guid Id { get; private set; }
    public Guid LibraryRootId { get; private set; }
    public string Title { get; private set; }
    public int? Year { get; private set; }
    public string? Overview { get; private set; }
    public int? TmdbId { get; private set; }
    public string? ArtworkHash { get; private set; }
    public string? BackdropHash { get; private set; }
    public bool IsMetadataLocked { get; private set; }
    public DateTimeOffset AddedAtUtc { get; private set; }

    public ICollection<MediaSource> Sources { get; } = [];

    public void ApplyScannedMetadata(string title, int? year, string? overview, int? tmdbId, string? artworkHash, string? backdropHash)
    {
        if (IsMetadataLocked)
        {
            return;
        }

        ArgumentException.ThrowIfNullOrWhiteSpace(title);
        Title = title.Trim();
        Year = year;
        Overview = overview;
        TmdbId = tmdbId;
        ArtworkHash = artworkHash;
        BackdropHash = backdropHash;
    }

    public void LockManualMatch(int tmdbId, string title, int? year, string? overview, string? artworkHash, string? backdropHash)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(title);
        TmdbId = tmdbId;
        Title = title.Trim();
        Year = year;
        Overview = overview;
        ArtworkHash = artworkHash;
        BackdropHash = backdropHash;
        IsMetadataLocked = true;
    }
}

public sealed class TvSeries
{
    private TvSeries()
    {
        Title = string.Empty;
    }

    public TvSeries(Guid libraryRootId, string title, int? year)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(title);

        Id = Guid.NewGuid();
        LibraryRootId = libraryRootId;
        Title = title.Trim();
        Year = year;
        AddedAtUtc = DateTimeOffset.UtcNow;
    }

    public Guid Id { get; private set; }
    public Guid LibraryRootId { get; private set; }
    public string Title { get; private set; }
    public int? Year { get; private set; }
    public string? Overview { get; private set; }
    public int? TmdbId { get; private set; }
    public string? ArtworkHash { get; private set; }
    public string? BackdropHash { get; private set; }
    public bool IsMetadataLocked { get; private set; }
    public DateTimeOffset AddedAtUtc { get; private set; }

    public ICollection<TvSeason> Seasons { get; } = [];

    public void ApplyScannedMetadata(string title, int? year, string? overview, int? tmdbId, string? artworkHash, string? backdropHash)
    {
        if (IsMetadataLocked)
        {
            return;
        }

        ArgumentException.ThrowIfNullOrWhiteSpace(title);
        Title = title.Trim();
        Year = year;
        Overview = overview;
        TmdbId = tmdbId;
        ArtworkHash = artworkHash;
        BackdropHash = backdropHash;
    }

    public void LockManualMatch(int tmdbId, string title, int? year, string? overview, string? artworkHash, string? backdropHash)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(title);
        TmdbId = tmdbId;
        Title = title.Trim();
        Year = year;
        Overview = overview;
        ArtworkHash = artworkHash;
        BackdropHash = backdropHash;
        IsMetadataLocked = true;
    }
}

public sealed class TvSeason
{
    private TvSeason()
    {
        Title = string.Empty;
    }

    public TvSeason(Guid tvSeriesId, int seasonNumber, string title, string? artworkHash = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(title);

        Id = Guid.NewGuid();
        TvSeriesId = tvSeriesId;
        SeasonNumber = seasonNumber;
        Title = title.Trim();
        ArtworkHash = artworkHash;
    }

    public Guid Id { get; private set; }
    public Guid TvSeriesId { get; private set; }
    public int SeasonNumber { get; private set; }
    public string Title { get; private set; }
    public string? ArtworkHash { get; private set; }

    public TvSeries TvSeries { get; private set; } = null!;
    public ICollection<Episode> Episodes { get; } = [];
}

public sealed class Episode
{
    private Episode()
    {
        Title = string.Empty;
    }

    public Episode(Guid tvSeasonId, int episodeNumber, string title, string? overview = null, string? stillArtworkHash = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(title);

        Id = Guid.NewGuid();
        TvSeasonId = tvSeasonId;
        EpisodeNumber = episodeNumber;
        Title = title.Trim();
        Overview = overview;
        StillArtworkHash = stillArtworkHash;
    }

    public Guid Id { get; private set; }
    public Guid TvSeasonId { get; private set; }
    public int EpisodeNumber { get; private set; }
    public string Title { get; private set; }
    public string? Overview { get; private set; }
    public string? StillArtworkHash { get; private set; }
    public bool IsMetadataLocked { get; private set; }

    public TvSeason TvSeason { get; private set; } = null!;
    public ICollection<MediaSource> Sources { get; } = [];
}

public sealed class MediaSource
{
    private MediaSource()
    {
        FilePath = string.Empty;
        SourceLabel = string.Empty;
        Container = string.Empty;
        VideoCodec = string.Empty;
        AudioCodec = string.Empty;
    }

    private MediaSource(
        Guid? movieId,
        Guid? episodeId,
        string filePath,
        string sourceLabel,
        string container,
        string videoCodec,
        string audioCodec,
        int width,
        int height,
        bool isHdr,
        long bitrateBps,
        long fileSizeBytes,
        long durationMs)
    {
        if (movieId is null && episodeId is null)
        {
            throw new ArgumentException("MediaSource must belong to a Movie or Episode.");
        }

        ArgumentException.ThrowIfNullOrWhiteSpace(filePath);
        ArgumentException.ThrowIfNullOrWhiteSpace(sourceLabel);

        Id = Guid.NewGuid();
        MovieId = movieId;
        EpisodeId = episodeId;
        FilePath = filePath.Trim();
        SourceLabel = sourceLabel.Trim();
        Container = container;
        VideoCodec = videoCodec;
        AudioCodec = audioCodec;
        Width = width;
        Height = height;
        IsHdr = isHdr;
        BitrateBps = bitrateBps;
        FileSizeBytes = fileSizeBytes;
        DurationMs = durationMs;
        FileLastWriteUtc = DateTimeOffset.UtcNow;
    }

    public Guid Id { get; private set; }
    public Guid? MovieId { get; private set; }
    public Guid? EpisodeId { get; private set; }
    public string FilePath { get; private set; }
    public string SourceLabel { get; private set; }
    public string Container { get; private set; }
    public string VideoCodec { get; private set; }
    public string AudioCodec { get; private set; }
    public int Width { get; private set; }
    public int Height { get; private set; }
    public bool IsHdr { get; private set; }
    public long BitrateBps { get; private set; }
    public long FileSizeBytes { get; private set; }
    public long DurationMs { get; private set; }
    public DateTimeOffset FileLastWriteUtc { get; private set; }
    public DateTimeOffset? MissingSinceUtc { get; private set; }

    public Movie? Movie { get; private set; }
    public Episode? Episode { get; private set; }
    public ICollection<MediaStream> Streams { get; } = [];

    public static MediaSource ForMovie(
        Guid movieId,
        string filePath,
        string sourceLabel,
        string container,
        string videoCodec,
        string audioCodec,
        int width,
        int height,
        bool isHdr,
        long bitrateBps,
        long fileSizeBytes,
        long durationMs) =>
        new(movieId, null, filePath, sourceLabel, container, videoCodec, audioCodec, width, height, isHdr, bitrateBps, fileSizeBytes, durationMs);

    public static MediaSource ForEpisode(
        Guid episodeId,
        string filePath,
        string sourceLabel,
        string container,
        string videoCodec,
        string audioCodec,
        int width,
        int height,
        bool isHdr,
        long bitrateBps,
        long fileSizeBytes,
        long durationMs) =>
        new(null, episodeId, filePath, sourceLabel, container, videoCodec, audioCodec, width, height, isHdr, bitrateBps, fileSizeBytes, durationMs);

    public void UpdateFileFingerprint(long fileSizeBytes, DateTimeOffset fileLastWriteUtc)
    {
        FileSizeBytes = fileSizeBytes;
        FileLastWriteUtc = fileLastWriteUtc;
        MissingSinceUtc = null;
    }

    public void MarkMissing(DateTimeOffset utcNow) => MissingSinceUtc ??= utcNow;

    public void MarkPresent() => MissingSinceUtc = null;
}

public sealed class MediaStream
{
    private MediaStream()
    {
        Codec = string.Empty;
        Language = "und";
        Title = string.Empty;
    }

    public MediaStream(Guid mediaSourceId, int streamIndex, StreamKind kind, string codec, string language, string title, bool isDefault)
    {
        Id = Guid.NewGuid();
        MediaSourceId = mediaSourceId;
        StreamIndex = streamIndex;
        Kind = kind;
        Codec = codec;
        Language = string.IsNullOrWhiteSpace(language) ? "und" : language;
        Title = title;
        IsDefault = isDefault;
    }

    public Guid Id { get; private set; }
    public Guid MediaSourceId { get; private set; }
    public int StreamIndex { get; private set; }
    public StreamKind Kind { get; private set; }
    public string Codec { get; private set; }
    public string Language { get; private set; }
    public string Title { get; private set; }
    public bool IsDefault { get; private set; }

    public MediaSource MediaSource { get; private set; } = null!;
}

public sealed class WatchProgress
{
    private const double WatchedThresholdRatio = 0.90;

    private WatchProgress()
    {
    }

    private WatchProgress(Guid id, Guid userId, Guid? movieId, Guid? episodeId)
    {
        if (movieId is null && episodeId is null)
        {
            throw new ArgumentException("WatchProgress must reference a Movie or Episode.");
        }

        Id = id;
        UserId = userId;
        MovieId = movieId;
        EpisodeId = episodeId;
        UpdatedAtUtc = DateTimeOffset.UtcNow;
    }

    public Guid Id { get; private set; }
    public Guid UserId { get; private set; }
    public Guid? MovieId { get; private set; }
    public Guid? EpisodeId { get; private set; }
    public long PositionMs { get; private set; }
    public long DurationMs { get; private set; }
    public bool IsWatched { get; private set; }
    public DateTimeOffset UpdatedAtUtc { get; private set; }

    public static WatchProgress ForMovie(Guid userId, Guid movieId) =>
        new(Guid.NewGuid(), userId, movieId, null);

    public static WatchProgress ForEpisode(Guid userId, Guid episodeId) =>
        new(Guid.NewGuid(), userId, null, episodeId);

    public void UpdatePosition(long positionMs, long durationMs, DateTimeOffset utcNow)
    {
        var safeDuration = Math.Max(0, durationMs);
        var clampedPosition = Math.Max(0, positionMs);
        if (safeDuration > 0 && clampedPosition > safeDuration)
        {
            clampedPosition = safeDuration;
        }

        PositionMs = clampedPosition;
        DurationMs = safeDuration;
        UpdatedAtUtc = utcNow;

        if (safeDuration > 0 && (double)clampedPosition / safeDuration >= WatchedThresholdRatio)
        {
            IsWatched = true;
        }
    }

    public void SetWatched(bool watched, DateTimeOffset utcNow)
    {
        IsWatched = watched;
        if (watched && DurationMs > 0)
        {
            PositionMs = DurationMs;
        }
        UpdatedAtUtc = utcNow;
    }
}
