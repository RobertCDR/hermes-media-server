import 'package:material_ui/material_ui.dart';

import '../../core/settings/hermes_preferences.dart';
import '../../core/theme/hermes_theme_tokens.dart';
import '../../core/widgets/hermes_artwork_image.dart';
import '../../core/widgets/hermes_icons.dart';
import 'cinema_models.dart';
import 'cinema_service.dart';
import 'cinema_shared_widgets.dart';
import 'source_selector_card.dart';

typedef CinemaPlayEpisodeCallback = void Function(
  MediaSourceModel source,
  VideoQualityPreset quality, {
  MovieSummary? movie,
  TvSeriesSummary? series,
  CinemaEpisodeEntry? episodeEntry,
  int initialPositionMs,
});

class CinemaDetailPage extends StatefulWidget {
  const CinemaDetailPage({
    super.key,
    this.movie,
    this.series,
    required this.cinemaService,
    required this.defaultQuality,
    this.accountPreferences = const HermesAccountPreferences(),
    this.reduceMotion = false,
    this.allMovies = const [],
    this.allSeries = const [],
    required this.onBack,
    required this.onPlay,
    required this.onToggleWatchlist,
    required this.onToggleWatched,
    this.onOpenRelatedMovie,
    this.onOpenRelatedSeries,
  }) : assert(
          movie != null || series != null,
          'CinemaDetailPage requires a movie or series.',
        );

  final MovieSummary? movie;
  final TvSeriesSummary? series;
  final CinemaService cinemaService;
  final VideoQualityPreset defaultQuality;
  final HermesAccountPreferences accountPreferences;
  final bool reduceMotion;
  final List<MovieSummary> allMovies;
  final List<TvSeriesSummary> allSeries;
  final VoidCallback onBack;
  final CinemaPlayEpisodeCallback onPlay;
  final VoidCallback onToggleWatchlist;
  final VoidCallback onToggleWatched;
  final ValueChanged<MovieSummary>? onOpenRelatedMovie;
  final ValueChanged<TvSeriesSummary>? onOpenRelatedSeries;

  @override
  State<CinemaDetailPage> createState() => _CinemaDetailPageState();
}

class _CinemaDetailPageState extends State<CinemaDetailPage> {
  late int _selectedSeasonNumber;
  String? _selectedSourceId;

  bool get _isMovie => widget.movie != null;
  String get _title => widget.movie?.title ?? widget.series!.title;
  int? get _year => widget.movie?.year ?? widget.series?.year;
  String? get _overview => widget.movie?.overview ?? widget.series?.overview;
  double? get _rating => widget.movie?.rating ?? widget.series?.rating;
  List<String> get _genres =>
      widget.movie?.genres ?? widget.series?.genres ?? const [];
  List<CastMemberModel> get _cast =>
      widget.movie?.cast ?? widget.series?.cast ?? const [];
  bool get _inWatchlist =>
      widget.movie?.isInWatchlist ?? widget.series?.isInWatchlist ?? false;
  bool get _isWatched =>
      widget.movie?.isWatched ?? widget.series?.isWatched ?? false;
  DateTime? get _addedAt => widget.movie?.addedAtUtc ?? widget.series?.addedAtUtc;

  @override
  void initState() {
    super.initState();
    _initDefaults();
  }

