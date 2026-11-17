import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/settings/hermes_preferences.dart';
import '../../core/theme/hermes_theme_tokens.dart';
import '../../core/widgets/hermes_artwork_image.dart';
import '../../core/widgets/hermes_icons.dart';
import 'cinema_models.dart';
import 'cinema_service.dart';

enum VideoRendererBackend {
  openGl('OpenGL (HDR Safe)'),
  auto('Auto (System)');

  const VideoRendererBackend(this.label);
  final String label;
}

class HermesVideoPlayerConfig {
  const HermesVideoPlayerConfig({
    required this.rendererBackend,
    required this.subtitleColor,
    required this.subtitleBackgroundColor,
    required this.mpvBackendProperties,
  });

  final VideoRendererBackend rendererBackend;
  final Color subtitleColor;
  final Color subtitleBackgroundColor;
  final Map<String, String> mpvBackendProperties;

  factory HermesVideoPlayerConfig.hdrSafeDefault({
    required HermesThemeTokens tokens,
    VideoRendererBackend rendererBackend = VideoRendererBackend.openGl,
  }) {
    final props = <String, String>{
      if (rendererBackend == VideoRendererBackend.openGl) 'gpu-api': 'opengl',
      'sub-color': '#D8D8D8',
      'sub-back-color': '#80000000',
    };

    return HermesVideoPlayerConfig(
      rendererBackend: rendererBackend,
      subtitleColor: tokens.subtitleSafeColor,
      subtitleBackgroundColor: const Color(0x80000000),
      mpvBackendProperties: props,
    );
  }
}

class WatchProgressReporter {
  WatchProgressReporter({
    required this.cinemaService,
    this.movieId,
    this.episodeId,
    required this.getPositionMs,
    required this.getDurationMs,
    this.interval = const Duration(seconds: 10),
  });

  final CinemaService cinemaService;
  final String? movieId;
  final String? episodeId;
  final int Function() getPositionMs;
  final int Function() getDurationMs;
  final Duration interval;

  Timer? _timer;

  void startPeriodic() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) {
      unawaited(reportNow());
    });
  }

  Future<WatchProgressModel?> reportNow({bool? markWatched}) async {
    final duration = getDurationMs();
    if (duration <= 0) {
      return null;
    }

    return cinemaService.updateWatchProgress(
      movieId: movieId,
      episodeId: episodeId,
      positionMs: getPositionMs(),
      durationMs: duration,
      markWatched: markWatched,
    );
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}

class HermesVideoPlayerScreen extends StatefulWidget {
  const HermesVideoPlayerScreen({
    super.key,
    required this.title,
    required this.source,
    required this.initialQuality,
    required this.config,
    required this.cinemaService,
    this.movieId,
    this.episodeId,
    this.subtitleLabel,
    this.backdropUri,
    this.titleTint,
    this.initialPositionMs = 0,
    this.accountPreferences = const HermesAccountPreferences(),
    this.reduceMotion = false,
    this.nextEpisodeCode,
    this.nextEpisodeTitle,
    this.nextEpisodeStillUri,
    this.onPlayNextEpisode,
  });

  final String title;
  final MediaSourceModel source;
  final VideoQualityPreset initialQuality;
  final HermesVideoPlayerConfig config;
  final CinemaService cinemaService;
  final String? movieId;
  final String? episodeId;
  final String? subtitleLabel;
  final Uri? backdropUri;
  final Color? titleTint;
  final int initialPositionMs;
  final HermesAccountPreferences accountPreferences;
  final bool reduceMotion;
  final String? nextEpisodeCode;
  final String? nextEpisodeTitle;
  final Uri? nextEpisodeStillUri;
  final VoidCallback? onPlayNextEpisode;

  @override
  State<HermesVideoPlayerScreen> createState() =>
      _HermesVideoPlayerScreenState();
}

class _HermesVideoPlayerScreenState extends State<HermesVideoPlayerScreen> {
  static const List<VideoQualityPreset> _qualityOrder = [
    VideoQualityPreset.p480,
    VideoQualityPreset.p720,
    VideoQualityPreset.p1080,
    VideoQualityPreset.directPlay,
  ];

