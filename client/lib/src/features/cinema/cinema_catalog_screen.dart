import 'package:material_ui/material_ui.dart';
import '../../core/theme/hermes_theme_tokens.dart';
import '../../core/widgets/hermes_artwork_image.dart';
import 'cinema_models.dart';
import 'cinema_service.dart';
import 'hermes_video_player.dart';
import 'source_selector_card.dart';

enum _CinemaFilter {
  all('All'),
  movies('Movies'),
  series('TV Series');

  const _CinemaFilter(this.label);
  final String label;
}

class _ContinueWatchingItem {
  const _ContinueWatchingItem({
    required this.title,
    required this.subtitle,
    required this.artworkUri,
    required this.progress,
    required this.sources,
    this.movieId,
    this.episodeId,
  });

  final String title;
  final String subtitle;
  final Uri? artworkUri;
  final WatchProgressModel progress;
  final List<MediaSourceModel> sources;
  final String? movieId;
  final String? episodeId;
}

class CinemaCatalogScreen extends StatefulWidget {
  const CinemaCatalogScreen({
    super.key,
    required this.cinemaService,
    required this.playerConfig,
    required this.defaultQuality,
  });

  final CinemaService cinemaService;
  final HermesVideoPlayerConfig playerConfig;
  final VideoQualityPreset defaultQuality;

  @override
  State<CinemaCatalogScreen> createState() => _CinemaCatalogScreenState();
}

class _CinemaCatalogScreenState extends State<CinemaCatalogScreen> {
  late Future<(List<MovieSummary>, List<TvSeriesSummary>)> _catalogFuture;
  _CinemaFilter _filter = _CinemaFilter.all;

  @override
  void initState() {
    super.initState();
    _catalogFuture = _load();
  }

  Future<(List<MovieSummary>, List<TvSeriesSummary>)> _load() async {
    final results = await Future.wait([
      widget.cinemaService.listMovies(),
      widget.cinemaService.listSeries(),
    ]);
    return (
      results[0] as List<MovieSummary>,
      results[1] as List<TvSeriesSummary>,
    );
  }

  void _refreshCatalog() {
    setState(() {
      _catalogFuture = _load();
    });
  }

