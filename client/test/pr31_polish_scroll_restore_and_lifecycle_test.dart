import 'dart:async';
import 'dart:convert';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_client/main.dart';
import 'package:hermes_client/src/core/auth/session_store.dart';
import 'package:hermes_client/src/core/network/hermes_sync_client.dart';
import 'package:hermes_client/src/core/settings/hermes_preferences.dart';
import 'package:hermes_client/src/core/storage/search_history_store.dart';
import 'package:hermes_client/src/core/theme/hermes_theme_tokens.dart';
import 'package:hermes_client/src/features/cinema/cinema_catalog_screen.dart';
import 'package:hermes_client/src/features/cinema/cinema_detail_page.dart';
import 'package:hermes_client/src/features/cinema/cinema_models.dart';
import 'package:hermes_client/src/features/cinema/cinema_service.dart';
import 'package:hermes_client/src/features/cinema/hermes_video_player.dart';
import 'package:hermes_client/src/features/music/music_models.dart';
import 'package:hermes_client/src/features/music/music_playback_coordinator.dart';
import 'package:hermes_client/src/features/music/music_service.dart';
import 'package:hermes_client/src/features/music/music_shared_widgets.dart';
import 'package:hermes_client/src/features/music/music_world_screen.dart';
import 'package:hermes_client/src/features/music/now_playing_panel.dart';
import 'package:hermes_client/src/features/music/os_media_bridge.dart';
import 'package:hermes_client/src/features/music/platform_media_bridge.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _SpyAudioEngine implements AudioEngineAdapter {
  int stopCalls = 0;

  @override
  Future<void> loadAndPlay(
    Uri streamUri,
    SongModel track,
    int startPositionMs,
  ) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(int positionMs) async {}

  @override
  Future<void> stop() async {
    stopCalls++;
  }
}

class _FakeConnectTransport implements ConnectTransport {
  _FakeConnectTransport(this._songs, {this.throwOnTransport = false})
      : _queueIds = _songs.map((s) => s.id).toList();

  final List<SongModel> _songs;
  final bool throwOnTransport;
  int _version = 1;
  PlaybackState _state = PlaybackState.playing;
  HermesRepeatMode _repeat = HermesRepeatMode.off;
  bool _shuffle = false;
  int _index = 0;
  int _positionMs = 0;
  List<String> _queueIds;

  PlaybackSessionState _snapshot() => PlaybackSessionState(
        sessionId: 'sess-pr31',
        version: _version,
        activeRendererDeviceId: 'dev-phone',
        activeRendererDeviceName: 'Honor Phone',
        state: _state,
        repeatMode: _repeat,
        shuffle: _shuffle,
        volume: 1.0,
        currentIndex: _index,
        currentSongId: _queueIds.isEmpty
            ? (_songs.isNotEmpty ? _songs.first.id : null)
            : _queueIds[_index.clamp(0, _queueIds.length - 1)],
        positionMs: _positionMs,
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
    _queueIds = List<String>.from(queueSongIds);
    _index = startIndex;
    _state = PlaybackState.playing;
    _positionMs = 0;
    return _snapshot();
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
    if (throwOnTransport) {
      throw http.ClientException('network down during shutdown');
    }
    _version++;
    _state = state;
    if (currentIndex != null) _index = currentIndex;
    if (positionMs != null) _positionMs = positionMs;
    if (repeatMode != null) _repeat = repeatMode;
    if (shuffle != null) _shuffle = shuffle;
    if (queueSongIds != null) _queueIds = List<String>.from(queueSongIds);
    return _snapshot();
  }

  @override
  Future<PlaybackSessionState> transferOutput(
    String targetDeviceId, {
    int? positionMs,
  }) async =>
      _snapshot();
}

class _FakeAudioSession extends Fake implements AudioSession {
  final _becomingNoisy = StreamController<void>.broadcast();
  final _interruptions = StreamController<AudioInterruptionEvent>.broadcast();
  final List<bool> activeHistory = [];

  @override
  Stream<void> get becomingNoisyEventStream => _becomingNoisy.stream;

