import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/network/hermes_sync_client.dart';
import '../../core/settings/hermes_preferences.dart';
import '../../core/theme/hermes_theme_tokens.dart';
import '../../core/widgets/hermes_artwork_image.dart';
import '../../core/widgets/hermes_icons.dart';
import '../../core/widgets/hermes_search_pill.dart';
import 'cinema_detail_page.dart';
import 'cinema_models.dart';
import 'cinema_service.dart';
import 'cinema_shared_widgets.dart';
import 'hermes_video_player.dart';

enum _CinemaFilter {
  all('Home'),
  movies('Movies'),
  series('TV Shows'),
  watchlist('Watchlist');

  const _CinemaFilter(this.label);
  final String label;
}

class _ContinueWatchingEntry {
  const _ContinueWatchingEntry({
    required this.title,
    required this.subtitle,
    required this.artworkUri,
    required this.progress,
    required this.isUpNext,
    required this.updatedAtUtc,
    required this.source,
    this.movie,
    this.series,
    this.episodeEntry,
    this.initialPositionMs = 0,
  });

  final String title;
  final String subtitle;
  final Uri? artworkUri;
  final double progress;
  final bool isUpNext;
  final DateTime updatedAtUtc;
  final MediaSourceModel source;
  final MovieSummary? movie;
  final TvSeriesSummary? series;
  final CinemaEpisodeEntry? episodeEntry;
  final int initialPositionMs;
}

class _HeroSelection {
  const _HeroSelection({this.movie, this.series});

  final MovieSummary? movie;
  final TvSeriesSummary? series;

  bool get isEmpty => movie == null && series == null;
  String get title => movie?.title ?? series?.title ?? '';
  int? get year => movie?.year ?? series?.year;
  String? get overview => movie?.overview ?? series?.overview;
  double? get rating => movie?.rating ?? series?.rating;
  List<String> get genres => movie?.genres ?? series?.genres ?? const [];
  bool get isInWatchlist =>
      movie?.isInWatchlist ?? series?.isInWatchlist ?? false;
}

class CinemaCatalogScreen extends StatefulWidget {
  const CinemaCatalogScreen({
    super.key,
    required this.cinemaService,
    required this.playerConfig,
    required this.defaultQuality,
    this.accountPreferences = const HermesAccountPreferences(),
    this.reduceMotion = false,
    this.watchProgressUpdates,
  });

  final CinemaService cinemaService;
  final HermesVideoPlayerConfig playerConfig;
  final VideoQualityPreset defaultQuality;
  final HermesAccountPreferences accountPreferences;
  final bool reduceMotion;
  final Stream<WatchProgressUpdatedEvent>? watchProgressUpdates;

  @override
  State<CinemaCatalogScreen> createState() => _CinemaCatalogScreenState();
}