  void _launchPlayer({
    required String title,
    required MediaSourceModel source,
    VideoQualityPreset? quality,
    String? movieId,
    String? episodeId,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HermesVideoPlayerScreen(
          title: title,
          source: source,
          initialQuality: quality ?? widget.defaultQuality,
          config: widget.playerConfig,
          cinemaService: widget.cinemaService,
          movieId: movieId,
          episodeId: episodeId,
        ),
      ),
    );
  }

  void _openSourceSheet({
    required String title,
    required List<MediaSourceModel> sources,
    String? movieId,
    String? episodeId,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: SourceSelectorCard(
          sources: sources,
          initialQuality: widget.defaultQuality,
          onPlaySource: (source, quality) {
            Navigator.of(ctx).pop();
            _launchPlayer(
              title: title,
              source: source,
              quality: quality,
              movieId: movieId,
              episodeId: episodeId,
            );
          },
        ),
      ),
    );
  }

  String _qualityBadgeFor(List<MediaSourceModel> sources) {
    if (sources.isEmpty) {
      return 'Offline';
    }
    final best = sources.reduce((a, b) => a.height >= b.height ? a : b);
    if (best.height >= 2160) {
      return best.isHdr ? '4K HDR' : '4K';
    }
    if (best.height >= 1080) {
      return '1080p';
    }
    if (best.height > 0) {
      return '${best.height}p';
    }
    return best.videoCodec.toUpperCase();
  }

  List<_ContinueWatchingItem> _buildContinueWatching(
    List<MovieSummary> movies,
    List<TvSeriesSummary> series,
  ) {
    final items = <_ContinueWatchingItem>[];

    for (final movie in movies) {
      final wp = movie.watchProgress;
      if (wp != null && !wp.isWatched && wp.positionMs > 0 && movie.sources.isNotEmpty) {
        items.add(
          _ContinueWatchingItem(
            title: movie.title,
            subtitle: movie.year == null ? 'Movie' : '${movie.year} • Movie',
            artworkUri: widget.cinemaService.buildArtworkUri(
              movie.backdropHash ?? movie.artworkHash,
              variant: movie.backdropHash != null ? 'backdrop_1280' : 'poster_800',
            ),
            progress: wp,
            sources: movie.sources,
            movieId: movie.id,
          ),
        );
      }
    }

    for (final show in series) {
      for (final season in show.seasons) {
        for (final ep in season.episodes) {
          final wp = ep.watchProgress;
          if (wp != null && !wp.isWatched && wp.positionMs > 0 && ep.sources.isNotEmpty) {
            items.add(
              _ContinueWatchingItem(
                title: show.title,
                subtitle: 'S${season.seasonNumber}E${ep.episodeNumber} • ${ep.title}',
                artworkUri: widget.cinemaService.buildArtworkUri(
                  ep.stillArtworkHash ?? show.backdropHash ?? show.artworkHash,
                  variant: show.backdropHash != null ? 'backdrop_1280' : 'poster_800',
                ),
                progress: wp,
                sources: ep.sources,
                episodeId: ep.id,
              ),
            );
          }
        }
      }
    }

    items.sort((a, b) => b.progress.updatedAtUtc.compareTo(a.progress.updatedAtUtc));
    return items;
  }

  void _openMovieDetail(MovieSummary movie) {
    final tokens = HermesThemeTokens.of(context);
    final badge = _qualityBadgeFor(movie.sources);
    final posterUri = widget.cinemaService.buildArtworkUri(movie.artworkHash, variant: 'poster_800');
    final backdropUri = widget.cinemaService.buildArtworkUri(
      movie.backdropHash ?? movie.artworkHash,
      variant: movie.backdropHash != null ? 'backdrop_1280' : 'poster_800',
    );

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: tokens.bgElevated,
      constraints: BoxConstraints(
        maxWidth: 780,
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                HermesArtworkImage(
                  uri: backdropUri,
                  fallbackTitle: movie.title,
                  fallbackIcon: Icons.movie_outlined,
                  width: double.infinity,
                  height: 240,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                  showFallbackLabel: false,
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.12),
                          tokens.bgElevated,
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  top: 12,
                  child: IconButton.filledTonal(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ),
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 16,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      HermesArtworkImage(
                        uri: posterUri,
                        fallbackTitle: movie.title,
                        fallbackIcon: Icons.movie_outlined,
                        width: 96,
                        height: 142,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              movie.title,
                              style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                if (movie.year != null) _MetaPill(label: '${movie.year}'),
                                _MetaPill(label: badge, accent: true),
                                if (movie.sources.isNotEmpty)
                                  _MetaPill(
                                    label: formatDurationMs(movie.sources.first.durationMs),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: movie.sources.isEmpty
                            ? null
                            : () {
                                Navigator.of(ctx).pop();
                                _launchPlayer(
                                  title: movie.title,
                                  source: movie.sources.first,
                                  movieId: movie.id,
                                );
                              },
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(
                          movie.watchProgress != null && !movie.watchProgress!.isWatched
                              ? 'Resume Movie'
                              : 'Play Movie',
                        ),
                      ),
                      if (movie.sources.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            _openSourceSheet(
                              title: movie.title,
                              sources: movie.sources,
                              movieId: movie.id,
                            );
                          },
                          icon: const Icon(Icons.tune),
                          label: Text(
                            movie.sources.length == 1
                                ? 'Version & Quality'
                                : 'Versions (${movie.sources.length})',
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (movie.overview != null && movie.overview!.trim().isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(
                      movie.overview!,
                      style: TextStyle(
                        color: tokens.textSecondary,
                        height: 1.5,
                        fontSize: 14,
                      ),
                    ),
                  ],
                  if (movie.sources.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      'Available Streams',
                      style: Theme.of(ctx).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    ...movie.sources.map(
                      (src) => Card(
                        color: tokens.bgPrimary,
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(Icons.high_quality_outlined, color: tokens.accentPrimary),
                          title: Text(src.sourceLabel),
                          subtitle: Text(
                            '${src.videoCodec.toUpperCase()} • ${src.audioCodec.toUpperCase()} • ${src.audioStreams.length} audio, ${src.subtitleStreams.length} subtitles',
                          ),
                          trailing: FilledButton.tonal(
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              _launchPlayer(
                                title: movie.title,
                                source: src,
                                movieId: movie.id,
                              );
                            },
                            child: const Text('Play'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openSeriesDetail(TvSeriesSummary show) {
    final tokens = HermesThemeTokens.of(context);
    var selectedSeasonIndex = 0;
    final backdropUri = widget.cinemaService.buildArtworkUri(
      show.backdropHash ?? show.artworkHash,
      variant: show.backdropHash != null ? 'backdrop_1280' : 'poster_800',
    );
    final posterUri = widget.cinemaService.buildArtworkUri(show.artworkHash, variant: 'poster_800');

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: tokens.bgElevated,
      constraints: BoxConstraints(
        maxWidth: 820,
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final activeSeason = show.seasons.isEmpty
              ? null
              : show.seasons[selectedSeasonIndex.clamp(0, show.seasons.length - 1)];

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    HermesArtworkImage(
                      uri: backdropUri,
                      fallbackTitle: show.title,
                      fallbackIcon: Icons.tv_outlined,
                      width: double.infinity,
                      height: 220,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                      showFallbackLabel: false,
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.14),
                              tokens.bgElevated,
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 12,
                      top: 12,
                      child: IconButton.filledTonal(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ),
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: 14,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          HermesArtworkImage(
                            uri: posterUri,
                            fallbackTitle: show.title,
                            fallbackIcon: Icons.tv_outlined,
                            width: 88,
                            height: 132,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  show.title,
                                  style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    if (show.year != null) _MetaPill(label: '${show.year}'),
                                    _MetaPill(
                                      label: '${show.seasons.length} Season(s)',
                                      accent: true,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (show.overview != null && show.overview!.trim().isNotEmpty) ...[
                        Text(
                          show.overview!,
                          style: TextStyle(color: tokens.textSecondary, height: 1.5, fontSize: 14),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (show.seasons.isNotEmpty) ...[
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: show.seasons.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final season = entry.value;
                            return ChoiceChip(
                              label: Text('Season ${season.seasonNumber}'),
                              selected: selectedSeasonIndex == idx,
                              onSelected: (_) => setModalState(() => selectedSeasonIndex = idx),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 14),
                      ],
                      if (activeSeason != null)
                        ...activeSeason.episodes.map((ep) {
                          final firstSource = ep.sources.firstOrNull;
                          final wp = ep.watchProgress;
                          return Card(
                            color: tokens.bgPrimary,
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              leading: CircleAvatar(
                                backgroundColor: tokens.accentPrimary.withValues(alpha: 0.16),
                                child: Text(
                                  'E${ep.episodeNumber}',
                                  style: TextStyle(
                                    color: tokens.accentPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              title: Text(
                                ep.title,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 2),
                                  Text(
                                    firstSource == null
                                        ? 'No streams indexed'
                                        : '${firstSource.sourceLabel} • ${formatDurationMs(firstSource.durationMs)}',
                                    style: TextStyle(color: tokens.textSecondary, fontSize: 12),
                                  ),
                                  if (wp != null && wp.positionMs > 0) ...[
                                    const SizedBox(height: 6),
                                    LinearProgressIndicator(value: wp.completionRatio),
                                  ],
                                ],
                              ),
                              trailing: Wrap(
                                spacing: 6,
                                children: [
                                  if (ep.sources.isNotEmpty)
                                    IconButton(
                                      tooltip: 'Version & Quality',
                                      icon: const Icon(Icons.tune),
                                      onPressed: () {
                                        Navigator.of(ctx).pop();
                                        _openSourceSheet(
                                          title:
                                              '${show.title} • S${activeSeason.seasonNumber}E${ep.episodeNumber}',
                                          sources: ep.sources,
                                          episodeId: ep.id,
                                        );
                                      },
                                    ),
                                  FilledButton.tonalIcon(
                                    onPressed: firstSource == null
                                        ? null
                                        : () {
                                            Navigator.of(ctx).pop();
                                            _launchPlayer(
                                              title:
                                                  '${show.title} • S${activeSeason.seasonNumber}E${ep.episodeNumber}',
                                              source: firstSource,
                                              episodeId: ep.id,
                                            );
                                          },
                                    icon: const Icon(Icons.play_arrow_rounded),
                                    label: const Text('Play'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeroBanner(
    BuildContext context,
    HermesThemeTokens tokens,
    MovieSummary? heroMovie,
    TvSeriesSummary? heroSeries,
  ) {
    final title = heroMovie?.title ?? heroSeries?.title ?? '';
    final year = heroMovie?.year ?? heroSeries?.year;
    final overview = heroMovie?.overview ?? heroSeries?.overview;
    final artworkHash = heroMovie != null
        ? (heroMovie.backdropHash ?? heroMovie.artworkHash)
        : (heroSeries?.backdropHash ?? heroSeries?.artworkHash);
    final isBackdrop = heroMovie != null
        ? heroMovie.backdropHash != null
        : heroSeries?.backdropHash != null;
    final heroUri = widget.cinemaService.buildArtworkUri(
      artworkHash,
      variant: isBackdrop ? 'backdrop_1280' : 'poster_800',
    );
    final badge = heroMovie != null
        ? _qualityBadgeFor(heroMovie.sources)
        : '${heroSeries?.seasons.length ?? 0} Season(s)';

    final firstSource = heroMovie != null
        ? heroMovie.sources.firstOrNull
        : heroSeries?.seasons.firstOrNull?.episodes.firstOrNull?.sources.firstOrNull;
    final firstEpisode = heroSeries?.seasons.firstOrNull?.episodes.firstOrNull;

    return Container(
      height: 300,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          HermesArtworkImage(
            uri: heroUri,
            fallbackTitle: title,
            fallbackIcon: heroMovie != null ? Icons.movie_outlined : Icons.tv_outlined,
            borderRadius: BorderRadius.circular(20),
            showFallbackLabel: false,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.centerRight,
                end: Alignment.centerLeft,
                colors: [
                  Colors.black.withValues(alpha: 0.15),
                  tokens.bgPrimary.withValues(alpha: 0.78),
                  tokens.bgPrimary.withValues(alpha: 0.96),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _MetaPill(label: heroMovie != null ? 'FEATURED MOVIE' : 'FEATURED SERIES', accent: true),
                    if (year != null) _MetaPill(label: '$year'),
                    _MetaPill(label: badge),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                if (overview != null && overview.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Text(
                      overview,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: tokens.textSecondary, height: 1.4),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: firstSource == null
                          ? null
                          : () {
                              if (heroMovie != null) {
                                _launchPlayer(
                                  title: heroMovie.title,
                                  source: firstSource,
                                  movieId: heroMovie.id,
                                );
                              } else if (heroSeries != null && firstEpisode != null) {
                                _launchPlayer(
                                  title: '${heroSeries.title} • S1E${firstEpisode.episodeNumber}',
                                  source: firstSource,
                                  episodeId: firstEpisode.id,
                                );
                              }
                            },
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Watch Now'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        if (heroMovie != null) {
                          _openMovieDetail(heroMovie);
                        } else if (heroSeries != null) {
                          _openSeriesDetail(heroSeries);
                        }
                      },
                      icon: const Icon(Icons.info_outline),
                      label: const Text('Details'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);

    return FutureBuilder<(List<MovieSummary>, List<TvSeriesSummary>)>(
      future: _catalogFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Failed to load Cinema catalog: ${snapshot.error}'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _refreshCatalog,
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        final (movies, series) = snapshot.data ?? (<MovieSummary>[], <TvSeriesSummary>[]);
        if (movies.isEmpty && series.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.movie_filter_outlined, size: 52, color: tokens.textSecondary),
                const SizedBox(height: 12),
                Text(
                  'No movies or series scanned yet. Open Admin Dashboard to scan a library.',
                  style: TextStyle(color: tokens.textSecondary),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _refreshCatalog,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh Catalog'),
                ),
              ],
            ),
          );
        }

        final continueWatching = _buildContinueWatching(movies, series);
        final showMovies = _filter != _CinemaFilter.series && movies.isNotEmpty;
        final showSeries = _filter != _CinemaFilter.movies && series.isNotEmpty;
        final heroMovie = _filter == _CinemaFilter.series ? null : movies.firstOrNull;
        final heroSeries = heroMovie == null ? series.firstOrNull : null;

        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _CinemaFilter.values.map((filter) {
                      return ChoiceChip(
                        label: Text(filter.label),
                        selected: _filter == filter,
                        onSelected: (_) => setState(() => _filter = filter),
                      );
                    }).toList(),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh catalog',
                  icon: const Icon(Icons.refresh),
                  onPressed: _refreshCatalog,
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (heroMovie != null || heroSeries != null) ...[
              _buildHeroBanner(context, tokens, heroMovie, heroSeries),
              const SizedBox(height: 28),
            ],
            if (continueWatching.isNotEmpty && _filter == _CinemaFilter.all) ...[
              Text(
                'Continue Watching',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 174,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: continueWatching.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                  itemBuilder: (_, idx) {
                    final item = continueWatching[idx];
                    return SizedBox(
                      width: 248,
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => _launchPlayer(
                            title: item.title,
                            source: item.sources.first,
                            movieId: item.movieId,
                            episodeId: item.episodeId,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Stack(
                                alignment: Alignment.bottomCenter,
                                children: [
                                  HermesArtworkImage(
                                    uri: item.artworkUri,
                                    fallbackTitle: item.title,
                                    width: 248,
                                    height: 100,
                                    borderRadius: BorderRadius.zero,
                                    showFallbackLabel: false,
                                  ),
                                  LinearProgressIndicator(
                                    value: item.progress.completionRatio,
                                    minHeight: 4,
                                  ),
                                ],
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                    Text(
                                      item.subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: tokens.textSecondary, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 28),
            ],
            if (showMovies) ...[
              Text(
                'Movies (${movies.length})',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 18,
                runSpacing: 22,
                children: movies.map((movie) {
                  final badge = _qualityBadgeFor(movie.sources);
                  final posterUri = widget.cinemaService.buildArtworkUri(
                    movie.artworkHash,
                    variant: 'poster_800',
                  );
                  return _PosterCard(
                    title: movie.title,
                    subtitle: movie.year?.toString() ?? 'Movie',
                    badge: badge,
                    artworkUri: posterUri,
                    fallbackIcon: Icons.movie_outlined,
                    progress: movie.watchProgress?.completionRatio,
                    onTap: () => _openMovieDetail(movie),
                  );
                }).toList(),
              ),
              const SizedBox(height: 28),
            ],
            if (showSeries) ...[
              Text(
                'TV Series (${series.length})',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 18,
                runSpacing: 22,
                children: series.map((show) {
                  final episodeCount = show.seasons.fold<int>(
                    0,
                    (sum, season) => sum + season.episodes.length,
                  );
                  final posterUri = widget.cinemaService.buildArtworkUri(
                    show.artworkHash,
                    variant: 'poster_800',
                  );
                  return _PosterCard(
                    title: show.title,
                    subtitle: show.year != null
                        ? '${show.year} • $episodeCount eps'
                        : '$episodeCount episode(s)',
                    badge: '${show.seasons.length}S',
                    artworkUri: posterUri,
                    fallbackIcon: Icons.tv_outlined,
                    onTap: () => _openSeriesDetail(show),
                  );
                }).toList(),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _PosterCard extends StatelessWidget {
  const _PosterCard({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.artworkUri,
    required this.fallbackIcon,
    this.progress,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String badge;
  final Uri? artworkUri;
  final IconData fallbackIcon;
  final double? progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);

    return SizedBox(
      width: 172,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x1FFFFFFF)),
              ),
              child: Stack(
                children: [
                  HermesArtworkImage(
                    uri: artworkUri,
                    fallbackTitle: title,
                    fallbackIcon: fallbackIcon,
                    width: 172,
                    height: 254,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0x33FFFFFF)),
                      ),
                      child: Text(
                        badge,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  if (progress != null && progress! > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(13)),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 4,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: tokens.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.label,
    this.accent = false,
  });

  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent
            ? tokens.accentPrimary.withValues(alpha: 0.22)
            : Colors.black.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: accent ? tokens.accentPrimary.withValues(alpha: 0.6) : const Color(0x2EFFFFFF),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: accent ? tokens.accentHover : tokens.textPrimary,
        ),
      ),
    );
  }
}
