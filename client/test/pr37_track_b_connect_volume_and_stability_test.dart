import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hermes_client/src/core/auth/auth_service.dart';
import 'package:hermes_client/src/core/auth/authenticated_http_client.dart';
import 'package:hermes_client/src/core/auth/session_store.dart';
import 'package:hermes_client/src/core/network/hermes_sync_client.dart';
import 'package:hermes_client/src/core/theme/hermes_theme_tokens.dart';
import 'package:hermes_client/src/features/admin/admin_dashboard_screen.dart';
import 'package:hermes_client/src/features/admin/admin_service.dart';
import 'package:hermes_client/src/features/cinema/cinema_service.dart';
import 'package:hermes_client/src/features/cinema/hermes_video_player.dart';
import 'package:hermes_client/src/features/music/device_picker_sheet.dart';
import 'package:hermes_client/src/features/music/music_models.dart';
import 'package:hermes_client/src/features/music/music_playback_coordinator.dart';
import 'package:hermes_client/src/features/music/music_service.dart';
import 'package:hermes_client/src/features/music/now_playing_panel.dart';
import 'package:hermes_client/src/features/music/platform_media_bridge.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _TrackingAudioEngine
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

class _RecordingConnectTransport implements ConnectTransport {
  int startPlaybackCalls = 0;
  final List<List<String>> startedQueues = [];
  final List<double?> sentVolumes = [];
  final List<List<String>?> sentQueues = [];
  final List<int?> sentIndices = [];
  String sessionId = 'sess-1';
  int version = 10;
  String activeRendererDeviceId = 'dev-pc';
  String activeRendererDeviceName = 'Desktop PC';
  int lastCurrentIndex = 0;
  double lastVolume = 0.8;

  @override
  Future<List<OnlineDeviceModel>> getOnlineDevices() async => const [];

  @override
  Future<PlaybackSessionState> startPlayback(
    List<String> queueSongIds,
    int startIndex,
  ) async {
    startPlaybackCalls++;
    startedQueues.add(List<String>.from(queueSongIds));
    version++;
    lastCurrentIndex = startIndex;
    activeRendererDeviceId = 'dev-phone';
    activeRendererDeviceName = 'Phone';
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
      currentSongId: queueSongIds[startIndex],
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
    sentVolumes.add(volume);
    sentQueues.add(queueSongIds);
    sentIndices.add(currentIndex);
    if (currentIndex != null) {
      lastCurrentIndex = currentIndex;
    }
    if (volume != null) {
      lastVolume = volume;
    }
    version++;
    final queue = queueSongIds ?? const ['s-1', 's-2'];
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
      currentIndex: 0,
      currentSongId: 's-1',
      positionMs: positionMs ?? 0,
      queueSongIds: const ['s-1', 's-2'],
    );
  }
}

class _FakeWsSink extends Fake implements WebSocketSink {
  @override
  void add(dynamic data) {}

  @override
  Future<void> get done => Future<void>.value();

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}
}