class _CinemaCatalogScreenState extends State<CinemaCatalogScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  bool _loading = true;
  Object? _loadError;
  List<MovieSummary> _movies = const [];
  List<TvSeriesSummary> _series = const [];

  _CinemaFilter _filter = _CinemaFilter.all;
  String _searchQuery = '';
  String? _selectedMovieId;
  String? _selectedSeriesId;
  StreamSubscription<WatchProgressUpdatedEvent>? _watchProgressSub;

  @override
  void initState() {
    super.initState();
    _subscribeWatchProgress();
    _loadCatalog();
  }

  @override
  void didUpdateWidget(covariant CinemaCatalogScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.watchProgressUpdates != widget.watchProgressUpdates) {
      unawaited(_watchProgressSub?.cancel());
      _subscribeWatchProgress();
    }
  }

  @override
  void dispose() {
    unawaited(_watchProgressSub?.cancel());
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _subscribeWatchProgress() {
    _watchProgressSub = widget.watchProgressUpdates?.listen(
      _applyWatchProgressEvent,
    );
  }

  void _applyWatchProgressEvent(WatchProgressUpdatedEvent event) {
    if (!mounted) return;
    final incoming = WatchProgressModel(
      positionMs: event.positionMs,
      durationMs: event.durationMs,
      isWatched: event.isWatched,
      updatedAtUtc: event.updatedAtUtc,
    );

    if (event.movieId != null) {
      final idx = _movies.indexWhere((m) => m.id == event.movieId);
      if (idx >= 0) {
        final existing = _movies[idx].watchProgress;
        if (existing != null &&
            event.updatedAtUtc.isBefore(existing.updatedAtUtc)) {
          return;
        }
        setState(() {
          _movies = List<MovieSummary>.from(_movies)
            ..[idx] = _movies[idx].copyWith(watchProgress: incoming);
        });
      }
      return;
    }

    if (event.episodeId != null) {
      for (var sIdx = 0; sIdx < _series.length; sIdx++) {
        final show = _series[sIdx];
        for (var snIdx = 0; snIdx < show.seasons.length; snIdx++) {
          final season = show.seasons[snIdx];
          final epIdx = season.episodes.indexWhere(
            (e) => e.id == event.episodeId,
          );
          if (epIdx < 0) continue;

          final existing = season.episodes[epIdx].watchProgress;
          if (existing != null &&
              event.updatedAtUtc.isBefore(existing.updatedAtUtc)) {
            return;
          }

          final updatedEpisodes = List<EpisodeSummary>.from(season.episodes)
            ..[epIdx] = season.episodes[epIdx].copyWith(watchProgress: incoming);
          final updatedSeasons = List<TvSeasonModel>.from(show.seasons)
            ..[snIdx] = season.copyWith(episodes: updatedEpisodes);
          setState(() {
            _series = List<TvSeriesSummary>.from(_series)
              ..[sIdx] = show.copyWith(seasons: updatedSeasons);
          });
          return;
        }
      }
    }
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final results = await Future.wait([
        widget.cinemaService.listMovies(),
        widget.cinemaService.listSeries(),
      ]);
      if (!mounted) return;
      setState(() {
        _movies = results[0] as List<MovieSummary>;
        _series = results[1] as List<TvSeriesSummary>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  Future<void> _toggleMovieWatchlist(MovieSummary movie) async {
    final targetState = !movie.isInWatchlist;
    setState(() {
      _movies = _movies
          .map((m) =>
              m.id == movie.id ? m.copyWith(isInWatchlist: targetState) : m)
          .toList(growable: false);
    });
    _showToast(
      targetState ? 'Added to Watchlist' : 'Removed from Watchlist',
    );
    try {
      await widget.cinemaService.setWatchlist(
        movieId: movie.id,
        inWatchlist: targetState,
      );
    } catch (_) {
      // Keep responsive state; next refresh reconciles with backend.
    }
  }

  Future<void> _toggleSeriesWatchlist(TvSeriesSummary show) async {
    final targetState = !show.isInWatchlist;
    setState(() {
      _series = _series
          .map((s) =>
              s.id == show.id ? s.copyWith(isInWatchlist: targetState) : s)
          .toList(growable: false);
    });
    _showToast(
      targetState ? 'Added to Watchlist' : 'Removed from Watchlist',
    );
    try {
      await widget.cinemaService.setWatchlist(
        tvSeriesId: show.id,
        inWatchlist: targetState,
      );
    } catch (_) {
      // Keep responsive state; next refresh reconciles with backend.
    }
  }

  Future<void> _toggleMovieWatched(MovieSummary movie) async {
    final targetWatched = !movie.isWatched;
    final durationMs = movie.sources.firstOrNull?.durationMs ?? 0;
    final updatedProgress = WatchProgressModel(
      positionMs: targetWatched ? durationMs : 0,
      durationMs: durationMs,
      isWatched: targetWatched,
      updatedAtUtc: DateTime.now().toUtc(),
    );

    setState(() {
      _movies = _movies
          .map((m) => m.id == movie.id
              ? m.copyWith(watchProgress: updatedProgress)
              : m)
          .toList(growable: false);
    });
    _showToast(targetWatched ? 'Marked as watched' : 'Marked as unwatched');

    try {
      await widget.cinemaService.updateWatchProgress(
        movieId: movie.id,
        positionMs: targetWatched ? durationMs : 0,
        durationMs: durationMs,
        markWatched: targetWatched,
      );
    } catch (_) {}
  }

  Future<void> _toggleSeriesWatched(TvSeriesSummary show) async {
    final targetWatched = !show.isWatched;
    final now = DateTime.now().toUtc();

    setState(() {
      _series = _series.map((s) {
        if (s.id != show.id) return s;
        return s.copyWith(
          seasons: s.seasons.map((sn) {
            return sn.copyWith(
              episodes: sn.episodes.map((ep) {
                final dur = ep.sources.firstOrNull?.durationMs ?? 0;
                return ep.copyWith(
                  watchProgress: WatchProgressModel(
                    positionMs: targetWatched ? dur : 0,
                    durationMs: dur,
                    isWatched: targetWatched,
                    updatedAtUtc: now,
                  ),
                );
              }).toList(growable: false),
            );
          }).toList(growable: false),
        );
      }).toList(growable: false);
    });
    _showToast(targetWatched ? 'Marked as watched' : 'Marked as unwatched');

    try {
      await widget.cinemaService.setSeriesWatched(
        seriesId: show.id,
        watched: targetWatched,
      );
    } catch (_) {}
  }

  void _showToast(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _launchPlayback(
    MediaSourceModel source,
    VideoQualityPreset quality, {
    MovieSummary? movie,
    TvSeriesSummary? series,
    CinemaEpisodeEntry? episodeEntry,
    int initialPositionMs = 0,
    bool replaceRoute = false,
  }) {
    final title = movie?.title ?? series?.title ?? 'Playback';
    final ep = episodeEntry;
    final subtitleLabel = ep != null
        ? '${ep.code} · ${ep.episode.title}'
        : movie?.year?.toString();

    final backdropHash = ep?.episode.stillArtworkHash ??
        series?.backdropHash ??
        movie?.backdropHash ??
        series?.artworkHash ??
        movie?.artworkHash;
    final backdropUri = widget.cinemaService.buildArtworkUri(
      backdropHash,
      variant: (ep?.episode.stillArtworkHash != null ||
              series?.backdropHash != null ||
              movie?.backdropHash != null)
          ? 'backdrop_1280'
          : 'poster_800',
    );

    final nextEntry = (series != null && ep != null)
        ? series.nextEpisodeAfter(ep.seasonNumber, ep.episode.episodeNumber)
        : null;
    final nextSource = nextEntry?.episode.sources.firstOrNull;
    final nextStillUri = nextEntry == null
        ? null
        : widget.cinemaService.buildArtworkUri(
            nextEntry.episode.stillArtworkHash ??
                series?.backdropHash ??
                series?.artworkHash,
            variant: 'backdrop_1280',
          );

    final route = MaterialPageRoute<void>(
      builder: (_) => HermesVideoPlayerScreen(
        title: title,
        subtitleLabel: subtitleLabel,
        source: source,
        initialQuality: quality,
        config: widget.playerConfig,
        cinemaService: widget.cinemaService,
        movieId: movie?.id,
        episodeId: ep?.episode.id,
        backdropUri: backdropUri,
        titleTint: deriveTitleTint(title),
        initialPositionMs: initialPositionMs,
        accountPreferences: widget.accountPreferences,
        reduceMotion: widget.reduceMotion,
        nextEpisodeCode: nextEntry?.code,
        nextEpisodeTitle: nextEntry?.episode.title,
        nextEpisodeStillUri: nextStillUri,
        onPlayNextEpisode: (nextEntry != null && nextSource != null)
            ? () => _launchPlayback(
                  nextSource,
                  quality,
                  series: series,
                  episodeEntry: nextEntry,
                  initialPositionMs: 0,
                  replaceRoute: true,
                )
            : null,
      ),
    );

    final nav = Navigator.of(context);
    if (replaceRoute) {
      nav.pushReplacement(route).then((_) {
        if (mounted) _loadCatalog();
      });
    } else {
      nav.push(route).then((_) {
        if (mounted) _loadCatalog();
      });
    }
  }

  List<_ContinueWatchingEntry> _buildContinueWatching(
    List<MovieSummary> movies,
    List<TvSeriesSummary> series,
  ) {
    final list = <_ContinueWatchingEntry>[];

    for (final m in movies) {
      final wp = m.watchProgress;
      if (wp != null &&
          !wp.isWatched &&
          wp.positionMs > 0 &&
          m.sources.isNotEmpty) {
        list.add(
          _ContinueWatchingEntry(
            title: m.title,
            subtitle: '${formatCinemaMinutes(m.resumePoint.remainingMinutes)} left',
            artworkUri: widget.cinemaService.buildArtworkUri(
              m.backdropHash ?? m.artworkHash,
              variant: m.backdropHash != null ? 'backdrop_1280' : 'poster_800',
            ),
            progress: wp.completionRatio,
            isUpNext: false,
            updatedAtUtc: wp.updatedAtUtc,
            source: m.sources.first,
            movie: m,
            initialPositionMs: wp.positionMs,
          ),
        );
      }
    }

    for (final s in series) {
      if (s.isWatched) continue;
      final r = s.resumePoint;
      if (r == null ||
          (r.mode != CinemaResumeMode.resume &&
              r.mode != CinemaResumeMode.next)) {
        continue;
      }
      final entry = r.episodeEntry;
      final source = entry?.episode.sources.firstOrNull;
      if (entry == null || source == null) continue;

      final isNext = r.mode == CinemaResumeMode.next;
      final sub = isNext
          ? 'Next · ${entry.code} ${entry.episode.title}'
          : '${entry.code} · ${formatCinemaMinutes(r.remainingMinutes)} left';

      DateTime sortTimestamp = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      for (final e in s.allEpisodes) {
        final ts = e.episode.watchProgress?.updatedAtUtc;
        if (ts != null && ts.isAfter(sortTimestamp)) {
          sortTimestamp = ts;
        }
      }

      list.add(
        _ContinueWatchingEntry(
          title: s.title,
          subtitle: sub,
          artworkUri: widget.cinemaService.buildArtworkUri(
            entry.episode.stillArtworkHash ?? s.backdropHash ?? s.artworkHash,
            variant: (entry.episode.stillArtworkHash != null ||
                    s.backdropHash != null)
                ? 'backdrop_1280'
                : 'poster_800',
          ),
          progress: r.progress,
          isUpNext: isNext,
          updatedAtUtc: sortTimestamp,
          source: source,
          series: s,
          episodeEntry: entry,
          initialPositionMs: entry.episode.watchProgress?.positionMs ?? 0,
        ),
      );
    }

    list.sort((a, b) => b.updatedAtUtc.compareTo(a.updatedAtUtc));
    return list;
  }

  _HeroSelection _selectHero(
    List<MovieSummary> filteredMovies,
    List<TvSeriesSummary> filteredSeries,
    List<_ContinueWatchingEntry> continueWatching,
  ) {
    final firstResume = continueWatching.firstOrNull;
    if (firstResume != null) {
      if (firstResume.movie != null &&
          filteredMovies.any((m) => m.id == firstResume.movie!.id)) {
        return _HeroSelection(movie: firstResume.movie);
      }
      if (firstResume.series != null &&
          filteredSeries.any((s) => s.id == firstResume.series!.id)) {
        return _HeroSelection(series: firstResume.series);
      }
    }

    if (filteredMovies.isNotEmpty) {
      return _HeroSelection(movie: filteredMovies.first);
    }
    if (filteredSeries.isNotEmpty) {
      return _HeroSelection(series: filteredSeries.first);
    }
    return const _HeroSelection();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);

    // Inline Nuvio Dedicated Detail Page
    if (_selectedMovieId != null) {
      final movie =
          _movies.where((m) => m.id == _selectedMovieId).firstOrNull;
      if (movie != null) {
        return CinemaDetailPage(
          movie: movie,
          cinemaService: widget.cinemaService,
          defaultQuality: widget.defaultQuality,
          accountPreferences: widget.accountPreferences,
          reduceMotion: widget.reduceMotion,
          allMovies: _movies,
          allSeries: _series,
          onBack: () => setState(() => _selectedMovieId = null),
          onPlay: _launchPlayback,
          onToggleWatchlist: () => _toggleMovieWatchlist(movie),
          onToggleWatched: () => _toggleMovieWatched(movie),
          onOpenRelatedMovie: (rel) => setState(() {
            _selectedMovieId = rel.id;
            _selectedSeriesId = null;
          }),
          onOpenRelatedSeries: (rel) => setState(() {
            _selectedSeriesId = rel.id;
            _selectedMovieId = null;
          }),
        );
      }
    }

    if (_selectedSeriesId != null) {
      final show =
          _series.where((s) => s.id == _selectedSeriesId).firstOrNull;
      if (show != null) {
        return CinemaDetailPage(
          series: show,
          cinemaService: widget.cinemaService,
          defaultQuality: widget.defaultQuality,
          accountPreferences: widget.accountPreferences,
          reduceMotion: widget.reduceMotion,
          allMovies: _movies,
          allSeries: _series,
          onBack: () => setState(() => _selectedSeriesId = null),
          onPlay: _launchPlayback,
          onToggleWatchlist: () => _toggleSeriesWatchlist(show),
          onToggleWatched: () => _toggleSeriesWatched(show),
          onOpenRelatedMovie: (rel) => setState(() {
            _selectedMovieId = rel.id;
            _selectedSeriesId = null;
          }),
          onOpenRelatedSeries: (rel) => setState(() {
            _selectedSeriesId = rel.id;
            _selectedMovieId = null;
          }),
        );
      }
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Failed to load Cinema catalog: $_loadError',
                textAlign: TextAlign.center,
                style: TextStyle(color: tokens.text2),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: _loadCatalog,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_movies.isEmpty && _series.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.movie_filter_outlined, size: 52, color: tokens.text3),
              const SizedBox(height: 12),
              Text(
                'No movies or series scanned yet. Open Server to scan a library.',
                textAlign: TextAlign.center,
                style: TextStyle(color: tokens.text2),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _loadCatalog,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Refresh catalog'),
              ),
            ],
          ),
        ),
      );
    }

    final query = _searchQuery.trim().toLowerCase();
    final isWatchlistTab = _filter == _CinemaFilter.watchlist;
    final showHero = query.isEmpty && !isWatchlistTab;

    final poolMovies = _filter == _CinemaFilter.series
        ? const <MovieSummary>[]
        : _movies;
    final poolSeries = _filter == _CinemaFilter.movies
        ? const <TvSeriesSummary>[]
        : _series;

    final continueWatching = _buildContinueWatching(poolMovies, poolSeries);
    final hero = _selectHero(poolMovies, poolSeries, continueWatching);

    final heroTokens = (!hero.isEmpty)
        ? tokens.withTitleTint(
            deriveTitleTint(hero.title),
            overrideAccent: widget.accountPreferences.matchTitleColors,
          )
        : tokens;

    return Theme(
      data: heroTokens.toThemeData(),
      child: Material(
        color: heroTokens.bg,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 760;
            final horizontalPad = isDesktop ? 48.0 : 20.0;

            return ListView(
              padding: const EdgeInsets.only(bottom: 56),
              children: [
                _buildPersistentHeader(
                  context,
                  heroTokens,
                  hero,
                  showHero: showHero && !hero.isEmpty,
                  isDesktop: isDesktop,
                  horizontalPad: horizontalPad,
                ),
                if (isWatchlistTab)
                  _buildWatchlistView(
                    context,
                    heroTokens,
                    query,
                    horizontalPad,
                  )
                else if (query.isNotEmpty)
                  _buildSearchResults(
                    context,
                    heroTokens,
                    poolMovies,
                    poolSeries,
                    query,
                    horizontalPad,
                  )
                else
                  _buildHomeRows(
                    context,
                    heroTokens,
                    poolMovies,
                    poolSeries,
                    continueWatching,
                    horizontalPad,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTopbar(
    HermesThemeTokens tokens,
    bool isDesktop, {
    required bool darkGlass,
  }) {
    final activeTextColor = darkGlass ? Colors.white : tokens.text;
    final inactiveTextColor = darkGlass
        ? Colors.white.withValues(alpha: 0.62)
        : tokens.text2;
    final refreshIconColor = darkGlass
        ? Colors.white.withValues(alpha: 0.72)
        : tokens.text2;

    final tabs = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: _CinemaFilter.values.map((tab) {
          final active = _filter == tab;
          return Padding(
            padding: const EdgeInsets.only(right: 24),
            child: InkWell(
              key: Key('cinema-tab-${tab.name}'),
              borderRadius: BorderRadius.circular(4),
              onTap: () => setState(() => _filter = tab),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  tab.label,
                  style: TextStyle(
                    fontFamily: 'Figtree',
                    fontSize: 15,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    color: active ? activeTextColor : inactiveTextColor,
                  ),
                ),
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );

    final searchBox = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: isDesktop ? 320 : double.infinity,
      ),
      child: HermesSearchPill(
        inputKey: const Key('cinema-search-input'),
        clearKey: const Key('cinema-search-clear'),
        controller: _searchController,
        focusNode: _searchFocusNode,
        hintText: 'Search titles, genres, cast...',
        darkGlass: darkGlass,
        height: 40,
        iconSize: 16,
        hasQuery: _searchQuery.isNotEmpty,
        onChanged: (value) => setState(() => _searchQuery = value),
        onClear: () {
          _searchController.clear();
          setState(() => _searchQuery = '');
        },
      ),
    );

    if (isDesktop) {
      return Row(
        children: [
          Expanded(child: tabs),
          const SizedBox(width: 16),
          searchBox,
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Refresh catalog',
            onPressed: _loadCatalog,
            icon: Icon(
              Icons.refresh_rounded,
              size: 20,
              color: refreshIconColor,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: tabs),
            IconButton(
              tooltip: 'Refresh catalog',
              onPressed: _loadCatalog,
              icon: Icon(
                Icons.refresh_rounded,
                size: 20,
                color: refreshIconColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        searchBox,
      ],
    );
  }

  Widget _buildPersistentHeader(
    BuildContext context,
    HermesThemeTokens tokens,
    _HeroSelection hero, {
    required bool showHero,
    required bool isDesktop,
    required double horizontalPad,
  }) {
    final movie = hero.movie;
    final show = hero.series;
    final resume = showHero ? (movie != null ? movie.resumePoint : show!.resumePoint) : null;

    final backdropHash = showHero
        ? (movie != null
            ? (movie.backdropHash ?? movie.artworkHash)
            : (show?.backdropHash ?? show?.artworkHash))
        : null;
    final isBackdrop = showHero &&
        (movie != null ? movie.backdropHash != null : show?.backdropHash != null);
    final heroUri = showHero
        ? widget.cinemaService.buildArtworkUri(
            backdropHash,
            variant: isBackdrop ? 'backdrop_1280' : 'poster_800',
          )
        : null;

    final primarySource = showHero
        ? (movie != null
            ? movie.sources.firstOrNull
            : resume?.episodeEntry?.episode.sources.firstOrNull ??
                show?.seasons.firstOrNull?.episodes.firstOrNull?.sources.firstOrNull)
        : null;
    final playInitialPos = !showHero
        ? 0
        : movie != null
            ? (movie.isWatched ? 0 : (movie.watchProgress?.positionMs ?? 0))
            : (resume?.episodeEntry?.episode.watchProgress?.isWatched == true
                ? 0
                : (resume?.episodeEntry?.episode.watchProgress?.positionMs ?? 0));

    final lengthLabel = !showHero
        ? ''
        : movie != null
            ? (movie.durationMinutes > 0
                ? formatCinemaMinutes(movie.durationMinutes)
                : '')
            : '${show!.seasons.length} ${show.seasons.length == 1 ? 'Season' : 'Seasons'}';

    final heroMinHeight = showHero ? (isDesktop ? 500.0 : 420.0) : 0.0;

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: heroMinHeight),
      child: Stack(
        children: [
          Positioned.fill(
            child: showHero
                ? HermesArtworkImage(
                    uri: heroUri,
                    fallbackTitle: hero.title,
                    fallbackIcon:
                        movie != null ? Icons.movie_outlined : Icons.tv_outlined,
                    borderRadius: BorderRadius.zero,
                    showFallbackLabel: false,
                  )
                : const SizedBox.shrink(),
          ),
          Positioned.fill(
            child: showHero
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        stops: const [0.0, 0.34, 0.70],
                        colors: [
                          tokens.pageWash,
                          tokens.pageWash.withValues(alpha: 0.78),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          Positioned.fill(
            child: showHero
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        stops: const [0.0, 0.42, 0.80, 1.0],
                        colors: [
                          tokens.bg,
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.45),
                        ],
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPad,
              22,
              horizontalPad,
              showHero ? 44 : 20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildTopbar(tokens, isDesktop, darkGlass: showHero),
                if (showHero) ...[
                  SizedBox(height: isDesktop ? 90 : 44),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hero.title,
                          style: TextStyle(
                            fontFamily: 'Figtree',
                            fontSize: isDesktop ? 48 : 34,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.1,
                            height: 1.03,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 14),
                        CinemaHeroMetaLine(
                          rating: hero.rating,
                          year: hero.year,
                          lengthLabel: lengthLabel,
                          genres: hero.genres,
                          qualityTag: primarySource?.shortTag,
                        ),
                        if (hero.overview != null &&
                            hero.overview!.trim().isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            hero.overview!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Figtree',
                              fontSize: 15,
                              height: 1.55,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        Wrap(
                          spacing: 12,
                          runSpacing: 10,
                          children: [
                            CinemaPlayPillButton(
                              label: resume?.playLabel ?? 'Play',
                              onPressed: primarySource == null
                                  ? null
                                  : () => _launchPlayback(
                                        primarySource,
                                        widget.defaultQuality,
                                        movie: movie,
                                        series: show,
                                        episodeEntry: resume?.episodeEntry,
                                        initialPositionMs: playInitialPos,
                                      ),
                            ),
                            CinemaGlassButton(
                              key: const Key('hero-watchlist-btn'),
                              icon: HermesBookmarkIcon(
                                size: 18,
                                filled: hero.isInWatchlist,
                                color: hero.isInWatchlist
                                    ? tokens.accent
                                    : Colors.white,
                              ),
                              label: hero.isInWatchlist
                                  ? 'In Watchlist'
                                  : 'Watchlist',
                              onPressed: () {
                                if (movie != null) {
                                  unawaited(_toggleMovieWatchlist(movie));
                                } else if (show != null) {
                                  unawaited(_toggleSeriesWatchlist(show));
                                }
                              },
                            ),
                            CinemaGlassButton(
                              key: const Key('hero-details-btn'),
                              icon: const Icon(
                                Icons.info_outline_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                              label: 'Details',
                              onPressed: () => setState(() {
                                _selectedMovieId = movie?.id;
                                _selectedSeriesId = show?.id;
                              }),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeRows(
    BuildContext context,
    HermesThemeTokens tokens,
    List<MovieSummary> poolMovies,
    List<TvSeriesSummary> poolSeries,
    List<_ContinueWatchingEntry> continueWatching,
    double horizontalPad,
  ) {
    final watchlistMovies =
        poolMovies.where((m) => m.isInWatchlist).toList(growable: false);
    final watchlistSeries =
        poolSeries.where((s) => s.isInWatchlist).toList(growable: false);

    final combinedRecent = <(DateTime?, MovieSummary?, TvSeriesSummary?)>[
      ...poolMovies.map((m) => (m.addedAtUtc, m, null)),
      ...poolSeries.map((s) => (s.addedAtUtc, null, s)),
    ]..sort((a, b) {
        final da = a.$1 ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
        final db = b.$1 ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
        return db.compareTo(da);
      });

    // "Because you watched" based on latest in-progress item's genres
    final seedEntry = continueWatching.firstOrNull;
    final seedTitle = seedEntry?.movie?.title ?? seedEntry?.series?.title;
    final seedGenres =
        seedEntry?.movie?.genres ?? seedEntry?.series?.genres ?? const <String>[];
    final similarMovies = seedGenres.isEmpty
        ? const <MovieSummary>[]
        : poolMovies
            .where(
              (m) =>
                  m.id != seedEntry?.movie?.id &&
                  m.genres.any((g) => seedGenres.contains(g)),
            )
            .toList(growable: false);
    final similarSeries = seedGenres.isEmpty
        ? const <TvSeriesSummary>[]
        : poolSeries
            .where(
              (s) =>
                  s.id != seedEntry?.series?.id &&
                  s.genres.any((g) => seedGenres.contains(g)),
            )
            .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (continueWatching.isNotEmpty) ...[
          _RowHeader(title: 'Continue Watching', horizontalPad: horizontalPad),
          const SizedBox(height: 12),
          SizedBox(
            height: 224,
            child: ListView.separated(
              padding: EdgeInsets.symmetric(horizontal: horizontalPad),
              scrollDirection: Axis.horizontal,
              itemCount: continueWatching.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (_, idx) {
                final item = continueWatching[idx];
                return CinemaLandscapeCard(
                  title: item.title,
                  subtitle: item.subtitle,
                  artworkUri: item.artworkUri,
                  progress: item.progress,
                  isUpNext: item.isUpNext,
                  reduceMotion: widget.reduceMotion,
                  onTap: () => _launchPlayback(
                    item.source,
                    widget.defaultQuality,
                    movie: item.movie,
                    series: item.series,
                    episodeEntry: item.episodeEntry,
                    initialPositionMs: item.initialPositionMs,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 36),
        ],
        if (watchlistMovies.isNotEmpty || watchlistSeries.isNotEmpty) ...[
          _RowHeader(
            title: 'Watchlist',
            horizontalPad: horizontalPad,
            trailing: TextButton(
              onPressed: () => setState(() => _filter = _CinemaFilter.watchlist),
              child: const Text('See all'),
            ),
          ),
          const SizedBox(height: 12),
          _PosterStrip(
            horizontalPad: horizontalPad,
            items: [
              ...watchlistMovies.map((m) => _buildMoviePoster(m)),
              ...watchlistSeries.map((s) => _buildSeriesPoster(s)),
            ],
          ),
          const SizedBox(height: 36),
        ],
        if (combinedRecent.isNotEmpty) ...[
          _RowHeader(title: 'Recently added', horizontalPad: horizontalPad),
          const SizedBox(height: 12),
          _PosterStrip(
            horizontalPad: horizontalPad,
            items: combinedRecent.map((entry) {
              if (entry.$2 != null) return _buildMoviePoster(entry.$2!);
              return _buildSeriesPoster(entry.$3!);
            }).toList(growable: false),
          ),
          const SizedBox(height: 36),
        ],
        if (seedTitle != null &&
            (similarMovies.isNotEmpty || similarSeries.isNotEmpty)) ...[
          _RowHeader(
            title: 'Because you watched $seedTitle',
            horizontalPad: horizontalPad,
          ),
          const SizedBox(height: 12),
          _PosterStrip(
            horizontalPad: horizontalPad,
            items: [
              ...similarMovies.map((m) => _buildMoviePoster(m)),
              ...similarSeries.map((s) => _buildSeriesPoster(s)),
            ],
          ),
          const SizedBox(height: 36),
        ],
        if (poolMovies.isNotEmpty && _filter != _CinemaFilter.series) ...[
          _RowHeader(title: 'Movies', horizontalPad: horizontalPad),
          const SizedBox(height: 12),
          _PosterStrip(
            horizontalPad: horizontalPad,
            items: poolMovies.map(_buildMoviePoster).toList(growable: false),
          ),
          const SizedBox(height: 36),
        ],
        if (poolSeries.isNotEmpty && _filter != _CinemaFilter.movies) ...[
          _RowHeader(title: 'TV Shows', horizontalPad: horizontalPad),
          const SizedBox(height: 12),
          _PosterStrip(
            horizontalPad: horizontalPad,
            items: poolSeries.map(_buildSeriesPoster).toList(growable: false),
          ),
        ],
      ],
    );
  }

  Widget _buildWatchlistView(
    BuildContext context,
    HermesThemeTokens tokens,
    String query,
    double horizontalPad,
  ) {
    final savedMovies = _movies.where((m) => m.isInWatchlist).toList();
    final savedSeries = _series.where((s) => s.isInWatchlist).toList();

    final filteredMovies = query.isEmpty
        ? savedMovies
        : savedMovies
            .where((m) => _matchesMovieQuery(m, query))
            .toList(growable: false);
    final filteredSeries = query.isEmpty
        ? savedSeries
        : savedSeries
            .where((s) => _matchesSeriesQuery(s, query))
            .toList(growable: false);

    final parts = <String>[
      if (savedMovies.isNotEmpty)
        '${savedMovies.length} ${savedMovies.length == 1 ? 'movie' : 'movies'}',
      if (savedSeries.isNotEmpty)
        '${savedSeries.length} ${savedSeries.length == 1 ? 'show' : 'shows'}',
    ];
    final summary = parts.isEmpty ? 'No saved titles yet' : parts.join(' · ');

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 16,
            runSpacing: 8,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Watchlist',
                    style: TextStyle(
                      fontFamily: 'Figtree',
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.64,
                      color: tokens.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    summary,
                    style: TextStyle(
                      fontFamily: 'Figtree',
                      fontSize: 13,
                      color: tokens.text2,
                    ),
                  ),
                ],
              ),
              Text(
                'Custom lists planned',
                style: TextStyle(
                  fontFamily: 'Figtree',
                  fontSize: 13,
                  color: tokens.text3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (savedMovies.isEmpty && savedSeries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your Watchlist is empty',
                    style: TextStyle(
                      fontFamily: 'Figtree',
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: tokens.text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Bookmark movies and shows to save them here for later.',
                    style: TextStyle(
                      fontFamily: 'Figtree',
                      fontSize: 14,
                      color: tokens.text2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () => setState(() => _filter = _CinemaFilter.all),
                    child: const Text('Browse Cinema'),
                  ),
                ],
              ),
            )
          else if (filteredMovies.isEmpty && filteredSeries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No Watchlist matches for "${_searchQuery.trim()}"',
                    style: TextStyle(
                      fontFamily: 'Figtree',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: tokens.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Try another search or clear the filter.',
                    style: TextStyle(color: tokens.text2, fontSize: 14),
                  ),
                ],
              ),
            )
          else
            _ResponsivePosterGrid(
              children: [
                ...filteredMovies.map(_buildMoviePoster),
                ...filteredSeries.map(_buildSeriesPoster),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(
    BuildContext context,
    HermesThemeTokens tokens,
    List<MovieSummary> poolMovies,
    List<TvSeriesSummary> poolSeries,
    String query,
    double horizontalPad,
  ) {
    final matchedMovies = poolMovies
        .where((m) => _matchesMovieQuery(m, query))
        .toList(growable: false);
    final matchedSeries = poolSeries
        .where((s) => _matchesSeriesQuery(s, query))
        .toList(growable: false);

    final matchedEpisodes = <(TvSeriesSummary, CinemaEpisodeEntry)>[];
    for (final s in poolSeries) {
      for (final entry in s.allEpisodes) {
        if (entry.episode.title.toLowerCase().contains(query)) {
          matchedEpisodes.add((s, entry));
        }
      }
    }

    if (matchedMovies.isEmpty &&
        matchedSeries.isEmpty &&
        matchedEpisodes.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPad, vertical: 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No results for "${_searchQuery.trim()}"',
              style: TextStyle(
                fontFamily: 'Figtree',
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: tokens.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Nothing in your library matches. Try a title, genre, or actor.',
              style: TextStyle(color: tokens.text2, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (matchedMovies.isNotEmpty || matchedSeries.isNotEmpty) ...[
          _RowHeader(title: 'Movies & TV Shows', horizontalPad: horizontalPad),
          const SizedBox(height: 14),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPad),
            child: _ResponsivePosterGrid(
              children: [
                ...matchedMovies.map(_buildMoviePoster),
                ...matchedSeries.map(_buildSeriesPoster),
              ],
            ),
          ),
          const SizedBox(height: 36),
        ],
        if (matchedEpisodes.isNotEmpty) ...[
          _RowHeader(title: 'Episodes', horizontalPad: horizontalPad),
          const SizedBox(height: 12),
          SizedBox(
            height: 224,
            child: ListView.separated(
              padding: EdgeInsets.symmetric(horizontal: horizontalPad),
              scrollDirection: Axis.horizontal,
              itemCount: matchedEpisodes.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (_, idx) {
                final (show, entry) = matchedEpisodes[idx];
                final src = entry.episode.sources.firstOrNull;
                final stillUri = widget.cinemaService.buildArtworkUri(
                  entry.episode.stillArtworkHash ??
                      show.backdropHash ??
                      show.artworkHash,
                  variant: (entry.episode.stillArtworkHash != null ||
                          show.backdropHash != null)
                      ? 'backdrop_1280'
                      : 'poster_800',
                );
                return CinemaLandscapeCard(
                  title: entry.episode.title,
                  subtitle:
                      '${show.title} · ${entry.code} · ${entry.episode.durationMinutes}m',
                  artworkUri: stillUri,
                  progress: entry.episode.watchProgress?.isWatched == true
                      ? 0
                      : (entry.episode.watchProgress?.completionRatio ?? 0),
                  reduceMotion: widget.reduceMotion,
                  onTap: src == null
                      ? () => setState(() => _selectedSeriesId = show.id)
                      : () => _launchPlayback(
                            src,
                            widget.defaultQuality,
                            series: show,
                            episodeEntry: entry,
                            initialPositionMs:
                                entry.episode.watchProgress?.positionMs ?? 0,
                          ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  bool _matchesMovieQuery(MovieSummary m, String query) {
    return [
      m.title,
      if (m.year != null) '${m.year}',
      ...m.genres,
      ...m.cast.map((c) => c.name),
    ].any((field) => field.toLowerCase().contains(query));
  }

  bool _matchesSeriesQuery(TvSeriesSummary s, String query) {
    return [
      s.title,
      if (s.year != null) '${s.year}',
      ...s.genres,
      ...s.cast.map((c) => c.name),
    ].any((field) => field.toLowerCase().contains(query));
  }

  Widget _buildMoviePoster(MovieSummary movie) {
    final posterUri = widget.cinemaService.buildArtworkUri(
      movie.artworkHash,
      variant: 'poster_800',
    );
    final durationLabel = movie.durationMinutes > 0
        ? formatCinemaMinutes(movie.durationMinutes)
        : (movie.sources.firstOrNull?.shortTag ?? 'Movie');
    final sub = movie.year == null
        ? durationLabel
        : '${movie.year} · $durationLabel';

    return CinemaPosterCard(
      itemKey: movie.id,
      title: movie.title,
      subtitle: sub,
      artworkUri: posterUri,
      fallbackIcon: Icons.movie_outlined,
      inWatchlist: movie.isInWatchlist,
      isWatched: movie.isWatched,
      isNew: movie.isNew,
      progress: movie.resumePoint.progress,
      reduceMotion: widget.reduceMotion,
      onToggleWatchlist: () => unawaited(_toggleMovieWatchlist(movie)),
      onTap: () => setState(() {
        _selectedMovieId = movie.id;
        _selectedSeriesId = null;
      }),
    );
  }

  Widget _buildSeriesPoster(TvSeriesSummary show) {
    final posterUri = widget.cinemaService.buildArtworkUri(
      show.artworkHash,
      variant: 'poster_800',
    );
    final sub = show.year == null ? 'Series' : '${show.year} · Series';

    return CinemaPosterCard(
      itemKey: show.id,
      title: show.title,
      subtitle: sub,
      artworkUri: posterUri,
      fallbackIcon: Icons.tv_outlined,
      inWatchlist: show.isInWatchlist,
      isWatched: show.isWatched,
      isNew: show.isNew,
      isPartial: show.isPartial,
      reduceMotion: widget.reduceMotion,
      onToggleWatchlist: () => unawaited(_toggleSeriesWatchlist(show)),
      onTap: () => setState(() {
        _selectedSeriesId = show.id;
        _selectedMovieId = null;
      }),
    );
  }
}

class _RowHeader extends StatelessWidget {
  const _RowHeader({
    required this.title,
    required this.horizontalPad,
    this.trailing,
  });

  final String title;
  final double horizontalPad;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPad),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Figtree',
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: tokens.text,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _PosterStrip extends StatelessWidget {
  const _PosterStrip({
    required this.horizontalPad,
    required this.items,
  });

  final double horizontalPad;
  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 318,
      child: ListView.separated(
        padding: EdgeInsets.symmetric(horizontal: horizontalPad),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (_, idx) => items[idx],
      ),
    );
  }
}

class _ResponsivePosterGrid extends StatelessWidget {
  const _ResponsivePosterGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 28,
      children: children,
    );
  }
}
