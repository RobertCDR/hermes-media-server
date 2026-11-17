import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart' as audio_svc;
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import 'platform_media_bridge.dart';

const String hermesSmtcChannelName = 'hermes.media/smtc';

PlatformMediaBridge createDefaultPlatformMediaBridge() {
  if (kIsWeb) {
    return InMemoryPlatformMediaBridge();
  }
  if (Platform.isWindows) {
    return WindowsSmtcMediaBridge();
  }
  if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
    return AndroidAudioServiceMediaBridge();
  }
  return InMemoryPlatformMediaBridge();
}

/// Bridges [PlatformMediaBridge] to Windows `SystemMediaTransportControls`
/// hosted in `windows/runner/hermes_smtc_bridge.cpp`.
class WindowsSmtcMediaBridge implements DisposableMediaBridge {
  WindowsSmtcMediaBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(hermesSmtcChannelName) {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  final MethodChannel _channel;
  FutureOr<void> Function(MediaButtonAction action)? _handler;
  bool _disposed = false;

  @override
  void setCommandHandler(
    FutureOr<void> Function(MediaButtonAction action) handler,
  ) {
    _handler = handler;
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (_disposed || call.method != 'onMediaButton') {
      return null;
    }
    final actionName = call.arguments as String?;
    final action = switch (actionName) {
      'play' => MediaButtonAction.play,
      'pause' => MediaButtonAction.pause,
      'next' => MediaButtonAction.next,
      'previous' => MediaButtonAction.previous,
      'stop' => MediaButtonAction.stop,
      _ => null,
    };
    if (action != null) {
      await _handler?.call(action);
    }
    return null;
  }

  @override
  Future<void> publishState(MediaBridgeMetadata metadata) async {
    if (_disposed) return;
    try {
      await _channel.invokeMethod<void>('publishState', <String, dynamic>{
        'title': metadata.title,
        'artist': metadata.artist,
        'album': metadata.album,
        'isPlaying': metadata.isPlaying,
        'positionMs': metadata.positionMs,
        'durationMs': metadata.durationMs,
        'artUrl': metadata.artUri?.toString() ?? '',
      });
    } on MissingPluginException {
      // Ignored in headless environments without the Windows runner attached.
    } catch (_) {
      // Non-fatal OS transport sync failure must never disrupt playback.
    }
  }

  @override
  Future<void> clearState() async {
    if (_disposed) return;
    try {
      await _channel.invokeMethod<void>('clearState');
    } on MissingPluginException {
      // Ignored in headless environments.
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _handler = null;
    _channel.setMethodCallHandler(null);
  }
}

typedef HermesAudioHandlerFactory = Future<HermesOsAudioHandler> Function();
typedef HermesAudioSessionProvider = Future<AudioSession> Function();

/// Minimal OS `AudioHandler` surface driven by [AndroidAudioServiceMediaBridge].
abstract interface class HermesOsAudioHandler {
  Future<void> updateMedia({
    required String id,
    required String title,
    required String artist,
    required String album,
    required bool isPlaying,
    required int positionMs,
    required int durationMs,
    Uri? artUri,
  });

  Future<void> clearPlayback();

  void attachBridgeCallbacks({
    required FutureOr<void> Function(MediaButtonAction action) onButton,
    required FutureOr<void> Function(int positionMs) onSeek,
  });

  void detachBridgeCallbacks();
}

class _AudioServiceHandlerAdapter extends audio_svc.BaseAudioHandler
    with audio_svc.SeekHandler
    implements HermesOsAudioHandler {
  FutureOr<void> Function(MediaButtonAction action)? _onButton;
  FutureOr<void> Function(int positionMs)? _onSeek;
  String? _lastMediaKey;

  @override
  void attachBridgeCallbacks({
    required FutureOr<void> Function(MediaButtonAction action) onButton,
    required FutureOr<void> Function(int positionMs) onSeek,
  }) {
    _onButton = onButton;
    _onSeek = onSeek;
  }

  @override
  void detachBridgeCallbacks() {
    _onButton = null;
    _onSeek = null;
  }

  @override
  Future<void> updateMedia({
    required String id,
    required String title,
    required String artist,
    required String album,
    required bool isPlaying,
    required int positionMs,
    required int durationMs,
    Uri? artUri,
  }) async {
    final mediaKey = '$id|$durationMs|${artUri?.toString() ?? ''}';
    if (_lastMediaKey != mediaKey) {
      _lastMediaKey = mediaKey;
      mediaItem.add(
        audio_svc.MediaItem(
          id: id,
          title: title,
          artist: artist,
          album: album,
          duration:
              durationMs > 0 ? Duration(milliseconds: durationMs) : null,
          artUri: artUri,
        ),
      );
    }

    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          audio_svc.MediaControl.skipToPrevious,
          if (isPlaying)
            audio_svc.MediaControl.pause
          else
            audio_svc.MediaControl.play,
          audio_svc.MediaControl.skipToNext,
          audio_svc.MediaControl.stop,
        ],
        systemActions: const {
          audio_svc.MediaAction.seek,
          audio_svc.MediaAction.playPause,
          audio_svc.MediaAction.skipToNext,
          audio_svc.MediaAction.skipToPrevious,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: audio_svc.AudioProcessingState.ready,
        playing: isPlaying,
        updatePosition: Duration(
          milliseconds: positionMs.clamp(0, 1 << 30),
        ),
      ),
    );
  }

  @override
  Future<void> clearPlayback() async {
    _lastMediaKey = null;
    playbackState.add(
      playbackState.value.copyWith(
        controls: const [],
        playing: false,
        processingState: audio_svc.AudioProcessingState.idle,
        updatePosition: Duration.zero,
      ),
    );
  }