  @override
  void didUpdateWidget(covariant CinemaDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.movie?.id != widget.movie?.id ||
        oldWidget.series?.id != widget.series?.id) {
      _selectedSourceId = null;
      _initDefaults();
    }
  }

  void _initDefaults() {
    final series = widget.series;
    if (series != null && series.seasons.isNotEmpty) {
      _selectedSeasonNumber =
          series.resumePoint?.episodeEntry?.seasonNumber ??
              series.seasons.first.seasonNumber;
    } else {
      _selectedSeasonNumber = 1;
    }
  }

  List<MediaSourceModel> _primarySources(CinemaResumePoint? resume) {
    if (widget.movie != null) {
      return widget.movie!.sources;
    }
    return resume?.episodeEntry?.episode.sources ??
        widget.series?.seasons.firstOrNull?.episodes.firstOrNull?.sources ??
        const [];
  }

  MediaSourceModel? _resolveActiveSource(List<MediaSourceModel> sources) {
    if (sources.isEmpty) return null;
    if (_selectedSourceId != null) {
      final hit = sources.where((s) => s.id == _selectedSourceId).firstOrNull;
      if (hit != null) return hit;
    }
    return sources.first;
  }

  String _formatAddedDate(DateTime? added) {
    if (added == null) return 'In library';
    final days = DateTime.now().toUtc().difference(added.toUtc()).inDays;
    if (days <= 0) return 'Today';
    if (days == 1) return '1 day ago';
    return '$days days ago';
  }

  void _openEpisodeSourceSheet(
    BuildContext context,
    String episodeTitle,
    List<MediaSourceModel> sources,
    CinemaEpisodeEntry entry,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: HermesThemeTokens.of(context).bgElevated,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: SourceSelectorCard(
          sources: sources,
          initialQuality: widget.defaultQuality,
          onPlaySource: (source, quality) {
            Navigator.of(ctx).pop();
            widget.onPlay(
              source,
              quality,
              series: widget.series,
              episodeEntry: entry,
              initialPositionMs: entry.episode.watchProgress?.isWatched == true
                  ? 0
                  : (entry.episode.watchProgress?.positionMs ?? 0),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final baseTokens = HermesThemeTokens.of(context);
    final tint = deriveTitleTint(_title);
    final pageTokens = baseTokens.withTitleTint(
      tint,
      overrideAccent: widget.accountPreferences.matchTitleColors,
    );

    final resume = widget.movie != null
        ? widget.movie!.resumePoint
        : widget.series!.resumePoint;
    final primarySources = _primarySources(resume);
    final activeSource = _resolveActiveSource(primarySources);

    final backdropHash = _isMovie
        ? (widget.movie!.backdropHash ?? widget.movie!.artworkHash)
        : (widget.series!.backdropHash ?? widget.series!.artworkHash);
    final isBackdrop = _isMovie
        ? widget.movie!.backdropHash != null
        : widget.series!.backdropHash != null;
    final backdropUri = widget.cinemaService.buildArtworkUri(
      backdropHash,
      variant: isBackdrop ? 'backdrop_1280' : 'poster_800',
    );

    final lengthLabel = _isMovie
        ? (widget.movie!.durationMinutes > 0
            ? formatCinemaMinutes(widget.movie!.durationMinutes)
            : '')
        : '${widget.series!.seasons.length} ${widget.series!.seasons.length == 1 ? 'Season' : 'Seasons'}';

    final resuming =
        resume != null && resume.mode == CinemaResumeMode.resume && !_isWatched;

    final playLabel = (_isWatched && _isMovie)
        ? 'Play'
        : (resume?.playLabel ?? 'Play');

    final playInitialPos = (_isWatched || resume == null)
        ? 0
        : (resume.episodeEntry != null
            ? (resume.episodeEntry!.episode.watchProgress?.isWatched == true
                ? 0
                : (resume.episodeEntry!.episode.watchProgress?.positionMs ?? 0))
            : (widget.movie?.watchProgress?.positionMs ?? 0));

    final relatedMovies = _genres.isEmpty
        ? const <MovieSummary>[]
        : widget.allMovies
            .where(
              (m) =>
                  m.id != widget.movie?.id &&
                  m.genres.any((g) => _genres.contains(g)),
            )
            .toList(growable: false);
    final relatedSeries = _genres.isEmpty
        ? const <TvSeriesSummary>[]
        : widget.allSeries
            .where(
              (s) =>
                  s.id != widget.series?.id &&
                  s.genres.any((g) => _genres.contains(g)),
            )
            .toList(growable: false);

    return Theme(
      data: pageTokens.toThemeData(),
      child: Material(
        color: pageTokens.bg,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 760;
            final horizontalPad = isDesktop ? 48.0 : 20.0;
            final heroMinHeight = isDesktop ? 420.0 : 340.0;

            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.45, 0.85],
                  colors: [
                    pageTokens.pageWash,
                    pageTokens.pageWash,
                    pageTokens.bg,
                  ],
                ),
              ),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 56),
                children: [
                  // Tightened Detail Hero
                  ConstrainedBox(
                    constraints: BoxConstraints(minHeight: heroMinHeight),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: HermesArtworkImage(
                            uri: backdropUri,
                            fallbackTitle: _title,
                            fallbackIcon: _isMovie
                                ? Icons.movie_outlined
                                : Icons.tv_outlined,
                            borderRadius: BorderRadius.zero,
                            showFallbackLabel: false,
                          ),
                        ),
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                stops: const [0.0, 0.35, 0.72],
                                colors: [
                                  pageTokens.pageWash,
                                  pageTokens.pageWash.withValues(alpha: 0.78),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                stops: const [0.0, 0.42, 0.85, 1.0],
                                colors: [
                                  pageTokens.pageWash,
                                  Colors.transparent,
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.45),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            horizontalPad,
                            20,
                            horizontalPad,
                            32,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Semantics(
                                container: true,
                                button: true,
                                excludeSemantics: true,
                                label: 'Back',
                                child: InkWell(
                                  key: const Key('detail-back-btn'),
                                  customBorder: const CircleBorder(),
                                  onTap: widget.onBack,
                                  child: Container(
                                    width: 40,
                                    height: 40,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.black.withValues(alpha: 0.5),
                                    ),
                                    child: const Icon(
                                      Icons.arrow_back_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: isDesktop ? 42 : 28),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 620),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _title,
                                      style: TextStyle(
                                        fontFamily: 'Figtree',
                                        fontSize: isDesktop ? 42 : 30,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.9,
                                        height: 1.05,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    CinemaHeroMetaLine(
                                      rating: _rating,
                                      year: _year,
                                      lengthLabel: lengthLabel,
                                      genres: _genres,
                                      qualityTag: activeSource?.shortTag,
                                    ),
                                    if (widget.series != null &&
                                        widget.series!.isPartial) ...[
                                      const SizedBox(height: 10),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.info_outline_rounded,
                                            size: 14,
                                            color: Colors.white
                                                .withValues(alpha: 0.75),
                                          ),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              '${widget.series!.availableEpisodeCount} of ${widget.series!.expectedTotalEpisodeCount} episodes are on the server',
                                              style: TextStyle(
                                                fontFamily: 'Figtree',
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.white
                                                    .withValues(alpha: 0.78),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                    if (_overview != null &&
                                        _overview!.trim().isNotEmpty) ...[
                                      const SizedBox(height: 12),
                                      Text(
                                        _overview!,
                                        maxLines: 5,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily: 'Figtree',
                                          fontSize: 15,
                                          height: 1.55,
                                          color: Colors.white
                                              .withValues(alpha: 0.8),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 24),
                                    // Nuvio Action Row: [Play] [Bookmark circle] [Watched check circle]
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 10,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        CinemaPlayPillButton(
                                          label: playLabel,
                                          onPressed: activeSource == null
                                              ? null
                                              : () => widget.onPlay(
                                                    activeSource,
                                                    widget.defaultQuality,
                                                    movie: widget.movie,
                                                    series: widget.series,
                                                    episodeEntry:
                                                        resume?.episodeEntry,
                                                    initialPositionMs:
                                                        playInitialPos,
                                                  ),
                                        ),
                                        CinemaGlassIconButton(
                                          key: const Key('detail-bookmark-btn'),
                                          tooltip: _inWatchlist
                                              ? 'Remove from Watchlist'
                                              : 'Add to Watchlist',
                                          highlightedAccent: _inWatchlist,
                                          onPressed: widget.onToggleWatchlist,
                                          icon: HermesBookmarkIcon(
                                            size: 20,
                                            filled: _inWatchlist,
                                            color: _inWatchlist
                                                ? pageTokens.accent
                                                : Colors.white,
                                          ),
                                        ),
                                        CinemaGlassIconButton(
                                          key: const Key('detail-watched-btn'),
                                          tooltip: _isWatched
                                              ? 'Mark as unwatched'
                                              : 'Mark as watched',
                                          filledWhite: _isWatched,
                                          onPressed: widget.onToggleWatched,
                                          icon: Icon(
                                            Icons.check_rounded,
                                            size: 20,
                                            color: _isWatched
                                                ? const Color(0xFF0B0B0B)
                                                : Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                    // Source / Version dropdown when multiple sources exist
                                    if (primarySources.length > 1) ...[
                                      const SizedBox(height: 16),
                                      Wrap(
                                        spacing: 12,
                                        runSpacing: 8,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Text(
                                            'Version',
                                            style: TextStyle(
                                              fontFamily: 'Figtree',
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: pageTokens.text2,
                                            ),
                                          ),
                                          HermesFlatDropdown<String>(
                                            value: activeSource!.id,
                                            options: primarySources
                                                .map(
                                                  (s) => HermesDropdownOption(
                                                    value: s.id,
                                                    label:
                                                        '${s.sourceLabel} (${s.container.toUpperCase()})',
                                                  ),
                                                )
                                                .toList(growable: false),
                                            onChanged: (nextId) {
                                              setState(
                                                () => _selectedSourceId = nextId,
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ],
                                    // Resume Progress Strip
                                    if (resuming) ...[
                                      const SizedBox(height: 18),
                                      ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 340),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(2),
                                                child: LinearProgressIndicator(
                                                  value: resume.progress,
                                                  minHeight: 3,
                                                  color: pageTokens.accent,
                                                  backgroundColor: Colors.white
                                                      .withValues(alpha: 0.25),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Text(
                                              resume.episodeEntry != null
                                                  ? '${resume.episodeEntry!.code} · ${formatCinemaMinutes(resume.remainingMinutes)} left'
                                                  : '${formatCinemaMinutes(resume.remainingMinutes)} left',
                                              style: TextStyle(
                                                fontFamily: 'Figtree',
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.white
                                                    .withValues(alpha: 0.72),
                                              ),
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
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Episodes section (TV Series)
                  if (widget.series != null &&
                      widget.series!.seasons.isNotEmpty) ...[
                    _buildEpisodesSection(context, pageTokens, horizontalPad),
                    const SizedBox(height: 36),
                  ],

                  // Cast section
                  if (_cast.isNotEmpty) ...[
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: horizontalPad),
                      child: Text(
                        'Cast',
                        style: TextStyle(
                          fontFamily: 'Figtree',
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: pageTokens.text,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 152,
                      child: ListView.separated(
                        padding:
                            EdgeInsets.symmetric(horizontal: horizontalPad),
                        scrollDirection: Axis.horizontal,
                        itemCount: _cast.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 14),
                        itemBuilder: (_, idx) => _CastCard(
                          member: _cast[idx],
                          cinemaService: widget.cinemaService,
                          tokens: pageTokens,
                        ),
                      ),
                    ),
                    const SizedBox(height: 36),
                  ],

                  // More like this section
                  if (relatedMovies.isNotEmpty || relatedSeries.isNotEmpty) ...[
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: horizontalPad),
                      child: Text(
                        'More like this',
                        style: TextStyle(
                          fontFamily: 'Figtree',
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: pageTokens.text,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 318,
                      child: ListView(
                        padding:
                            EdgeInsets.symmetric(horizontal: horizontalPad),
                        scrollDirection: Axis.horizontal,
                        children: [
                          ...relatedMovies.map(
                            (m) => Padding(
                              padding: const EdgeInsets.only(right: 14),
                              child: CinemaPosterCard(
                                itemKey: m.id,
                                title: m.title,
                                subtitle: m.year == null
                                    ? formatCinemaMinutes(m.durationMinutes)
                                    : '${m.year} · ${formatCinemaMinutes(m.durationMinutes)}',
                                artworkUri:
                                    widget.cinemaService.buildArtworkUri(
                                  m.artworkHash,
                                  variant: 'poster_800',
                                ),
                                fallbackIcon: Icons.movie_outlined,
                                inWatchlist: m.isInWatchlist,
                                isWatched: m.isWatched,
                                isNew: m.isNew,
                                progress: m.resumePoint.progress,
                                reduceMotion: widget.reduceMotion,
                                onTap: () =>
                                    widget.onOpenRelatedMovie?.call(m),
                              ),
                            ),
                          ),
                          ...relatedSeries.map(
                            (s) => Padding(
                              padding: const EdgeInsets.only(right: 14),
                              child: CinemaPosterCard(
                                itemKey: s.id,
                                title: s.title,
                                subtitle:
                                    s.year == null ? 'Series' : '${s.year} · Series',
                                artworkUri:
                                    widget.cinemaService.buildArtworkUri(
                                  s.artworkHash,
                                  variant: 'poster_800',
                                ),
                                fallbackIcon: Icons.tv_outlined,
                                inWatchlist: s.isInWatchlist,
                                isWatched: s.isWatched,
                                isNew: s.isNew,
                                isPartial: s.isPartial,
                                reduceMotion: widget.reduceMotion,
                                onTap: () =>
                                    widget.onOpenRelatedSeries?.call(s),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 36),
                  ],

                  // Technical Details Facts Grid
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: horizontalPad),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Details',
                          style: TextStyle(
                            fontFamily: 'Figtree',
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: pageTokens.text,
                          ),
                        ),
                        const SizedBox(height: 14),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: _FactsTable(
                            tokens: pageTokens,
                            genres: _genres,
                            source: activeSource,
                            addedLabel: _formatAddedDate(_addedAt),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildEpisodesSection(
    BuildContext context,
    HermesThemeTokens tokens,
    double horizontalPad,
  ) {
    final series = widget.series!;
    final activeSeason = series.seasons
            .where((s) => s.seasonNumber == _selectedSeasonNumber)
            .firstOrNull ??
        series.seasons.first;
    final missingCount = activeSeason.missingEpisodeCount;
    final cardCount =
        activeSeason.episodes.length + (missingCount > 0 ? 1 : 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPad),
          child: Row(
            children: [
              Text(
                'Episodes',
                style: TextStyle(
                  fontFamily: 'Figtree',
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: tokens.text,
                ),
              ),
              const SizedBox(width: 14),
              HermesFlatDropdown<int>(
                minWidth: 150,
                value: activeSeason.seasonNumber,
                options: series.seasons
                    .map(
                      (s) => HermesDropdownOption(
                        value: s.seasonNumber,
                        label: s.expectedEpisodeCount != null
                            ? 'Season ${s.seasonNumber} (${s.episodes.length}/${s.expectedEpisodeCount})'
                            : 'Season ${s.seasonNumber}',
                      ),
                    )
                    .toList(growable: false),
                onChanged: (nextSeason) {
                  setState(() => _selectedSeasonNumber = nextSeason);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPad),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: cardCount,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (_, idx) {
              if (idx < activeSeason.episodes.length) {
                final ep = activeSeason.episodes[idx];
                final entry = CinemaEpisodeEntry(
                  seasonNumber: activeSeason.seasonNumber,
                  episode: ep,
                );
                final firstSource = ep.sources.firstOrNull;
                final stillUri = widget.cinemaService.buildArtworkUri(
                  ep.stillArtworkHash ?? series.backdropHash ?? series.artworkHash,
                  variant: ep.stillArtworkHash != null || series.backdropHash != null
                      ? 'backdrop_1280'
                      : 'poster_800',
                );

                return _EpisodeTileCard(
                  episode: ep,
                  stillUri: stillUri,
                  tokens: tokens,
                  reduceMotion: widget.reduceMotion,
                  onPlay: firstSource == null
                      ? null
                      : () => widget.onPlay(
                            firstSource,
                            widget.defaultQuality,
                            series: series,
                            episodeEntry: entry,
                            initialPositionMs:
                                ep.watchProgress?.isWatched == true
                                    ? 0
                                    : (ep.watchProgress?.positionMs ?? 0),
                          ),
                  onPickVersion: ep.sources.length > 1
                      ? () => _openEpisodeSourceSheet(
                            context,
                            '${series.title} · S${activeSeason.seasonNumber} E${ep.episodeNumber}',
                            ep.sources,
                            entry,
                          )
                      : null,
                );
              }

              final startMissing = activeSeason.episodes.length + 1;
              final expectedTotal = activeSeason.expectedEpisodeCount!;
              return _MissingEpisodePlaceholderCard(
                tokens: tokens,
                seriesTitle: series.title,
                rangeLabel: activeSeason.episodes.isEmpty
                    ? 'All $expectedTotal episodes'
                    : 'Episodes $startMissing–$expectedTotal',
                missingCount: missingCount,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EpisodeTileCard extends StatefulWidget {
  const _EpisodeTileCard({
    required this.episode,
    required this.stillUri,
    required this.tokens,
    required this.reduceMotion,
    this.onPlay,
    this.onPickVersion,
  });

  final EpisodeSummary episode;
  final Uri? stillUri;
  final HermesThemeTokens tokens;
  final bool reduceMotion;
  final VoidCallback? onPlay;
  final VoidCallback? onPickVersion;

  @override
  State<_EpisodeTileCard> createState() => _EpisodeTileCardState();
}

class _EpisodeTileCardState extends State<_EpisodeTileCard> {
  bool _hovered = false;

  Widget _buildThumbnail({
    required double width,
    required double height,
    required WatchProgressModel? wp,
    required bool done,
    required bool inProgress,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ExcludeSemantics(
              child: AnimatedScale(
                scale: (_hovered && !widget.reduceMotion) ? 1.04 : 1.0,
                duration: widget.reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                child: HermesArtworkImage(
                  uri: widget.stillUri,
                  fallbackTitle: widget.episode.title,
                  width: width,
                  height: height,
                  borderRadius: BorderRadius.zero,
                  showFallbackLabel: false,
                ),
              ),
            ),
            if (widget.onPlay != null)
              ExcludeSemantics(
                child: AnimatedOpacity(
                  alwaysIncludeSemantics: true,
                  opacity: _hovered ? 1.0 : 0.0,
                  duration: widget.reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 160),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.35),
                    alignment: Alignment.center,
                    child: const HermesPlayIcon(
                      size: 30,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            if (done)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Watched',
                    style: TextStyle(
                      fontFamily: 'Figtree',
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            if (inProgress && wp != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ExcludeSemantics(
                  child: LinearProgressIndicator(
                    value: wp.completionRatio,
                    minHeight: 4,
                    color: widget.tokens.accent,
                    backgroundColor: Colors.white.withValues(alpha: 0.22),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetaColumn(String durText) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.episode.sources.isEmpty
                    ? 'Episode ${widget.episode.episodeNumber} · Not indexed'
                    : 'Episode ${widget.episode.episodeNumber} · $durText',
                style: TextStyle(
                  fontFamily: 'Figtree',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: widget.tokens.text2,
                ),
              ),
            ),
            if (widget.onPickVersion != null)
              Semantics(
                container: true,
                button: true,
                excludeSemantics: true,
                label: 'Select version',
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: widget.onPickVersion,
                  child: Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.tokens.surface3,
                    ),
                    child: Icon(
                      Icons.tune_rounded,
                      size: 15,
                      color: widget.tokens.text,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          widget.episode.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Figtree',
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: widget.tokens.text,
          ),
        ),
        if (widget.episode.overview != null &&
            widget.episode.overview!.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            widget.episode.overview!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Figtree',
              fontSize: 13,
              height: 1.45,
              color: widget.tokens.text2,
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final wp = widget.episode.watchProgress;
    final done = wp?.isWatched == true;
    final inProgress = wp != null && !done && wp.positionMs > 0;
    final durText = inProgress
        ? '${formatCinemaMinutes(wp.remainingMinutes)} left'
        : '${widget.episode.durationMinutes}m';

    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: MouseRegion(
        cursor: widget.onPlay != null
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPlay,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _hovered ? widget.tokens.surface2 : widget.tokens.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: widget.tokens.lineSoft),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 560;
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _buildThumbnail(
                        width: 216,
                        height: 121.5,
                        wp: wp,
                        done: done,
                        inProgress: inProgress,
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: _buildMetaColumn(durText)),
                    ],
                  );
                }

                final thumbWidth = constraints.maxWidth;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildThumbnail(
                      width: thumbWidth,
                      height: thumbWidth * 9 / 16,
                      wp: wp,
                      done: done,
                      inProgress: inProgress,
                    ),
                    const SizedBox(height: 10),
                    _buildMetaColumn(durText),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _MissingEpisodePlaceholderCard extends StatelessWidget {
  const _MissingEpisodePlaceholderCard({
    required this.tokens,
    required this.seriesTitle,
    required this.rangeLabel,
    required this.missingCount,
  });

  final HermesThemeTokens tokens;
  final String seriesTitle;
  final String rangeLabel;
  final int missingCount;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      alwaysIncludeSemantics: true,
      opacity: 0.85,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: tokens.lineSoft),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: tokens.surface2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: tokens.line),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.layers_outlined,
                size: 24,
                color: tokens.text3,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rangeLabel,
                    style: TextStyle(
                      fontFamily: 'Figtree',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: tokens.text2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    missingCount == 1
                        ? '1 episode isn\'t on the server'
                        : '$missingCount episodes aren\'t on the server',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Figtree',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: tokens.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Add episodes under $seriesTitle and scan the TV Shows library.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Figtree',
                      fontSize: 13,
                      height: 1.4,
                      color: tokens.text2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CastCard extends StatelessWidget {
  const _CastCard({
    required this.member,
    required this.cinemaService,
    required this.tokens,
  });

  final CastMemberModel member;
  final CinemaService cinemaService;
  final HermesThemeTokens tokens;

  @override
  Widget build(BuildContext context) {
    final uri = cinemaService.buildArtworkUri(
      member.artworkHash,
      variant: 'poster_800',
    );
    final initial =
        member.name.trim().isEmpty ? '?' : member.name.trim()[0].toUpperCase();

    return SizedBox(
      width: 108,
      child: Column(
        children: [
          ClipOval(
            child: SizedBox(
              width: 96,
              height: 96,
              child: uri != null
                  ? HermesArtworkImage(
                      uri: uri,
                      fallbackTitle: member.name,
                      width: 96,
                      height: 96,
                      borderRadius: BorderRadius.circular(48),
                      showFallbackLabel: false,
                    )
                  : Container(
                      color: tokens.surface2,
                      alignment: Alignment.center,
                      child: Text(
                        initial,
                        style: TextStyle(
                          fontFamily: 'Figtree',
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: tokens.text2,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            member.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Figtree',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: tokens.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            member.role,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Figtree',
              fontSize: 12,
              color: tokens.text2,
            ),
          ),
        ],
      ),
    );
  }
}

class _FactsTable extends StatelessWidget {
  const _FactsTable({
    required this.tokens,
    required this.genres,
    required this.source,
    required this.addedLabel,
  });

  final HermesThemeTokens tokens;
  final List<String> genres;
  final MediaSourceModel? source;
  final String addedLabel;

  @override
  Widget build(BuildContext context) {
    final audioTracks = source?.audioStreams
            .map((s) => s.title.isEmpty ? s.language.toUpperCase() : s.title)
            .toList(growable: false) ??
        const <String>[];
    final subTracks = source?.subtitleStreams
            .map((s) => s.title.isEmpty ? s.language.toUpperCase() : s.title)
            .toList(growable: false) ??
        const <String>[];

    final videoSummary = source == null
        ? 'Unavailable'
        : '${source!.width}x${source!.height} · ${source!.videoCodec.toUpperCase()}${source!.isHdr ? ' HDR' : ''} · ${(source!.bitrateBps / 1000000).toStringAsFixed(1)} Mbps';
    final audioSummary = source == null
        ? 'Unavailable'
        : audioTracks.isEmpty
            ? source!.audioCodec.toUpperCase()
            : '${source!.audioCodec.toUpperCase()} · Tracks: ${audioTracks.join(', ')}';

    final rows = <(String, String)>[
      if (genres.isNotEmpty) ('Genres', genres.join(', ')),
      ('Video', videoSummary),
      ('Audio', audioSummary),
      (
        'Subtitles',
        subTracks.isEmpty ? 'None indexed' : subTracks.join(', '),
      ),
      ('Container', source?.container.toUpperCase() ?? 'MKV'),
      ('Added', addedLabel),
    ];

    return Column(
      children: rows.map((entry) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                child: Text(
                  entry.$1,
                  style: TextStyle(
                    fontFamily: 'Figtree',
                    fontSize: 14,
                    color: tokens.text2,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  entry.$2,
                  style: TextStyle(
                    fontFamily: 'Figtree',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: tokens.text,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(growable: false),
    );
  }
}
