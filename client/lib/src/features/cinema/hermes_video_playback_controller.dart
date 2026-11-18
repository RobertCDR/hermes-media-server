import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/media/hermes_media_runtime.dart';
import 'cinema_models.dart';
import 'hermes_video_player.dart';

/// Abstraction over the underlying video playback engine so UI controls work
/// uniformly across `media_kit` (`libmpv`) runtime and headless test stubs.
abstract interface class HermesVideoPlaybackController {
  bool get hasVideoOutput;

  Stream<int> get positionMsStream;
  Stream<int> get durationMsStream;
  Stream<bool> get playingStream;
  Stream<bool> get bufferingStream;
  Stream<bool> get completedStream;
  Stream<List<String>> get subtitleLinesStream;
  Stream<String> get errorStream;

  Future<void> open(
    Uri streamUri, {
    int startPositionMs = 0,
    Uri? subtitleUri,
    String? subtitleTitle,
    String? subtitleLanguage,
    bool autoPlay = true,
  });

  Future<void> setExternalSubtitle(
    Uri? subtitleUri, {
    String? title,
    String? language,
  });

  Future<void> selectEmbeddedAudioTrack({
    required int streamIndex,
    required List<MediaStreamModel> availableAudioStreams,
  });

  Future<void> setSubtitleDelaySeconds(double seconds);

  Future<void> play();
  Future<void> pause();
  Future<void> seek(int positionMs);
  Future<void> setVolume(double volume0to100);
  Future<void> stop();

  Widget buildVideoSurface(BuildContext context);

  Future<void> dispose();
}

/// Production `media_kit` (`libmpv`) video playback controller.
class MediaKitVideoPlaybackController implements HermesVideoPlaybackController {
  MediaKitVideoPlaybackController({
    required this.config,
    Player Function(PlayerConfiguration configuration)? playerFactory,
    VideoController Function(
      Player player,
      VideoControllerConfiguration configuration,
    )? videoControllerFactory,
  }) {
    if (playerFactory == null) {
      HermesMediaRuntime.ensureInitialized();
    }
    _player = (playerFactory ??
        ((c) => Player(configuration: c)))(
      const PlayerConfiguration(title: 'Hermes Cinema'),
    );
    _videoController = (videoControllerFactory ??
        ((p, c) => VideoController(p, configuration: c)))(
      _player,
      const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );
    _attachListeners();
  }

  final HermesVideoPlayerConfig config;
  late final Player _player;
  late final VideoController _videoController;

  final StreamController<int> _positionController =
      StreamController<int>.broadcast();
  final StreamController<int> _durationController =
      StreamController<int>.broadcast();
  final StreamController<bool> _playingController =
      StreamController<bool>.broadcast();
  final StreamController<bool> _bufferingController =
      StreamController<bool>.broadcast();
  final StreamController<bool> _completedController =
      StreamController<bool>.broadcast();
  final StreamController<List<String>> _subtitleController =
      StreamController<List<String>>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<List<String>>? _subSub;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<Tracks>? _tracksSub;

  Uri? _desiredSubtitleUri;
  String? _desiredSubtitleTitle;
  String? _desiredSubtitleLanguage;
  Uri? _appliedSubtitleUri;
  double _subtitleDelaySeconds = 0.0;
  bool _propertiesApplied = false;
  bool _mediaLoaded = false;
  bool _disposed = false;
  int _openGeneration = 0;

  @override
  bool get hasVideoOutput => true;

  @override
  Stream<int> get positionMsStream => _positionController.stream;

  @override
  Stream<int> get durationMsStream => _durationController.stream;

  @override
  Stream<bool> get playingStream => _playingController.stream;

  @override
  Stream<bool> get bufferingStream => _bufferingController.stream;

  @override
  Stream<bool> get completedStream => _completedController.stream;

  @override
  Stream<List<String>> get subtitleLinesStream => _subtitleController.stream;

  @override
  Stream<String> get errorStream => _errorController.stream;