  @override
  Future<void> play() async => _onButton?.call(MediaButtonAction.play);

  @override
  Future<void> pause() async => _onButton?.call(MediaButtonAction.pause);

  @override
  Future<void> skipToNext() async => _onButton?.call(MediaButtonAction.next);

  @override
  Future<void> skipToPrevious() async =>
      _onButton?.call(MediaButtonAction.previous);

  @override
  Future<void> stop() async => _onButton?.call(MediaButtonAction.stop);

  @override
  Future<void> seek(Duration position) async =>
      _onSeek?.call(position.inMilliseconds);
}

/// Mobile/Apple OS media notification, lockscreen, audio-focus, and headset
/// control bridge powered by `audio_service` and `audio_session`.
class AndroidAudioServiceMediaBridge
    implements SeekCapableMediaBridge, DisposableMediaBridge {
  AndroidAudioServiceMediaBridge({
    HermesAudioHandlerFactory? handlerFactory,
    HermesAudioSessionProvider? sessionProvider,
  })  : _handlerFactory = handlerFactory ?? _defaultSharedHandlerInit,
        _sessionProvider =
            sessionProvider ?? (() => AudioSession.instance);

  static Future<HermesOsAudioHandler>? _sharedHandlerFuture;

  static Future<HermesOsAudioHandler> _defaultSharedHandlerInit() {
    return _sharedHandlerFuture ??=
        audio_svc.AudioService.init<_AudioServiceHandlerAdapter>(
      builder: _AudioServiceHandlerAdapter.new,
      config: const audio_svc.AudioServiceConfig(
        androidNotificationChannelId: 'dev.hermes.hermes_client.channel.audio',
        androidNotificationChannelName: 'Hermes Music',
        androidNotificationChannelDescription:
            'Playback controls for Hermes music streaming',
        androidNotificationIcon: 'mipmap/ic_launcher',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: true,
      ),
    );
  }

  final HermesAudioHandlerFactory _handlerFactory;
  final HermesAudioSessionProvider _sessionProvider;

  HermesOsAudioHandler? _handler;
  Future<void>? _initFuture;
  AudioSession? _audioSession;
  StreamSubscription<void>? _noisySub;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;

  FutureOr<void> Function(MediaButtonAction action)? _commandHandler;
  FutureOr<void> Function(int positionMs)? _seekHandler;
  bool _isPlaying = false;
  bool _pausedByTransientInterruption = false;
  bool _disposed = false;

  @override
  void setCommandHandler(
    FutureOr<void> Function(MediaButtonAction action) handler,
  ) {
    _commandHandler = handler;
  }

  @override
  void setSeekHandler(FutureOr<void> Function(int positionMs) handler) {
    _seekHandler = handler;
  }

  Future<HermesOsAudioHandler?> _ensureInitialized() async {
    if (_disposed) return null;
    if (_handler != null) return _handler;

    await (_initFuture ??= _performInit());
    return _handler;
  }

  Future<void> _performInit() async {
    try {
      final session = await _sessionProvider();
      await session.configure(const AudioSessionConfiguration.music());
      _audioSession = session;

      _noisySub = session.becomingNoisyEventStream.listen((_) {
        if (!_disposed && _isPlaying) {
          unawaited(
            Future<void>.sync(
              () => _commandHandler?.call(MediaButtonAction.pause),
            ),
          );
        }
      });

      _interruptionSub = session.interruptionEventStream.listen((event) {
        if (_disposed) return;
        if (event.begin) {
          if (event.type == AudioInterruptionType.pause ||
              event.type == AudioInterruptionType.unknown) {
            if (_isPlaying) {
              _pausedByTransientInterruption =
                  event.type == AudioInterruptionType.pause;
              unawaited(
                Future<void>.sync(
                  () => _commandHandler?.call(MediaButtonAction.pause),
                ),
              );
            }
          }
        } else {
          if (event.type == AudioInterruptionType.pause &&
              _pausedByTransientInterruption) {
            _pausedByTransientInterruption = false;
            unawaited(
              Future<void>.sync(
                () => _commandHandler?.call(MediaButtonAction.play),
              ),
            );
          }
        }
      });

      final handler = await _handlerFactory();
      if (_disposed) return;
      handler.attachBridgeCallbacks(
        onButton: (action) => _commandHandler?.call(action),
        onSeek: (positionMs) => _seekHandler?.call(positionMs),
      );
      _handler = handler;
    } catch (_) {
      // Allow playback to continue cleanly if OS service registration fails.
    }
  }

  @override
  Future<void> publishState(MediaBridgeMetadata metadata) async {
    if (_disposed) return;
    _isPlaying = metadata.isPlaying;
    final handler = await _ensureInitialized();
    if (_disposed || handler == null) return;

    if (metadata.isPlaying) {
      await _audioSession?.setActive(true);
    }

    await handler.updateMedia(
      id: '${metadata.artist}|${metadata.album}|${metadata.title}',
      title: metadata.title,
      artist: metadata.artist,
      album: metadata.album,
      isPlaying: metadata.isPlaying,
      positionMs: metadata.positionMs,
      durationMs: metadata.durationMs,
      artUri: metadata.artUri,
    );
  }

  @override
  Future<void> clearState() async {
    if (_disposed) return;
    _isPlaying = false;
    _pausedByTransientInterruption = false;
    await _handler?.clearPlayback();
    await _audioSession?.setActive(false);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _commandHandler = null;
    _seekHandler = null;
    _handler?.detachBridgeCallbacks();
    _handler = null;
    await Future.wait([
      ?_noisySub?.cancel(),
      ?_interruptionSub?.cancel(),
    ]);
  }
}
