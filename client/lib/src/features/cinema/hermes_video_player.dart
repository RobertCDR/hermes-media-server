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

part 'hermes_video_player_overlays.dart';

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

    try {
      return await cinemaService.updateWatchProgress(
        movieId: movieId,
        episodeId: episodeId,
        positionMs: getPositionMs(),
        durationMs: duration,
        markWatched: markWatched,
      );
    } catch (_) {
      return null;
    }
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
  int _loadGeneration = 0;
  bool _disposed = false;
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
    _disposed = true;
    _loadGeneration++;
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
    final gen = ++_loadGeneration;
    if (_disposed) return;
    try {
      if (forceFreshTicket) {
        final prevTicket = _ticket;
        _ticket = null;
        try {
          _ticket = await widget.cinemaService.issueStreamTicket(widget.source.id);
        } catch (_) {
          _ticket = prevTicket;
        }
        if (_disposed || !mounted || gen != _loadGeneration) return;
      }
      final ticket = await _ensureTicket();
      if (_disposed || !mounted || gen != _loadGeneration) return;
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
      if (_disposed || !mounted || gen != _loadGeneration) return;
      setState(() {
        _hlsAnchorMs = anchorMs;
        _completionHandled = false;
        _playbackError = null;
        _activeStreamUri = streamUri;
        _activeSubtitleUri = subUri;
      });
      await _playback.open(
        streamUri,
        startPositionMs: isDirect ? targetPosMs : 0,
        subtitleUri: subUri,
        subtitleTitle: subStream?.title,
        subtitleLanguage: subStream?.language,
        autoPlay: _playing,
      );
      if (_disposed || !mounted || gen != _loadGeneration) return;
      await _playback.setVolume(_muted ? 0 : _volume);
    } catch (e) {
      if (_disposed || !mounted || gen != _loadGeneration) return;
      if (_playback.hasVideoOutput) {
        setState(() {
          _playbackError = 'Unable to load video stream: $e';
        });
      }
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
              Positioned.fill(
                child: GestureDetector(
                  key: const Key('vp-canvas-gestures'),
                  behavior: HitTestBehavior.translucent,
                  onTap: _wakeControls,
                  onDoubleTap: _isMobilePlatform ? null : _toggleFullscreenMode,
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
                                    formatDurationMs(_positionMs),
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
                                    '-${formatDurationMs(remainingMs)}',
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
    );
  }
}
