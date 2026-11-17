import 'dart:async';

enum MediaButtonAction { play, pause, next, previous, stop }

class MediaBridgeMetadata {
  const MediaBridgeMetadata({
    required this.title,
    required this.artist,
    required this.album,
    required this.isPlaying,
    required this.positionMs,
    required this.durationMs,
    this.artUri,
  });

  final String title;
  final String artist;
  final String album;
  final bool isPlaying;
  final int positionMs;
  final int durationMs;
  final Uri? artUri;
}

abstract interface class PlatformMediaBridge {
  Future<void> publishState(MediaBridgeMetadata metadata);
  Future<void> clearState();
  void setCommandHandler(
    FutureOr<void> Function(MediaButtonAction action) handler,
  );
}

abstract interface class SeekCapableMediaBridge implements PlatformMediaBridge {
  void setSeekHandler(FutureOr<void> Function(int positionMs) handler);
}

abstract interface class DisposableMediaBridge implements PlatformMediaBridge {
  Future<void> dispose();
}

class InMemoryPlatformMediaBridge
    implements SeekCapableMediaBridge, DisposableMediaBridge {
  MediaBridgeMetadata? lastPublished;
  FutureOr<void> Function(MediaButtonAction action)? _handler;
  FutureOr<void> Function(int positionMs)? _seekHandler;

  @override
  Future<void> publishState(MediaBridgeMetadata metadata) async {
    lastPublished = metadata;
  }

  @override
  Future<void> clearState() async {
    lastPublished = null;
  }

  @override
  void setCommandHandler(
    FutureOr<void> Function(MediaButtonAction action) handler,
  ) {
    _handler = handler;
  }

  @override
  void setSeekHandler(FutureOr<void> Function(int positionMs) handler) {
    _seekHandler = handler;
  }

  Future<void> simulateMediaButton(MediaButtonAction action) async {
    final handler = _handler;
    if (handler != null) {
      await handler(action);
    }
  }

  Future<void> simulateSeek(int positionMs) async {
    final handler = _seekHandler;
    if (handler != null) {
      await handler(positionMs);
    }
  }

  @override
  Future<void> dispose() async {
    _handler = null;
    _seekHandler = null;
  }
}
