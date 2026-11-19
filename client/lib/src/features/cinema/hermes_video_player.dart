import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/media/hermes_media_runtime.dart';
import '../../core/settings/hermes_preferences.dart';
import '../../core/theme/hermes_theme_tokens.dart';
import '../../core/widgets/hermes_artwork_image.dart';
import '../../core/widgets/hermes_icons.dart';
import '../../core/window/hermes_window_bridge.dart';
import 'cinema_models.dart';
import 'cinema_service.dart';
import 'hermes_video_playback_controller.dart';

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

typedef HermesVideoControllerFactory = HermesVideoPlaybackController Function(
  HermesVideoPlayerConfig config,
);

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
    this.playbackControllerFactory,
    this.windowBridge,
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
  final HermesVideoControllerFactory? playbackControllerFactory;
  final HermesWindowBridge? windowBridge;

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
  late final String _clientSessionKey =
      'p-${DateTime.now().microsecondsSinceEpoch}';
  bool _startedHls = false;
  bool _playing = true;
  bool _buffering = false;
  bool _scrubbing = false;
  bool _hasVideoFrame = false;
  late int _positionMs;
  int _engineDurationMs = 0;
  int _hlsAnchorMs = 0;
  double _volume = 80;
  bool _muted = false;
  bool _panelOpen = false;
  bool _controlsHidden = false;
  bool _upNextDismissed = false;
  bool _completionHandled = false;
  bool _isFullscreen = false;
  VideoAspectMode _aspectMode = VideoAspectMode.fit;
  String? _hudLabel;
  Timer? _hudTimer;
  double _subtitleDelaySeconds = 0.0;
  double _subtitleVerticalOffset = 0.0;
  late SubtitleSizePreset _subtitleSize = widget.accountPreferences.subtitleSize;
  late SubtitleBackgroundStyle _subtitleBackground =
      widget.accountPreferences.subtitleBackground;
  late Color _subtitleColor = widget.config.subtitleColor;
  final FocusNode _playerFocusNode = FocusNode();
  late final HermesWindowBridge _windowBridge =
      widget.windowBridge ?? HermesWindowBridge.instance;
  List<String> _liveSubtitleLines = const [];
  String? _playbackError;
  Timer? _idleTimer;
  late final WatchProgressReporter _reporter;
  late final HermesVideoPlaybackController _playback;
  StreamSubscription<int>? _posSub;
  StreamSubscription<int>? _durSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<List<String>>? _subLinesSub;
  StreamSubscription<String>? _errorSub;

  bool get _isRealMobileRuntime =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  bool get _isMobilePlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    _quality = widget.initialQuality;
    _positionMs = widget.initialPositionMs.clamp(
      0,
      widget.source.durationMs > 0 ? widget.source.durationMs : 1 << 30,
    );

    if (_isRealMobileRuntime) {
      _isFullscreen = true;
      unawaited(
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.immersiveSticky,
          overlays: const [],
        ),
      );
      unawaited(
        SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]),
      );
    }

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

    _playback = widget.playbackControllerFactory?.call(widget.config) ??
        (HermesMediaRuntime.isInitialized
            ? MediaKitVideoPlaybackController(config: widget.config)
            : StubVideoPlaybackController());
    _attachPlaybackListeners();

    _reporter = WatchProgressReporter(
      cinemaService: widget.cinemaService,
      movieId: widget.movieId,
      episodeId: widget.episodeId,
      getPositionMs: () => _positionMs,
      getDurationMs: _effectiveDurationMs,
    );
    _reporter.startPeriodic();
    unawaited(_loadPlaybackUri());
    _wakeControls();
  }

  int _effectiveDurationMs() {
    if (widget.source.durationMs > 0) {
      return widget.source.durationMs;
    }
    return _hlsAnchorMs + _engineDurationMs;
  }

  void _attachPlaybackListeners() {
    _posSub = _playback.positionMsStream.listen((enginePosMs) {
      if (!mounted || _scrubbing) return;
      final absolute = (_hlsAnchorMs + enginePosMs).clamp(
        0,
        _effectiveDurationMs() > 0 ? _effectiveDurationMs() : 1 << 30,
      );
      if (absolute > 0 && !_hasVideoFrame) {
        _hasVideoFrame = true;
      }
      if ((absolute - _positionMs).abs() >= 250 ||
          (absolute == 0 && _positionMs != 0)) {
        setState(() {
          _positionMs = absolute;
        });
      }
    });

    _durSub = _playback.durationMsStream.listen((durMs) {
      if (!mounted || durMs <= 0) return;
      setState(() {
        _engineDurationMs = durMs;
        _hasVideoFrame = true;
      });
    });

    _playingSub = _playback.playingStream.listen((playing) {
      if (!mounted || _playing == playing) return;
      setState(() => _playing = playing);
      _wakeControls();
    });

    _bufferingSub = _playback.bufferingStream.listen((buffering) {
      if (!mounted || _buffering == buffering) return;
      setState(() => _buffering = buffering);
    });

    _completedSub = _playback.completedStream.listen((completed) {
      if (!mounted || !completed || _completionHandled) return;
      _completionHandled = true;
      unawaited(_reporter.reportNow(markWatched: true));
      if (widget.accountPreferences.autoplayNextEpisode &&
          !_upNextDismissed &&
          widget.onPlayNextEpisode != null) {
        widget.onPlayNextEpisode!();
      }
    });

    _subLinesSub = _playback.subtitleLinesStream.listen((lines) {
      if (!mounted) return;
      setState(() => _liveSubtitleLines = lines);
    });

    _errorSub = _playback.errorStream.listen((message) {
      if (!mounted) return;
      setState(() => _playbackError = message);
    });
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _hudTimer?.cancel();
    unawaited(_posSub?.cancel());
    unawaited(_durSub?.cancel());
    unawaited(_playingSub?.cancel());
    unawaited(_bufferingSub?.cancel());
    unawaited(_completedSub?.cancel());
    unawaited(_subLinesSub?.cancel());
    unawaited(_errorSub?.cancel());
    unawaited(_reporter.reportNow());
    _reporter.dispose();
    if (_startedHls && _ticket != null) {
      unawaited(
        widget.cinemaService.stopClientHlsSessions(
          mediaSourceId: widget.source.id,
          clientSession: _clientSessionKey,
          ticket: _ticket!,
        ),
      );
    }
    if (_isFullscreen) {
      unawaited(
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.edgeToEdge,
          overlays: SystemUiOverlay.values,
        ),
      );
      if (_isMobilePlatform) {
        unawaited(SystemChrome.setPreferredOrientations(DeviceOrientation.values));
      } else {
        unawaited(_windowBridge.setFullscreen(false));
      }
    }
    _playerFocusNode.dispose();
    unawaited(_playback.dispose());
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

  MediaStreamModel? _findSubtitleStream(int? streamIndex) {
    if (streamIndex == null) return null;
    return widget.source.subtitleStreams
        .where((s) => s.streamIndex == streamIndex)
        .firstOrNull;
  }

  Future<String> _ensureTicket() async {
    final existing = _ticket;
    if (existing != null) return existing;
    final issued = await widget.cinemaService.issueStreamTicket(widget.source.id);
    _ticket = issued;
    return issued;
  }

  Future<void> _loadPlaybackUri({
    int? overridePositionMs,
    bool forceFreshTicket = false,
  }) async {
    try {
      if (forceFreshTicket) {
        final prevTicket = _ticket;
        _ticket = null;
        try {
          _ticket = await widget.cinemaService.issueStreamTicket(widget.source.id);
        } catch (_) {
          _ticket = prevTicket;
        }
      }
      final ticket = await _ensureTicket();
      final targetPosMs = overridePositionMs ?? _positionMs;
      final isDirect = _quality == VideoQualityPreset.directPlay;
      final anchorMs = isDirect ? 0 : (targetPosMs ~/ 1000) * 1000;
      if (!isDirect) {
        _startedHls = true;
      }
      final streamUri = widget.cinemaService.buildVideoStreamUri(
        mediaSourceId: widget.source.id,
        ticket: ticket,
        quality: _quality,
        audioStreamIndex: _selectedAudioIndex,
        startSeconds: targetPosMs ~/ 1000,
        clientSession: isDirect ? null : _clientSessionKey,
      );
      final subStream = _findSubtitleStream(_selectedSubtitleIndex);
      final subUri = _selectedSubtitleIndex == null
          ? null
          : widget.cinemaService.buildSubtitleVttUri(
              mediaSourceId: widget.source.id,
              streamIndex: _selectedSubtitleIndex!,
              ticket: ticket,
            );
      if (mounted) {
        setState(() {
          _hlsAnchorMs = anchorMs;
          _completionHandled = false;
          _playbackError = null;
          _activeStreamUri = streamUri;
          _activeSubtitleUri = subUri;
        });
      }
      await _playback.open(
        streamUri,
        startPositionMs: isDirect ? targetPosMs : 0,
        subtitleUri: subUri,
        subtitleTitle: subStream?.title,
        subtitleLanguage: subStream?.language,
        autoPlay: _playing,
      );
      await _playback.setVolume(_muted ? 0 : _volume);
    } catch (_) {
      // Surface kept intact cleanly when running against offline test stubs.
    }
  }

  Future<void> _applySubtitleSelection(int? streamIndex) async {
    Uri? subUri;
    MediaStreamModel? subStream;
    if (streamIndex != null) {
      subStream = _findSubtitleStream(streamIndex);
      try {
        final ticket = await _ensureTicket();
        subUri = widget.cinemaService.buildSubtitleVttUri(
          mediaSourceId: widget.source.id,
          streamIndex: streamIndex,
          ticket: ticket,
        );
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _selectedSubtitleIndex = streamIndex;
        _activeSubtitleUri = subUri;
        if (streamIndex == null) {
          _liveSubtitleLines = const [];
        }
      });
    }
    await _playback.setExternalSubtitle(
      subUri,
      title: subStream?.title,
      language: subStream?.language,
    );
  }

  Future<void> _applyAudioSelection(int streamIndex) async {
    setState(() => _selectedAudioIndex = streamIndex);
    if (_quality == VideoQualityPreset.directPlay) {
      await _playback.selectEmbeddedAudioTrack(
        streamIndex: streamIndex,
        availableAudioStreams: widget.source.audioStreams,
      );
      return;
    }
    await _loadPlaybackUri();
  }

  void _togglePlayPause() {
    final nextPlaying = !_playing;
    setState(() {
      _playing = nextPlaying;
    });
    if (nextPlaying) {
      unawaited(_playback.play());
    } else {
      unawaited(_playback.pause());
    }
    _wakeControls();
  }

  Future<void> _seekToPositionMs(int targetMs) async {
    final duration = _effectiveDurationMs() > 0 ? _effectiveDurationMs() : 1;
    final clamped = targetMs.clamp(0, duration);
    setState(() {
      _positionMs = clamped;
      _completionHandled = false;
    });
    _wakeControls();

    if (_quality == VideoQualityPreset.directPlay) {
      await _playback.seek(clamped);
    } else {
      final relativeTargetMs = clamped - _hlsAnchorMs;
      if (relativeTargetMs >= 0 &&
          _engineDurationMs > 0 &&
          relativeTargetMs <= _engineDurationMs) {
        await _playback.seek(relativeTargetMs);
      } else {
        await _loadPlaybackUri(overridePositionMs: clamped);
      }
    }
    await _reporter.reportNow();
  }

  void _skipSeconds(int deltaSeconds) {
    unawaited(_seekToPositionMs(_positionMs + deltaSeconds * 1000));
  }

  void _showHud(String message) {
    _hudTimer?.cancel();
    if (!mounted) return;
    setState(() => _hudLabel = message);
    _hudTimer = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) {
        setState(() => _hudLabel = null);
      }
    });
  }

  void _setAspectMode(VideoAspectMode mode) {
    if (_aspectMode == mode) return;
    setState(() => _aspectMode = mode);
    _showHud('Display: ${mode.label}');
    _wakeControls();
  }

  void _cycleAspectMode() {
    const modes = VideoAspectMode.values;
    final next = modes[(_aspectMode.index + 1) % modes.length];
    _setAspectMode(next);
  }

  void _nudgeVolume(double delta) {
    final current = _muted ? 0.0 : _volume;
    final next = (current + delta).clamp(0.0, 100.0);
    setState(() {
      _volume = next;
      _muted = next <= 0.0;
    });
    unawaited(_playback.setVolume(_muted ? 0.0 : _volume));
    _showHud(_muted ? 'Muted' : 'Volume ${_volume.round()}%');
    _wakeControls();
  }

  void _toggleMute() {
    final nextMuted = !_muted;
    setState(() => _muted = nextMuted);
    unawaited(_playback.setVolume(nextMuted ? 0 : _volume));
    _showHud(nextMuted ? 'Muted' : 'Volume ${_volume.round()}%');
    _wakeControls();
  }

  void _toggleFullscreenMode() {
    final next = !_isFullscreen;
    setState(() => _isFullscreen = next);
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        next ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
        overlays: next ? const [] : SystemUiOverlay.values,
      ),
    );
    if (_isMobilePlatform) {
      unawaited(
        SystemChrome.setPreferredOrientations(
          next
              ? const [
                  DeviceOrientation.landscapeLeft,
                  DeviceOrientation.landscapeRight,
                ]
              : DeviceOrientation.values,
        ),
      );
    } else {
      unawaited(_windowBridge.setFullscreen(next));
    }
    _wakeControls();
  }

  KeyEventResult _handleKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyK) {
      _togglePlayPause();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.keyJ) {
      _skipSeconds(-10);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.keyL) {
      _skipSeconds(10);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _nudgeVolume(5);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _nudgeVolume(-5);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyM) {
      _toggleMute();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyA) {
      _cycleAspectMode();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF || key == LogicalKeyboardKey.f11) {
      _toggleFullscreenMode();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (_panelOpen) {
        setState(() => _panelOpen = false);
      } else if (_isFullscreen) {
        _toggleFullscreenMode();
      } else {
        unawaited(Navigator.of(context).maybePop());
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _setSubtitleDelay(double nextSeconds) {
    final stepped = (nextSeconds * 4).round() / 4.0;
    final clamped = stepped.clamp(-5.0, 5.0);
    setState(() => _subtitleDelaySeconds = clamped);
    _wakeControls();
    unawaited(_playback.setSubtitleDelaySeconds(clamped));
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

    final duration = _effectiveDurationMs() <= 0 ? 1 : _effectiveDurationMs();
    final remainingMs = (duration - _positionMs).clamp(0, duration);
    final remainingSeconds = (remainingMs / 1000).ceil();
    final showUpNext = widget.nextEpisodeTitle != null &&
        duration > 1 &&
        remainingSeconds <= 20 &&
        !_upNextDismissed;

    final viewportHeight = MediaQuery.sizeOf(context).height;
    final baseSubBottomOffset = showUpNext
        ? 230.0
        : (_controlsHidden ? 56.0 : 128.0);
    final subBottomOffset = (baseSubBottomOffset + _subtitleVerticalOffset)
        .clamp(16.0, math.max<double>(96.0, viewportHeight * 0.48))
        .toDouble();

    final liveSubText = _liveSubtitleLines
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n');
    final subtitleDisplayText = _selectedSubtitleIndex == null
        ? ''
        : liveSubText.isNotEmpty
            ? liveSubText
            : (!_playback.hasVideoOutput
                ? (_activeSubtitleUri == null
                    ? 'Subtitles enabled (#D8D8D8 HDR-safe)'
                    : 'WebVTT Subtitles Ready (#D8D8D8)')
                : '');

    return Focus(
      focusNode: _playerFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: MouseRegion(
        cursor:
            _controlsHidden ? SystemMouseCursors.none : SystemMouseCursors.basic,
        onHover: (_) => _wakeControls(),
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _wakeControls(),
          onPointerSignal: (event) {
            if (!_panelOpen && event is PointerScrollEvent) {
              _nudgeVolume(event.scrollDelta.dy < 0 ? 5 : -5);
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _wakeControls,
            onDoubleTap: _isMobilePlatform ? null : _toggleFullscreenMode,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_playback.hasVideoOutput)
                  Positioned.fill(
                    child: _playback.buildVideoSurface(
                      context,
                      fit: _aspectMode.boxFit,
                    ),
                  ),
              // Frame placeholder / backdrop before video frames start rendering
              if ((!_playback.hasVideoOutput || !_hasVideoFrame) &&
                  widget.backdropUri != null)
                ExcludeSemantics(
                  child: Opacity(
                    alwaysIncludeSemantics: true,
                    opacity: 0.72,
                    child: HermesArtworkImage(
                      uri: widget.backdropUri,
                      fallbackTitle: widget.title,
                      showFallbackLabel: false,
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                ),
              // Center stream metadata (visible on stub backend without native surface)
              if (!_playback.hasVideoOutput)
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
              if (_playback.hasVideoOutput && _buffering && _playbackError == null)
                const Center(
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Colors.white70,
                    ),
                  ),
                ),
              if (_playbackError != null)
                Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 420),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xD9101010),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: tokens.accent),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Playback failed',
                          style: TextStyle(
                            fontFamily: 'Figtree',
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: tokens.text,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _playbackError!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Figtree',
                            fontSize: 13,
                            color: tokens.text2,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () => unawaited(_loadPlaybackUri()),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              // Top & bottom protective scrim gradient
              IgnorePointer(
                child: ExcludeSemantics(
                  child: AnimatedOpacity(
                    alwaysIncludeSemantics: true,
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
              ),
              // Live HDR-safe Subtitles (#D8D8D8)
              if (subtitleDisplayText.isNotEmpty)
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
                      text: subtitleDisplayText,
                      color: _subtitleColor,
                      sizePreset: _subtitleSize,
                      backgroundStyle: _subtitleBackground,
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
                alwaysIncludeSemantics: true,
                opacity: _controlsHidden ? 0.0 : 1.0,
                duration: widget.reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 280),
                child: IgnorePointer(
                  ignoring: _controlsHidden,
                  child: SafeArea(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final availWidth = constraints.maxWidth;
                        final availHeight = constraints.maxHeight;
                        final isShortOrNarrow =
                            availWidth < 760 || availHeight < 540;
                        final isLandscapeDock =
                            isShortOrNarrow && availWidth >= 560;
                        final panelMaxWidth = isLandscapeDock
                            ? math.min(380.0, availWidth * 0.56)
                            : (isShortOrNarrow
                                ? math.max(240.0, availWidth - 24)
                                : math.min(640.0, math.max(320.0, availWidth - 48)));
                        final panelMaxHeight = isLandscapeDock
                            ? (availHeight - 86).clamp(160.0, 560.0)
                            : (isShortOrNarrow
                                ? math
                                    .min(availHeight * 0.58, availHeight - 104)
                                    .clamp(160.0, 440.0)
                                : math
                                    .min(400.0, availHeight - 116)
                                    .clamp(200.0, 400.0));

                        return Stack(
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
                                container: true,
                                button: true,
                                excludeSemantics: true,
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
                                        onChangeStart: (_) {
                                          setState(() => _scrubbing = true);
                                        },
                                        onChanged: (val) {
                                          setState(() => _positionMs = val.toInt());
                                          _wakeControls();
                                        },
                                        onChangeEnd: (val) {
                                          setState(() => _scrubbing = false);
                                          unawaited(
                                            _seekToPositionMs(val.round()),
                                          );
                                        },
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
                                    tooltip: _muted ? 'Unmute (M)' : 'Mute (M)',
                                    onPressed: _toggleMute,
                                    icon: Icon(
                                      _muted || _volume == 0
                                          ? Icons.volume_off_rounded
                                          : Icons.volume_up_rounded,
                                      size: 20,
                                      color: Colors.white,
                                    ),
                                  ),
                                  if (MediaQuery.sizeOf(context).width >= 640) ...[
                                    SizedBox(
                                      width: 84,
                                      child: SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          activeTrackColor: Colors.white,
                                          inactiveTrackColor: Colors.white
                                              .withValues(alpha: 0.25),
                                          thumbColor: Colors.white,
                                          trackHeight: 3,
                                          thumbShape:
                                              const RoundSliderThumbShape(
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
                                          onChanged: (next) {
                                            setState(() {
                                              _volume = next;
                                              _muted = next == 0;
                                            });
                                            unawaited(
                                              _playback.setVolume(next),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
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
                                    key: const Key('vp-aspect-btn'),
                                    tooltip:
                                        'Display: ${_aspectMode.label} (A)',
                                    onPressed: _cycleAspectMode,
                                    icon: Icon(
                                      Icons.aspect_ratio_rounded,
                                      size: 21,
                                      color: _aspectMode != VideoAspectMode.fit
                                          ? tokens.accent
                                          : Colors.white,
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
                                  IconButton(
                                    key: const Key('vp-fullscreen-btn'),
                                    tooltip: _isFullscreen
                                        ? 'Exit fullscreen (F)'
                                        : 'Fullscreen (F)',
                                    onPressed: _toggleFullscreenMode,
                                    icon: Icon(
                                      _isFullscreen
                                          ? Icons.fullscreen_exit_rounded
                                          : Icons.fullscreen_rounded,
                                      size: 22,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Nuvio-style Viewport-Bounded Scrollable Tracks & Subtitle Style Panel
                        if (_panelOpen)
                          Positioned(
                            top: isLandscapeDock ? 12 : null,
                            left: isLandscapeDock
                                ? null
                                : (isShortOrNarrow ? 12 : null),
                            right: isShortOrNarrow ? 12 : 24,
                            bottom: isLandscapeDock
                                ? 74
                                : (isShortOrNarrow ? 80 : 92),
                            width: isLandscapeDock ? panelMaxWidth : null,
                            child: Listener(
                              onPointerDown: (_) => _wakeControls(),
                              child: _TracksAndQualityPanel(
                                tokens: tokens,
                                source: widget.source,
                                compact: isShortOrNarrow,
                                maxWidth: panelMaxWidth,
                                maxHeight: panelMaxHeight,
                                selectedAudioIndex: _selectedAudioIndex,
                                selectedSubtitleIndex: _selectedSubtitleIndex,
                                selectedQuality: _quality,
                                selectedAspectMode: _aspectMode,
                                qualityOrder: _qualityOrder,
                                subtitleDelaySeconds: _subtitleDelaySeconds,
                                subtitleVerticalOffset: _subtitleVerticalOffset,
                                subtitleSize: _subtitleSize,
                                subtitleBackground: _subtitleBackground,
                                subtitleColor: _subtitleColor,
                                onInteraction: _wakeControls,
                                onClose: () =>
                                    setState(() => _panelOpen = false),
                                onSelectAudio: (idx) {
                                  _wakeControls();
                                  unawaited(_applyAudioSelection(idx));
                                },
                                onSelectSubtitle: (idx) {
                                  _wakeControls();
                                  unawaited(_applySubtitleSelection(idx));
                                },
                                onSelectQuality: (q) {
                                  _wakeControls();
                                  setState(() => _quality = q);
                                  unawaited(
                                    _loadPlaybackUri(
                                      forceFreshTicket:
                                          q != VideoQualityPreset.directPlay,
                                    ),
                                  );
                                },
                                onSelectAspectMode: _setAspectMode,
                                onSubtitleDelayChanged: _setSubtitleDelay,
                                onSubtitleOffsetChanged: (offset) {
                                  _wakeControls();
                                  setState(
                                    () => _subtitleVerticalOffset = offset,
                                  );
                                },
                                onSubtitleSizeChanged: (size) {
                                  _wakeControls();
                                  setState(() => _subtitleSize = size);
                                },
                                onSubtitleBackgroundChanged: (bg) {
                                  _wakeControls();
                                  setState(() => _subtitleBackground = bg);
                                },
                                onSubtitleColorChanged: (color) {
                                  _wakeControls();
                                  setState(() => _subtitleColor = color);
                                },
                              ),
                            ),
                          ),
                      ],
                    );
                      },
                    ),
                  ),
                ),
              ),
              if (_hudLabel != null)
                Positioned(
                  top: 72,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        key: const Key('vp-hud-pill'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.78),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.16),
                          ),
                        ),
                        child: Text(
                          _hudLabel!,
                          style: const TextStyle(
                            fontFamily: 'Figtree',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
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
      child: Builder(
        builder: (context) {
          final trimmed = text.trim();
          final isWrappedItalic = RegExp(
            r'^<\s*i\b[^>]*>.*<\s*/\s*i\s*>$',
            caseSensitive: false,
            dotAll: true,
          ).hasMatch(trimmed);
          final cleanedText = text
              .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
              .replaceAll(RegExp(r'<[^>]+>'), '')
              .trim();
          return Text(
            cleanedText,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Figtree',
              color: color,
              fontSize: sizePreset.playerFontSize,
              fontWeight: FontWeight.w600,
              fontStyle: isWrappedItalic ? FontStyle.italic : FontStyle.normal,
              height: 1.3,
              shadows: shadows,
            ),
          );
        },
      ),
    );
  }
}

enum _TrackPanelTab { subtitles, style, audio, quality }

class _TracksAndQualityPanel extends StatefulWidget {
  const _TracksAndQualityPanel({
    required this.tokens,
    required this.source,
    required this.compact,
    required this.maxWidth,
    required this.maxHeight,
    required this.selectedAudioIndex,
    required this.selectedSubtitleIndex,
    required this.selectedQuality,
    required this.selectedAspectMode,
    required this.qualityOrder,
    required this.subtitleDelaySeconds,
    required this.subtitleVerticalOffset,
    required this.subtitleSize,
    required this.subtitleBackground,
    required this.subtitleColor,
    required this.onClose,
    required this.onSelectAudio,
    required this.onSelectSubtitle,
    required this.onSelectQuality,
    required this.onSelectAspectMode,
    required this.onSubtitleDelayChanged,
    required this.onSubtitleOffsetChanged,
    required this.onSubtitleSizeChanged,
    required this.onSubtitleBackgroundChanged,
    required this.onSubtitleColorChanged,
    this.onInteraction,
  });

  final HermesThemeTokens tokens;
  final MediaSourceModel source;
  final bool compact;
  final double maxWidth;
  final double maxHeight;
  final int selectedAudioIndex;
  final int? selectedSubtitleIndex;
  final VideoQualityPreset selectedQuality;
  final VideoAspectMode selectedAspectMode;
  final List<VideoQualityPreset> qualityOrder;
  final double subtitleDelaySeconds;
  final double subtitleVerticalOffset;
  final SubtitleSizePreset subtitleSize;
  final SubtitleBackgroundStyle subtitleBackground;
  final Color subtitleColor;
  final VoidCallback onClose;
  final ValueChanged<int> onSelectAudio;
  final ValueChanged<int?> onSelectSubtitle;
  final ValueChanged<VideoQualityPreset> onSelectQuality;
  final ValueChanged<VideoAspectMode> onSelectAspectMode;
  final ValueChanged<double> onSubtitleDelayChanged;
  final ValueChanged<double> onSubtitleOffsetChanged;
  final ValueChanged<SubtitleSizePreset> onSubtitleSizeChanged;
  final ValueChanged<SubtitleBackgroundStyle> onSubtitleBackgroundChanged;
  final ValueChanged<Color> onSubtitleColorChanged;
  final VoidCallback? onInteraction;

  @override
  State<_TracksAndQualityPanel> createState() => _TracksAndQualityPanelState();
}

class _TracksAndQualityPanelState extends State<_TracksAndQualityPanel> {
  _TrackPanelTab _activeTab = _TrackPanelTab.subtitles;
  bool _desktopShowStyle = false;

  List<_PanelOption> _audioItems() {
    if (widget.source.audioStreams.isEmpty) {
      return [
        _PanelOption(
          label: widget.source.audioCodec.isEmpty
              ? 'Default audio'
              : widget.source.audioCodec.toUpperCase(),
          active: true,
          onTap: () {},
        ),
      ];
    }
    return widget.source.audioStreams
        .map(
          (s) => _PanelOption(
            label: '${s.language.toUpperCase()} (${s.codec})',
            active: widget.selectedAudioIndex == s.streamIndex,
            onTap: () => widget.onSelectAudio(s.streamIndex),
          ),
        )
        .toList(growable: false);
  }

  List<_PanelOption> _subtitleItems() {
    return [
      _PanelOption(
        label: 'Off',
        active: widget.selectedSubtitleIndex == null,
        onTap: () => widget.onSelectSubtitle(null),
      ),
      ...widget.source.subtitleStreams.map(
        (s) => _PanelOption(
          label: '${s.language.toUpperCase()} (${s.title})',
          active: widget.selectedSubtitleIndex == s.streamIndex,
          onTap: () => widget.onSelectSubtitle(s.streamIndex),
        ),
      ),
    ];
  }

  List<_PanelOption> _qualityItems() {
    return widget.qualityOrder
        .map(
          (q) => _PanelOption(
            label: q == VideoQualityPreset.directPlay
                ? 'Original · ${widget.source.shortTag}'
                : q.label,
            active: widget.selectedQuality == q,
            onTap: () => widget.onSelectQuality(q),
          ),
        )
        .toList(growable: false);
  }

  Widget _buildAspectRow(HermesThemeTokens tokens) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Display',
          style: TextStyle(
            fontFamily: 'Figtree',
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.72),
          ),
        ),
        const SizedBox(width: 4),
        for (final mode in VideoAspectMode.values)
          _HeaderPillChip(
            key: Key('vp-aspect-${mode.name}'),
            label: mode.label,
            selected: widget.selectedAspectMode == mode,
            tokens: tokens,
            onTap: () => widget.onSelectAspectMode(mode),
          ),
      ],
    );
  }

  Widget _buildStyleEditor() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(right: 4, bottom: 4),
      child: _SubtitleStyleEditor(
        tokens: widget.tokens,
        delaySeconds: widget.subtitleDelaySeconds,
        verticalOffset: widget.subtitleVerticalOffset,
        sizePreset: widget.subtitleSize,
        backgroundStyle: widget.subtitleBackground,
        color: widget.subtitleColor,
        onDelayChanged: widget.onSubtitleDelayChanged,
        onOffsetChanged: widget.onSubtitleOffsetChanged,
        onSizeChanged: widget.onSubtitleSizeChanged,
        onBackgroundChanged: widget.onSubtitleBackgroundChanged,
        onColorChanged: widget.onSubtitleColorChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    final decoration = BoxDecoration(
      color: const Color(0xF2121215),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: tokens.line),
      boxShadow: const [
        BoxShadow(
          color: Color(0x88000000),
          blurRadius: 36,
          offset: Offset(0, 16),
        ),
      ],
    );

    if (widget.compact) {
      return Material(
        color: Colors.transparent,
        child: Container(
          key: const Key('vp-panel'),
          constraints: BoxConstraints(
            maxWidth: widget.maxWidth,
            maxHeight: widget.maxHeight,
          ),
          padding: const EdgeInsets.all(12),
          decoration: decoration,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Player settings',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Figtree',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: widget.onClose,
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _CompactTabChip(
                    label: 'Subtitles',
                    selected: _activeTab == _TrackPanelTab.subtitles,
                    tokens: tokens,
                    onTap: () {
                      widget.onInteraction?.call();
                      setState(() => _activeTab = _TrackPanelTab.subtitles);
                    },
                  ),
                  const SizedBox(width: 6),
                  _CompactTabChip(
                    label: 'Style',
                    selected: _activeTab == _TrackPanelTab.style,
                    tokens: tokens,
                    onTap: () {
                      widget.onInteraction?.call();
                      setState(() => _activeTab = _TrackPanelTab.style);
                    },
                  ),
                  const SizedBox(width: 6),
                  _CompactTabChip(
                    label: 'Audio',
                    selected: _activeTab == _TrackPanelTab.audio,
                    tokens: tokens,
                    onTap: () {
                      widget.onInteraction?.call();
                      setState(() => _activeTab = _TrackPanelTab.audio);
                    },
                  ),
                  const SizedBox(width: 6),
                  _CompactTabChip(
                    label: 'Quality',
                    selected: _activeTab == _TrackPanelTab.quality,
                    tokens: tokens,
                    onTap: () {
                      widget.onInteraction?.call();
                      setState(() => _activeTab = _TrackPanelTab.quality);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: _activeTab == _TrackPanelTab.style
                    ? _buildStyleEditor()
                    : _activeTab == _TrackPanelTab.quality
                        ? SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _PanelColumn(
                                  title: 'Quality',
                                  tokens: tokens,
                                  items: _qualityItems(),
                                  fillWidth: true,
                                ),
                                const SizedBox(height: 10),
                                Divider(height: 1, color: tokens.lineSoft),
                                const SizedBox(height: 10),
                                _buildAspectRow(tokens),
                              ],
                            ),
                          )
                        : _PanelColumn(
                            title: switch (_activeTab) {
                              _TrackPanelTab.subtitles => 'Subtitles',
                              _TrackPanelTab.style => 'Style',
                              _TrackPanelTab.audio => 'Audio',
                              _TrackPanelTab.quality => 'Quality',
                            },
                            tokens: tokens,
                            items: switch (_activeTab) {
                              _TrackPanelTab.subtitles => _subtitleItems(),
                              _TrackPanelTab.style => const [],
                              _TrackPanelTab.audio => _audioItems(),
                              _TrackPanelTab.quality => _qualityItems(),
                            },
                            fillWidth: true,
                          ),
              ),
            ],
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: Container(
        key: const Key('vp-panel'),
        constraints: BoxConstraints(
          maxWidth: widget.maxWidth,
          maxHeight: widget.maxHeight,
        ),
        padding: const EdgeInsets.all(14),
        decoration: decoration,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Tracks & subtitles',
                  style: TextStyle(
                    fontFamily: 'Figtree',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(width: 12),
                _HeaderPillChip(
                  label: 'Tracks',
                  selected: !_desktopShowStyle,
                  tokens: tokens,
                  onTap: () {
                    widget.onInteraction?.call();
                    setState(() => _desktopShowStyle = false);
                  },
                ),
                const SizedBox(width: 6),
                _HeaderPillChip(
                  label: 'Subtitle Style',
                  selected: _desktopShowStyle,
                  tokens: tokens,
                  onTap: () {
                    widget.onInteraction?.call();
                    setState(() => _desktopShowStyle = true);
                  },
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Close panel',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: widget.onClose,
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Flexible(
              child: _desktopShowStyle
                  ? _buildStyleEditor()
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _PanelColumn(
                            title: 'Audio',
                            tokens: tokens,
                            items: _audioItems(),
                          ),
                          const SizedBox(width: 12),
                          _PanelColumn(
                            title: 'Subtitles',
                            tokens: tokens,
                            items: _subtitleItems(),
                          ),
                          const SizedBox(width: 12),
                          _PanelColumn(
                            title: 'Quality',
                            tokens: tokens,
                            items: _qualityItems(),
                          ),
                        ],
                      ),
                    ),
            ),
            if (!_desktopShowStyle) ...[
              const SizedBox(height: 10),
              Divider(height: 1, color: tokens.lineSoft),
              const SizedBox(height: 10),
              _buildAspectRow(tokens),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeaderPillChip extends StatelessWidget {
  const _HeaderPillChip({
    super.key,
    required this.label,
    required this.selected,
    required this.tokens,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final HermesThemeTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? tokens.accent.withValues(alpha: 0.24)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? tokens.accent : tokens.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Figtree',
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? Colors.white : Colors.white.withValues(alpha: 0.78),
          ),
        ),
      ),
    );
  }
}

