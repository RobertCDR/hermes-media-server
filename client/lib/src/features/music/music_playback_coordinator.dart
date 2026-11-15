import 'package:material_ui/material_ui.dart';
import 'music_models.dart';
import 'music_service.dart';
import 'platform_media_bridge.dart';

abstract interface class ConnectTransport {
  Future<PlaybackSessionState> startPlayback(List<String> queueSongIds, int startIndex);
  Future<PlaybackSessionState> sendTransport(
    PlaybackState state, {
    int? currentIndex,
    int? positionMs,
    HermesRepeatMode? repeatMode,
    bool? shuffle,
    double? volume,
  });
  Future<PlaybackSessionState> transferOutput(String targetDeviceId);
  Future<List<OnlineDeviceModel>> getOnlineDevices();
}

abstract interface class AudioEngineAdapter {
  Future<void> loadAndPlay(Uri streamUri, SongModel track, int startPositionMs);
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(int positionMs);
}

class NoOpAudioEngineAdapter implements AudioEngineAdapter {
  @override
  Future<void> loadAndPlay(Uri streamUri, SongModel track, int startPositionMs) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(int positionMs) async {}

  @override
  Future<void> stop() async {}
}

class MusicPlaybackCoordinator extends ChangeNotifier {
  MusicPlaybackCoordinator({
    required this.localDeviceId,
    required this.musicService,
    required this.audioEngine,
    required this.mediaBridge,
    this.transport,
    this.audioQualityPolicy = const AudioQualityPolicy(),
    Future<String> Function(String songId)? ticketIssuer,
    Map<String, SongModel>? catalogSongs,
  }) : _ticketIssuer = ticketIssuer ?? musicService.issueAudioTicket {
    if (catalogSongs != null) {
      _songsById.addAll(catalogSongs);
    }
    mediaBridge.setCommandHandler(_handleMediaButton);
  }

  final String localDeviceId;
  final MusicService musicService;
  final AudioEngineAdapter audioEngine;
  final PlatformMediaBridge mediaBridge;
  final ConnectTransport? transport;
  AudioQualityPolicy audioQualityPolicy;
  final Future<String> Function(String songId) _ticketIssuer;

  final Map<String, SongModel> _songsById = {};
  NetworkTransportMode _networkMode = NetworkTransportMode.wifi;
  PlaybackSessionState? _session;
  int _lastAppliedVersion = 0;

  int get lastAppliedVersion => _lastAppliedVersion;
  PlaybackSessionState? get session => _session;
  NetworkTransportMode get networkMode => _networkMode;
  AudioQualityPreset get effectiveQuality => audioQualityPolicy.presetFor(_networkMode);

  bool get isLocalRenderer =>
      _session != null && _session!.activeRendererDeviceId == localDeviceId;

  SongModel? get currentSong {
    final songId = _session?.currentSongId;
    return songId == null ? null : _songsById[songId];
  }

  void indexSongs(List<SongModel> songs) {
    for (final song in songs) {
      _songsById[song.id] = song;
    }
    notifyListeners();
  }

  void setNetworkMode(NetworkTransportMode mode) {
    _networkMode = mode;
    notifyListeners();
  }

  void updateQualityPolicy(AudioQualityPolicy nextPolicy) {
    audioQualityPolicy = nextPolicy;
    notifyListeners();
  }

  Future<void> applyServerSession(PlaybackSessionState incoming) async {
    // Strict monotonic Connect guard: discard stale/reordered packets.
    if (incoming.version <= _lastAppliedVersion) {
      return;
    }

    _lastAppliedVersion = incoming.version;
    _session = incoming;
    final rendererLocal = incoming.activeRendererDeviceId == localDeviceId;

    if (!rendererLocal) {
      // Remote Control mode: silence local output without stealing ActiveRenderer.
      await audioEngine.stop();
      notifyListeners();
      return;
    }

    final trackId = incoming.currentSongId;
    final track = trackId == null ? null : _songsById[trackId];

    if (incoming.state == PlaybackState.playing && track != null) {
      final ticket = await _ticketIssuer(track.id);
      final streamUri = musicService.buildAudioStreamUri(
        songId: track.id,
        ticket: ticket,
        quality: effectiveQuality,
      );
      await audioEngine.loadAndPlay(streamUri, track, incoming.positionMs);
      await mediaBridge.publishState(
        MediaBridgeMetadata(
          title: track.title,
          artist: track.artistName,
          album: track.albumTitle,
          isPlaying: true,
          positionMs: incoming.positionMs,
          durationMs: track.durationMs,
        ),
      );
    } else if (incoming.state == PlaybackState.paused && track != null) {
      await audioEngine.pause();
      await mediaBridge.publishState(
        MediaBridgeMetadata(
          title: track.title,
          artist: track.artistName,
          album: track.albumTitle,
          isPlaying: false,
          positionMs: incoming.positionMs,
          durationMs: track.durationMs,
        ),
      );
    } else {
      await audioEngine.stop();
      await mediaBridge.clearState();
    }

    notifyListeners();
  }