class _FakeWsChannel extends Fake implements WebSocketChannel {
  final _incoming = StreamController<dynamic>();
  final _sink = _FakeWsSink();

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

void main() {
  const song1 = SongModel(
    id: 's-1',
    artistId: 'art-1',
    artistName: 'Daft Punk, Pharrell Williams',
    albumId: 'alb-1',
    albumTitle: 'Random Access Memories',
    title: 'Get Lucky',
    trackNumber: 1,
    discNumber: 1,
    durationMs: 248000,
    codec: 'flac',
    bitrateBps: 1411000,
    sampleRateHz: 44100,
    bitDepth: 16,
    isLiked: false,
    isMissing: false,
    artistCredits: [
      ArtistCreditModel(artistId: 'art-1', name: 'Daft Punk'),
      ArtistCreditModel(artistId: 'art-2', name: 'Pharrell Williams'),
    ],
  );

  const song2 = SongModel(
    id: 's-2',
    artistId: 'art-1',
    artistName: 'Daft Punk',
    albumId: 'alb-1',
    albumTitle: 'Random Access Memories',
    title: 'Instant Crush',
    trackNumber: 2,
    discNumber: 1,
    durationMs: 337000,
    codec: 'flac',
    bitrateBps: 1411000,
    sampleRateHz: 44100,
    bitDepth: 16,
    isLiked: false,
    isMissing: false,
  );

  Map<String, dynamic> songJson(SongModel song) => {
        'id': song.id,
        'artistId': song.artistId,
        'artistName': song.artistName,
        'albumId': song.albumId,
        'albumTitle': song.albumTitle,
        'title': song.title,
        'trackNumber': song.trackNumber,
        'discNumber': song.discNumber,
        'durationMs': song.durationMs,
        'codec': song.codec,
        'bitrateBps': song.bitrateBps,
        'sampleRateHz': song.sampleRateHz,
        'bitDepth': song.bitDepth,
        'isLiked': song.isLiked,
        'isMissing': song.isMissing,
        'artistCredits': song.artistCredits
            .map((c) => {'artistId': c.artistId, 'name': c.name})
            .toList(),
      };

  MusicService buildMusicService({VoidCallback? onListSongs}) {
    final client = MockClient((req) async {
      if (req.url.path == '/api/v1/music/songs') {
        onListSongs?.call();
        return http.Response(jsonEncode([songJson(song1), songJson(song2)]), 200);
      }
      if (req.url.path.endsWith('/audio/ticket')) {
        return http.Response(jsonEncode({'ticket': 'tkt-http'}), 200);
      }
      return http.Response('{}', 200);
    });
    return MusicService(
      baseUri: Uri.parse('http://localhost:5258'),
      accessToken: 'jwt',
      httpClient: client,
    );
  }

  group('Track B Connect stability, remote renderer preservation & speed', () {
    test(
      'startQueue and playUpNextAt preserve remote renderer via sendTransport instead of startPlayback',
      () async {
        final engine = _TrackingAudioEngine();
        addTearDown(engine.dispose);
        final transport = _RecordingConnectTransport()
          ..activeRendererDeviceId = 'dev-pc'
          ..activeRendererDeviceName = 'Desktop PC';

        final coordinator = MusicPlaybackCoordinator(
          localDeviceId: 'dev-phone',
          musicService: buildMusicService(),
          audioEngine: engine,
          mediaBridge: InMemoryPlatformMediaBridge(),
          transport: transport,
          catalogSongs: {song1.id: song1, song2.id: song2},
          ticketIssuer: (id) async => 'tkt-$id',
        );
        addTearDown(coordinator.dispose);

        await coordinator.applyServerSession(
          const PlaybackSessionState(
            sessionId: 'sess-1',
            version: 2,
            activeRendererDeviceId: 'dev-pc',
            activeRendererDeviceName: 'Desktop PC',
            state: PlaybackState.playing,
            repeatMode: HermesRepeatMode.off,
            shuffle: false,
            volume: 0.8,
            currentIndex: 0,
            currentSongId: 's-1',
            positionMs: 1000,
            queueSongIds: ['s-1', 's-2'],
          ),
        );
        expect(coordinator.isControllingRemoteDevice, isTrue);
        expect(engine.warmUpCalls, 1);

        // Selecting another track on phone sends sendTransport with queueSongIds and keeps dev-pc.
        await coordinator.startQueue([song1, song2], 1, sourceLabel: 'RAM');
        expect(transport.startPlaybackCalls, 0);
        expect(transport.sentQueues.last, ['s-1', 's-2']);
        expect(transport.sentIndices.last, 1);
        expect(coordinator.session?.activeRendererDeviceId, 'dev-pc');
        expect(engine.loadedSongIds, isEmpty);

        // Playing an Up Next item also keeps dev-pc without hijacking renderer.
        coordinator.addToQueue(song1);
        await coordinator.playUpNextAt(0);
        expect(transport.startPlaybackCalls, 0);
        expect(coordinator.session?.activeRendererDeviceId, 'dev-pc');
      },
    );

    test(
      'deduplicates same-version echoes, caches tickets, accepts new sessionId, lazy-loads catalog, and survives in-flight volume update',
      () async {
        final engine = _TrackingAudioEngine();
        addTearDown(engine.dispose);
        var listSongsCalls = 0;
        var ticketCalls = 0;
        final pendingTicket = Completer<String>();

        final coordinator = MusicPlaybackCoordinator(
          localDeviceId: 'dev-pc',
          musicService: buildMusicService(onListSongs: () => listSongsCalls++),
          audioEngine: engine,
          mediaBridge: InMemoryPlatformMediaBridge(),
          ticketIssuer: (songId) {
            ticketCalls++;
            if (ticketCalls == 1 && songId == 's-1') {
              return pendingTicket.future;
            }
            return Future<String>.value('tkt-$songId-$ticketCalls');
          },
        );
        addTearDown(coordinator.dispose);

        // Start playback with empty catalogSongs; must lazy-load catalog and wait on pendingTicket.
        final firstApply = coordinator.applyServerSession(
          const PlaybackSessionState(
            sessionId: 'sess-a',
            version: 4,
            activeRendererDeviceId: 'dev-pc',
            activeRendererDeviceName: 'Desktop PC',
            state: PlaybackState.playing,
            repeatMode: HermesRepeatMode.off,
            shuffle: false,
            volume: 0.7,
            currentIndex: 0,
            currentSongId: 's-1',
            positionMs: 0,
            queueSongIds: ['s-1', 's-2'],
          ),
        );
        await pumpEventQueue();
        expect(listSongsCalls, 1);
        expect(ticketCalls, 1);

        // Duplicate same-version echo arrives -> ignored.
        await coordinator.applyServerSession(
          const PlaybackSessionState(
            sessionId: 'sess-a',
            version: 4,
            activeRendererDeviceId: 'dev-pc',
            activeRendererDeviceName: 'Desktop PC',
            state: PlaybackState.playing,
            repeatMode: HermesRepeatMode.off,
            shuffle: false,
            volume: 0.7,
            currentIndex: 0,
            currentSongId: 's-1',
            positionMs: 0,
            queueSongIds: ['s-1', 's-2'],
          ),
        );
        expect(ticketCalls, 1);

        // Volume update arrives while first ticket is still in flight -> must NOT mark _loadedTrackId early!
        final volumeApply = coordinator.applyServerSession(
          const PlaybackSessionState(
            sessionId: 'sess-a',
            version: 5,
            activeRendererDeviceId: 'dev-pc',
            activeRendererDeviceName: 'Desktop PC',
            state: PlaybackState.playing,
            repeatMode: HermesRepeatMode.off,
            shuffle: false,
            volume: 0.5,
            currentIndex: 0,
            currentSongId: 's-1',
            positionMs: 0,
            queueSongIds: ['s-1', 's-2'],
          ),
        );
        pendingTicket.complete('tkt-s-1');
        await Future.wait([firstApply, volumeApply]);

        // loadAndPlay must still execute once despite the concurrent v5 volume update!
        expect(engine.loadedSongIds, ['s-1']);

        // Switch away to s-2 and back to s-1 -> cached ticket reused for s-1!
        await coordinator.applyServerSession(
          const PlaybackSessionState(
            sessionId: 'sess-a',
            version: 6,
            activeRendererDeviceId: 'dev-pc',
            activeRendererDeviceName: 'Desktop PC',
            state: PlaybackState.playing,
            repeatMode: HermesRepeatMode.off,
            shuffle: false,
            volume: 0.5,
            currentIndex: 1,
            currentSongId: 's-2',
            positionMs: 0,
            queueSongIds: ['s-1', 's-2'],
          ),
        );
        expect(ticketCalls, 2);

        // Brand-new sessionId with version 1 (smaller version number than 6) must NOT be dropped!
        await coordinator.applyServerSession(
          const PlaybackSessionState(
            sessionId: 'sess-b',
            version: 1,
            activeRendererDeviceId: 'dev-pc',
            activeRendererDeviceName: 'Desktop PC',
            state: PlaybackState.playing,
            repeatMode: HermesRepeatMode.off,
            shuffle: false,
            volume: 0.6,
            currentIndex: 0,
            currentSongId: 's-1',
            positionMs: 0,
            queueSongIds: ['s-1', 's-2'],
          ),
        );
        expect(coordinator.session?.sessionId, 'sess-b');
        expect(ticketCalls, 2); // s-1 ticket served from 4h cache
        expect(engine.loadedSongIds, ['s-1', 's-2', 's-1']);
      },
    );

    test(
      'skipPrevious uses live engine position (> 4s) to restart track instead of jumping back',
      () async {
        final engine = _TrackingAudioEngine();
        addTearDown(engine.dispose);
        final transport = _RecordingConnectTransport()
          ..activeRendererDeviceId = 'dev-pc'
          ..lastCurrentIndex = 1;

        final coordinator = MusicPlaybackCoordinator(
          localDeviceId: 'dev-pc',
          musicService: buildMusicService(),
          audioEngine: engine,
          mediaBridge: InMemoryPlatformMediaBridge(),
          transport: transport,
          catalogSongs: {song1.id: song1, song2.id: song2},
          ticketIssuer: (id) async => 'tkt-$id',
        );
        addTearDown(coordinator.dispose);

        await coordinator.applyServerSession(
          const PlaybackSessionState(
            sessionId: 'sess-1',
            version: 1,
            activeRendererDeviceId: 'dev-pc',
            activeRendererDeviceName: 'Desktop PC',
            state: PlaybackState.playing,
            repeatMode: HermesRepeatMode.off,
            shuffle: false,
            volume: 0.9,
            currentIndex: 1,
            currentSongId: 's-2',
            positionMs: 0,
            queueSongIds: ['s-1', 's-2'],
          ),
        );

        engine.emitPositionMs(5200);
        await pumpEventQueue();

        await coordinator.skipPrevious();
        expect(coordinator.session?.currentIndex, 1);
        expect(coordinator.session?.currentSongId, 's-2');
      },
    );

    test(
      'setVolume coalesces rapid drags into one throttled transport call and toggleMute uses effectiveVolume',
      () async {
        final engine = _TrackingAudioEngine();
        addTearDown(engine.dispose);
        final transport = _RecordingConnectTransport()
          ..activeRendererDeviceId = 'dev-pc'
          ..lastCurrentIndex = 1;

        final coordinator = MusicPlaybackCoordinator(
          localDeviceId: 'dev-phone',
          musicService: buildMusicService(),
          audioEngine: engine,
          mediaBridge: InMemoryPlatformMediaBridge(),
          transport: transport,
          catalogSongs: {song1.id: song1},
          ticketIssuer: (id) async => 'tkt-$id',
        );
        addTearDown(coordinator.dispose);

        await coordinator.applyServerSession(
          const PlaybackSessionState(
            sessionId: 'sess-1',
            version: 1,
            activeRendererDeviceId: 'dev-pc',
            activeRendererDeviceName: 'Desktop PC',
            state: PlaybackState.playing,
            repeatMode: HermesRepeatMode.off,
            shuffle: false,
            volume: 0.8,
            currentIndex: 0,
            currentSongId: 's-1',
            positionMs: 0,
            queueSongIds: ['s-1'],
          ),
        );

        unawaited(coordinator.setVolume(0.4, immediate: false));
        unawaited(coordinator.setVolume(0.3, immediate: false));
        unawaited(coordinator.setVolume(0.25, immediate: false));
        expect(coordinator.effectiveVolume, 0.25);
        expect(transport.sentVolumes, isEmpty);

        await Future<void>.delayed(const Duration(milliseconds: 140));
        expect(transport.sentVolumes, [0.25]);

        await coordinator.setVolume(0.6, immediate: true);
        expect(transport.sentVolumes, [0.25, 0.6]);

        await coordinator.toggleMute();
        expect(coordinator.effectiveVolume, 0.0);
        expect(transport.sentVolumes.last, 0.0);

        await coordinator.toggleMute();
        expect(coordinator.effectiveVolume, 0.6);
      },
    );
  });

  group('Remote Volume UI & Player Artist Navigation widgets', () {
    testWidgets(
      'DevicePickerSheet deduplicates idle local device and forwards volume slider interactions',
      (tester) async {
        var selectedVol = 0.5;
        double? endedVol;
        var muteTaps = 0;

        final devices = [
          OnlineDeviceModel(
            deviceId: 'dev-phone',
            deviceName: 'Pixel 9',
            platform: 'Android',
            connectedAtUtc: DateTime.utc(2026, 11, 22),
          ),
          OnlineDeviceModel(
            deviceId: 'dev-pc',
            deviceName: 'Workstation',
            platform: 'Windows',
            connectedAtUtc: DateTime.utc(2026, 11, 22),
          ),
        ];

        await tester.pumpWidget(
          MaterialApp(
            theme: HermesThemeTokens.resolve().toThemeData(),
            home: Scaffold(
              body: DevicePickerSheet(
                devices: devices,
                activeRendererDeviceId: null,
                localDeviceId: 'dev-phone',
                volume: selectedVol,
                volumeTargetLabel: 'Volume · This device',
                onVolumeChanged: (v) => selectedVol = v,
                onVolumeChangeEnd: (v) => endedVol = v,
                onToggleMute: () => muteTaps++,
                onSelectDevice: (_) {},
              ),
            ),
          ),
        );

        expect(find.textContaining('Pixel 9'), findsOneWidget);
        expect(find.text('Workstation'), findsOneWidget);
        expect(find.text('Volume · This device'), findsOneWidget);
        expect(find.byType(Slider), findsOneWidget);

        await tester.tap(find.byIcon(Icons.volume_up_rounded));
        expect(muteTaps, 1);

        final sliderBox = tester.getRect(find.byType(Slider));
        await tester.dragFrom(
          sliderBox.center,
          Offset(sliderBox.width * 0.3, 0),
        );
        await tester.pumpAndSettle();
        expect(selectedVol, greaterThan(0.5));
        expect(endedVol, isNotNull);
      },
    );

    testWidgets(
      'MobileNowPlayingPage shows Remote volume bar only when controlling remote device and opens collaborator artist',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(412, 892));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final engine = _TrackingAudioEngine();
        addTearDown(engine.dispose);
        final transport = _RecordingConnectTransport()
          ..activeRendererDeviceId = 'dev-phone';
        final coordinator = MusicPlaybackCoordinator(
          localDeviceId: 'dev-phone',
          musicService: buildMusicService(),
          audioEngine: engine,
          mediaBridge: InMemoryPlatformMediaBridge(),
          transport: transport,
          catalogSongs: {song1.id: song1},
          ticketIssuer: (id) async => 'tkt-$id',
        );
        addTearDown(coordinator.dispose);

        await coordinator.applyServerSession(
          const PlaybackSessionState(
            sessionId: 'sess-1',
            version: 1,
            activeRendererDeviceId: 'dev-phone',
            activeRendererDeviceName: 'Pixel 9',
            state: PlaybackState.playing,
            repeatMode: HermesRepeatMode.off,
            shuffle: false,
            volume: 0.7,
            currentIndex: 0,
            currentSongId: 's-1',
            positionMs: 0,
            queueSongIds: ['s-1'],
          ),
        );

        MusicPageRoute? navigatedRoute;
        await tester.pumpWidget(
          MaterialApp(
            theme: HermesThemeTokens.resolve().toThemeData(),
            home: Scaffold(
              body: MobileNowPlayingPage(
                coordinator: coordinator,
                musicService: buildMusicService(),
                localDeviceId: 'dev-phone',
                onClose: () {},
                onOpenDevices: () {},
                onNavigate: (route) => navigatedRoute = route,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Local device: Remote bar hidden.
        expect(
          find.byKey(const Key('mobile-player-remote-volume-bar')),
          findsNothing,
        );

        // Collaborator artist inside player navigates cleanly.
        await tester.tap(find.text('Pharrell Williams').first);
        await tester.pump();
        expect(navigatedRoute, const MusicPageRoute.artist('art-2'));

        // Switch active renderer to Desktop -> Remote volume bar appears immediately.
        await coordinator.applyServerSession(
          const PlaybackSessionState(
            sessionId: 'sess-1',
            version: 2,
            activeRendererDeviceId: 'dev-pc',
            activeRendererDeviceName: 'Desktop PC',
            state: PlaybackState.playing,
            repeatMode: HermesRepeatMode.off,
            shuffle: false,
            volume: 0.45,
            currentIndex: 0,
            currentSongId: 's-1',
            positionMs: 0,
            queueSongIds: ['s-1'],
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('mobile-player-remote-volume-bar')),
          findsOneWidget,
        );
      },
    );
  });

  group('Track B stability: Auth 5xx, WatchProgress, Admin dirty settings & Sync offline', () {
    test(
      'AuthService preserves stored session on 503 refresh failure and AuthenticatedHttpClient skips signout',
      () async {
        var refreshStatus = 503;
        final mockHttp = MockClient((req) async {
          if (req.url.path == '/api/v1/auth/refresh') {
            return http.Response('{"error":"unavailable"}', refreshStatus);
          }
          if (req.url.path == '/api/v1/auth/login') {
            return http.Response(
              jsonEncode({
                'userId': 'u-1',
                'username': 'admin',
                'role': 'Admin',
                'accessToken': 'jwt-1',
                'refreshToken': 'ref-1',
              }),
              200,
            );
          }
          return http.Response('Unauthorized', 401);
        });

        final store = InMemorySessionStore();
        final auth = AuthService(httpClient: mockHttp, sessionStore: store);
        await auth.login(
          primaryUrl: 'http://localhost:5258',
          resolvedBaseUrl: 'http://localhost:5258',
          serverId: 'srv-1',
          username: 'admin',
          password: 'Password123!',
          deviceId: 'dev-1',
          deviceName: 'Test',
        );
        expect(await store.load(), isNotNull);

        await expectLater(
          () => auth.refreshSession('http://localhost:5258'),
          throwsA(isA<AuthException>()),
        );
        expect(await store.load(), isNotNull);

        // AuthenticatedHttpClient skips onSessionExpired on transient 503 AuthException.
        var expiredCalls = 0;
        final client = AuthenticatedHttpClient(
          inner: mockHttp,
          getAccessToken: () => 'jwt-1',
          refreshAccessToken: () async {
            final s = await auth.refreshSession('http://localhost:5258');
            return s.accessToken;
          },
          onSessionExpired: () => expiredCalls++,
        );
        final res503 = await client.get(
          Uri.parse('http://localhost:5258/api/v1/cinema/movies'),
        );
        expect(res503.statusCode, 503);
        expect(expiredCalls, 0);

        // HTTP 401 clears stored session.
        refreshStatus = 401;
        await expectLater(
          () => auth.refreshSession('http://localhost:5258'),
          throwsA(isA<AuthException>()),
        );
        expect(await store.load(), isNull);
        client.close();
      },
    );

    test(
      'WatchProgressReporter.reportNow swallows API failures without throwing',
      () async {
        final mockHttp = MockClient(
          (_) async => http.Response('{"error":"offline"}', 503),
        );
        final cinemaService = CinemaService(
          baseUri: Uri.parse('http://localhost:5258'),
          accessToken: 'jwt',
          httpClient: mockHttp,
        );
        final reporter = WatchProgressReporter(
          cinemaService: cinemaService,
          movieId: 'mov-1',
          getPositionMs: () => 50000,
          getDurationMs: () => 500000,
        );
        addTearDown(reporter.dispose);

        final result = await reporter.reportNow();
        expect(result, isNull);
      },
    );

    testWidgets(
      'AdminDashboardScreen preserves dirty settings across background scan poll and saves edits',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        var scanning = true;
        String? savedName;

        final mockHttp = MockClient((req) async {
          if (req.url.path == '/api/v1/admin/libraries') {
            return http.Response(
              jsonEncode([
                {
                  'id': 'lib-1',
                  'name': 'Movies',
                  'mediaType': 0,
                  'rootPath': '/media/Movies',
                  'watchEnabled': true,
                  'fetchMetadata': true,
                  'isScanning': scanning,
                  'createdAtUtc': '2026-11-16T10:00:00Z',
                  'itemCount': 1,
                  'totalSizeBytes': 1000,
                },
              ]),
              200,
            );
          }
          if (req.url.path == '/api/v1/admin/settings') {
            if (req.method == 'PUT') {
              final body = jsonDecode(req.body) as Map<String, dynamic>;
              savedName = body['serverName'] as String?;
              scanning = false;
              return http.Response(
                jsonEncode({
                  'serverId': 'srv-1',
                  'serverName': savedName ?? 'Hermes Home',
                  'transcodingEnabled': body['transcodingEnabled'],
                  'maxConcurrentVideoTranscodes':
                      body['maxConcurrentVideoTranscodes'],
                  'maxConcurrentAudioTranscodes':
                      body['maxConcurrentAudioTranscodes'],
                  'maxRemoteVideoBitrateBps': body['maxRemoteVideoBitrateBps'],
                  'hardwareAccelerationMode': body['hardwareAccelerationMode'],
                  'updatedAtUtc': '2026-11-22T02:00:00Z',
                  'totalMediaSizeBytes': 1000,
                  'libraryCount': 1,
                  'totalMovies': 1,
                  'totalSeries': 0,
                  'totalEpisodes': 0,
                  'totalSongs': 0,
                }),
                200,
              );
            }
            return http.Response(
              jsonEncode({
                'serverId': 'srv-1',
                'serverName': 'Hermes Home',
                'transcodingEnabled': true,
                'maxConcurrentVideoTranscodes': 2,
                'maxConcurrentAudioTranscodes': 4,
                'maxRemoteVideoBitrateBps': null,
                'hardwareAccelerationMode': 0,
                'updatedAtUtc': '2026-11-22T01:00:00Z',
                'totalMediaSizeBytes': 1000,
                'libraryCount': 1,
                'totalMovies': 1,
                'totalSeries': 0,
                'totalEpisodes': 0,
                'totalSongs': 0,
              }),
              200,
            );
          }
          return http.Response('[]', 200);
        });

        final adminService = AdminService(
          baseUri: Uri.parse('http://localhost:5258'),
          accessToken: 'jwt',
          httpClient: mockHttp,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: HermesThemeTokens.resolve().toThemeData(),
            home: Scaffold(
              body: AdminDashboardScreen(adminService: adminService),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final saveBtn = find.text('Save settings');
        await tester.ensureVisible(saveBtn);
        await tester.pump();

        await tester.enterText(
          find.widgetWithText(TextField, 'Hermes Home'),
          'My Dirty NAS',
        );
        // Trigger 900ms background scan poll; dirty serverName must survive.
        await tester.pump(const Duration(milliseconds: 950));
        await tester.pump();

        expect(find.widgetWithText(TextField, 'My Dirty NAS'), findsOneWidget);

        await tester.tap(saveBtn);
        await tester.pumpAndSettle();
        expect(savedName, 'My Dirty NAS');
      },
    );

    test(
      'SignalRConnectTransport offline fallback syncs currentSession and HermesSyncClient ignores malformed payloads',
      () async {
        late _FakeWsChannel fakeChannel;
        final mockHttp = MockClient((req) async {
          if (req.url.path == '/hubs/sync/negotiate') {
            return http.Response(
              jsonEncode({
                'negotiateVersion': 1,
                'connectionToken': 'c-1',
                'connectionId': 'c-1',
              }),
              200,
            );
          }
          return http.Response('{}', 200);
        });

        final syncClient = HermesSyncClient(
          baseUri: Uri.parse('http://localhost:5258'),
          httpClient: mockHttp,
          getAccessToken: () => 'jwt',
          deviceId: 'dev-1',
          deviceName: 'PC',
          platform: 'Windows',
          channelFactory: (_) {
            fakeChannel = _FakeWsChannel();
            return fakeChannel;
          },
        );

        final offlineTransport = SignalRConnectTransport(
          syncClient: syncClient,
          musicService: buildMusicService(),
          localDeviceId: 'dev-1',
          localDeviceName: 'PC',
        );

        final started = await offlineTransport.startPlayback(['s-1', 's-2'], 1);
        expect(syncClient.currentSession?.currentSongId, 's-2');
        expect(started.version, 1);

        final updated = await offlineTransport.sendTransport(
          PlaybackState.playing,
          volume: 0.35,
        );
        expect(updated.queueSongIds, ['s-1', 's-2']);
        expect(updated.currentIndex, 1);
        expect(updated.volume, 0.35);

        final validSessions = <PlaybackSessionState>[];
        final sub = syncClient.sessionStream.listen(validSessions.add);
        syncClient.start();
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        // Bad payload (missing/wrong types) followed by valid frame.
        fakeChannel.pushServerText(
          '{}\u001E'
          '{"type":1,"target":"SessionStateUpdated","arguments":[{"sessionId":123,"version":"bad"}]}\u001E'
          '{"type":1,"target":"SessionStateUpdated","arguments":[{"sessionId":"srv-1","version":9,"activeRendererDeviceId":"dev-1","activeRendererDeviceName":"PC","state":1,"repeatMode":0,"shuffle":false,"volume":0.8,"currentIndex":0,"currentSongId":"s-1","positionMs":0,"queueSongIds":["s-1"]}]}\u001E',
        );
        await Future<void>.delayed(Duration.zero);

        expect(validSessions, hasLength(1));
        expect(validSessions.single.sessionId, 'srv-1');
        await sub.cancel();
        await syncClient.dispose();
        await fakeChannel.dispose();
      },
    );
  });
}
