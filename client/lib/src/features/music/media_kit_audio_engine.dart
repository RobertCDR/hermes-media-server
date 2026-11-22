import 'dart:async';

import 'package:media_kit/media_kit.dart';

import '../../core/media/hermes_media_runtime.dart';
import 'music_models.dart';
import 'music_playback_coordinator.dart';

/// Audio-only playback adapter backed by `package:media_kit` (`libmpv`).
///
/// Configures headless audio output (`vo: 'null'`) and lazily instantiates
/// [Player] only when native audio playback begins so headless tests and
/// remote-control mode allocate zero decoder threads until needed.
class MediaKitAudioEngineAdapter
    implements ControllableAudioEngine, PrewarmableAudioEngine {
  MediaKitAudioEngineAdapter({
    Player Function()? playerFactory,
  }) : _playerFactory = playerFactory ??
            (() {
              HermesMediaRuntime.ensureInitialized();
              return Player(
                configuration: const PlayerConfiguration(
                  vo: 'null',
                  title: 'Hermes Music',
                ),
              );
            });

  final Player Function() _playerFactory;
  final StreamController<int> _positionController =
      StreamController<int>.broadcast();
  final StreamController<void> _completedController =
      StreamController<void>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  Player? _player;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<String>? _errorSub;

  double _volume01 = 1.0;
  bool _normalizeVolume = false;
  int _suppressCompletionDepth = 0;
  bool _lastCompletedState = false;
  bool _disposed = false;

  @override
  Stream<int> get positionMsStream => _positionController.stream;

  @override
  Stream<void> get trackCompletedStream => _completedController.stream;

  Stream<String> get errorStream => _errorController.stream;

  /// Pre-initializes the underlying mpv audio player before a Connect transfer
  /// so handoff starts playing without cold-start player allocation latency.
  @override
  Future<void> warmUp() async {
    if (_disposed || _player != null) return;
    try {
      await _ensurePlayer();
    } catch (_) {
      // Non-fatal pre-warm failure falls back to lazy creation on play.
    }
  }

  Future<Player> _ensurePlayer() async {
    final existing = _player;
    if (existing != null) {
      return existing;
    }

    final player = _playerFactory();
    _player = player;

    _posSub = player.stream.position.listen((duration) {
      if (!_disposed && !_positionController.isClosed) {
        _positionController.add(duration.inMilliseconds);
      }
    });

    _completedSub = player.stream.completed.listen((completed) {
      if (_disposed) return;
      final roseToCompleted = completed && !_lastCompletedState;
      _lastCompletedState = completed;
      if (roseToCompleted &&
          _suppressCompletionDepth == 0 &&
          !_completedController.isClosed) {
        _completedController.add(null);
      }
    });

    _errorSub = player.stream.error.listen((message) {
      if (!_disposed &&
          message.trim().isNotEmpty &&
          !_errorController.isClosed) {
        _errorController.add(message);
      }
    });

    await _configureLowLatencyAudioProperties(player);
    if (_disposed) return player;
    await player.setVolume((_volume01 * 100.0).clamp(0.0, 100.0));
    if (_disposed) return player;
    await _applyNormalizationFilter(player, _normalizeVolume);
    return player;
  }

  Future<void> _configureLowLatencyAudioProperties(Player player) async {
    if (player.platform case final NativePlayer nativePlatform) {
      const props = <String, String>{
        'demuxer-max-bytes': '8MiB',
        'demuxer-max-back-bytes': '2MiB',
        'cache-secs': '10',
        'audio-wait-open': '0',
        'network-timeout': '15',
      };
      for (final entry in props.entries) {
        try {
          await nativePlatform.setProperty(entry.key, entry.value);
        } catch (_) {
          // Ignore on headless/stub implementations without mpv backend support.
        }
      }
    }
  }

  Future<void> _applyNormalizationFilter(Player player, bool enabled) async {
    if (player.platform case final NativePlayer nativePlatform) {
      try {
        await nativePlatform.setProperty(
          'af',
          enabled ? 'dynaudnorm=f=150:g=15' : '',
        );
      } catch (_) {
        // Ignore on mpv builds lacking dynaudnorm lavfi filter.
      }
    }
  }

  @override
  Future<void> loadAndPlay(
    Uri streamUri,
    SongModel track,
    int startPositionMs,
  ) async {
    if (_disposed) return;
    _suppressCompletionDepth++;
    _lastCompletedState = false;
    try {
      final player = await _ensurePlayer();
      if (_disposed) return;
      await player.setVolume((_volume01 * 100.0).clamp(0.0, 100.0));
      if (_disposed) return;
      await player.open(
        Media(
          streamUri.toString(),
          start: startPositionMs > 0
              ? Duration(milliseconds: startPositionMs)
              : null,
        ),
        play: true,
      );
      if (_disposed) return;
      await player.setVolume((_volume01 * 100.0).clamp(0.0, 100.0));
    } finally {
      if (_suppressCompletionDepth > 0) {
        _suppressCompletionDepth--;
      }
    }
  }

  @override
  Future<void> resume() async {
    if (_disposed) return;
    await _player?.play();
  }

  @override
  Future<void> pause() async {
    if (_disposed) return;
    await _player?.pause();
  }

  @override
  Future<void> stop() async {
    if (_disposed) return;
    final player = _player;
    if (player == null) return;
    _suppressCompletionDepth++;
    try {
      await player.stop();
    } finally {
      if (_suppressCompletionDepth > 0) {
        _suppressCompletionDepth--;
      }
    }
  }

  @override
  Future<void> seek(int positionMs) async {
    if (_disposed) return;
    final player = _player;
    if (player == null) return;
    await player.seek(Duration(milliseconds: positionMs.clamp(0, 1 << 30)));
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume01 = volume.clamp(0.0, 1.0);
    if (_disposed) return;
    final player = _player;
    if (player != null) {
      await player.setVolume((_volume01 * 100.0).clamp(0.0, 100.0));
    }
  }

  @override
  Future<void> setNormalizationEnabled(bool enabled) async {
    _normalizeVolume = enabled;
    if (_disposed) return;
    final player = _player;
    if (player != null) {
      await _applyNormalizationFilter(player, enabled);
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _posSub?.cancel();
    await _completedSub?.cancel();
    await _errorSub?.cancel();
    await _positionController.close();
    await _completedController.close();
    await _errorController.close();
    await _player?.dispose();
    _player = null;
  }
}
