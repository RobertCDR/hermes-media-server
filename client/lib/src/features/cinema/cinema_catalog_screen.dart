import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/network/hermes_sync_client.dart';
import '../../core/settings/hermes_preferences.dart';
import '../../core/storage/search_history_store.dart';
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
  watchlist('Watchlist'),
  lists('Lists'),
  history('History');

  const _CinemaFilter(this.label);
  final String label;
}

enum _CinemaLibrarySection {
  watchlist('Watchlist'),
  lists('Lists'),
  movies('Movies'),
  series('TV Shows'),
  history('History');

  const _CinemaLibrarySection(this.label);
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
    this.navigationController,
    this.searchHistoryStore,
    this.externalMobileNav = false,
  });

  final CinemaService cinemaService;
  final HermesVideoPlayerConfig playerConfig;
  final VideoQualityPreset defaultQuality;
  final HermesAccountPreferences accountPreferences;
  final bool reduceMotion;
  final Stream<WatchProgressUpdatedEvent>? watchProgressUpdates;
  final CinemaNavigationController? navigationController;
  final SearchHistoryStore? searchHistoryStore;
  final bool externalMobileNav;

  @override
  State<CinemaCatalogScreen> createState() => _CinemaCatalogScreenState();
}

class _CinemaCatalogScreenState extends State<CinemaCatalogScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final OverlayPortalController _desktopSearchOverlayController =
      OverlayPortalController();
  final LayerLink _desktopSearchLayerLink = LayerLink();

  bool _loading = true;
  Object? _loadError;
  List<MovieSummary> _movies = const [];
  List<TvSeriesSummary> _series = const [];
  List<CustomListModel> _customLists = const [];
  List<String> _cinemaSearchHistory = const [];

  _CinemaFilter _filter = _CinemaFilter.all;
  CinemaMobileTab _mobileTab = CinemaMobileTab.home;
  _CinemaLibrarySection _librarySection = _CinemaLibrarySection.watchlist;
  String _searchQuery = '';
  bool _searchFocused = false;
  bool _desktopPortalActive = false;
  String? _selectedMovieId;
  String? _selectedSeriesId;
  StreamSubscription<WatchProgressUpdatedEvent>? _watchProgressSub;

  SearchHistoryStore get _searchHistoryStore =>
      widget.searchHistoryStore ?? SharedPrefsSearchHistoryStore();

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_onSearchFocusChanged);
    unawaited(_loadCinemaSearchHistory());
    _mobileTab =
        widget.navigationController?.mobileTabNotifier.value ??
        CinemaMobileTab.home;
    _attachNavigationController(widget.navigationController);
    if (widget.cinemaService.hasCachedCatalog) {
      _movies = List<MovieSummary>.from(widget.cinemaService.cachedMovies!);
      _series =
          List<TvSeriesSummary>.from(widget.cinemaService.cachedSeries!);
      _customLists = List<CustomListModel>.from(
        widget.cinemaService.cachedCustomLists ?? const [],
      );
      _loading = false;
    }
    _subscribeWatchProgress();
    unawaited(_performLoadCatalog(silent: !_loading));
  }

  @override
  void didUpdateWidget(covariant CinemaCatalogScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.watchProgressUpdates != widget.watchProgressUpdates) {
      unawaited(_watchProgressSub?.cancel());
      _subscribeWatchProgress();
    }
    if (oldWidget.navigationController != widget.navigationController) {
      _detachNavigationController(oldWidget.navigationController);
      _attachNavigationController(widget.navigationController);
    }
  }

  @override
  void dispose() {
    _searchFocusNode.removeListener(_onSearchFocusChanged);
    _detachNavigationController(widget.navigationController);
    unawaited(_watchProgressSub?.cancel());
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchFocusChanged() {
    if (!mounted) return;
    final next = _searchFocusNode.hasFocus;
    if (next != _searchFocused) {
      setState(() => _searchFocused = next);
    }
    _syncDesktopSearchOverlay();
  }

  void _syncDesktopSearchOverlay() {
    if (!mounted || !_desktopPortalActive) return;
    final shouldShow = _searchFocused &&
        _searchQuery.trim().isEmpty &&
        _cinemaSearchHistory.isNotEmpty;
    if (shouldShow && !_desktopSearchOverlayController.isShowing) {
      _desktopSearchOverlayController.show();
    } else if (!shouldShow && _desktopSearchOverlayController.isShowing) {
      _desktopSearchOverlayController.hide();
    }
  }

  Future<void> _loadCinemaSearchHistory() async {
    final loaded = await _searchHistoryStore.loadCinemaHistory();
    if (!mounted) return;
    setState(() => _cinemaSearchHistory = loaded);
    _syncDesktopSearchOverlay();
  }

  Future<void> _recordCinemaSearchQuery(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return;
    final updated = await _searchHistoryStore.addCinemaQuery(clean);
    if (!mounted) return;
    setState(() => _cinemaSearchHistory = updated);
    _syncDesktopSearchOverlay();
  }

  Future<void> _removeCinemaSearchQuery(String query) async {
    final updated = await _searchHistoryStore.removeCinemaQuery(query);
    if (!mounted) return;
    setState(() => _cinemaSearchHistory = updated);
    _syncDesktopSearchOverlay();
  }

  Future<void> _clearCinemaSearchHistory() async {
    await _searchHistoryStore.clearCinemaHistory();
    if (!mounted) return;
    setState(() => _cinemaSearchHistory = const []);
    _syncDesktopSearchOverlay();
  }

  void _applyHistoryCinemaQuery(String query) {
    _searchController.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    setState(() => _searchQuery = query);
    unawaited(_recordCinemaSearchQuery(query));
    _syncDesktopSearchOverlay();
  }

  void _attachNavigationController(CinemaNavigationController? controller) {
    if (controller == null) return;
    controller.onSelectMobileTab = _onSelectMobileTab;
    controller.onHandleBack = _handleBack;
  }

  void _detachNavigationController(CinemaNavigationController? controller) {
    if (controller == null) return;
    if (controller.onSelectMobileTab == _onSelectMobileTab) {
      controller.onSelectMobileTab = null;
    }
    if (controller.onHandleBack == _handleBack) {
      controller.onHandleBack = null;
    }
  }

  void _onSelectMobileTab(CinemaMobileTab tab) {
    if (!mounted) return;
    setState(() {
      _selectedMovieId = null;
      _selectedSeriesId = null;
      _mobileTab = tab;
    });
  }

  bool _handleBack() {
    if (!mounted) return false;
    if (_selectedMovieId != null || _selectedSeriesId != null) {
      setState(() {
        _selectedMovieId = null;
        _selectedSeriesId = null;
      });
      return true;
    }
    if (_searchQuery.isNotEmpty) {
      _searchController.clear();
      setState(() => _searchQuery = '');
      return true;
    }
    if (widget.externalMobileNav && _mobileTab != CinemaMobileTab.home) {
      setState(() => _mobileTab = CinemaMobileTab.home);
      widget.navigationController?.mobileTabNotifier.value =
          CinemaMobileTab.home;
      return true;
    }
    if (_filter != _CinemaFilter.all) {
      setState(() => _filter = _CinemaFilter.all);
      return true;
    }
    return false;
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

  Future<T> _safeOptional<T>(Future<T> Function() loader, T fallback) async {
    try {
      return await loader();
    } catch (_) {
      return fallback;
    }
  }

  Future<void> _loadCatalog() => _performLoadCatalog(silent: false);

  Future<void> _performLoadCatalog({required bool silent}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }

    try {
      final results = await Future.wait([
        widget.cinemaService.listMovies(),
        widget.cinemaService.listSeries(),
        _safeOptional(
          widget.cinemaService.listCustomLists,
          const <CustomListModel>[],
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _movies = results[0] as List<MovieSummary>;
        _series = results[1] as List<TvSeriesSummary>;
        _customLists = results[2] as List<CustomListModel>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      if (!silent || (_movies.isEmpty && _series.isEmpty)) {
        setState(() {
          _loadError = error;
          _loading = false;
        });
      }
    }
  }

  Future<void> _openCreateOrRenameListDialog([CustomListModel? existing]) async {
    final result = await showDialog<({String name, String description})>(
      context: context,
      builder: (_) => _CustomListEditorDialog(existing: existing),
    );
    if (result == null || !mounted) return;
    final name = result.name;
    final desc = result.description;

    try {
      final saved = existing == null
          ? await widget.cinemaService.createCustomList(
              name: name,
              description: desc.isEmpty ? null : desc,
            )
          : await widget.cinemaService.updateCustomList(
              listId: existing.id,
              name: name,
              description: desc.isEmpty ? null : desc,
            );
      if (!mounted) return;
      setState(() {
        if (existing == null) {
          _customLists = [saved, ..._customLists];
        } else {
          _customLists = _customLists
              .map((l) => l.id == saved.id ? saved : l)
              .toList(growable: false);
        }
      });
      _showToast(existing == null ? 'Created "${saved.name}".' : 'Updated "${saved.name}".');
    } catch (e) {
      _showToast('Could not save list: $e');
    }
  }

  Future<void> _deleteCustomList(CustomListModel list) async {
    try {
      await widget.cinemaService.deleteCustomList(list.id);
      if (!mounted) return;
      setState(() {
        _customLists = _customLists.where((l) => l.id != list.id).toList(growable: false);
      });
      _showToast('Deleted "${list.name}".');
    } catch (e) {
      _showToast('Could not delete list: $e');
    }
  }

  Future<void> _openAddToListDialog({MovieSummary? movie, TvSeriesSummary? series}) async {
    final targetTitle = movie?.title ?? series?.title ?? 'Title';
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        final tokens = HermesThemeTokens.of(dialogCtx);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: tokens.surface2,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: Text(
                'Add "$targetTitle" to list',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: tokens.text),
              ),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_customLists.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'No custom lists yet. Create one first.',
                          style: TextStyle(fontSize: 13, color: tokens.text2),
                        ),
                      )
                    else
                      for (final list in _customLists)
                        Builder(
                          builder: (_) {
                            final present = list.items.any(
                              (i) =>
                                  (movie != null && i.movieId == movie.id) ||
                                  (series != null && i.tvSeriesId == series.id),
                            );
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(list.name, style: TextStyle(color: tokens.text, fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                '${list.items.length} ${list.items.length == 1 ? 'item' : 'items'}',
                                style: TextStyle(fontSize: 12, color: tokens.text2),
                              ),
                              trailing: Icon(
                                present ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                                color: present ? tokens.accent : tokens.text2,
                              ),
                              onTap: () async {
                                try {
                                  final updated = present
                                      ? await widget.cinemaService.removeItemFromCustomList(
                                          listId: list.id,
                                          movieId: movie?.id,
                                          tvSeriesId: series?.id,
                                        )
                                      : await widget.cinemaService.addItemToCustomList(
                                          listId: list.id,
                                          movieId: movie?.id,
                                          tvSeriesId: series?.id,
                                        );
                                  if (!mounted) return;
                                  setState(() {
                                    _customLists = _customLists
                                        .map((l) => l.id == updated.id ? updated : l)
                                        .toList(growable: false);
                                  });
                                  setDialogState(() {});
                                } catch (e) {
                                  _showToast('List update failed: $e');
                                }
                              },
                            );
                          },
                        ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    Navigator.of(dialogCtx).pop();
                    await _openCreateOrRenameListDialog();
                  },
                  child: const Text('New list'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
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

    // Build inline detail overlay while keeping catalog ListView mounted Offstage
    // so navigating back restores the exact scroll position.
    Widget? activeDetail;
    if (_selectedMovieId != null) {
      final movie =
          _movies.where((m) => m.id == _selectedMovieId).firstOrNull;
      if (movie != null) {
        activeDetail = CinemaDetailPage(
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
          onAddToList: () => unawaited(_openAddToListDialog(movie: movie)),
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
    } else if (_selectedSeriesId != null) {
      final show =
          _series.where((s) => s.id == _selectedSeriesId).firstOrNull;
      if (show != null) {
        activeDetail = CinemaDetailPage(
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
          onAddToList: () => unawaited(_openAddToListDialog(series: show)),
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

    if (activeDetail != null && _loading) {
      return activeDetail;
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
    final isListsTab = _filter == _CinemaFilter.lists;
    final showHero = query.isEmpty && !isWatchlistTab && !isListsTab;

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

    final catalogBody = Theme(
      data: heroTokens.toThemeData(),
      child: Material(
        color: heroTokens.bg,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 760;
            final horizontalPad = isDesktop ? 48.0 : 20.0;
            final useExternalMobile = !isDesktop && widget.externalMobileNav;
            _desktopPortalActive = !useExternalMobile && isDesktop;
            if (!_desktopPortalActive &&
                _desktopSearchOverlayController.isShowing) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted &&
                    !_desktopPortalActive &&
                    _desktopSearchOverlayController.isShowing) {
                  _desktopSearchOverlayController.hide();
                }
              });
            }

            if (useExternalMobile) {
              if (_mobileTab == CinemaMobileTab.search) {
                return _buildMobileSearchView(
                  context,
                  tokens,
                  poolMovies,
                  poolSeries,
                  query,
                  horizontalPad,
                );
              }
              if (_mobileTab == CinemaMobileTab.library) {
                return _buildMobileLibraryView(
                  context,
                  tokens,
                  query,
                  horizontalPad,
                );
              }
              return ListView(
                padding: const EdgeInsets.only(bottom: 56),
                children: [
                  _buildPersistentHeader(
                    context,
                    heroTokens,
                    hero,
                    showHero: !hero.isEmpty,
                    isDesktop: false,
                    horizontalPad: horizontalPad,
                    hideNavigationBar: true,
                  ),
                  _buildHomeRows(
                    context,
                    heroTokens,
                    _movies,
                    _series,
                    continueWatching,
                    horizontalPad,
                  ),
                ],
              );
            }

            final isHistoryTab = _filter == _CinemaFilter.history;

            return ListView(
              padding: const EdgeInsets.only(bottom: 56),
              children: [
                _buildPersistentHeader(
                  context,
                  heroTokens,
                  hero,
                  showHero: showHero && !isHistoryTab && !hero.isEmpty,
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
                else if (isListsTab)
                  _buildCustomListsView(
                    context,
                    heroTokens,
                    query,
                    horizontalPad,
                  )
                else if (isHistoryTab)
                  _buildWatchHistoryView(
                    context,
                    heroTokens,
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

    return IndexedStack(
      index: activeDetail == null ? 0 : 1,
      sizing: StackFit.expand,
      children: [
        TickerMode(enabled: activeDetail == null, child: catalogBody),
        if (activeDetail != null)
          KeyedSubtree(
            key: ValueKey(
              'cinema-detail-${_selectedMovieId ?? _selectedSeriesId}',
            ),
            child: activeDetail,
          ),
      ],
    );
  }

  Widget _buildDesktopCinemaSearchHistoryOverlay(
    BuildContext context,
  ) {
    final tokens = HermesThemeTokens.of(context);
    return Positioned(
      left: 0,
      top: 0,
      child: CompositedTransformFollower(
        link: _desktopSearchLayerLink,
        showWhenUnlinked: false,
        targetAnchor: Alignment.bottomLeft,
        followerAnchor: Alignment.topLeft,
        offset: const Offset(0, 6),
        child: TextFieldTapRegion(
          child: Material(
            color: Colors.transparent,
            child: Container(
              key: const Key('cinema-recent-searches'),
              width: 320,
              constraints: const BoxConstraints(maxHeight: 300),
              padding: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: tokens.surface2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: tokens.line),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x88000000),
                    blurRadius: 24,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: _buildCinemaHistoryRows(tokens, isDropdown: true),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCinemaHistoryRows(
    HermesThemeTokens tokens, {
    required bool isDropdown,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            isDropdown ? 14 : 0,
            isDropdown ? 10 : 0,
            isDropdown ? 8 : 0,
            4,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Recent searches',
                  style: TextStyle(
                    fontFamily: 'Figtree',
                    fontSize: isDropdown ? 13 : 15,
                    fontWeight: FontWeight.w700,
                    color: tokens.text,
                  ),
                ),
              ),
              TextButton(
                key: const Key('cinema-clear-search-history'),
                onPressed: () => unawaited(_clearCinemaSearchHistory()),
                child: Text(
                  'Clear',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: tokens.text2,
                  ),
                ),
              ),
            ],
          ),
        ),
        for (final q in _cinemaSearchHistory)
          InkWell(
            onTap: () => _applyHistoryCinemaQuery(q),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isDropdown ? 14 : 4,
                vertical: 8,
              ),
              child: Row(
                children: [
                  Icon(Icons.history_rounded, size: 17, color: tokens.text3),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      q,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Figtree',
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: tokens.text,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove search',
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => unawaited(_removeCinemaSearchQuery(q)),
                    icon: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: tokens.text3,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSearchInputBox({
    required bool isDesktop,
    required bool darkGlass,
  }) {
    final pill = HermesSearchPill(
      inputKey: const Key('cinema-search-input'),
      clearKey: const Key('cinema-search-clear'),
      controller: _searchController,
      focusNode: _searchFocusNode,
      hintText: 'Search titles, genres, cast...',
      darkGlass: darkGlass,
      height: 40,
      iconSize: 16,
      hasQuery: _searchQuery.isNotEmpty,
      onChanged: (value) {
        setState(() => _searchQuery = value);
        _syncDesktopSearchOverlay();
      },
      onSubmitted: (value) {
        unawaited(_recordCinemaSearchQuery(value));
      },
      onClear: () {
        _searchController.clear();
        setState(() => _searchQuery = '');
        _syncDesktopSearchOverlay();
      },
    );

    if (!isDesktop) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: double.infinity),
        child: pill,
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: TextFieldTapRegion(
        child: CompositedTransformTarget(
          link: _desktopSearchLayerLink,
          child: OverlayPortal(
            controller: _desktopSearchOverlayController,
            overlayChildBuilder: _buildDesktopCinemaSearchHistoryOverlay,
            child: pill,
          ),
        ),
      ),
    );
  }

  Widget _buildTopbar(
    HermesThemeTokens tokens,
    bool isDesktop, {
    required bool darkGlass,
    bool hideNavigationBar = false,
  }) {
    final activeTextColor = darkGlass ? Colors.white : tokens.text;
    final inactiveTextColor = darkGlass
        ? Colors.white.withValues(alpha: 0.62)
        : tokens.text2;
    final refreshIconColor = darkGlass
        ? Colors.white.withValues(alpha: 0.72)
        : tokens.text2;

    if (hideNavigationBar) {
      return SizedBox(height: MediaQuery.paddingOf(context).top + 36);
    }

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

    final searchBox = _buildSearchInputBox(
      isDesktop: isDesktop,
      darkGlass: darkGlass,
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
    bool hideNavigationBar = false,
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
                _buildTopbar(
                  tokens,
                  isDesktop,
                  darkGlass: showHero,
                  hideNavigationBar: hideNavigationBar,
                ),
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

  Widget _buildCustomListsView(
    BuildContext context,
    HermesThemeTokens tokens,
    String query,
    double horizontalPad,
  ) {
    final visibleLists = query.isEmpty
        ? _customLists
        : _customLists
            .where((l) =>
                l.name.toLowerCase().contains(query) ||
                l.items.any((i) => i.title.toLowerCase().contains(query)))
            .toList(growable: false);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 10,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Custom lists',
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
                    'Curate collections of movies and TV shows',
                    style: TextStyle(fontFamily: 'Figtree', fontSize: 13, color: tokens.text2),
                  ),
                ],
              ),
              FilledButton.icon(
                onPressed: () => unawaited(_openCreateOrRenameListDialog()),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New list'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (visibleLists.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Text(
                query.isEmpty
                    ? 'No custom lists yet. Click "New list" to start organizing titles.'
                    : 'No custom lists match "$query".',
                style: TextStyle(fontSize: 14, color: tokens.text2),
              ),
            )
          else
            for (final list in visibleLists) ...[
              Container(
                padding: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: tokens.lineSoft)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${list.name} (${list.items.length})',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: tokens.text,
                            ),
                          ),
                          if (list.description != null && list.description!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                list.description!,
                                style: TextStyle(fontSize: 13, color: tokens.text2),
                              ),
                            ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => unawaited(_openCreateOrRenameListDialog(list)),
                      child: const Text('Rename'),
                    ),
                    TextButton(
                      onPressed: () => unawaited(_deleteCustomList(list)),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (list.items.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Text(
                    'No titles in this list yet. Open any movie or show and click "Add to custom list".',
                    style: TextStyle(fontSize: 13, color: tokens.text3),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 28),
                  child: _ResponsivePosterGrid(
                    children: list.items.map((item) {
                      final matchedMovie = item.movieId == null
                          ? null
                          : _movies.where((m) => m.id == item.movieId).firstOrNull;
                      if (matchedMovie != null) {
                        return _buildMoviePoster(matchedMovie);
                      }
                      final matchedSeries = item.tvSeriesId == null
                          ? null
                          : _series.where((s) => s.id == item.tvSeriesId).firstOrNull;
                      if (matchedSeries != null) {
                        return _buildSeriesPoster(matchedSeries);
                      }
                      return CinemaPosterCard(
                        itemKey: item.id,
                        title: item.title,
                        subtitle: item.year?.toString() ?? (item.isMovie ? 'Movie' : 'Series'),
                        artworkUri: widget.cinemaService.buildArtworkUri(item.artworkHash, variant: 'poster_800'),
                        fallbackIcon: item.isMovie ? Icons.movie_outlined : Icons.tv_rounded,
                        inWatchlist: false,
                        isWatched: false,
                        isNew: false,
                        reduceMotion: widget.reduceMotion,
                        onTap: () {
                          if (item.movieId != null) {
                            setState(() => _selectedMovieId = item.movieId);
                          } else if (item.tvSeriesId != null) {
                            setState(() => _selectedSeriesId = item.tvSeriesId);
                          }
                        },
                      );
                    }).toList(growable: false),
                  ),
                ),
            ],
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
      onTap: () {
        if (_searchQuery.trim().isNotEmpty) {
          unawaited(_recordCinemaSearchQuery(_searchQuery));
        }
        setState(() {
          _selectedMovieId = movie.id;
          _selectedSeriesId = null;
        });
      },
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
      onTap: () {
        if (_searchQuery.trim().isNotEmpty) {
          unawaited(_recordCinemaSearchQuery(_searchQuery));
        }
        setState(() {
          _selectedSeriesId = show.id;
          _selectedMovieId = null;
        });
      },
    );
  }

  Widget _buildMobileSearchView(
    BuildContext context,
    HermesThemeTokens tokens,
    List<MovieSummary> poolMovies,
    List<TvSeriesSummary> poolSeries,
    String query,
    double horizontalPad,
  ) {
    return ListView(
      key: const Key('cinema-mobile-search-view'),
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + 58,
        bottom: 56,
      ),
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Search',
                style: TextStyle(
                  fontFamily: 'Figtree',
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: tokens.text,
                ),
              ),
              const SizedBox(height: 12),
              _buildSearchInputBox(isDesktop: false, darkGlass: false),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (query.isNotEmpty)
          _buildSearchResults(
            context,
            tokens,
            poolMovies,
            poolSeries,
            query,
            horizontalPad,
          )
        else ...[
          if (_cinemaSearchHistory.isNotEmpty) ...[
            Padding(
              key: const Key('cinema-recent-searches'),
              padding: EdgeInsets.symmetric(horizontal: horizontalPad),
              child: _buildCinemaHistoryRows(tokens, isDropdown: false),
            ),
            const SizedBox(height: 18),
          ],
          Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPad),
            child: Text(
              'Search your movies, shows, episodes, genres, and cast.',
              style: TextStyle(fontSize: 13, color: tokens.text2),
            ),
          ),
          if (_movies.isNotEmpty || _series.isNotEmpty) ...[
            const SizedBox(height: 20),
            _RowHeader(title: 'Browse Cinema', horizontalPad: horizontalPad),
            const SizedBox(height: 12),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPad),
              child: _ResponsivePosterGrid(
                children: [
                  ..._movies.take(6).map(_buildMoviePoster),
                  ..._series.take(6).map(_buildSeriesPoster),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildMobileLibraryView(
    BuildContext context,
    HermesThemeTokens tokens,
    String query,
    double horizontalPad,
  ) {
    return ListView(
      key: const Key('cinema-mobile-library-view'),
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + 58,
        bottom: 56,
      ),
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPad),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Library',
                style: TextStyle(
                  fontFamily: 'Figtree',
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: tokens.text,
                ),
              ),
              IconButton(
                tooltip: 'Refresh catalog',
                onPressed: _loadCatalog,
                icon: Icon(
                  Icons.refresh_rounded,
                  size: 20,
                  color: tokens.text2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: horizontalPad),
          child: Row(
            children: [
              for (final section in _CinemaLibrarySection.values) ...[
                ChoiceChip(
                  key: Key('cinema-library-chip-${section.name}'),
                  label: Text(section.label),
                  selected: _librarySection == section,
                  onSelected: (_) => setState(() => _librarySection = section),
                  selectedColor: tokens.accent.withValues(alpha: 0.22),
                  backgroundColor: tokens.surface2,
                  labelStyle: TextStyle(
                    fontFamily: 'Figtree',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _librarySection == section
                        ? tokens.accent
                        : tokens.text2,
                  ),
                  side: BorderSide(
                    color: _librarySection == section
                        ? tokens.accent
                        : tokens.line,
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        switch (_librarySection) {
          _CinemaLibrarySection.watchlist => _buildWatchlistView(
              context,
              tokens,
              query,
              horizontalPad,
            ),
          _CinemaLibrarySection.lists => _buildCustomListsView(
              context,
              tokens,
              query,
              horizontalPad,
            ),
          _CinemaLibrarySection.movies => _buildPosterSectionGrid(
              tokens: tokens,
              title: 'Movies',
              emptyMessage: 'No movies in your library yet.',
              items: _movies.map(_buildMoviePoster).toList(growable: false),
              horizontalPad: horizontalPad,
            ),
          _CinemaLibrarySection.series => _buildPosterSectionGrid(
              tokens: tokens,
              title: 'TV Shows',
              emptyMessage: 'No TV series in your library yet.',
              items: _series.map(_buildSeriesPoster).toList(growable: false),
              horizontalPad: horizontalPad,
            ),
          _CinemaLibrarySection.history => _buildWatchHistoryView(
              context,
              tokens,
              horizontalPad,
            ),
        },
      ],
    );
  }

  Widget _buildPosterSectionGrid({
    required HermesThemeTokens tokens,
    required String title,
    required String emptyMessage,
    required List<Widget> items,
    required double horizontalPad,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Figtree',
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: tokens.text,
            ),
          ),
          const SizedBox(height: 16),
          if (items.isEmpty)
            Text(
              emptyMessage,
              style: TextStyle(fontSize: 14, color: tokens.text2),
            )
          else
            _ResponsivePosterGrid(children: items),
        ],
      ),
    );
  }

  Widget _buildWatchHistoryView(
    BuildContext context,
    HermesThemeTokens tokens,
    double horizontalPad,
  ) {
    final entries = <(DateTime, Widget)>[];
    for (final movie in _movies) {
      final wp = movie.watchProgress;
      if (wp != null && (wp.isWatched || wp.positionMs > 0)) {
        entries.add((wp.updatedAtUtc, _buildMoviePoster(movie)));
      }
    }
    for (final show in _series) {
      DateTime? latest;
      for (final season in show.seasons) {
        for (final ep in season.episodes) {
          final wp = ep.watchProgress;
          if (wp != null && (wp.isWatched || wp.positionMs > 0)) {
            if (latest == null || wp.updatedAtUtc.isAfter(latest)) {
              latest = wp.updatedAtUtc;
            }
          }
        }
      }
      if (latest != null) {
        entries.add((latest, _buildSeriesPoster(show)));
      }
    }
    entries.sort((a, b) => b.$1.compareTo(a.$1));

    return _buildPosterSectionGrid(
      tokens: tokens,
      title: 'Watch history',
      emptyMessage: 'No watch history yet',
      items: entries.map((e) => e.$2).toList(growable: false),
      horizontalPad: horizontalPad,
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

class _CustomListEditorDialog extends StatefulWidget {
  const _CustomListEditorDialog({this.existing});

  final CustomListModel? existing;

  @override
  State<_CustomListEditorDialog> createState() =>
      _CustomListEditorDialogState();
}

class _CustomListEditorDialogState extends State<_CustomListEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _descController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _descController =
        TextEditingController(text: widget.existing?.description ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HermesThemeTokens.of(context);
    final isEdit = widget.existing != null;
    return AlertDialog(
      backgroundColor: tokens.surface2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(
        isEdit ? 'Rename list' : 'Create list',
        style: TextStyle(fontWeight: FontWeight.w800, color: tokens.text),
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'List name',
                hintText: 'Weekend Sci-Fi',
                filled: true,
                fillColor: tokens.surface3,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descController,
              decoration: InputDecoration(
                labelText: 'Description (optional)',
                filled: true,
                fillColor: tokens.surface3,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: tokens.text2)),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) return;
            Navigator.of(context).pop((
              name: name,
              description: _descController.text.trim(),
            ));
          },
          child: Text(isEdit ? 'Save' : 'Create list'),
        ),
      ],
    );
  }
}