  Future<void> startQueue(List<SongModel> songs, int startIndex) async {
    indexSongs(songs);
    final ids = songs.map((s) => s.id).toList();
    if (transport != null) {
      final updated = await transport!.startPlayback(ids, startIndex);
      await applyServerSession(updated);
      return;
    }

    await applyServerSession(
      PlaybackSessionState(
        sessionId: 'local',
        version: _lastAppliedVersion + 1,
        activeRendererDeviceId: localDeviceId,
        activeRendererDeviceName: 'This Device',
        state: PlaybackState.playing,
        repeatMode: HermesRepeatMode.off,
        shuffle: false,
        volume: 1.0,
        currentIndex: startIndex,
        currentSongId: ids[startIndex],
        positionMs: 0,
        queueSongIds: ids,
      ),
    );
  }

  Future<void> togglePlayPause() async {
    final current = _session;
    if (current == null) {
      return;
    }

    final nextState = current.state == PlaybackState.playing
        ? PlaybackState.paused
        : PlaybackState.playing;
    await _dispatchTransport(nextState);
  }

  Future<void> skipNext() async {
    final current = _session;
    if (current == null || current.queueSongIds.isEmpty) {
      return;
    }

    final nextIndex = (current.currentIndex + 1) % current.queueSongIds.length;
    await _dispatchTransport(PlaybackState.playing, currentIndex: nextIndex, positionMs: 0);
  }

  Future<void> skipPrevious() async {
    final current = _session;
    if (current == null || current.queueSongIds.isEmpty) {
      return;
    }

    final prevIndex = (current.currentIndex - 1 + current.queueSongIds.length) % current.queueSongIds.length;
    await _dispatchTransport(PlaybackState.playing, currentIndex: prevIndex, positionMs: 0);
  }

  Future<void> transferOutputTo(String targetDeviceId) async {
    if (transport != null) {
      final updated = await transport!.transferOutput(targetDeviceId);
      await applyServerSession(updated);
    }
  }

  Future<void> _dispatchTransport(
    PlaybackState state, {
    int? currentIndex,
    int? positionMs,
  }) async {
    if (transport != null) {
      final updated = await transport!.sendTransport(
        state,
        currentIndex: currentIndex,
        positionMs: positionMs,
      );
      await applyServerSession(updated);
      return;
    }

    final current = _session;
    if (current == null) {
      return;
    }
    final nextIdx = currentIndex ?? current.currentIndex;
    final nextSongId = current.queueSongIds.isEmpty
        ? null
        : current.queueSongIds[nextIdx.clamp(0, current.queueSongIds.length - 1)];

    await applyServerSession(
      PlaybackSessionState(
        sessionId: current.sessionId,
        version: _lastAppliedVersion + 1,
        activeRendererDeviceId: current.activeRendererDeviceId,
        activeRendererDeviceName: current.activeRendererDeviceName,
        state: state,
        repeatMode: current.repeatMode,
        shuffle: current.shuffle,
        volume: current.volume,
        currentIndex: nextIdx,
        currentSongId: nextSongId,
        positionMs: positionMs ?? current.positionMs,
        queueSongIds: current.queueSongIds,
      ),
    );
  }

  Future<void> _handleMediaButton(MediaButtonAction action) async {
    switch (action) {
      case MediaButtonAction.play:
        await _dispatchTransport(PlaybackState.playing);
      case MediaButtonAction.pause:
        await _dispatchTransport(PlaybackState.paused);
      case MediaButtonAction.stop:
        await _dispatchTransport(PlaybackState.stopped);
      case MediaButtonAction.next:
        await skipNext();
      case MediaButtonAction.previous:
        await skipPrevious();
    }
  }
}
