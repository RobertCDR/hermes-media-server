import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_client/src/features/music/music_models.dart';
import 'package:hermes_client/src/features/music/music_playback_coordinator.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class SpyAudioEngine
    implements ControllableAudioEngine, PrewarmableAudioEngine {
  final _posController = StreamController<int>.broadcast();
  final _doneController = StreamController<void>.broadcast();
  final List<String> loadedSongIds = [];
  final List<int> seekPositions = [];
  final List<double> setVolumes = [];
  int warmUpCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;
  int resumeCalls = 0;

  @override
  Stream<int> get positionMsStream => _posController.stream;

  @override
  Stream<void> get trackCompletedStream => _doneController.stream;

  void emitPositionMs(int posMs) {
    if (!_posController.isClosed) {
      _posController.add(posMs);
    }
  }

  void emitCompleted() {
    if (!_doneController.isClosed) {
      _doneController.add(null);
    }
  }

  @override
  Future<void> warmUp() async {
    warmUpCalls++;
  }

  @override
  Future<void> loadAndPlay(
    Uri streamUri,
    SongModel track,
    int startPositionMs,
  ) async {
    loadedSongIds.add(track.id);
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
  }

  @override
  Future<void> resume() async {
    resumeCalls++;
  }

  @override
  Future<void> seek(int positionMs) async {
    seekPositions.add(positionMs);
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  Future<void> setVolume(double volume01) async {
    setVolumes.add(volume01);
  }

  @override
  Future<void> setNormalizationEnabled(bool enabled) async {}

  Future<void> dispose() async {
    await _posController.close();
    await _doneController.close();
  }
}

class SpyConnectTransport implements ConnectTransport {
  int startPlaybackCalls = 0;
  final List<String> sentCommands = [];
  final List<double?> sentVolumes = [];
  String? lastTransferredTarget;
  String sessionId = 'sess-1';
  int version = 1;
  String activeRendererDeviceId = 'dev-pc';
  String activeRendererDeviceName = 'Desktop PC';
  int lastCurrentIndex = 0;
  double lastVolume = 1.0;

  @override
  Future<List<OnlineDeviceModel>> getOnlineDevices() async => const [];

  @override
  Future<PlaybackSessionState> startPlayback(
    List<String> queueSongIds,
    int startIndex,
  ) async {
    startPlaybackCalls++;
    version++;
    lastCurrentIndex = startIndex;
    return PlaybackSessionState(
      sessionId: sessionId,
      version: version,
      activeRendererDeviceId: activeRendererDeviceId,
      activeRendererDeviceName: activeRendererDeviceName,
      state: PlaybackState.playing,
      repeatMode: HermesRepeatMode.off,
      shuffle: false,
      volume: lastVolume,
      currentIndex: startIndex,
      currentSongId: queueSongIds.isEmpty ? null : queueSongIds[startIndex],
      positionMs: 0,
      queueSongIds: queueSongIds,
    );
  }

  @override
  Future<PlaybackSessionState> sendTransport(
    PlaybackState state, {
    int? currentIndex,
    int? positionMs,
    HermesRepeatMode? repeatMode,
    bool? shuffle,
    double? volume,
    List<String>? queueSongIds,
  }) async {
    sentCommands.add('${state.name}:$currentIndex');
    sentVolumes.add(volume);
    if (currentIndex != null) {
      lastCurrentIndex = currentIndex;
    }
    if (volume != null) {
      lastVolume = volume;
    }
    version++;
    final queue = queueSongIds ?? const ['s-1'];
    final idx = (currentIndex ?? lastCurrentIndex).clamp(0, queue.length - 1);
    return PlaybackSessionState(
      sessionId: sessionId,
      version: version,
      activeRendererDeviceId: activeRendererDeviceId,
      activeRendererDeviceName: activeRendererDeviceName,
      state: state,
      repeatMode: repeatMode ?? HermesRepeatMode.off,
      shuffle: shuffle ?? false,
      volume: lastVolume,
      currentIndex: idx,
      currentSongId: queue[idx],
      positionMs: positionMs ?? 0,
      queueSongIds: queue,
    );
  }

  @override
  Future<PlaybackSessionState> transferOutput(
    String targetDeviceId, {
    int? positionMs,
  }) async {
    version++;
    lastTransferredTarget = targetDeviceId;
    activeRendererDeviceId = targetDeviceId;
    return PlaybackSessionState(
      sessionId: sessionId,
      version: version,
      activeRendererDeviceId: targetDeviceId,
      activeRendererDeviceName: 'Target',
      state: PlaybackState.playing,
      repeatMode: HermesRepeatMode.off,
      shuffle: false,
      volume: lastVolume,
      currentIndex: lastCurrentIndex,
      currentSongId: 's-1',
      positionMs: positionMs ?? 0,
      queueSongIds: const ['s-1'],
    );
  }
}

class _FakeWebSocketSink extends Fake implements WebSocketSink {
  _FakeWebSocketSink(this.onAdd, this.onClose);

  final void Function(dynamic data) onAdd;
  final Future<void> Function() onClose;

  @override
  void add(dynamic data) => onAdd(data);

  @override
  Future<void> get done => Future<void>.value();

  @override
  Future<void> close([int? closeCode, String? closeReason]) => onClose();
}

class FakeWebSocketChannel extends Fake implements WebSocketChannel {
  FakeWebSocketChannel() {
    _sink = _FakeWebSocketSink(
      (data) => sentMessages.add(data.toString()),
      () async {
        closed = true;
        if (!_incoming.isClosed) {
          await _incoming.close();
        }
      },
    );
  }

  final _incoming = StreamController<dynamic>.broadcast();
  late final _FakeWebSocketSink _sink;
  final List<String> sentMessages = [];
  bool closed = false;

  void pushServerText(String text) {
    if (!_incoming.isClosed) {
      _incoming.add(text);
    }
  }

  @override
  Future<void> get ready => Future<void>.value();

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _sink;

  Future<void> dispose() async {
    await _incoming.close();
  }
}

SongModel makeSampleSong({
  String id = 's-1',
  String title = 'Midnight City',
  String artistId = 'art-1',
  String artistName = 'M83',
  String albumId = 'alb-1',
  String albumTitle = 'Hurry Up, Were Dreaming',
  int durationMs = 244000,
  List<ArtistCreditModel> artistCredits = const [],
}) =>
    SongModel(
      id: id,
      artistId: artistId,
      artistName: artistName,
      albumId: albumId,
      albumTitle: albumTitle,
      title: title,
      trackNumber: 1,
      discNumber: 1,
      durationMs: durationMs,
      codec: 'flac',
      bitrateBps: 1411000,
      sampleRateHz: 44100,
      bitDepth: 16,
      isLiked: false,
      isMissing: false,
      artistCredits: artistCredits,
    );