  late VideoQualityPreset _quality;
  int _selectedAudioIndex = 1;
  int? _selectedSubtitleIndex;
  Uri? _activeStreamUri;
  Uri? _activeSubtitleUri;
  String? _ticket;
  bool _playing = true;
  late int _positionMs;
  double _volume = 80;
  bool _muted = false;
  bool _panelOpen = false;
  bool _controlsHidden = false;
  bool _upNextDismissed = false;
  Timer? _idleTimer;
  late final WatchProgressReporter _reporter;

  @override
  void initState() {
    super.initState();
    _quality = widget.initialQuality;
    _positionMs = widget.initialPositionMs.clamp(
      0,
      widget.source.durationMs > 0 ? widget.source.durationMs : 1 << 30,
    );

    final defaultAudio = widget.source.audioStreams
            .where((s) => s.isDefault)
            .firstOrNull ??
        widget.source.audioStreams.firstOrNull;
    if (defaultAudio != null) {
      _selectedAudioIndex = defaultAudio.streamIndex;
    }

    _selectedSubtitleIndex = widget.source.subtitleStreams
        .where((s) => s.isDefault)
        .firstOrNull
        ?.streamIndex;

    _reporter = WatchProgressReporter(
      cinemaService: widget.cinemaService,
      movieId: widget.movieId,
      episodeId: widget.episodeId,
      getPositionMs: () => _positionMs,
      getDurationMs: () => widget.source.durationMs,
    );
    _reporter.startPeriodic();
    unawaited(_loadPlaybackUri());
    _wakeControls();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    unawaited(_reporter.reportNow());
    _reporter.dispose();
    super.dispose();
  }