  @override
  Stream<AudioInterruptionEvent> get interruptionEventStream =>
      _interruptions.stream;

  @override
  Future<void> configure(AudioSessionConfiguration configuration) async {}

  @override
  Future<bool> setActive(
    bool active, {
    AVAudioSessionSetActiveOptions? avAudioSessionSetActiveOptions,
    AndroidAudioFocusGainType? androidAudioFocusGainType,
    AndroidAudioAttributes? androidAudioAttributes,
    bool? androidWillPauseWhenDucked,
    AudioSessionConfiguration fallbackConfiguration =
        const AudioSessionConfiguration.music(),
  }) async {
    activeHistory.add(active);
    return true;
  }

  Future<void> dispose() async {
    await _becomingNoisy.close();
    await _interruptions.close();
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

SongModel _song(String id, String title) => SongModel(
      id: id,
      artistId: 'art-1',
      artistName: 'Daft Punk',
      albumId: 'alb-1',
      albumTitle: 'Discovery',
      title: title,
      trackNumber: 1,
      discNumber: 1,
      durationMs: 240000,
      codec: 'flac',
      bitrateBps: 1411000,
      sampleRateHz: 44100,
      bitDepth: 16,
      isLiked: false,
      isMissing: false,
    );

Map<String, dynamic> _songJson(SongModel s) => {
      'id': s.id,
      'artistId': s.artistId,
      'artistName': s.artistName,
      'albumId': s.albumId,
      'albumTitle': s.albumTitle,
      'title': s.title,
      'trackNumber': s.trackNumber,
      'discNumber': s.discNumber,
      'durationMs': s.durationMs,
      'codec': s.codec,
      'bitrateBps': s.bitrateBps,
      'sampleRateHz': s.sampleRateHz,
      'bitDepth': s.bitDepth,
      'isLiked': s.isLiked,
      'isMissing': s.isMissing,
    };

Finder _firstOnscreen(
  WidgetTester tester,
  Finder finder, {
  double minY = 160,
  double maxY = 640,
}) {
  for (var i = 0; i < finder.evaluate().length; i++) {
    final candidate = finder.at(i);
    final dy = tester.getCenter(candidate).dy;
    if (dy >= minY && dy <= maxY) {
      return candidate;
    }
  }
  return finder.first;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PR31 Search History 20 Cap, Playing Highlight & Swipe-to-Queue', () {
    test('InMemorySearchHistoryStore & SharedPrefsSearchHistoryStore cap at 20', () async {
      SharedPreferences.setMockInitialValues({});
      final inMemory = InMemorySearchHistoryStore();
      final prefs = SharedPrefsSearchHistoryStore();

      for (var i = 1; i <= 25; i++) {
        final item = MusicSearchHistoryItem(
          id: 'song:s-$i',
          kind: MusicSearchHistoryKind.song,
          title: 'Track $i',
          subtitle: 'Song • Artist',
          targetId: 's-$i',
          timestampMs: i,
        );
        await inMemory.addMusicItem(item);
        await prefs.addMusicItem(item);
        await inMemory.addCinemaQuery('Movie $i');
        await prefs.addCinemaQuery('Movie $i');
      }

      expect((await inMemory.loadMusicHistory()).length, 20);
      expect((await prefs.loadMusicHistory()).length, 20);
      expect((await inMemory.loadCinemaHistory()).length, 20);
      expect((await prefs.loadCinemaHistory()).length, 20);
    });

    testWidgets(
      'MusicWorldScreen highlights active playing song and supports swipe-to-queue on search history rows',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final songs = [
          _song('s-1', 'One More Time'),
          _song('s-2', 'Digital Love'),
        ];
        final mockHttp = MockClient((req) async {
          if (req.url.path == '/api/v1/music/songs') {
            return http.Response(
              jsonEncode(songs.map(_songJson).toList()),
              200,
            );
          }
          if (req.url.path == '/api/v1/music/albums') {
            return http.Response(
              jsonEncode([
                {
                  'id': 'alb-1',
                  'artistId': 'art-1',
                  'artistName': 'Daft Punk',
                  'title': 'Discovery',
                  'year': 2001,
                  'songCount': 2,
                },
              ]),
              200,
            );
          }
          if (req.url.path == '/api/v1/music/artists') {
            return http.Response(
              jsonEncode([
                {'id': 'art-1', 'name': 'Daft Punk', 'albumCount': 1},
              ]),
              200,
            );
          }
          if (req.url.path == '/api/v1/auth/stream-tickets') {
            return http.Response(jsonEncode({'ticket': 'tok-pr31'}), 200);
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
          audioEngine: _SpyAudioEngine(),
          mediaBridge: InMemoryPlatformMediaBridge(),
          transport: _FakeConnectTransport(songs),
          catalogSongs: {for (final s in songs) s.id: s},
        );
        addTearDown(coordinator.dispose);

        await coordinator.applyServerSession(
          const PlaybackSessionState(
            sessionId: 'sess-pr31',
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
        );

        final store = InMemorySearchHistoryStore(
          initialMusic: const [
            MusicSearchHistoryItem(
              id: 'song:s-1',
              kind: MusicSearchHistoryKind.song,
              title: 'One More Time',
              subtitle: 'Song • Daft Punk',
              targetId: 's-1',
              timestampMs: 2,
            ),
            MusicSearchHistoryItem(
              id: 'song:s-2',
              kind: MusicSearchHistoryKind.song,
              title: 'Digital Love',
              subtitle: 'Song • Daft Punk',
              targetId: 's-2',
              timestampMs: 1,
            ),
          ],
        );
        final nav = MusicNavigationController()
          ..navigate(const MusicPageRoute.search());
        final tokens = HermesThemeTokens.resolve();

        await tester.pumpWidget(
          MaterialApp(
            theme: tokens.toThemeData(),
            home: Scaffold(
              body: MusicWorldScreen(
                musicService: service,
                coordinator: coordinator,
                navigationController: nav,
                searchHistoryStore: store,
                externalMobileNav: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final activeText = tester.widget<Text>(find.text('One More Time'));
        final inactiveText = tester.widget<Text>(find.text('Digital Love'));
        expect(activeText.style?.color, tokens.accent);
        expect(inactiveText.style?.color, tokens.text);
        expect(
          find.descendant(
            of: find.byKey(const Key('music-recent-searches')),
            matching: find.byType(HermesEqBars),
          ),
          findsOneWidget,
        );

        // Swipe Digital Love right past arm threshold to queue without dismissing.
        final swipeTarget = find.byKey(
          const Key('search-history-swipe-song:s-2'),
        );
        expect(swipeTarget, findsOneWidget);
        await tester.drag(swipeTarget, const Offset(150, 0));
        await tester.pumpAndSettle();

        expect(coordinator.upNext.map((s) => s.id), contains('s-2'));
        expect(find.text('Digital Love'), findsOneWidget);
      },
    );
  });

  group('PR31 Scroll Restoration on Back (Cinema & Music)', () {
    testWidgets('CinemaCatalogScreen preserves scroll offset when returning from CinemaDetailPage', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(390, 700);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final genrePool = ['Sci-Fi', 'Action', 'Drama', 'Thriller', 'Comedy', 'Mystery'];
      final moviesJson = [
        for (var i = 1; i <= 18; i++)
          {
            'id': 'mov-$i',
            'title': 'Movie $i',
            'year': 2000 + i,
            'overview': 'Overview $i',
            'genres': [genrePool[i % genrePool.length]],
            'isInWatchlist': false,
            'cast': <Map<String, dynamic>>[],
            'sources': <Map<String, dynamic>>[],
          },
      ];

      final client = MockClient((req) async {
        if (req.url.path == '/api/v1/cinema/movies') {
          return http.Response(jsonEncode(moviesJson), 200);
        }
        if (req.url.path == '/api/v1/cinema/series' ||
            req.url.path == '/api/v1/cinema/lists') {
          return http.Response('[]', 200);
        }
        return http.Response('{}', 200);
      });
      final cinemaService = CinemaService(
        baseUri: Uri.parse('http://localhost:5258'),
        accessToken: 'jwt',
        httpClient: client,
      );
      final tokens = HermesThemeTokens.resolve();

      await tester.pumpWidget(
        MaterialApp(
          theme: tokens.toThemeData(),
          home: Scaffold(
            body: CinemaCatalogScreen(
              cinemaService: cinemaService,
              playerConfig: HermesVideoPlayerConfig.hdrSafeDefault(tokens: tokens),
              defaultQuality: VideoQualityPreset.directPlay,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final catalogScrollable = find.byType(Scrollable).first;
      final scrollState = tester.state<ScrollableState>(catalogScrollable);
      scrollState.position.jumpTo(280);
      await tester.pumpAndSettle();
      final offsetBeforeDetail = scrollState.position.pixels;
      expect(offsetBeforeDetail, greaterThan(200));

      // Tap any currently visible poster title card to open detail page.
      final visibleCard = _firstOnscreen(tester, find.textContaining('Movie '));
      await tester.tap(visibleCard);
      await tester.pumpAndSettle();
      expect(find.byType(CinemaDetailPage), findsOneWidget);

      await tester.tap(find.byKey(const Key('detail-back-btn')));
      await tester.pumpAndSettle();
      expect(find.byType(CinemaDetailPage), findsNothing);

      final offsetAfterBack =
          tester.state<ScrollableState>(catalogScrollable).position.pixels;
      expect(offsetAfterBack, closeTo(offsetBeforeDetail, 2.0));
    });

    testWidgets('MusicWorldScreen preserves scroll offset when returning from subpage', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(390, 700);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final albumsJson = [
        for (var i = 1; i <= 18; i++)
          {
            'id': 'alb-$i',
            'artistId': 'art-1',
            'artistName': 'Artist One',
            'title': 'Album $i',
            'year': 2000 + i,
            'songCount': 1,
          },
      ];
      final songs = [
        for (var i = 1; i <= 18; i++) _song('s-$i', 'Song $i'),
      ];

      final client = MockClient((req) async {
        if (req.url.path == '/api/v1/music/albums') {
          return http.Response(jsonEncode(albumsJson), 200);
        }
        if (req.url.path == '/api/v1/music/songs') {
          return http.Response(
            jsonEncode(songs.map(_songJson).toList()),
            200,
          );
        }
        if (req.url.path == '/api/v1/music/artists') {
          return http.Response(
            jsonEncode([
              {'id': 'art-1', 'name': 'Artist One', 'albumCount': 18},
            ]),
            200,
          );
        }
        return http.Response('[]', 200);
      });
      final service = MusicService(
        baseUri: Uri.parse('http://localhost:5258'),
        accessToken: 'jwt',
        httpClient: client,
      );
      final coordinator = MusicPlaybackCoordinator(
        localDeviceId: 'dev-1',
        musicService: service,
        audioEngine: _SpyAudioEngine(),
        mediaBridge: InMemoryPlatformMediaBridge(),
        transport: _FakeConnectTransport(songs),
        catalogSongs: {for (final s in songs) s.id: s},
      );
      addTearDown(coordinator.dispose);

      final nav = MusicNavigationController()
        ..navigate(const MusicPageRoute.albums());
      await tester.pumpWidget(
        MaterialApp(
          theme: HermesThemeTokens.resolve().toThemeData(),
          home: Scaffold(
            body: MusicWorldScreen(
              musicService: service,
              coordinator: coordinator,
              navigationController: nav,
              externalMobileNav: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollFinder = find.byType(Scrollable).first;
      final scrollState = tester.state<ScrollableState>(scrollFinder);
      scrollState.position.jumpTo(260);
      await tester.pumpAndSettle();
      final offsetBefore = scrollState.position.pixels;
      expect(offsetBefore, greaterThan(180));

      final visibleAlbum = _firstOnscreen(tester, find.textContaining('Album '));
      await tester.tap(visibleAlbum);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      final offsetAfter =
          tester.state<ScrollableState>(scrollFinder).position.pixels;
      expect(offsetAfter, closeTo(offsetBefore, 2.0));
    });
  });

  group('PR31 Floating Mobile Top Bar, Toggle Pill & Watchlist Cleanup', () {
    testWidgets(
      'Mobile shell renders full-bleed world under floating chrome, toggles world on whole pill tap, and hides Watchlist custom list counter',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final sessionStore = InMemorySessionStore();
        await sessionStore.save(
          const HermesSession(
            serverPrimaryUrl: 'http://127.0.0.1:5258',
            serverLanFallbackUrl: 'http://127.0.0.1:5258',
            serverId: 'srv-1',
            deviceId: 'dev-phone',
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
                'serverId': 'srv-1',
                'serverName': 'Hermes Home',
                'version': '1.0.0',
                'setupCompleted': true,
              }),
              200,
            );
          }
          if (p == '/api/v1/auth/refresh') {
            return http.Response(
              jsonEncode({'accessToken': 'jwt-2', 'refreshToken': 'ref-2', 'role': 'Admin'}),
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
              jsonEncode([_songJson(_song('s-1', 'Granite'))]),
              200,
            );
          }
          if (p == '/api/v1/music/albums') {
            return http.Response(
              jsonEncode([
                {
                  'id': 'alb-1',
                  'artistId': 'art-1',
                  'artistName': 'Daft Punk',
                  'title': 'Discovery',
                  'year': 2001,
                  'songCount': 1,
                },
              ]),
              200,
            );
          }
          if (p == '/api/v1/cinema/movies') {
            return http.Response(
              jsonEncode([
                {
                  'id': 'mov-1',
                  'title': 'Interstellar',
                  'year': 2014,
                  'overview': 'Space',
                  'genres': ['Sci-Fi'],
                  'isInWatchlist': true,
                  'cast': <Map<String, dynamic>>[],
                  'sources': <Map<String, dynamic>>[],
                },
              ]),
              200,
            );
          }
          if (p == '/api/v1/cinema/lists') {
            return http.Response(
              jsonEncode([
                {
                  'id': 'lst-1',
                  'name': 'Favorites',
                  'createdAtUtc': '2026-11-18T00:00:00Z',
                  'updatedAtUtc': '2026-11-18T00:00:00Z',
                  'items': <Map<String, dynamic>>[],
                },
              ]),
              200,
            );
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

        // Floating top bar sits on top of full-bleed world (top == 0, not pushed down by black bar).
        expect(tester.getTopLeft(find.byType(MusicWorldScreen)).dy, 0.0);

        // Tapping anywhere on the pill (even the already-selected side!) toggles worlds.
        await tester.tap(find.byKey(const Key('mobile-world-pill-music')));
        await tester.pumpAndSettle();
        expect(find.byType(CinemaCatalogScreen), findsOneWidget);
        expect(tester.getTopLeft(find.byType(CinemaCatalogScreen)).dy, 0.0);

        // Watchlist view inside Cinema Library has no stray "Custom lists (N)" counter.
        await tester.tap(find.text('Library'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('cinema-library-chip-watchlist')));
        await tester.pumpAndSettle();
        expect(find.text('Watchlist'), findsWidgets);
        expect(find.textContaining('Custom lists'), findsNothing);

        // Toggling whole pill again returns to Music world cleanly.
        await tester.tap(find.byKey(const Key('mobile-world-pill')));
        await tester.pumpAndSettle();
        expect(find.byType(MusicWorldScreen), findsOneWidget);
      },
    );
  });

  group('PR31 Android onTaskRemoved Stop & Mobile Player Sub-view Back Stack', () {
    test('onTaskRemoved immediately stops audio engine and clears bridge even when transport fails', () async {
      final spyEngine = _SpyAudioEngine();
      final osHandler = createDefaultOsAudioHandlerForTest();
      final fakeSession = _FakeAudioSession();
      final bridge = AndroidAudioServiceMediaBridge(
        handlerFactory: () async => osHandler,
        sessionProvider: () async => fakeSession,
      );

      final service = MusicService(
        baseUri: Uri.parse('http://localhost:5258'),
        accessToken: 'jwt',
        httpClient: MockClient((req) async {
          if (req.url.path == '/api/v1/auth/stream-tickets') {
            return http.Response(jsonEncode({'ticket': 'tok-stop'}), 200);
          }
          return http.Response('[]', 200);
        }),
      );
      final song = _song('s-1', 'One More Time');
      final transport = _FakeConnectTransport([song], throwOnTransport: true);
      final coordinator = MusicPlaybackCoordinator(
        localDeviceId: 'dev-phone',
        musicService: service,
        audioEngine: spyEngine,
        mediaBridge: bridge,
        transport: transport,
        catalogSongs: {'s-1': song},
      );

      await coordinator.applyServerSession(
        const PlaybackSessionState(
          sessionId: 'sess-stop',
          version: 1,
          activeRendererDeviceId: 'dev-phone',
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
      expect(fakeSession.activeHistory, [true]);

      await invokeTaskRemovedOnAudioHandlerForTest(osHandler);

      expect(spyEngine.stopCalls, greaterThanOrEqualTo(1));
      expect(coordinator.session?.state, PlaybackState.stopped);
      expect(fakeSession.activeHistory.last, isFalse);

      coordinator.dispose();
      await fakeSession.dispose();
    });

    testWidgets(
      'MobileNowPlayingPage removes Back to player button and steps Back through Queue -> Lyrics -> Player -> closes',
      (tester) async {
        final songs = [_song('s-1', 'One More Time'), _song('s-2', 'Aerodynamic')];
        final mockHttp = MockClient((req) async {
          if (req.url.path == '/api/v1/music/songs/s-1/lyrics') {
            return http.Response(
              jsonEncode({
                'songId': 's-1',
                'isSynced': true,
                'source': 'lrc',
                'lines': [
                  {'timeMs': 0, 'text': 'One more time'},
                  {'timeMs': 4000, 'text': "We're gonna celebrate"},
                ],
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
          audioEngine: _SpyAudioEngine(),
          mediaBridge: InMemoryPlatformMediaBridge(),
          transport: _FakeConnectTransport(songs),
          catalogSongs: {for (final s in songs) s.id: s},
        );
        addTearDown(coordinator.dispose);

        await coordinator.applyServerSession(
          const PlaybackSessionState(
            sessionId: 'sess-nav',
            version: 1,
            activeRendererDeviceId: 'dev-phone',
            state: PlaybackState.paused,
            repeatMode: HermesRepeatMode.off,
            shuffle: false,
            volume: 1.0,
            currentIndex: 0,
            currentSongId: 's-1',
            positionMs: 0,
            queueSongIds: ['s-1', 's-2'],
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: HermesThemeTokens.resolve().toThemeData(),
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (routeCtx) => MobileNowPlayingPage(
                          coordinator: coordinator,
                          musicService: service,
                          localDeviceId: 'dev-phone',
                          onClose: () => Navigator.of(routeCtx).pop(),
                          onOpenDevices: () {},
                          onNavigate: (_) {},
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Player'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Player'));
        await tester.pumpAndSettle();
        expect(find.byType(MobileNowPlayingPage), findsOneWidget);

        // Open Lyrics -> verify "Back to player" is removed.
        await tester.tap(find.byKey(const Key('mobile-player-lyrics-toggle')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('mobile-player-lyrics-view')), findsOneWidget);
        expect(find.text('Back to player'), findsNothing);

        // Open Queue from Lyrics -> verify "Back to player" is removed.
        await tester.tap(find.byKey(const Key('mobile-player-queue-toggle')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('mobile-player-queue-view')), findsOneWidget);
        expect(find.text('Back to player'), findsNothing);

        // System Back 1: Queue -> Lyrics (stays in MobileNowPlayingPage).
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(MobileNowPlayingPage), findsOneWidget);
        expect(find.byKey(const Key('mobile-player-lyrics-view')), findsOneWidget);

        // System Back 2: Lyrics -> main player.
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(MobileNowPlayingPage), findsOneWidget);
        expect(find.byKey(const Key('mobile-player-lyrics-view')), findsNothing);
        expect(find.byKey(const Key('mobile-player-queue-view')), findsNothing);

        // System Back 3: main player -> closes sheet/route.
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(MobileNowPlayingPage), findsNothing);
      },
    );
  });
}
