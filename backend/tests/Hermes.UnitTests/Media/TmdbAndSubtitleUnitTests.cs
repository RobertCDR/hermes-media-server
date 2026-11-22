using System.Net;
using System.Text;
using FluentAssertions;
using Hermes.Domain.Entities;
using Hermes.Domain.Enums;
using Hermes.Domain.Ports;
using Hermes.Infrastructure.Media;
using Microsoft.Extensions.Configuration;
using Xunit;

namespace Hermes.UnitTests.Media;

public class TmdbAndSubtitleUnitTests
{
    [Fact]
    public async Task TmdbMetadataClient_HandlesMissingKey_Search_Details_AndImageDownloads()
    {
        var unconfigured = new TmdbMetadataClient(
            new HttpClient(new StubHttpMessageHandler(_ => throw new InvalidOperationException("Should not call HTTP"))),
            new ConfigurationBuilder().AddInMemoryCollection([]).Build());

        (await unconfigured.SearchAsync(LibraryMediaType.Movies, "Dune", 2024, CancellationToken.None)).Should().BeEmpty();
        (await unconfigured.GetDetailsAsync(LibraryMediaType.Movies, 693134, CancellationToken.None)).Should().BeNull();
        (await unconfigured.DownloadImageBytesAsync(" ", CancellationToken.None)).Should().BeNull();

        var requestedUrls = new List<string>();
        var handler = new StubHttpMessageHandler(req =>
        {
            var url = req.RequestUri!.ToString();
            requestedUrls.Add(url);

            if (url.Contains("/3/search/movie", StringComparison.Ordinal))
            {
                return JsonOk("""{"results":[{"id":693134,"title":"Dune: Part Two","release_date":"2024-02-27","overview":"Paul Atreides","poster_path":"/poster.jpg","backdrop_path":"/bg.jpg"}]}""");
            }

            if (url.Contains("/3/search/tv", StringComparison.Ordinal))
            {
                if (url.Contains("DARK", StringComparison.OrdinalIgnoreCase))
                {
                    return JsonOk("""{"results":[{"id":2883,"name":"Dark Shadows","original_name":"Dark Shadows","first_air_date":"1966-06-27","vote_count":98,"popularity":107.79},{"id":70523,"name":"Dark","original_name":"Dark","first_air_date":"2017-12-01","overview":"Time travel","vote_count":8005,"popularity":41.84}]}""");
                }
                return JsonOk("""{"results":[{"id":95396,"name":"Severance","first_air_date":"bad","overview":"Macrodata","poster_path":"/tv.jpg","backdrop_path":"/tvbg.jpg"}]}""");
            }

            if (url.Contains("/3/tv/70523/season/1", StringComparison.Ordinal))
            {
                return JsonOk("""{"episodes":[{"episode_number":1,"name":"Secrets","overview":"First episode","still_path":"/ep1.jpg"}]}""");
            }

            if (url.Contains("/3/movie/693134", StringComparison.Ordinal))
            {
                return JsonOk("""{"id":693134,"title":"Dune: Part Two","release_date":"2024-02-27","overview":"Part Two","poster_path":"/p.jpg","backdrop_path":"/b.jpg","vote_average":8.35,"runtime":166,"genres":[{"name":"Science Fiction"},{"name":"Adventure"}],"credits":{"cast":[{"name":"Zendaya","character":"Chani","order":1,"profile_path":"/z.jpg"},{"name":"Timothee Chalamet","character":"Paul Atreides","order":0,"profile_path":"/t.jpg"}]}}""");
            }

            if (url.Contains("/3/tv/95396", StringComparison.Ordinal))
            {
                return JsonOk("""{"id":95396,"name":"Severance","first_air_date":"2022-02-18","overview":"Lumon","poster_path":"/p2.jpg","backdrop_path":"/b2.jpg","vote_average":8.72,"episode_run_time":[55],"genres":[{"name":"Drama"},{"name":"Mystery"}],"seasons":[{"season_number":1,"episode_count":9}],"credits":{"cast":[{"name":"Adam Scott","character":"Mark Scout","order":0}]}}""");
            }

            if (url.StartsWith("https://image.tmdb.org/t/p/original/poster.jpg", StringComparison.Ordinal))
            {
                return new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent([1, 2, 3, 4]) };
            }

            if (url == "https://image.tmdb.org/t/p/original/custom.jpg")
            {
                return new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent([5, 6]) };
            }

            if (url == "https://cdn.example.com/custom.webp" || url == "http://image.tmdb.org/t/p/original/poster.jpg")
            {
                throw new InvalidOperationException("Rejected host/scheme should never be requested.");
            }

            return new HttpResponseMessage(HttpStatusCode.NotFound);
        });

        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?> { ["Hermes:TmdbApiKey"] = "test-tmdb-key" })
            .Build();
        var client = new TmdbMetadataClient(new HttpClient(handler), config);

        (await client.SearchAsync(LibraryMediaType.Movies, " ", null, CancellationToken.None)).Should().BeEmpty();

        var movieHits = await client.SearchAsync(LibraryMediaType.Movies, "Dune Part Two", 2024, CancellationToken.None);
        movieHits.Should().ContainSingle(c => c.TmdbId == 693134 && c.Title == "Dune: Part Two" && c.Year == 2024);

        var tvHits = await client.SearchAsync(LibraryMediaType.Series, "Severance", 2022, CancellationToken.None);
        tvHits.Should().ContainSingle(c => c.TmdbId == 95396 && c.Title == "Severance" && c.Year == null);

        var darkHits = await client.SearchAsync(LibraryMediaType.Series, "DARK", null, CancellationToken.None);
        darkHits.First().TmdbId.Should().Be(70523);
        darkHits.First().Title.Should().Be("Dark");

        var seasonEpisodes = await client.GetSeasonEpisodesAsync(70523, 1, CancellationToken.None);
        seasonEpisodes.Should().ContainSingle(e => e.EpisodeNumber == 1 && e.Title == "Secrets");

        var movieDetail = await client.GetDetailsAsync(LibraryMediaType.Movies, 693134, CancellationToken.None);
        movieDetail.Should().NotBeNull();
        movieDetail!.Overview.Should().Be("Part Two");

        var movieRich = await client.GetRichDetailsAsync(LibraryMediaType.Movies, 693134, CancellationToken.None);
        movieRich.Should().NotBeNull();
        movieRich!.Rating.Should().Be(8.4);
        movieRich.RuntimeMinutes.Should().Be(166);
        movieRich.Genres.Should().Equal("Science Fiction", "Adventure");
        movieRich.Cast.Select(c => c.Name).Should().Equal("Timothee Chalamet", "Zendaya");

        var tvDetail = await client.GetDetailsAsync(LibraryMediaType.Series, 95396, CancellationToken.None);
        tvDetail.Should().NotBeNull();
        tvDetail!.Year.Should().Be(2022);

        var tvRich = await client.GetRichDetailsAsync(LibraryMediaType.Series, 95396, CancellationToken.None);
        tvRich.Should().NotBeNull();
        tvRich!.Rating.Should().Be(8.7);
        tvRich.Seasons.Should().ContainSingle(s => s.SeasonNumber == 1 && s.EpisodeCount == 9);

        (await client.DownloadImageBytesAsync("/poster.jpg", CancellationToken.None)).Should().Equal([1, 2, 3, 4]);
        (await client.DownloadImageBytesAsync("https://image.tmdb.org/t/p/original/custom.jpg", CancellationToken.None)).Should().Equal([5, 6]);
        (await client.DownloadImageBytesAsync("https://cdn.example.com/custom.webp", CancellationToken.None)).Should().BeNull();
        (await client.DownloadImageBytesAsync("http://image.tmdb.org/t/p/original/poster.jpg", CancellationToken.None)).Should().BeNull();
        (await client.DownloadImageBytesAsync("http://127.0.0.1/secret.png", CancellationToken.None)).Should().BeNull();
        (await client.DownloadImageBytesAsync("/missing.jpg", CancellationToken.None)).Should().BeNull();
        requestedUrls.Should().Contain(u => u.Contains("first_air_date_year=2022", StringComparison.Ordinal));
    }

    [Fact]
    public async Task CinemaMetadataEnricher_EnrichesMoviesSeriesCastAndExpectedSeasonsSafely()
    {
        var tempArtwork = Path.Combine(Path.GetTempPath(), $"hermes-enrich-art-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempArtwork);
        try
        {
            var artworkStore = new SkiaArtworkStore(tempArtwork);
            var tmdb = new StubEnricherTmdbClient();
            var root = new MediaLibraryRoot("Cinema", LibraryMediaType.Movies, "/media/movies", false);
            var movie = new Movie(root.Id, "Dune: Part Two", 2024);
            movie.ApplyScannedMetadata("Dune: Part Two", 2024, "Overview", 693134, null, null);

            await CinemaMetadataEnricher.EnrichMovieAsync(tmdb, artworkStore, movie, CancellationToken.None);
            movie.Rating.Should().Be(8.4);
            movie.RuntimeMinutes.Should().Be(166);
            CinemaMetadataEnricher.ParseGenresCsv(movie.GenresCsv).Should().Equal("Science Fiction", "Adventure");
            var movieCast = CinemaMetadataEnricher.DeserializeCastJson(movie.CastJson);
            movieCast.Should().HaveCount(1);
            movieCast[0].Name.Should().Be("Timothee Chalamet");
            movieCast[0].ArtworkHash.Should().BeNull(); // null image bytes safely handled

            var series = new TvSeries(root.Id, "Dark", 2017);
            series.ApplyScannedMetadata("Dark", 2017, "Winden", 70523, null, null);
            var season1 = new TvSeason(series.Id, 1, "Season 1");
            series.Seasons.Add(season1);

            await CinemaMetadataEnricher.EnrichSeriesAsync(tmdb, artworkStore, series, CancellationToken.None);
            series.Rating.Should().Be(8.8);
            season1.ExpectedEpisodeCount.Should().Be(10);
            CinemaMetadataEnricher.DeserializeCastJson("invalid-json").Should().BeEmpty();
        }
        finally
        {
            if (Directory.Exists(tempArtwork))
            {
                Directory.Delete(tempArtwork, recursive: true);
            }
        }
    }

    private sealed class StubEnricherTmdbClient : ITmdbClient
    {
        public Task<IReadOnlyList<TmdbSearchCandidate>> SearchAsync(LibraryMediaType mediaType, string query, int? year, CancellationToken cancellationToken) =>
            Task.FromResult<IReadOnlyList<TmdbSearchCandidate>>([]);

        public Task<TmdbSearchCandidate?> GetDetailsAsync(LibraryMediaType mediaType, int tmdbId, CancellationToken cancellationToken) =>
            Task.FromResult<TmdbSearchCandidate?>(null);

        public Task<byte[]?> DownloadImageBytesAsync(string remotePath, CancellationToken cancellationToken) =>
            Task.FromResult<byte[]?>(null);

        public Task<TmdbRichDetails?> GetRichDetailsAsync(LibraryMediaType mediaType, int tmdbId, CancellationToken cancellationToken)
        {
            if (mediaType == LibraryMediaType.Movies)
            {
                return Task.FromResult<TmdbRichDetails?>(new TmdbRichDetails(
                    8.4,
                    166,
                    ["Science Fiction", "Adventure"],
                    [new TmdbCastCandidate("Timothee Chalamet", "Paul Atreides", "/tc.jpg")],
                    []));
            }

            return Task.FromResult<TmdbRichDetails?>(new TmdbRichDetails(
                8.8,
                55,
                ["Sci-Fi", "Mystery"],
                [new TmdbCastCandidate("Louis Hofmann", "Jonas Kahnwald", null)],
                [new TmdbSeasonCountCandidate(1, 10)]));
        }
    }

    [Fact]
    public async Task SubtitleExtractorService_ConvertsSrtAssAndVttSidecars_AndFallsBackSafely()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"hermes-subs-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            var service = new SubtitleExtractorService();
            (await service.ExtractWebVttAsync(Path.Combine(tempDir, "missing.mkv"), 0, CancellationToken.None))
                .Should().BeNull();

            // 1. Headerless VTT sidecar
            var vttMovie = Path.Combine(tempDir, "SampleVtt.mkv");
            await File.WriteAllBytesAsync(vttMovie, [0x00]);
            await File.WriteAllTextAsync(Path.Combine(tempDir, "SampleVtt.vtt"), "00:00:01.000 --> 00:00:02.000\nHello VTT\n");
            var extractedVtt = await service.ExtractWebVttAsync(vttMovie, 0, CancellationToken.None);
            extractedVtt.Should().StartWith("WEBVTT");
            extractedVtt.Should().Contain("Hello VTT");

            // 2. Language-tagged ASS sidecar
            var assMovie = Path.Combine(tempDir, "SampleAss.mkv");
            await File.WriteAllBytesAsync(assMovie, [0x00]);
            var assContent = """
                [Script Info]
                Title: Sample
                [Events]
                Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
                Dialogue: 0,0:00:01.25,0:00:04.50,Default,,0,0,0,,{\i1}Line one\NLine two
                Dialogue: 0,0:00:05.00,0:00:06.00,Default,,0,0,0,,
                Dialogue: malformed
                """;
            await File.WriteAllTextAsync(Path.Combine(tempDir, "SampleAss.en.ass"), assContent);
            var extractedAss = await service.ExtractWebVttAsync(assMovie, 0, CancellationToken.None);
            extractedAss.Should().StartWith("WEBVTT");
            extractedAss.Should().Contain("00:00:01.250 --> 00:00:04.500");
            extractedAss.Should().Contain("Line one\nLine two");
            extractedAss.Should().NotContain(@"\i1");

            // 3. SRT conversion helper
            var srt = SubtitleExtractorService.ConvertSrtToWebVtt("1\r\n00:00:01,250 --> 00:00:02,750\r\nHi there!\r\n");
            srt.Should().Contain("00:00:01.250 --> 00:00:02.750");
            srt.Should().NotContain("\n1\n");

            // 4. Invalid video without sidecar -> ffmpeg returns non-zero cleanly as null
            var noSidecarMovie = Path.Combine(tempDir, "Broken.mkv");
            await File.WriteAllBytesAsync(noSidecarMovie, [0x01, 0x02, 0x03]);
            (await service.ExtractWebVttAsync(noSidecarMovie, 0, CancellationToken.None)).Should().BeNull();
        }
        finally
        {
            if (Directory.Exists(tempDir))
            {
                Directory.Delete(tempDir, recursive: true);
            }
        }
    }

    [Fact]
    public void TagLibAudioMetadataReader_HandlesMissingAndCorruptAudioFiles()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"hermes-taglib-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            var reader = new TagLibAudioMetadataReader();
            reader.ReadMetadata(Path.Combine(tempDir, "nope.mp3")).Should().BeNull();

            var corruptFile = Path.Combine(tempDir, "Corrupt Track.mp3");
            File.WriteAllBytes(corruptFile, [0xFF, 0x00, 0x13, 0x37]);

            var fallback = reader.ReadMetadata(corruptFile);
            fallback.Should().NotBeNull();
            fallback!.Title.Should().Be("Corrupt Track");
            fallback.ArtistName.Should().Be("Unknown Artist");
            fallback.AlbumTitle.Should().Be("Unknown Album");
            fallback.Codec.Should().Be("mp3");
            fallback.BitrateBps.Should().Be(320_000L);
        }
        finally
        {
            if (Directory.Exists(tempDir))
            {
                Directory.Delete(tempDir, recursive: true);
            }
        }
    }

    [Fact]
    public async Task LrcLyricsService_ParsesSyncedSidecarTimestamps_MultiTimestamps_Offset_AndPlainFallback()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"hermes-lrc-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            var songPath = Path.Combine(tempDir, "Midnight City.mp3");
            File.WriteAllBytes(songPath, [0x01, 0x02]);
            var lrcPath = Path.Combine(tempDir, "Midnight City.lrc");
            await File.WriteAllTextAsync(lrcPath, """
                [ti:Midnight City]
                [ar:M83]
                [offset:500]
                [00:12.50][00:45.2]Waiting in a car
                [00:20.00]Waiting for a ride in the dark
                """, CancellationToken.None);

            var service = new LrcLyricsService();
            var result = await service.ReadLyricsAsync(songPath, CancellationToken.None);

            result.IsSynced.Should().BeTrue();
            result.Source.Should().Be("sidecar");
            result.Lines.Should().HaveCount(3);
            result.Lines[0].TimestampMs.Should().Be(12_000L);
            result.Lines[0].Text.Should().Be("Waiting in a car");
            result.Lines[1].TimestampMs.Should().Be(19_500L);
            result.Lines[2].TimestampMs.Should().Be(44_700L);

            var plain = LrcLyricsService.ParseLrcText("First plain line\nSecond plain line\n");
            plain.IsSynced.Should().BeFalse();
            plain.Source.Should().Be("plain");
            plain.Lines.Select(l => l.TimestampMs).Should().AllBeEquivalentTo((long?)null);
            plain.Lines.Select(l => l.Text).Should().Equal("First plain line", "Second plain line");

            var missing = await service.ReadLyricsAsync(Path.Combine(tempDir, "absent.flac"), CancellationToken.None);
            missing.Lines.Should().BeEmpty();
            missing.Source.Should().Be("none");
        }
        finally
        {
            if (Directory.Exists(tempDir))
            {
                Directory.Delete(tempDir, recursive: true);
            }
        }
    }

    [Fact]
    public async Task LibraryScanProgressTracker_And_TranscodeGetActiveSessions_TrackLiveLifecycle()
    {
        var tracker = new LibraryScanProgressTracker();
        var libId = Guid.NewGuid();
        tracker.GetProgress(libId).Should().BeNull();

        tracker.BeginScan(libId, 10);
        tracker.Advance(libId);
        tracker.Advance(libId);
        var snap = tracker.GetProgress(libId);
        snap.Should().NotBeNull();
        snap!.IsScanning.Should().BeTrue();
        snap.ProcessedFiles.Should().Be(2);
        snap.TotalFiles.Should().Be(10);

        tracker.Complete(libId);
        tracker.GetProgress(libId).Should().BeNull();

        var tempDir = Path.Combine(Path.GetTempPath(), $"hermes-tr-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        try
        {
            var fakeMedia = Path.Combine(tempDir, "sample.mp4");
            File.WriteAllBytes(fakeMedia, [0x00, 0x01]);
            await using var manager = new FfmpegTranscodeSessionManager(tempDir);
            var lease = await manager.TryStartVideoHlsSessionAsync(
                Guid.NewGuid(),
                Guid.NewGuid(),
                fakeMedia,
                VideoQualityPreset.P720,
                1,
                0,
                2,
                CancellationToken.None);
            lease.Should().NotBeNull();
            var active = manager.GetActiveSessions();
            active.Should().ContainSingle(s => s.SessionId == lease!.SessionId && s.QualityLabel == nameof(VideoQualityPreset.P720));

            await manager.StopSessionAsync(lease!.SessionId, CancellationToken.None);
            manager.GetActiveSessions().Should().BeEmpty();
        }
        finally
        {
            if (Directory.Exists(tempDir))
            {
                Directory.Delete(tempDir, recursive: true);
            }
        }
    }

    [Fact]
    public async Task LibraryScanProgressTracker_TracksProgress_AndSerializesConcurrentScansPerLibrary()
    {
        var tracker = new LibraryScanProgressTracker();
        var libA = Guid.NewGuid();
        var libB = Guid.NewGuid();

        tracker.BeginScan(libA, 4, DateTimeOffset.UtcNow);
        tracker.Advance(libA);
        var snap = tracker.GetProgress(libA);
        snap.Should().NotBeNull();
        snap!.IsScanning.Should().BeTrue();
        snap.ProcessedFiles.Should().Be(1);
        snap.TotalFiles.Should().Be(4);
        tracker.Complete(libA);
        tracker.GetProgress(libA).Should().BeNull();

        using var firstLock = await tracker.AcquireScanLockAsync(libA, CancellationToken.None);
        var secondAcquired = false;
        var waitingTask = Task.Run(async () =>
        {
            using var second = await tracker.AcquireScanLockAsync(libA, CancellationToken.None);
            secondAcquired = true;
        });

        // Different library acquires immediately without waiting for libA.
        using (await tracker.AcquireScanLockAsync(libB, CancellationToken.None))
        {
            secondAcquired.Should().BeFalse();
        }

        firstLock.Dispose();
        await waitingTask;
        secondAcquired.Should().BeTrue();
    }

    [Fact]
    public async Task SubtitleExtractorService_DecodesWindows1250RomanianDiacriticsAndDiscoversSidecars()
    {
        // Windows-1250 bytes: "două înainte când Şi ţară" -> 0xE3 ('ă'), 0xEE ('î'), 0xE2 ('â'), 0xAA ('Ş'->'Ș'), 0xFE ('ţ'->'ț')
        byte[] win1250Bytes =
        [
            (byte)'1', (byte)'\n',
            (byte)'0', (byte)'0', (byte)':', (byte)'0', (byte)'0', (byte)':', (byte)'0', (byte)'1', (byte)',', (byte)'0', (byte)'0', (byte)'0',
            (byte)' ', (byte)'-', (byte)'-', (byte)'>', (byte)' ',
            (byte)'0', (byte)'0', (byte)':', (byte)'0', (byte)'0', (byte)':', (byte)'0', (byte)'3', (byte)',', (byte)'0', (byte)'0', (byte)'0', (byte)'\n',
            (byte)'d', (byte)'o', (byte)'u', 0xE3, (byte)' ',
            0xEE, (byte)'n', (byte)'a', (byte)'i', (byte)'n', (byte)'t', (byte)'e', (byte)' ',
            (byte)'c', 0xE2, (byte)'n', (byte)'d', (byte)' ',
            0xAA, (byte)'i', (byte)' ',
            0xFE, (byte)'a', (byte)'r', 0xE3, (byte)'\n',
        ];

        var decoded = SubtitleExtractorService.DecodeSubtitleBytes(win1250Bytes);
        decoded.Should().Contain("două înainte când Ș"+"i țară");

        var tempDir = Path.Combine(Path.GetTempPath(), $"hermes-sub-1250-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        try
        {
            var moviePath = Path.Combine(tempDir, "Primal.Fear.1996.2160p.mkv");
            var srtPath = Path.Combine(tempDir, "Primal.Fear.1996.2160p.srt");
            await File.WriteAllBytesAsync(moviePath, [0x01, 0x02]);
            await File.WriteAllBytesAsync(srtPath, win1250Bytes);

            var discovered = SubtitleExtractorService.DiscoverSidecarSubtitles(moviePath);
            discovered.Should().ContainSingle(s =>
                s.StreamIndex == SubtitleExtractorService.SidecarStreamIndexOffset &&
                s.Language == "rum" &&
                s.Codec == "srt");

            var extractor = new SubtitleExtractorService();
            var vtt = await extractor.ExtractWebVttAsync(
                moviePath,
                SubtitleExtractorService.SidecarStreamIndexOffset,
                CancellationToken.None);
            vtt.Should().NotBeNull();
            vtt!.Should().StartWith("WEBVTT");
            vtt.Should().Contain("două înainte când Ș"+"i țară");
        }
        finally
        {
            if (Directory.Exists(tempDir))
            {
                Directory.Delete(tempDir, recursive: true);
            }
        }
    }

    [Fact]
    public async Task SubtitleExtractorService_OutOfRangeSidecarIndexReturnsNull_AndDoesNotMatchSequelSubtitles()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"hermes-sub-bounds-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        try
        {
            var moviePath = Path.Combine(tempDir, "The.Matrix.mkv");
            var ownSrtPath = Path.Combine(tempDir, "The.Matrix.en.srt");
            var sequelSrtPath = Path.Combine(tempDir, "The.Matrix.Reloaded.en.srt");

            await File.WriteAllBytesAsync(moviePath, [0x01, 0x02]);
            await File.WriteAllTextAsync(ownSrtPath, "1\n00:00:01,000 --> 00:00:02,000\nWake up.\n");
            await File.WriteAllTextAsync(sequelSrtPath, "1\n00:00:01,000 --> 00:00:02,000\nReloaded.\n");

            var discovered = SubtitleExtractorService.DiscoverSidecarSubtitles(moviePath);
            discovered.Should().ContainSingle(s => s.FilePath == ownSrtPath && s.Language == "eng");

            var extractor = new SubtitleExtractorService();
            var outOfRange = await extractor.ExtractWebVttAsync(
                moviePath,
                SubtitleExtractorService.SidecarStreamIndexOffset + 5,
                CancellationToken.None);
            outOfRange.Should().BeNull();
        }
        finally
        {
            if (Directory.Exists(tempDir))
            {
                Directory.Delete(tempDir, recursive: true);
            }
        }
    }

    [Fact]
    public async Task SkiaArtworkStore_ConcurrentWrites_ProduceValidWebpWithoutIOException()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"hermes-art-race-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        try
        {
            var store = new SkiaArtworkStore(tempDir);
            var pngBytes = Convert.FromBase64String("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==");

            var tasks = Enumerable.Range(0, 8)
                .Select(_ => Task.Run(() => store.SaveArtworkVariantsAsync(pngBytes, CancellationToken.None)));
            var hashes = await Task.WhenAll(tasks);

            hashes.Should().AllSatisfy(h => h.Should().NotBeNullOrWhiteSpace());
            hashes.Distinct().Should().ContainSingle();

            var variantPath = store.ResolveVariantFilePath(hashes[0]!, "poster_800.webp");
            variantPath.Should().NotBeNull();
            new FileInfo(variantPath!).Length.Should().BeGreaterThan(0);
        }
        finally
        {
            if (Directory.Exists(tempDir))
            {
                Directory.Delete(tempDir, recursive: true);
            }
        }
    }

    private static HttpResponseMessage JsonOk(string json) =>
        new(HttpStatusCode.OK)
        {
            Content = new StringContent(json, Encoding.UTF8, "application/json")
        };

    private sealed class StubHttpMessageHandler(Func<HttpRequestMessage, HttpResponseMessage> handler) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
            Task.FromResult(handler(request));
    }
}
