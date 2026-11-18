import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_client/main.dart';
import 'package:hermes_client/src/core/auth/session_store.dart';
import 'package:hermes_client/src/core/network/hermes_sync_client.dart';
import 'package:hermes_client/src/core/settings/hermes_preferences.dart';
import 'package:hermes_client/src/core/storage/hermes_cache_manager.dart';
import 'package:hermes_client/src/core/theme/hermes_theme_tokens.dart';
import 'package:hermes_client/src/core/widgets/hermes_marquee_text.dart';
import 'package:hermes_client/src/features/cinema/cinema_catalog_screen.dart';
import 'package:hermes_client/src/features/cinema/cinema_models.dart';
import 'package:hermes_client/src/features/cinema/hermes_video_player.dart';
import 'package:hermes_client/src/features/music/mini_player_bar.dart';
import 'package:hermes_client/src/features/music/music_models.dart';
import 'package:hermes_client/src/features/music/music_playback_coordinator.dart';
import 'package:hermes_client/src/features/music/music_service.dart';
import 'package:hermes_client/src/features/music/music_world_screen.dart';
import 'package:hermes_client/src/features/music/now_playing_panel.dart';
import 'package:hermes_client/src/features/music/platform_media_bridge.dart';
import 'package:hermes_client/src/features/settings/player_and_theme_settings_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _NoopAudioEngine implements AudioEngineAdapter {
  @override
  Future<void> loadAndPlay(Uri streamUri, SongModel track, int startPositionMs) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(int positionMs) async {}

  @override
  Future<void> stop() async {}
}

class _Pr28ConnectTransport implements ConnectTransport {
  _Pr28ConnectTransport(this._songs);

  final List<SongModel> _songs;
  int _version = 0;
  PlaybackState _state = PlaybackState.stopped;
  HermesRepeatMode _repeat = HermesRepeatMode.off;
  bool _shuffle = false;
  int _index = 0;
  int _posMs = 0;
  List<String> _queueIds = const [];
  String? _rendererId;
  final List<String?> transferredTargets = [];
  final List<List<String>?> sentQueueUpdates = [];

  PlaybackSessionState _buildSession() => PlaybackSessionState(
        sessionId: 'sess-pr28',
        version: _version,
        activeRendererDeviceId: _rendererId,
        activeRendererDeviceName: _rendererId == null ? null : 'Honor Phone',
        state: _state,
        repeatMode: _repeat,
        shuffle: _shuffle,
        volume: 1.0,
        currentIndex: _index,
        currentSongId: _queueIds.isEmpty
            ? (_songs.isNotEmpty ? _songs.first.id : null)
            : _queueIds[_index.clamp(0, _queueIds.length - 1)],
        positionMs: _posMs,
        queueSongIds: List<String>.from(_queueIds),
      );

  @override
  Future<List<OnlineDeviceModel>> getOnlineDevices() async => const [];

  @override
  Future<PlaybackSessionState> startPlayback(
    List<String> queueSongIds,
    int startIndex,
  ) async {
    _version++;
    _rendererId ??= 'dev-phone';
    _queueIds = List<String>.from(queueSongIds);
    _index = startIndex;
    _state = PlaybackState.playing;
    _posMs = 0;
    return _buildSession();
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
    _version++;
    _state = state;
    if (queueSongIds != null) {
      _queueIds = List<String>.from(queueSongIds);
    }
    sentQueueUpdates.add(queueSongIds == null ? null : List<String>.from(queueSongIds));
    if (currentIndex != null) _index = currentIndex;
    if (positionMs != null) _posMs = positionMs;
    if (repeatMode != null) _repeat = repeatMode;
    if (shuffle != null) _shuffle = shuffle;
    return _buildSession();
  }

  @override
  Future<PlaybackSessionState> transferOutput(
    String targetDeviceId, {
    int? positionMs,
  }) async {
    _version++;
    _rendererId = targetDeviceId;
    transferredTargets.add(targetDeviceId);
    if (positionMs != null) _posMs = positionMs;
    return _buildSession();
  }
}

class _FakeSink extends Fake implements WebSocketSink {
  final Completer<void> _done = Completer<void>();

  @override
  void add(dynamic data) {}

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    if (!_done.isCompleted) _done.complete();
  }
}

class _FakeChannel extends Fake implements WebSocketChannel {
  final _incoming = StreamController<dynamic>.broadcast();
  late final _sink = _FakeSink();