class _SubtitleStyleEditor extends StatelessWidget {
  const _SubtitleStyleEditor({
    required this.tokens,
    required this.delaySeconds,
    required this.verticalOffset,
    required this.sizePreset,
    required this.backgroundStyle,
    required this.color,
    required this.onDelayChanged,
    required this.onOffsetChanged,
    required this.onSizeChanged,
    required this.onBackgroundChanged,
    required this.onColorChanged,
  });

  final HermesThemeTokens tokens;
  final double delaySeconds;
  final double verticalOffset;
  final SubtitleSizePreset sizePreset;
  final SubtitleBackgroundStyle backgroundStyle;
  final Color color;
  final ValueChanged<double> onDelayChanged;
  final ValueChanged<double> onOffsetChanged;
  final ValueChanged<SubtitleSizePreset> onSizeChanged;
  final ValueChanged<SubtitleBackgroundStyle> onBackgroundChanged;
  final ValueChanged<Color> onColorChanged;

  static const List<({String label, Color color})> _colorPresets = [
    (label: 'HDR', color: Color(0xFFD8D8D8)),
    (label: 'White', color: Color(0xFFFFFFFF)),
    (label: 'Yellow', color: Color(0xFFF5D76E)),
    (label: 'Cyan', color: Color(0xFF8CE8FF)),
  ];