  void _attachListeners() {
    _posSub = _player.stream.position.listen((d) {
      if (!_disposed && !_positionController.isClosed) {
        _positionController.add(d.inMilliseconds);
      }
    });
    _durSub = _player.stream.duration.listen((d) {
      if (_disposed) return;
      final ms = d.inMilliseconds;
      if (ms > 0) {
        _mediaLoaded = true;
        unawaited(_syncPendingSubtitle());
      }
      if (!_durationController.isClosed) {
        _durationController.add(ms);
      }
    });
    _playingSub = _player.stream.playing.listen((playing) {
      if (!_disposed && !_playingController.isClosed) {
        _playingController.add(playing);
      }
    });
    _bufferingSub = _player.stream.buffering.listen((buffering) {
      if (!_disposed && !_bufferingController.isClosed) {
        _bufferingController.add(buffering);
      }
    });
    _completedSub = _player.stream.completed.listen((completed) {
      if (!_disposed && !_completedController.isClosed) {
        _completedController.add(completed);
      }
    });
    _subSub = _player.stream.subtitle.listen((lines) {
      if (!_disposed && !_subtitleController.isClosed) {
        _subtitleController.add(lines);
      }
    });
    _errorSub = _player.stream.error.listen((msg) {
      if (!_disposed && msg.trim().isNotEmpty && !_errorController.isClosed) {
        _errorController.add(msg);
      }
    });
    _tracksSub = _player.stream.tracks.listen((tracks) {
      if (_disposed) return;
      final hasTracks = tracks.video.any((t) => t.id != 'auto' && t.id != 'no') ||
          tracks.audio.any((t) => t.id != 'auto' && t.id != 'no');
      if (hasTracks) {
        _mediaLoaded = true;
        unawaited(_syncPendingSubtitle());
      }
    });
  }

  Future<void> _ensureMpvProperties() async {
    if (_propertiesApplied || _disposed) return;
    _propertiesApplied = true;
    if (_player.platform case final NativePlayer nativePlatform) {
      for (final entry in config.mpvBackendProperties.entries) {
        try {
          await nativePlatform.setProperty(entry.key, entry.value);
        } catch (_) {
          // Ignore unsupported mpv properties across platform builds.
        }
      }
      if (_subtitleDelaySeconds != 0.0) {
        try {
          await nativePlatform.setProperty(
            'sub-delay',
            _subtitleDelaySeconds.toStringAsFixed(2),
          );
        } catch (_) {
          // Ignore unsupported mpv properties across platform builds.
        }
      }
    }
  }

  Future<void> _syncPendingSubtitle([int? expectedGeneration]) async {
    if (_disposed || !_mediaLoaded) return;
    if (expectedGeneration != null && expectedGeneration != _openGeneration) {
      return;
    }
    final desired = _desiredSubtitleUri;
    if (desired == _appliedSubtitleUri) return;

    _appliedSubtitleUri = desired;
    if (desired == null) {
      await _player.setSubtitleTrack(SubtitleTrack.no());
      return;
    }

    await _player.setSubtitleTrack(
      SubtitleTrack.uri(
        desired.toString(),
        title: _desiredSubtitleTitle ?? 'Subtitles',
        language: _desiredSubtitleLanguage ?? 'und',
      ),
    );
  }

  @override
  Future<void> open(
    Uri streamUri, {
    int startPositionMs = 0,
    Uri? subtitleUri,
    String? subtitleTitle,
    String? subtitleLanguage,
    bool autoPlay = true,
  }) async {
    if (_disposed) return;
    final gen = ++_openGeneration;
    _mediaLoaded = false;
    _appliedSubtitleUri = null;
    _desiredSubtitleUri = subtitleUri;
    _desiredSubtitleTitle = subtitleTitle;
    _desiredSubtitleLanguage = subtitleLanguage;

    await _ensureMpvProperties();
    if (_disposed || gen != _openGeneration) return;
    await _player.open(
      Media(
        streamUri.toString(),
        start: startPositionMs > 0
            ? Duration(milliseconds: startPositionMs)
            : null,
      ),
      play: autoPlay,
    );
    if (_disposed || gen != _openGeneration) return;
    if (_mediaLoaded) {
      await _syncPendingSubtitle(gen);
    }
  }

  @override
  Future<void> setExternalSubtitle(
    Uri? subtitleUri, {
    String? title,
    String? language,
  }) async {
    if (_disposed) return;
    _desiredSubtitleUri = subtitleUri;
    _desiredSubtitleTitle = title;
    _desiredSubtitleLanguage = language;
    if (subtitleUri == null) {
      _appliedSubtitleUri = null;
      await _player.setSubtitleTrack(SubtitleTrack.no());
      return;
    }
    if (_mediaLoaded) {
      await _syncPendingSubtitle();
    }
  }

