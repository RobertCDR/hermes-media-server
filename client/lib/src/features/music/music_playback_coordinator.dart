import 'dart:async';
import 'dart:math';
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
  Future<PlaybackSessionState> transferOutput(String targetDeviceId, {int? positionMs});
  Future<List<OnlineDeviceModel>> getOnlineDevices();
}

abstract interface class AudioEngineAdapter {
  Future<void> loadAndPlay(Uri streamUri, SongModel track, int startPositionMs);
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(int positionMs);
}

abstract interface class ControllableAudioEngine implements AudioEngineAdapter {
  Future<void> resume();
  Future<void> setVolume(double volume01);
  Future<void> setNormalizationEnabled(bool enabled);
  Stream<int> get positionMsStream;
  Stream<void> get trackCompletedStream;
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
    this.onProgressHeartbeat,
  }) : _ticketIssuer = ticketIssuer ?? musicService.issueAudioTicket {
    if (catalogSongs != null) {
      _songsById.addAll(catalogSongs);
    }
    mediaBridge.setCommandHandler(_handleMediaButton);
    if (mediaBridge case final SeekCapableMediaBridge seeker) {
      seeker.setSeekHandler(seekTo);
    }
    if (audioEngine case final ControllableAudioEngine controllable) {
      _positionSub = controllable.positionMsStream.listen(_onEnginePositionMs);
      _completedSub = controllable.trackCompletedStream.listen((_) {
        unawaited(_onEngineTrackCompleted());
      });
    }
  }

  final String localDeviceId;
  final MusicService musicService;
  final AudioEngineAdapter audioEngine;
  final PlatformMediaBridge mediaBridge;
  final ConnectTransport? transport;
  AudioQualityPolicy audioQualityPolicy;
  final Future<String> Function(String songId) _ticketIssuer;
  Future<void> Function(int positionMs)? onProgressHeartbeat;

  final Map<String, SongModel> _songsById = {};
  final List<String> _upNextSongIds = [];
  NetworkTransportMode _networkMode = NetworkTransportMode.wifi;
  PlaybackSessionState? _session;
  String? _lastRecordedListenSongId;
  int _lastAppliedVersion = 0;
  String? _activeSourceLabel;
  MusicPageRoute? _activeSourceRoute;
  bool _nowPlayingOpen = false;
  double _lastNonZeroVolume = 0.85;
  final Random _random = Random();

  StreamSubscription<int>? _positionSub;
  StreamSubscription<void>? _completedSub;
  Timer? _remoteTickTimer;
  String? _loadedTrackId;
  AudioQualityPreset? _loadedQuality;
  PlaybackState _loadedEngineState = PlaybackState.stopped;
  int _livePositionMs = 0;
  int _lastNotifiedPositionMs = -1000;
  int _lastHeartbeatPositionMs = -10000;
  bool _disposed = false;

  int get lastAppliedVersion => _lastAppliedVersion;
  PlaybackSessionState? get session => _session;
  int get currentPositionMs =>
      _session != null && _session!.state != PlaybackState.stopped
          ? _livePositionMs
          : (_session?.positionMs ?? 0);
  NetworkTransportMode get networkMode => _networkMode;
  AudioQualityPreset get effectiveQuality => audioQualityPolicy.presetFor(_networkMode);
  bool get nowPlayingOpen => _nowPlayingOpen;
  String? get activeSourceLabel => _activeSourceLabel;
  MusicPageRoute? get activeSourceRoute => _activeSourceRoute;

  bool get isLocalRenderer =>
      _session != null && _session!.activeRendererDeviceId == localDeviceId;

  SongModel? get currentSong {
    final songId = _session?.currentSongId;
    return songId == null ? null : _songsById[songId];
  }

  SongModel? songById(String songId) => _songsById[songId];

  List<SongModel> get upNext => _upNextSongIds
      .map((id) => _songsById[id])
      .whereType<SongModel>()
      .toList();

  List<SongModel> get upcomingFromSource {
    final s = _session;
    if (s == null || s.queueSongIds.isEmpty) {
      return const [];
    }
    final start = (s.currentIndex + 1).clamp(0, s.queueSongIds.length);
    return s.queueSongIds
        .sublist(start)
        .map((id) => _songsById[id])
        .whereType<SongModel>()
        .toList();
  }

  void indexSongs(List<SongModel> songs) {
    var changed = false;
    for (final song in songs) {
      final existing = _songsById[song.id];
      if (existing == null || existing.isLiked != song.isLiked || existing.title != song.title) {
        changed = true;
      }
      _songsById[song.id] = song;
    }
    if (changed) {
      notifyListeners();
    }
  }

  void updateSongLikeState(String songId, bool liked) {
    final existing = _songsById[songId];
    if (existing == null || existing.isLiked == liked) {
      return;
    }
    _songsById[songId] = existing.copyWith(isLiked: liked);
    notifyListeners();
  }

  Future<bool> toggleLikeSong(String songId) async {
    final nextLiked = await musicService.toggleLikeSong(songId);
    updateSongLikeState(songId, nextLiked);
    return nextLiked;
  }

  void toggleNowPlaying([bool? open]) {
    final next = open ?? !_nowPlayingOpen;
    if (_nowPlayingOpen == next) {
      return;
    }
    _nowPlayingOpen = next;
    notifyListeners();
  }

  void addToQueue(SongModel song) {
    _songsById[song.id] = song;
    _upNextSongIds.add(song.id);
    notifyListeners();
  }

  void addAllToQueue(Iterable<SongModel> songs) {
    var added = false;
    for (final song in songs) {
      _songsById[song.id] = song;
      _upNextSongIds.add(song.id);
      added = true;
    }
    if (added) {
      notifyListeners();
    }
  }

  void playNext(SongModel song) {
    _songsById[song.id] = song;
    _upNextSongIds.insert(0, song.id);
    notifyListeners();
  }

  void removeFromUpNext(int index) {
    if (index < 0 || index >= _upNextSongIds.length) {
      return;
    }
    _upNextSongIds.removeAt(index);
    notifyListeners();
  }

  void clearUpNext() {
    if (_upNextSongIds.isEmpty) {
      return;
    }
    _upNextSongIds.clear();
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

  Future<void> setNormalizationEnabled(bool enabled) async {
    if (audioEngine case final ControllableAudioEngine controllable) {
      await controllable.setNormalizationEnabled(enabled);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _remoteTickTimer?.cancel();
    _remoteTickTimer = null;
    unawaited(_positionSub?.cancel());
    unawaited(_completedSub?.cancel());
    _positionSub = null;
    _completedSub = null;
    super.dispose();
  }

  void _syncRemoteProgressTimer() {
    final shouldTick =
        !_disposed && !isLocalRenderer && _session?.state == PlaybackState.playing;
    if (!shouldTick) {
      _remoteTickTimer?.cancel();
      _remoteTickTimer = null;
      return;
    }

    if (_remoteTickTimer != null && _remoteTickTimer!.isActive) {
      return;
    }

    _remoteTickTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_disposed || isLocalRenderer || _session?.state != PlaybackState.playing) {
        _remoteTickTimer?.cancel();
        _remoteTickTimer = null;
        return;
      }
      final maxDur = currentSong?.durationMs ?? 0;
      final next = _livePositionMs + 250;
      _livePositionMs = maxDur > 0 ? next.clamp(0, maxDur) : next;
      notifyListeners();
    });
  }

  void _onEnginePositionMs(int positionMs) {
    if (_disposed || !isLocalRenderer || _session?.state != PlaybackState.playing) {
      return;
    }
    _livePositionMs = positionMs;
    if ((positionMs - _lastNotifiedPositionMs).abs() >= 250) {
      _lastNotifiedPositionMs = positionMs;
      notifyListeners();
    }
    if ((positionMs - _lastHeartbeatPositionMs).abs() >= 3000) {
      _lastHeartbeatPositionMs = positionMs;
      final cb = onProgressHeartbeat;
      if (cb != null) {
        unawaited(cb(positionMs));
      }
    }

    final track = currentSong;
    if (track != null && _lastRecordedListenSongId != track.id) {
      final dur = track.durationMs;
      final threshold = dur > 0 ? min(30000, max(5000, dur ~/ 3)) : 5000;
      if (positionMs >= threshold) {
        _lastRecordedListenSongId = track.id;
        unawaited(_recordListenSafely(track, positionMs));
      }
    }
  }

  Future<void> _recordListenSafely(SongModel track, int positionMs) async {
    try {
      await musicService.recordListen(
        songId: track.id,
        positionMs: positionMs,
        durationMs: track.durationMs,
        deviceId: localDeviceId,
        contextLabel: activeSourceLabel,
      );
    } catch (_) {
      // History sync is best-effort and must never interrupt playback.
    }
  }

  Future<void> _onEngineTrackCompleted() async {
    if (_disposed || !isLocalRenderer) {
      return;
    }
    final current = _session;
    if (current == null || current.state != PlaybackState.playing) {
      return;
    }
    _loadedTrackId = null;
    _loadedEngineState = PlaybackState.stopped;

    if (current.repeatMode == HermesRepeatMode.one) {
      await _dispatchTransport(
        PlaybackState.playing,
        currentIndex: current.currentIndex,
        positionMs: 0,
      );
      return;
    }

    final hasNext = _upNextSongIds.isNotEmpty ||
        current.repeatMode == HermesRepeatMode.all ||
        current.currentIndex + 1 < current.queueSongIds.length;
    if (hasNext) {
      await skipNext();
    } else {
      await _dispatchTransport(PlaybackState.paused, positionMs: 0);
    }
  }

  Future<void> applyServerSession(PlaybackSessionState incoming) async {
    // Strict monotonic Connect guard: discard stale/reordered packets.
    if (_disposed || incoming.version < _lastAppliedVersion) {
      return;
    }

    final previousTrackId = _session?.currentSongId;
    final previousVolume = _session?.volume;
    _lastAppliedVersion = incoming.version;
    _session = incoming;
    if (incoming.volume > 0) {
      _lastNonZeroVolume = incoming.volume;
    }
    final rendererLocal = incoming.activeRendererDeviceId == localDeviceId;

    if (!rendererLocal) {
      // Remote Control mode: silence local output and clear OS media notification without stealing ActiveRenderer.
      _loadedTrackId = null;
      _loadedQuality = null;
      _loadedEngineState = PlaybackState.stopped;
      _livePositionMs = incoming.positionMs;
      _syncRemoteProgressTimer();
      await audioEngine.stop();
      await mediaBridge.clearState();
      notifyListeners();
      return;
    }

    _syncRemoteProgressTimer();

    final trackId = incoming.currentSongId;
    final track = trackId == null ? null : _songsById[trackId];

    if (incoming.state == PlaybackState.playing && track != null) {
      final controllable = audioEngine is ControllableAudioEngine
          ? audioEngine as ControllableAudioEngine
          : null;
      final quality = effectiveQuality;
      final sameTrackLoaded = controllable != null &&
          _loadedTrackId == track.id &&
          _loadedQuality == quality &&
          _loadedEngineState != PlaybackState.stopped;

      if (sameTrackLoaded) {
        if (previousVolume != incoming.volume) {
          await controllable.setVolume(incoming.volume);
        }
        if ((incoming.positionMs - _livePositionMs).abs() > 2500) {
          _livePositionMs = incoming.positionMs;
          await audioEngine.seek(incoming.positionMs);
        }
        if (_loadedEngineState == PlaybackState.paused) {
          await controllable.resume();
        }
        _loadedEngineState = PlaybackState.playing;
      } else {
        final ticket = await _ticketIssuer(track.id);
        final streamUri = musicService.buildAudioStreamUri(
          songId: track.id,
          ticket: ticket,
          quality: quality,
        );
        _loadedTrackId = track.id;
        _loadedQuality = quality;
        _loadedEngineState = PlaybackState.playing;
        _livePositionMs = incoming.positionMs;
        _lastNotifiedPositionMs = incoming.positionMs;
        _lastHeartbeatPositionMs = incoming.positionMs;
        await audioEngine.loadAndPlay(streamUri, track, incoming.positionMs);
        await controllable?.setVolume(incoming.volume);
      }
      await mediaBridge.publishState(
        MediaBridgeMetadata(
          title: track.title,
          artist: track.artistName,
          album: track.albumTitle,
          isPlaying: true,
          positionMs: _livePositionMs,
          durationMs: track.durationMs,
          artUri: musicService.buildArtworkUri(track.artworkHash),
        ),
      );
    } else if (incoming.state == PlaybackState.paused && track != null) {
      if (previousTrackId != track.id ||
          (incoming.positionMs - _livePositionMs).abs() > 2500) {
        _livePositionMs = incoming.positionMs;
      }
      _loadedEngineState = PlaybackState.paused;
      if (audioEngine case final ControllableAudioEngine controllable) {
        if (previousVolume != incoming.volume) {
          await controllable.setVolume(incoming.volume);
        }
      }
      await audioEngine.pause();
      await mediaBridge.publishState(
        MediaBridgeMetadata(
          title: track.title,
          artist: track.artistName,
          album: track.albumTitle,
          isPlaying: false,
          positionMs: _livePositionMs,
          durationMs: track.durationMs,
          artUri: musicService.buildArtworkUri(track.artworkHash),
        ),
      );
    } else {
      _loadedTrackId = null;
      _loadedQuality = null;
      _loadedEngineState = PlaybackState.stopped;
      _livePositionMs = 0;
      await audioEngine.stop();
      await mediaBridge.clearState();
    }

    notifyListeners();
  }

  Future<void> startQueue(
    List<SongModel> songs,
    int startIndex, {
    String? sourceLabel,
    MusicPageRoute? sourceRoute,
  }) async {
    if (songs.isEmpty) {
      return;
    }
    final safeIndex = startIndex.clamp(0, songs.length - 1);
    indexSongs(songs);
    _activeSourceLabel = sourceLabel ?? songs[safeIndex].albumTitle;
    _activeSourceRoute = sourceRoute;
    final ids = songs.map((s) => s.id).toList();
    if (transport != null) {
      final updated = await transport!.startPlayback(ids, safeIndex);
      await applyServerSession(updated);
      return;
    }

    final currentRepeat = _session?.repeatMode ?? HermesRepeatMode.off;
    final currentShuffle = _session?.shuffle ?? false;
    final currentVol = _session?.volume ?? _lastNonZeroVolume;
    await applyServerSession(
      PlaybackSessionState(
        sessionId: 'local',
        version: _lastAppliedVersion + 1,
        activeRendererDeviceId: localDeviceId,
        activeRendererDeviceName: 'This Device',
        state: PlaybackState.playing,
        repeatMode: currentRepeat,
        shuffle: currentShuffle,
        volume: currentVol,
        currentIndex: safeIndex,
        currentSongId: ids[safeIndex],
        positionMs: 0,
        queueSongIds: ids,
      ),
    );
  }

  Future<void> playAtIndex(int index) async {
    final current = _session;
    if (current == null || current.queueSongIds.isEmpty) {
      return;
    }
    final safeIndex = index.clamp(0, current.queueSongIds.length - 1);
    await _dispatchTransport(PlaybackState.playing, currentIndex: safeIndex, positionMs: 0);
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

  Future<void> playUpNextAt(int index) async {
    final current = _session;
    if (index < 0 || index >= _upNextSongIds.length) {
      return;
    }
    final nextId = _upNextSongIds.removeAt(index);
    if (current == null || current.queueSongIds.isEmpty) {
      final song = _songsById[nextId];
      if (song != null) {
        await startQueue([song], 0);
      }
      return;
    }

    final updatedQueue = List<String>.from(current.queueSongIds);
    final insertAt = (current.currentIndex + 1).clamp(0, updatedQueue.length);
    updatedQueue.insert(insertAt, nextId);
    if (transport != null) {
      final updated = await transport!.startPlayback(updatedQueue, insertAt);
      await applyServerSession(updated);
      return;
    }
    await applyServerSession(
      PlaybackSessionState(
        sessionId: current.sessionId,
        version: _lastAppliedVersion + 1,
        activeRendererDeviceId: current.activeRendererDeviceId,
        activeRendererDeviceName: current.activeRendererDeviceName,
        state: PlaybackState.playing,
        repeatMode: current.repeatMode,
        shuffle: current.shuffle,
        volume: current.volume,
        currentIndex: insertAt,
        currentSongId: nextId,
        positionMs: 0,
        queueSongIds: updatedQueue,
      ),
    );
  }

  Future<void> skipNext() async {
    final current = _session;
    if (current == null || current.queueSongIds.isEmpty) {
      return;
    }

    if (_upNextSongIds.isNotEmpty) {
      await playUpNextAt(0);
      return;
    }

    final length = current.queueSongIds.length;
    var nextIndex = (current.currentIndex + 1) % length;
    if (current.repeatMode == HermesRepeatMode.one) {
      nextIndex = current.currentIndex;
    } else if (current.shuffle && length > 1) {
      var candidate = _random.nextInt(length);
      if (candidate == current.currentIndex) {
        candidate = (current.currentIndex + 1) % length;
      }
      nextIndex = candidate;
    }
    await _dispatchTransport(PlaybackState.playing, currentIndex: nextIndex, positionMs: 0);
  }

  Future<void> skipPrevious() async {
    final current = _session;
    if (current == null || current.queueSongIds.isEmpty) {
      return;
    }

    if (current.positionMs > 4000) {
      await seekTo(0);
      return;
    }

    final prevIndex = (current.currentIndex - 1 + current.queueSongIds.length) % current.queueSongIds.length;
    await _dispatchTransport(PlaybackState.playing, currentIndex: prevIndex, positionMs: 0);
  }

  Future<void> seekTo(int positionMs) async {
    final current = _session;
    if (current == null) {
      return;
    }
    final duration = currentSong?.durationMs ?? positionMs;
    final clamped = positionMs.clamp(0, duration > 0 ? duration : positionMs);
    if (isLocalRenderer) {
      _livePositionMs = clamped;
      _lastNotifiedPositionMs = clamped;
      await audioEngine.seek(clamped);
    }
    await _dispatchTransport(current.state, positionMs: clamped);
  }

  Future<void> toggleShuffle() async {
    final current = _session;
    if (current == null) {
      return;
    }
    await _dispatchTransport(current.state, shuffle: !current.shuffle);
  }

  Future<void> cycleRepeatMode() async {
    final current = _session;
    if (current == null) {
      return;
    }
    final nextMode = switch (current.repeatMode) {
      HermesRepeatMode.off => HermesRepeatMode.all,
      HermesRepeatMode.all => HermesRepeatMode.one,
      HermesRepeatMode.one => HermesRepeatMode.off,
    };
    await _dispatchTransport(current.state, repeatMode: nextMode);
  }

  Future<void> setVolume(double volume) async {
    final current = _session;
    if (current == null) {
      return;
    }
    final clamped = volume.clamp(0.0, 1.0);
    if (clamped > 0.0) {
      _lastNonZeroVolume = clamped;
    }
    await _dispatchTransport(current.state, volume: clamped);
  }

  Future<void> toggleMute() async {
    final current = _session;
    if (current == null) {
      return;
    }
    final nextVol = current.volume > 0 ? 0.0 : (_lastNonZeroVolume > 0 ? _lastNonZeroVolume : 0.7);
    await setVolume(nextVol);
  }

  Future<void> transferOutputTo(String targetDeviceId) async {
    if (transport != null) {
      final updated = await transport!.transferOutput(
        targetDeviceId,
        positionMs: currentPositionMs,
      );
      await applyServerSession(updated);
    }
  }

  Future<void> _dispatchTransport(
    PlaybackState state, {
    int? currentIndex,
    int? positionMs,
    HermesRepeatMode? repeatMode,
    bool? shuffle,
    double? volume,
  }) async {
    if (transport != null) {
      final updated = await transport!.sendTransport(
        state,
        currentIndex: currentIndex,
        positionMs: positionMs,
        repeatMode: repeatMode,
        shuffle: shuffle,
        volume: volume,
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
        repeatMode: repeatMode ?? current.repeatMode,
        shuffle: shuffle ?? current.shuffle,
        volume: volume ?? current.volume,
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
