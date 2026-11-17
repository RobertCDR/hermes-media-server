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
class MediaKitAudioEngineAdapter implements ControllableAudioEngine {
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
  bool _suppressCompletion = false;
  bool _lastCompletedState = false;
  bool _disposed = false;

  @override
  Stream<int> get positionMsStream => _positionController.stream;

  @override
  Stream<void> get trackCompletedStream => _completedController.stream;

  Stream<String> get errorStream => _errorController.stream;

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
          !_suppressCompletion &&
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

    await player.setVolume((_volume01 * 100.0).clamp(0.0, 100.0));
    await _applyNormalizationFilter(player, _normalizeVolume);
    return player;
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
    _suppressCompletion = true;
    _lastCompletedState = false;
    try {
      final player = await _ensurePlayer();
      await player.open(
        Media(
          streamUri.toString(),
          start: startPositionMs > 0
              ? Duration(milliseconds: startPositionMs)
              : null,
        ),
        play: true,
      );
      await player.setVolume((_volume01 * 100.0).clamp(0.0, 100.0));
    } finally {
      _suppressCompletion = false;
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
    _suppressCompletion = true;
    try {
      await player.stop();
    } finally {
      _suppressCompletion = false;
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