  @override
  Future<void> selectEmbeddedAudioTrack({
    required int streamIndex,
    required List<MediaStreamModel> availableAudioStreams,
  }) async {
    if (_disposed) return;
    final realTracks = _player.state.tracks.audio
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList(growable: false);
    if (realTracks.isEmpty) return;

    final ordinal = availableAudioStreams.indexWhere(
      (s) => s.streamIndex == streamIndex,
    );
    AudioTrack? chosen;
    if (ordinal >= 0 && ordinal < realTracks.length) {
      chosen = realTracks[ordinal];
    } else if (ordinal >= 0) {
      final lang = availableAudioStreams[ordinal].language.toLowerCase();
      chosen = realTracks
          .where((t) => (t.language ?? '').toLowerCase() == lang)
          .firstOrNull;
    }
    chosen ??= realTracks.first;
    await _player.setAudioTrack(chosen);
  }

  @override
  Future<void> setSubtitleDelaySeconds(double seconds) async {
    _subtitleDelaySeconds = seconds.clamp(-10.0, 10.0);
    if (_disposed) return;
    if (_player.platform case final NativePlayer nativePlatform) {
      try {
        await nativePlatform.setProperty(
          'sub-delay',
          _subtitleDelaySeconds.toStringAsFixed(2),
        );
      } catch (_) {
        // Ignore unsupported mpv properties across platform builds.
      }
    }
  }

  @override
  Future<void> play() async {
    if (_disposed) return;
    await _player.play();
  }

  @override
  Future<void> pause() async {
    if (_disposed) return;
    await _player.pause();
  }

  @override
  Future<void> seek(int positionMs) async {
    if (_disposed) return;
    await _player.seek(Duration(milliseconds: positionMs.clamp(0, 1 << 30)));
  }

  @override
  Future<void> setVolume(double volume0to100) async {
    if (_disposed) return;
    await _player.setVolume(volume0to100.clamp(0.0, 100.0));
  }

  @override
  Future<void> stop() async {
    if (_disposed) return;
    _mediaLoaded = false;
    await _player.stop();
  }

  @override
  Widget buildVideoSurface(BuildContext context) {
    return Video(
      controller: _videoController,
      controls: NoVideoControls,
      fill: Colors.black,
      fit: BoxFit.contain,
      // Subtitles are rendered by Hermes HDR-safe caption overlay so
      // None / Shadow / Box and text-size preferences apply consistently.
      subtitleViewConfiguration: const SubtitleViewConfiguration(
        visible: false,
      ),
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await Future.wait([
      ?_posSub?.cancel(),
      ?_durSub?.cancel(),
      ?_playingSub?.cancel(),
      ?_bufferingSub?.cancel(),
      ?_completedSub?.cancel(),
      ?_subSub?.cancel(),
      ?_errorSub?.cancel(),
      ?_tracksSub?.cancel(),
    ]);
    await Future.wait([
      _positionController.close(),
      _durationController.close(),
      _playingController.close(),
      _bufferingController.close(),
      _completedController.close(),
      _subtitleController.close(),
      _errorController.close(),
    ]);
    await _player.dispose();
  }
}

/// Lightweight fallback controller used when native `libmpv` has not been
/// initialized (e.g. headless CI widget tests).
class StubVideoPlaybackController implements HermesVideoPlaybackController {
  @override
  bool get hasVideoOutput => false;

  @override
  Stream<int> get positionMsStream => const Stream<int>.empty();

  @override
  Stream<int> get durationMsStream => const Stream<int>.empty();

  @override
  Stream<bool> get playingStream => const Stream<bool>.empty();

  @override
  Stream<bool> get bufferingStream => const Stream<bool>.empty();

  @override
  Stream<bool> get completedStream => const Stream<bool>.empty();

  @override
  Stream<List<String>> get subtitleLinesStream =>
      const Stream<List<String>>.empty();

  @override
  Stream<String> get errorStream => const Stream<String>.empty();

  @override
  Future<void> open(
    Uri streamUri, {
    int startPositionMs = 0,
    Uri? subtitleUri,
    String? subtitleTitle,
    String? subtitleLanguage,
    bool autoPlay = true,
  }) async {}

  @override
  Future<void> setExternalSubtitle(
    Uri? subtitleUri, {
    String? title,
    String? language,
  }) async {}

  @override
  Future<void> selectEmbeddedAudioTrack({
    required int streamIndex,
    required List<MediaStreamModel> availableAudioStreams,
  }) async {}

  @override
  Future<void> setSubtitleDelaySeconds(double seconds) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(int positionMs) async {}

  @override
  Future<void> setVolume(double volume0to100) async {}

  @override
  Future<void> stop() async {}

  @override
  Widget buildVideoSurface(BuildContext context) => const SizedBox.shrink();

  @override
  Future<void> dispose() async {}
}