  @override
  Future<void> get ready => Future<void>.value();

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _sink;
}

SongModel _song(String id, String title, {bool isLiked = false}) => SongModel(
      id: id,
      artistId: 'art-1',
      artistName: 'Sleep Token, Guest Artist',
      albumId: 'alb-1',
      albumTitle: 'Eden',
      title: title,
      trackNumber: 1,
      discNumber: 1,
      durationMs: 240000,
      codec: 'flac',
      bitrateBps: 1411000,
      sampleRateHz: 44100,
      bitDepth: 16,
      isLiked: isLiked,
      isMissing: false,
    );

void main() {
  group('PR28 Fisher-Yates full-playlist shuffle & remote disconnect takeover', () {
    test('startQueue with shuffle on puts tapped track first and shuffles all playlist tracks', () async {
      final songs = [
        _song('s-1', 'Track One'),
        _song('s-2', 'Track Two'),
        _song('s-3', 'Track Three'),
        _song('s-4', 'Track Four'),
        _song('s-5', 'Track Five'),
      ];
      final service = MusicService(
        baseUri: Uri.parse('http://localhost:5258'),
        accessToken: 'jwt',
        httpClient: MockClient((_) async => http.Response('[]', 200)),
      );
      final transport = _Pr28ConnectTransport(songs);
      final coordinator = MusicPlaybackCoordinator(
        localDeviceId: 'dev-phone',
        musicService: service,
        audioEngine: _NoopAudioEngine(),
        mediaBridge: InMemoryPlatformMediaBridge(),
        transport: transport,
        ticketIssuer: (_) async => 'tkt',
        catalogSongs: {for (final s in songs) s.id: s},
      );
      addTearDown(coordinator.dispose);

      // Turn shuffle ON first via existing playback.
      await coordinator.startQueue(songs, 0);
      await coordinator.toggleShuffle();
      expect(coordinator.session?.shuffle, isTrue);

      // Now tap track at index 2 (s-3) inside the 5-track playlist with shuffle ON.
      await coordinator.startQueue(songs, 2);

      final shuffledQueue = coordinator.session!.queueSongIds;
      expect(coordinator.session!.currentIndex, 0);
      expect(coordinator.session!.currentSongId, 's-3');
      expect(shuffledQueue.first, 's-3');
      // Must contain ALL 5 playlist tracks (including s-1 and s-2 before index 2!).
      expect(shuffledQueue.toSet(), {'s-1', 's-2', 's-3', 's-4', 's-5'});
      expect(shuffledQueue.length, 5);

      // Tapping another track (index 4 -> s-5) places s-5 first and keeps all 5.
      await coordinator.startQueue(songs, 4);
      final secondShuffle = coordinator.session!.queueSongIds;
      expect(secondShuffle.first, 's-5');
      expect(secondShuffle.toSet(), {'s-1', 's-2', 's-3', 's-4', 's-5'});

      // Turning shuffle OFF restores the original unshuffled order preserving s-5.
      await coordinator.toggleShuffle();
      expect(coordinator.session?.shuffle, isFalse);
      expect(
        coordinator.session?.queueSongIds,
        ['s-1', 's-2', 's-3', 's-4', 's-5'],
      );
      expect(coordinator.session?.currentSongId, 's-5');
      expect(coordinator.session?.currentIndex, 4);
    });

    test('automatically claims renderer via transferOutput when remote renderer disconnects', () async {
      final s1 = _song('s-1', 'Alpha');
      final service = MusicService(
        baseUri: Uri.parse('http://localhost:5258'),
        accessToken: 'jwt',
        httpClient: MockClient((_) async => http.Response('[]', 200)),
      );
      final transport = _Pr28ConnectTransport([s1]);
      final coordinator = MusicPlaybackCoordinator(
        localDeviceId: 'dev-phone',
        musicService: service,
        audioEngine: _NoopAudioEngine(),
        mediaBridge: InMemoryPlatformMediaBridge(),
        transport: transport,
        ticketIssuer: (_) async => 'tkt',
        catalogSongs: {'s-1': s1},
      );
      addTearDown(coordinator.dispose);

      // Desktop is initially the active playing renderer.
      await coordinator.applyServerSession(
        const PlaybackSessionState(
          sessionId: 'sess-1',
          version: 1,
          activeRendererDeviceId: 'dev-desktop',
          activeRendererDeviceName: 'Windows PC',
          state: PlaybackState.playing,
          repeatMode: HermesRepeatMode.off,
          shuffle: false,
          volume: 1.0,
          currentIndex: 0,
          currentSongId: 's-1',
          positionMs: 12000,
          queueSongIds: ['s-1'],
        ),
      );
      expect(transport.transferredTargets, isEmpty);

      // Desktop disconnects -> backend broadcasts activeRendererDeviceId = null while playing.
      await coordinator.applyServerSession(
        const PlaybackSessionState(
          sessionId: 'sess-1',
          version: 2,
          activeRendererDeviceId: null,
          activeRendererDeviceName: null,
          state: PlaybackState.playing,
          repeatMode: HermesRepeatMode.off,
          shuffle: false,
          volume: 1.0,
          currentIndex: 0,
          currentSongId: 's-1',
          positionMs: 12000,
          queueSongIds: ['s-1'],
        ),
      );

      expect(transport.transferredTargets, ['dev-phone']);
    });
  });

  group('PR28 Marquee, Mobile MiniPlayer Swipe & Lyrics Autoscroll', () {
    testWidgets('HermesMarqueeText fits and overflows cleanly without infinite layout or pumpAndSettle hang', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 120,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HermesMarqueeText(
                    'Short',
                    style: TextStyle(fontSize: 14),
                  ),
                  HermesMarqueeText(
                    'This Is An Extraordinarily Long Track Title That Overflows Horizontally',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Short'), findsOneWidget);
      expect(
        find.text('This Is An Extraordinarily Long Track Title That Overflows Horizontally'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('mobile MiniPlayerBar renders Spotify layout with Like, Pause and swipe next/previous', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var nextCalls = 0;
      var prevCalls = 0;
      var likeCalls = 0;
      var playPauseCalls = 0;
      final song = _song('s-1', 'Very Long Track Title Beyond Screen Width');

      await tester.pumpWidget(
        MaterialApp(
          theme: HermesThemeTokens.resolve().toThemeData(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: MiniPlayerBar(
                session: const PlaybackSessionState(
                  sessionId: 'sess',
                  version: 1,
                  activeRendererDeviceId: 'dev-phone',
                  state: PlaybackState.playing,
                  repeatMode: HermesRepeatMode.off,
                  shuffle: false,
                  volume: 1.0,
                  currentIndex: 0,
                  currentSongId: 's-1',
                  positionMs: 1000,
                  queueSongIds: ['s-1'],
                ),
                currentSong: song,
                localDeviceId: 'dev-phone',
                positionMs: 1000,
                onTogglePlayPause: () => playPauseCalls++,
                onSkipNext: () => nextCalls++,
                onSkipPrevious: () => prevCalls++,
                onToggleLike: () => likeCalls++,
                onOpenDevicePicker: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mini-player-mobile-like')), findsOneWidget);
      expect(find.byKey(const Key('mini-player-mobile-play')), findsOneWidget);
      expect(find.byKey(const Key('mini-player-mobile-swipe-area')), findsOneWidget);
      // Connect devices button stays out of the compact mobile bar.
      expect(find.byTooltip('Connect Devices'), findsNothing);

      await tester.tap(find.byKey(const Key('mini-player-mobile-like')));
      await tester.tap(find.byKey(const Key('mini-player-mobile-play')));
      expect(likeCalls, 1);
      expect(playPauseCalls, 1);

      await tester.fling(
        find.byKey(const Key('mini-player-mobile-swipe-area')),
        const Offset(-220, 0),
        900,
      );
      await tester.pumpAndSettle();
      expect(nextCalls, 1);

      await tester.fling(
        find.byKey(const Key('mini-player-mobile-swipe-area')),
        const Offset(220, 0),
        900,
      );
      await tester.pumpAndSettle();
      expect(prevCalls, 1);
    });

    testWidgets('MobileNowPlayingPage hides queue badge and autoscrolls synced lyrics', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final songs = List.generate(5, (i) => _song('s-${i + 1}', 'Song ${i + 1}'));
      final lyricLines = List.generate(
        35,
        (i) => {
          'timestampMs': i * 4000,
          'text': 'Lyric verse line number ${i + 1}',
        },
      );
      final mockHttp = MockClient((req) async {
        if (req.url.path == '/api/v1/music/songs/s-1/lyrics') {
          return http.Response(
            jsonEncode({
              'songId': 's-1',
              'isSynced': true,
              'source': 'lrc',
              'lines': lyricLines,
            }),
            200,
          );
        }
        return http.Response('[]', 200);
      });
      final service = MusicService(
        baseUri: Uri.parse('http://localhost:5258'),
        accessToken: 'jwt',
        httpClient: mockHttp,
      );
      final coordinator = MusicPlaybackCoordinator(
        localDeviceId: 'dev-phone',
        musicService: service,
        audioEngine: _NoopAudioEngine(),
        mediaBridge: InMemoryPlatformMediaBridge(),
        transport: _Pr28ConnectTransport(songs),
        catalogSongs: {for (final s in songs) s.id: s},
      );
      addTearDown(coordinator.dispose);

      await coordinator.applyServerSession(
        PlaybackSessionState(
          sessionId: 'sess-lyrics',
          version: 1,
          activeRendererDeviceId: 'dev-phone',
          state: PlaybackState.paused,
          repeatMode: HermesRepeatMode.off,
          shuffle: false,
          volume: 1.0,
          currentIndex: 0,
          currentSongId: 's-1',
          positionMs: 0,
          queueSongIds: songs.map((s) => s.id).toList(),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: HermesThemeTokens.resolve().toThemeData(),
          home: MobileNowPlayingPage(
            coordinator: coordinator,
            musicService: service,
            localDeviceId: 'dev-phone',
            onClose: () {},
            onOpenDevices: () {},
            onNavigate: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Queue button should NOT render numeric count badge ("5" or "4").
      final queueBtn = find.byKey(const Key('mobile-player-queue-toggle'));
      expect(queueBtn, findsOneWidget);
      expect(find.text('4'), findsNothing);
      expect(find.text('5'), findsNothing);

      // Open Lyrics view.
      await tester.tap(find.byKey(const Key('mobile-player-lyrics-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mobile-player-lyrics-view')), findsOneWidget);

      final scrollState = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const Key('mobile-player-lyrics-view')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(scrollState.position.pixels, 0);

      // Advance playback timestamp to line 26 (104000 ms) -> autoscrolls downward!
      await coordinator.applyServerSession(
        PlaybackSessionState(
          sessionId: 'sess-lyrics',
          version: 2,
          activeRendererDeviceId: 'dev-phone',
          state: PlaybackState.paused,
          repeatMode: HermesRepeatMode.off,
          shuffle: false,
          volume: 1.0,
          currentIndex: 0,
          currentSongId: 's-1',
          positionMs: 104000,
          queueSongIds: songs.map((s) => s.id).toList(),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(scrollState.position.pixels, greaterThan(100));
    });
  });

  group('PR28 Mobile Navigation Redesign, Default Music & System Back', () {
    testWidgets('HermesApp with isMobilePlatformOverride opens on Music world with 3-tab mobile chrome and handles in-app Back', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final sessionStore = InMemorySessionStore();
      await sessionStore.save(
        const HermesSession(
          serverPrimaryUrl: 'http://127.0.0.1:5258',
          serverLanFallbackUrl: 'http://127.0.0.1:5258',
          serverId: 'srv-mob',
          deviceId: 'dev-phone-1',
          deviceName: 'Honor Phone',
          userId: 'usr-1',
          username: 'robert',
          role: 'Admin',
          accessToken: 'jwt-1',
          refreshToken: 'ref-1',
        ),
      );

      final mockHttp = MockClient((req) async {
        final p = req.url.path;
        if (p == '/api/v1/system/info') {
          return http.Response(
            jsonEncode({
              'serverId': 'srv-mob',
              'serverName': 'Hermes Home',
              'version': '1.0.0',
              'setupCompleted': true,
            }),
            200,
          );
        }
        if (p == '/api/v1/auth/refresh') {
          return http.Response(
            jsonEncode({
              'accessToken': 'jwt-2',
              'refreshToken': 'ref-2',
              'role': 'Admin',
            }),
            200,
          );
        }
        if (p == '/api/v1/auth/me/preferences') {
          return http.Response(
            jsonEncode(const HermesAccountPreferences().toJson()),
            200,
          );
        }
        if (p == '/api/v1/music/songs') {
          return http.Response(
            jsonEncode([
              {
                'id': 's-mob-1',
                'artistId': 'art-mob-1',
                'artistName': 'Sleep Token',
                'albumId': 'alb-mob-1',
                'albumTitle': 'Take Me Back To Eden',
                'title': 'Granite',
                'trackNumber': 1,
                'discNumber': 1,
                'durationMs': 225000,
                'codec': 'flac',
                'bitrateBps': 1411000,
                'sampleRateHz': 44100,
                'bitDepth': 16,
                'isLiked': true,
                'isMissing': false,
              },
            ]),
            200,
          );
        }
        if (p == '/api/v1/music/albums') {
          return http.Response(
            jsonEncode([
              {
                'id': 'alb-mob-1',
                'artistId': 'art-mob-1',
                'artistName': 'Sleep Token',
                'title': 'Take Me Back To Eden',
                'year': 2023,
                'songCount': 1,
              },
            ]),
            200,
          );
        }
        if (p == '/api/v1/music/artists') {
          return http.Response(
            jsonEncode([
              {'id': 'art-mob-1', 'name': 'Sleep Token', 'albumCount': 1},
            ]),
            200,
          );
        }
        if (p == '/api/v1/cinema/movies') {
          return http.Response(
            jsonEncode([
              {
                'id': 'mov-mob-1',
                'title': 'Blade Runner 2049',
                'year': 2017,
                'overview': 'Replicant blade runner.',
                'genres': ['Sci-Fi'],
                'isInWatchlist': true,
                'cast': <Map<String, dynamic>>[],
                'watchProgress': {
                  'positionMs': 180000,
                  'durationMs': 9800000,
                  'isWatched': true,
                  'updatedAtUtc': '2026-11-18T12:00:00Z',
                },
                'sources': [
                  {
                    'id': 'src-mob-1',
                    'sourceLabel': '4K',
                    'container': 'mkv',
                    'videoCodec': 'hevc',
                    'audioCodec': 'eac3',
                    'width': 3840,
                    'height': 2160,
                    'isHdr': true,
                    'bitrateBps': 18000000,
                    'durationMs': 9800000,
                    'isAvailable': true,
                    'streams': <Map<String, dynamic>>[],
                  },
                ],
              },
            ]),
            200,
          );
        }
        if (p == '/api/v1/cinema/series' ||
            p == '/api/v1/cinema/lists' ||
            p == '/api/v1/music/playlists' ||
            p == '/api/v1/music/history') {
          return http.Response('[]', 200);
        }
        if (p == '/hubs/sync/negotiate') {
          return http.Response(
            jsonEncode({'negotiateVersion': 1, 'connectionToken': 'tok'}),
            200,
          );
        }
        return http.Response('[]', 200);
      });

      await tester.pumpWidget(
        HermesApp(
          isMobilePlatformOverride: true,
          sessionStore: sessionStore,
          preferencesStore: InMemoryDevicePreferencesStore(),
          httpClient: mockHttp,
          syncClientFactory: ({
            required baseUri,
            required httpClient,
            required getAccessToken,
            required deviceId,
            required deviceName,
            required platform,
          }) =>
              HermesSyncClient(
            baseUri: baseUri,
            httpClient: httpClient,
            getAccessToken: getAccessToken,
            deviceId: deviceId,
            deviceName: deviceName,
            platform: platform,
            channelFactory: (_) => _FakeChannel(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Default world on mobile is Music!
      expect(find.byType(MusicWorldScreen), findsOneWidget);
      expect(find.byType(CinemaCatalogScreen), findsNothing);

      // Top bar has icon-only world pill (zero text labels inside pill) and Account button.
      final worldPill = find.byKey(const Key('mobile-world-pill'));
      expect(worldPill, findsOneWidget);
      expect(
        find.descendant(of: worldPill, matching: find.byType(Text)),
        findsNothing,
      );
      expect(find.byKey(const Key('mobile-account-btn')), findsOneWidget);

      // Bottom NavigationBar has exactly Home, Search, Library (no Server or Settings).
      expect(find.byType(NavigationDestination), findsNWidgets(3));
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Search'), findsOneWidget);
      expect(find.text('Library'), findsOneWidget);

      // Account sheet contains Settings, Server dashboard, Account settings, Sign out.
      await tester.tap(find.byKey(const Key('mobile-account-btn')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mobile-account-sheet')), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Server dashboard'), findsOneWidget);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerAndThemeSettingsScreen), findsOneWidget);

      // System Back returns from Settings overlay to active Music world cleanly.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(MusicWorldScreen), findsOneWidget);

      // Navigate to Search tab, then Library -> Songs, then press Back step by step!
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('music-mobile-search-view')), findsOneWidget);

      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('music-lib-songs')));
      await tester.pumpAndSettle();
      expect(find.text('Granite'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('music-lib-songs')), findsOneWidget);

      // Switch to Cinema world via icon pill and inspect Watch History in Library.
      await tester.tap(find.byKey(const Key('mobile-world-pill-cinema')));
      await tester.pumpAndSettle();
      expect(find.byType(CinemaCatalogScreen), findsOneWidget);

      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();
      final historyChip = find.byKey(const Key('cinema-library-chip-history'));
      expect(historyChip, findsOneWidget);
      await tester.ensureVisible(historyChip);
      await tester.pumpAndSettle();
      await tester.tap(historyChip);
      await tester.pumpAndSettle();
      expect(find.text('Watch history'), findsOneWidget);
      expect(find.text('Blade Runner 2049'), findsWidgets);

      // System Back returns from Cinema Library to Cinema Home rather than leaving app.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('hero-details-btn')), findsOneWidget);
    });
  });

  group('PR28 Storage & Cache Viewer, Cap & Clear', () {
    test('HermesCacheManager measures disk bytes, applies image cache cap, and clears disk entries', () async {
      final tempDir = await Directory.systemTemp.createTemp('hermes_cache_test_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final sampleFile = File('${tempDir.path}${Platform.pathSeparator}poster.webp');
      await sampleFile.writeAsBytes(List<int>.filled(4096, 7));

      final manager = HermesCacheManager(diskCacheDir: tempDir);
      manager.applyCapMb(256);
      expect(PaintingBinding.instance.imageCache.maximumSizeBytes, 256 * 1024 * 1024);

      final before = await manager.inspect(capMb: 256);
      expect(before.diskCacheBytes, greaterThanOrEqualTo(4096));

      var catalogCleared = false;
      final after = await manager.clearAll(
        capMb: 256,
        onClearCatalogCaches: () => catalogCleared = true,
      );
      expect(catalogCleared, isTrue);
      expect(after.diskCacheBytes, 0);
      expect(await sampleFile.exists(), isFalse);
    });

    testWidgets('PlayerAndThemeSettingsScreen displays cache size, cap selector, and clears cache cleanly', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      late Directory tempDir;
      late File sampleFile;
      await tester.runAsync(() async {
        tempDir = await Directory.systemTemp.createTemp('hermes_settings_cache_');
        sampleFile = File('${tempDir.path}${Platform.pathSeparator}cover.bin');
        await sampleFile.writeAsBytes(List<int>.filled(2048, 3));
      });
      addTearDown(() async {
        await tester.runAsync(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });
      });

      final manager = HermesCacheManager(diskCacheDir: tempDir);
      var catalogCleared = false;
      HermesDevicePreferences? updatedPrefs;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerAndThemeSettingsScreen(
              tokens: HermesThemeTokens.resolve(),
              rendererBackend: VideoRendererBackend.openGl,
              defaultVideoQuality: VideoQualityPreset.directPlay,
              onThemeChanged: (_) {},
              onRendererChanged: (_) {},
              onDefaultVideoQualityChanged: (_) {},
              cacheManager: manager,
              onClearCatalogCaches: () => catalogCleared = true,
              onDevicePreferencesChanged: (p) => updatedPrefs = p,
            ),
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pumpAndSettle();
        if (find.textContaining('2.0 KB used of 512 MB').evaluate().isNotEmpty) {
          break;
        }
      }

      await tester.scrollUntilVisible(
        find.byKey(const Key('clear-cache-btn')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cache-size-label')), findsOneWidget);
      expect(find.textContaining('2.0 KB used of 512 MB'), findsOneWidget);
      expect(find.byKey(const Key('cache-cap-selector')), findsOneWidget);

      await tester.tap(find.byKey(const Key('cache-cap-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 GB').last);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      expect(updatedPrefs?.cacheCapMb, 1024);
      expect(find.textContaining('used of 1 GB'), findsOneWidget);

      await tester.tap(find.byKey(const Key('clear-cache-btn')));
      var existsAfter = true;
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          existsAfter = await sampleFile.exists();
        });
        await tester.pumpAndSettle();
        if (!existsAfter && find.text('Cache cleared').evaluate().isNotEmpty) {
          break;
        }
      }

      expect(catalogCleared, isTrue);
      expect(existsAfter, isFalse);
      expect(find.text('Cache cleared'), findsOneWidget);
      expect(find.textContaining('0 B used of 1 GB'), findsOneWidget);
    });
  });
}