  String _formatDelay(double s) {
    if (s.abs() < 0.01) return '0.00s';
    final prefix = s > 0 ? '+' : '';
    return '$prefix${s.toStringAsFixed(2)}s';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _sectionTitle('Timing delay'),
        const SizedBox(height: 6),
        Row(
          children: [
            _stepButton(
              key: const Key('vp-sub-delay-minus'),
              label: '-0.25s',
              onTap: () => onDelayChanged(delaySeconds - 0.25),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _formatDelay(delaySeconds),
                  key: const Key('vp-sub-delay-value'),
                  style: const TextStyle(
                    fontFamily: 'Figtree',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _stepButton(
              key: const Key('vp-sub-delay-plus'),
              label: '+0.25s',
              onTap: () => onDelayChanged(delaySeconds + 0.25),
            ),
            if (delaySeconds.abs() >= 0.01) ...[
              const SizedBox(width: 6),
              TextButton(
                key: const Key('vp-sub-delay-reset'),
                onPressed: () => onDelayChanged(0.0),
                style: TextButton.styleFrom(
                  foregroundColor: tokens.accent,
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('Reset', style: TextStyle(fontSize: 12)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _sectionTitle('Vertical position')),
            Text(
              '${verticalOffset >= 0 ? '+' : ''}${verticalOffset.round()} px',
              style: TextStyle(
                fontFamily: 'Figtree',
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.72),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            activeTrackColor: tokens.accent,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
            thumbColor: tokens.accent,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          ),
          child: Slider(
            key: const Key('vp-sub-offset-slider'),
            value: verticalOffset.clamp(-24.0, 120.0),
            min: -24.0,
            max: 120.0,
            divisions: 24,
            onChanged: onOffsetChanged,
          ),
        ),
        const SizedBox(height: 4),
        _sectionTitle('Text size'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final preset in SubtitleSizePreset.values)
              _styleChoiceChip(
                label: preset.label,
                selected: sizePreset == preset,
                onTap: () => onSizeChanged(preset),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _sectionTitle('Background'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final bg in SubtitleBackgroundStyle.values)
              _styleChoiceChip(
                label: bg.label,
                selected: backgroundStyle == bg,
                onTap: () => onBackgroundChanged(bg),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _sectionTitle('Color'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final preset in _colorPresets)
              _styleChoiceChip(
                label: preset.label,
                swatchColor: preset.color,
                selected: color.toARGB32() == preset.color.toARGB32(),
                onTap: () => onColorChanged(preset.color),
              ),
          ],
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'Figtree',
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Colors.white.withValues(alpha: 0.65),
      ),
    );
  }

  Widget _stepButton({
    required Key key,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: tokens.line),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'Figtree',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _styleChoiceChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    Color? swatchColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? tokens.accent.withValues(alpha: 0.24)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? tokens.accent : tokens.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (swatchColor != null) ...[
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: swatchColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black54, width: 0.8),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Figtree',
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.82),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactTabChip extends StatelessWidget {
  const _CompactTabChip({
    required this.label,
    required this.selected,
    required this.tokens,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final HermesThemeTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? tokens.accent.withValues(alpha: 0.24)
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? tokens.accent : tokens.line,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Figtree',
              fontSize: 11.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? Colors.white : Colors.white.withValues(alpha: 0.78),
            ),
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
    this.fillWidth = false,
  });

  final String title;
  final HermesThemeTokens tokens;
  final List<_PanelOption> items;
  final bool fillWidth;

  @override
  Widget build(BuildContext context) {
    final column = SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!fillWidth)
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
                  mainAxisSize: fillWidth ? MainAxisSize.max : MainAxisSize.min,
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
                    if (fillWidth)
                      Flexible(
                        child: Text(
                          item.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Figtree',
                            fontSize: 14,
                            fontWeight: item.active
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: item.active
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      )
                    else
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
    );
    if (fillWidth) {
      return column;
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 150),
      child: column,
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
