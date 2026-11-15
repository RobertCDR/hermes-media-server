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
  });

  final String title;
  final String artist;
  final String album;
  final bool isPlaying;
  final int positionMs;
  final int durationMs;
}

abstract interface class PlatformMediaBridge {
  Future<void> publishState(MediaBridgeMetadata metadata);
  Future<void> clearState();
  void setCommandHandler(FutureOr<void> Function(MediaButtonAction action) handler);
}

class InMemoryPlatformMediaBridge implements PlatformMediaBridge {
  MediaBridgeMetadata? lastPublished;
  FutureOr<void> Function(MediaButtonAction action)? _handler;

  @override
  Future<void> publishState(MediaBridgeMetadata metadata) async {
    lastPublished = metadata;
  }

  @override
  Future<void> clearState() async {
    lastPublished = null;
  }

  @override
  void setCommandHandler(FutureOr<void> Function(MediaButtonAction action) handler) {
    _handler = handler;
  }

  Future<void> simulateMediaButton(MediaButtonAction action) async {
    final handler = _handler;
    if (handler != null) {
      await handler(action);
    }
  }
}