  void _wakeControls() {
    _idleTimer?.cancel();
    if (_controlsHidden) {
      setState(() => _controlsHidden = false);
    }
    if (_playing && !_panelOpen) {
      _idleTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && _playing && !_panelOpen) {
          setState(() => _controlsHidden = true);
        }
      });
    }
  }

  Future<void> _loadPlaybackUri() async {
    try {
      final ticket = _ticket ??
          await widget.cinemaService.issueStreamTicket(widget.source.id);
      _ticket = ticket;
      final streamUri = widget.cinemaService.buildVideoStreamUri(
        mediaSourceId: widget.source.id,
        ticket: ticket,
        quality: _quality,
        audioStreamIndex: _selectedAudioIndex,
        startSeconds: _positionMs ~/ 1000,
      );
      final subUri = _selectedSubtitleIndex == null
          ? null
          : widget.cinemaService.buildSubtitleVttUri(
              mediaSourceId: widget.source.id,
              streamIndex: _selectedSubtitleIndex!,
              ticket: ticket,
            );
      if (mounted) {
        setState(() {
          _activeStreamUri = streamUri;
          _activeSubtitleUri = subUri;
        });
      }
    } catch (_) {
      // Surface kept intact cleanly when running against offline test stubs.
    }
  }

  void _togglePlayPause() {
    setState(() {
      _playing = !_playing;
    });
    _wakeControls();
  }

  void _skipSeconds(int deltaSeconds) {
    final duration = widget.source.durationMs > 0 ? widget.source.durationMs : 1;
    setState(() {
      _positionMs = (_positionMs + deltaSeconds * 1000).clamp(0, duration);
    });
    _wakeControls();
    unawaited(_reporter.reportNow());
  }

  String _formatClock(int ms) {
    final totalSec = (ms / 1000).floor().clamp(0, 86400);
    final h = totalSec ~/ 3600;
    final m = (totalSec % 3600) ~/ 60;
    final s = totalSec % 60;
    final mm = h > 0 ? m.toString().padLeft(2, '0') : m.toString();
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final baseTokens = HermesThemeTokens.of(context);
    final tokens = widget.titleTint != null
        ? baseTokens.withTitleTint(
            widget.titleTint!,
            overrideAccent: widget.accountPreferences.matchTitleColors,
          )
        : baseTokens;

    final duration = widget.source.durationMs <= 0 ? 1 : widget.source.durationMs;
    final remainingMs = (duration - _positionMs).clamp(0, duration);
    final remainingSeconds = (remainingMs / 1000).ceil();
    final showUpNext = widget.nextEpisodeTitle != null &&
        widget.source.durationMs > 0 &&
        remainingSeconds <= 20 &&
        !_upNextDismissed;

    final subBottomOffset = showUpNext
        ? 230.0
        : (_controlsHidden ? 64.0 : 134.0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: MouseRegion(
        cursor:
            _controlsHidden ? SystemMouseCursors.none : SystemMouseCursors.basic,
        onHover: (_) => _wakeControls(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _wakeControls,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Frame placeholder / backdrop
              if (widget.backdropUri != null)
                Opacity(
                  opacity: 0.72,
                  child: HermesArtworkImage(
                    uri: widget.backdropUri,
                    fallbackTitle: widget.title,
                    showFallbackLabel: false,
                    borderRadius: BorderRadius.zero,
                  ),
                ),
              // Center video stream info indicator when controls visible or paused
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 110),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${widget.source.sourceLabel} · ${_quality == VideoQualityPreset.directPlay ? 'Original' : _quality.label}',
                        style: TextStyle(
                          fontFamily: 'Figtree',
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_activeStreamUri != null)
                        Padding(
                          padding: const EdgeInsets.only(
                            top: 4,
                            left: 32,
                            right: 32,
                          ),
                          child: Text(
                            _activeStreamUri.toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // Top & bottom protective scrim gradient
              IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _controlsHidden ? 0.0 : 1.0,
                  duration: widget.reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 280),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.24, 0.60, 1.0],
                        colors: [
                          Colors.black.withValues(alpha: 0.72),
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.88),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Live HDR-safe Subtitles (#D8D8D8)
              if (_selectedSubtitleIndex != null)
                AnimatedPositioned(
                  duration: widget.reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  left: 32,
                  right: 32,
                  bottom: subBottomOffset,
                  child: Center(
                    child: _PlayerSubtitleCaption(
                      text: _activeSubtitleUri == null
                          ? 'Subtitles enabled (#D8D8D8 HDR-safe)'
                          : 'WebVTT Subtitles Ready (#D8D8D8)',
                      color: widget.config.subtitleColor,
                      sizePreset: widget.accountPreferences.subtitleSize,
                      backgroundStyle:
                          widget.accountPreferences.subtitleBackground,
                    ),
                  ),
                ),
              // Up Next 20s Card (TV Episodes)
              if (showUpNext)
                Positioned(
                  right: 24,
                  left: 24,
                  bottom: 124,
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: _UpNextCard(
                      tokens: tokens,
                      autoplay: widget.accountPreferences.autoplayNextEpisode,
                      remainingSeconds: remainingSeconds,
                      episodeCode: widget.nextEpisodeCode ?? '',
                      episodeTitle: widget.nextEpisodeTitle!,
                      stillUri: widget.nextEpisodeStillUri,
                      onPlayNow: () {
                        widget.onPlayNextEpisode?.call();
                      },
                      onDismiss: () {
                        setState(() => _upNextDismissed = true);
                      },
                    ),
                  ),
                ),
              // Auto-hiding HUD Chrome
              AnimatedOpacity(
                opacity: _controlsHidden ? 0.0 : 1.0,
                duration: widget.reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 280),
                child: IgnorePointer(
                  ignoring: _controlsHidden,
                  child: SafeArea(
                    child: Stack(
                      children: [
                        // Top bar
                        Positioned(
                          left: 24,
                          right: 24,
                          top: 16,
                          child: Row(
                            children: [
                              InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () => Navigator.of(context).pop(),
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
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontFamily: 'Figtree',
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                    if (widget.subtitleLabel != null &&
                                        widget.subtitleLabel!.isNotEmpty)
                                      Text(
                                        widget.subtitleLabel!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily: 'Figtree',
                                          fontSize: 13,
                                          color: Colors.white
                                              .withValues(alpha: 0.72),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Text(
                                  widget.config.rendererBackend ==
                                          VideoRendererBackend.openGl
                                      ? 'OpenGL HDR'
                                      : 'Auto GPU',
                                  style: const TextStyle(
                                    fontFamily: 'Figtree',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Center skip & Play/Pause cluster
                        Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Back 10 seconds',
                                onPressed: () => _skipSeconds(-10),
                                icon: const Icon(
                                  Icons.replay_10_rounded,
                                  size: 40,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 44),
                              Semantics(
                                button: true,
                                label: _playing ? 'Pause' : 'Play',
                                child: InkWell(
                                  key: const Key('vp-center-play-btn'),
                                  customBorder: const CircleBorder(),
                                  onTap: _togglePlayPause,
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: _playing
                                        ? const HermesPauseIcon(
                                            size: 52,
                                            color: Colors.white,
                                          )
                                        : const HermesPlayIcon(
                                            size: 52,
                                            color: Colors.white,
                                          ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 44),
                              IconButton(
                                tooltip: 'Forward 10 seconds',
                                onPressed: () => _skipSeconds(10),
                                icon: const Icon(
                                  Icons.forward_10_rounded,
                                  size: 40,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Bottom controls bar
                        Positioned(
                          left: 24,
                          right: 24,
                          bottom: 20,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    _formatClock(_positionMs),
                                    style: TextStyle(
                                      fontFamily: 'Figtree',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color:
                                          Colors.white.withValues(alpha: 0.85),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        activeTrackColor: tokens.accent,
                                        inactiveTrackColor:
                                            Colors.white.withValues(alpha: 0.24),
                                        thumbColor: tokens.accent,
                                        trackHeight: 4,
                                      ),
                                      child: Slider(
                                        value: _positionMs
                                            .clamp(0, duration)
                                            .toDouble(),
                                        max: duration.toDouble(),
                                        onChanged: (val) {
                                          setState(() => _positionMs = val.toInt());
                                          _wakeControls();
                                        },
                                        onChangeEnd: (_) =>
                                            unawaited(_reporter.reportNow()),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    '-${_formatClock(remainingMs)}',
                                    style: TextStyle(
                                      fontFamily: 'Figtree',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color:
                                          Colors.white.withValues(alpha: 0.85),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  IconButton(
                                    key: const Key('vp-bottom-play-btn'),
                                    tooltip: _playing ? 'Pause' : 'Play',
                                    onPressed: _togglePlayPause,
                                    icon: _playing
                                        ? const HermesPauseIcon(
                                            size: 20,
                                            color: Colors.white,
                                          )
                                        : const HermesPlayIcon(
                                            size: 20,
                                            color: Colors.white,
                                          ),
                                  ),
                                  IconButton(
                                    tooltip: 'Back 10s',
                                    onPressed: () => _skipSeconds(-10),
                                    icon: const Icon(
                                      Icons.replay_10_rounded,
                                      size: 22,
                                      color: Colors.white,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Forward 10s',
                                    onPressed: () => _skipSeconds(10),
                                    icon: const Icon(
                                      Icons.forward_10_rounded,
                                      size: 22,
                                      color: Colors.white,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: _muted ? 'Unmute' : 'Mute',
                                    onPressed: () =>
                                        setState(() => _muted = !_muted),
                                    icon: Icon(
                                      _muted || _volume == 0
                                          ? Icons.volume_off_rounded
                                          : Icons.volume_up_rounded,
                                      size: 20,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(
                                    width: 84,
                                    child: SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        activeTrackColor: Colors.white,
                                        inactiveTrackColor:
                                            Colors.white.withValues(alpha: 0.25),
                                        thumbColor: Colors.white,
                                        trackHeight: 3,
                                        thumbShape: const RoundSliderThumbShape(
                                          enabledThumbRadius: 5,
                                        ),
                                        overlayShape:
                                            const RoundSliderOverlayShape(
                                          overlayRadius: 10,
                                        ),
                                      ),
                                      child: Slider(
                                        value: _muted ? 0 : _volume,
                                        max: 100,
                                        onChanged: (next) => setState(() {
                                          _volume = next;
                                          _muted = next == 0;
                                        }),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _quality == VideoQualityPreset.directPlay
                                          ? 'Direct Play · original quality'
                                          : 'Converting to ${_quality.label}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontFamily: 'Figtree',
                                        fontSize: 13,
                                        color:
                                            Colors.white.withValues(alpha: 0.68),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    key: const Key('vp-tracks-btn'),
                                    tooltip: 'Audio, subtitles & quality',
                                    onPressed: () {
                                      setState(() => _panelOpen = !_panelOpen);
                                      _wakeControls();
                                    },
                                    icon: Icon(
                                      Icons.subtitles_outlined,
                                      size: 22,
                                      color: _panelOpen
                                          ? tokens.accent
                                          : Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // 3-Column Tracks & Quality Panel (.vp-panel)
                        if (_panelOpen)
                          Positioned(
                            right: 24,
                            bottom: 92,
                            child: _TracksAndQualityPanel(
                              tokens: tokens,
                              source: widget.source,
                              selectedAudioIndex: _selectedAudioIndex,
                              selectedSubtitleIndex: _selectedSubtitleIndex,
                              selectedQuality: _quality,
                              qualityOrder: _qualityOrder,
                              onSelectAudio: (idx) {
                                setState(() => _selectedAudioIndex = idx);
                                unawaited(_loadPlaybackUri());
                              },
                              onSelectSubtitle: (idx) {
                                setState(() => _selectedSubtitleIndex = idx);
                                unawaited(_loadPlaybackUri());
                              },
                              onSelectQuality: (q) {
                                setState(() => _quality = q);
                                unawaited(_loadPlaybackUri());
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerSubtitleCaption extends StatelessWidget {
  const _PlayerSubtitleCaption({
    required this.text,
    required this.color,
    required this.sizePreset,
    required this.backgroundStyle,
  });

  final String text;
  final Color color;
  final SubtitleSizePreset sizePreset;
  final SubtitleBackgroundStyle backgroundStyle;

  @override
  Widget build(BuildContext context) {
    final shadows = switch (backgroundStyle) {
      SubtitleBackgroundStyle.shadow => const [
          Shadow(
            color: Color(0xE6000000),
            offset: Offset(0, 2),
            blurRadius: 4,
          ),
          Shadow(
            color: Color(0xE6000000),
            offset: Offset(0, 0),
            blurRadius: 2,
          ),
        ],
      _ => null,
    };

    return Container(
      padding: backgroundStyle == SubtitleBackgroundStyle.box
          ? const EdgeInsets.symmetric(horizontal: 14, vertical: 6)
          : EdgeInsets.zero,
      decoration: backgroundStyle == SubtitleBackgroundStyle.box
          ? BoxDecoration(
              color: const Color(0xBF000000),
              borderRadius: BorderRadius.circular(4),
            )
          : null,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Figtree',
          color: color,
          fontSize: sizePreset.playerFontSize,
          fontWeight: FontWeight.w600,
          height: 1.3,
          shadows: shadows,
        ),
      ),
    );
  }
}

class _TracksAndQualityPanel extends StatelessWidget {
  const _TracksAndQualityPanel({
    required this.tokens,
    required this.source,
    required this.selectedAudioIndex,
    required this.selectedSubtitleIndex,
    required this.selectedQuality,
    required this.qualityOrder,
    required this.onSelectAudio,
    required this.onSelectSubtitle,
    required this.onSelectQuality,
  });

  final HermesThemeTokens tokens;
  final MediaSourceModel source;
  final int selectedAudioIndex;
  final int? selectedSubtitleIndex;
  final VideoQualityPreset selectedQuality;
  final List<VideoQualityPreset> qualityOrder;
  final ValueChanged<int> onSelectAudio;
  final ValueChanged<int?> onSelectSubtitle;
  final ValueChanged<VideoQualityPreset> onSelectQuality;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        key: const Key('vp-panel'),
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 320),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xF0101010),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: tokens.line),
          boxShadow: const [
            BoxShadow(
              color: Color(0x80000000),
              blurRadius: 36,
              offset: Offset(0, 16),
            ),
          ],
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PanelColumn(
                title: 'Audio',
                tokens: tokens,
                items: source.audioStreams.isEmpty
                    ? [
                        _PanelOption(
                          label: source.audioCodec.isEmpty
                              ? 'Default audio'
                              : source.audioCodec.toUpperCase(),
                          active: true,
                          onTap: () {},
                        ),
                      ]
                    : source.audioStreams
                        .map(
                          (s) => _PanelOption(
                            label: '${s.language.toUpperCase()} (${s.codec})',
                            active: selectedAudioIndex == s.streamIndex,
                            onTap: () => onSelectAudio(s.streamIndex),
                          ),
                        )
                        .toList(growable: false),
              ),
              const SizedBox(width: 12),
              _PanelColumn(
                title: 'Subtitles',
                tokens: tokens,
                items: [
                  _PanelOption(
                    label: 'Off',
                    active: selectedSubtitleIndex == null,
                    onTap: () => onSelectSubtitle(null),
                  ),
                  ...source.subtitleStreams.map(
                    (s) => _PanelOption(
                      label: '${s.language.toUpperCase()} (${s.title})',
                      active: selectedSubtitleIndex == s.streamIndex,
                      onTap: () => onSelectSubtitle(s.streamIndex),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              _PanelColumn(
                title: 'Quality',
                tokens: tokens,
                items: qualityOrder
                    .map(
                      (q) => _PanelOption(
                        label: q == VideoQualityPreset.directPlay
                            ? 'Original · ${source.shortTag}'
                            : q.label,
                        active: selectedQuality == q,
                        onTap: () => onSelectQuality(q),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PanelColumn extends StatelessWidget {
  const _PanelColumn({
    required this.title,
    required this.tokens,
    required this.items,
  });

  final String title;
  final HermesThemeTokens tokens;
  final List<_PanelOption> items;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 150),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Text(
                title,
                style: TextStyle(
                  fontFamily: 'Figtree',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ),
            ...items.map(
              (item) => InkWell(
                borderRadius: BorderRadius.circular(6),
                hoverColor: Colors.white.withValues(alpha: 0.1),
                onTap: item.onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 18,
                        child: item.active
                            ? Icon(
                                Icons.check_rounded,
                                size: 16,
                                color: tokens.accent,
                              )
                            : null,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontFamily: 'Figtree',
                          fontSize: 14,
                          fontWeight:
                              item.active ? FontWeight.w700 : FontWeight.w500,
                          color: item.active
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelOption {
  const _PanelOption({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
}

class _UpNextCard extends StatelessWidget {
  const _UpNextCard({
    required this.tokens,
    required this.autoplay,
    required this.remainingSeconds,
    required this.episodeCode,
    required this.episodeTitle,
    required this.stillUri,
    required this.onPlayNow,
    required this.onDismiss,
  });

  final HermesThemeTokens tokens;
  final bool autoplay;
  final int remainingSeconds;
  final String episodeCode;
  final String episodeTitle;
  final Uri? stillUri;
  final VoidCallback onPlayNow;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final countdownProgress =
        ((20 - remainingSeconds.clamp(0, 20)) / 20.0).clamp(0.0, 1.0);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Container(
        key: const Key('vp-upnext-card'),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xE0101010),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: tokens.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 112,
                      height: 63,
                      child: HermesArtworkImage(
                        uri: stillUri,
                        fallbackTitle: episodeTitle,
                        showFallbackLabel: false,
                        borderRadius: BorderRadius.zero,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          autoplay
                              ? 'Next episode in ${remainingSeconds.clamp(1, 20)}s'
                              : 'Next episode',
                          style: TextStyle(
                            fontFamily: 'Figtree',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: 0.65),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          episodeCode.isEmpty
                              ? episodeTitle
                              : '$episodeCode · $episodeTitle',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Figtree',
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: onPlayNow,
                              child: Container(
                                height: 32,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    HermesPlayIcon(
                                      size: 14,
                                      color: Color(0xFF0B0B0B),
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'Play now',
                                      style: TextStyle(
                                        fontFamily: 'Figtree',
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF0B0B0B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: onDismiss,
                              child: Container(
                                height: 32,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Center(
                                  widthFactor: 1.0,
                                  child: Text(
                                    'Watch credits',
                                    style: TextStyle(
                                      fontFamily: 'Figtree',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (autoplay)
              LinearProgressIndicator(
                value: countdownProgress,
                minHeight: 3,
                color: tokens.accent,
                backgroundColor: Colors.transparent,
              ),
          ],
        ),
      ),
    );
  }
}
