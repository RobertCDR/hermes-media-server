import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_client/src/core/settings/hermes_preferences.dart';
import 'package:hermes_client/src/core/storage/hermes_cache_manager.dart';
import 'package:hermes_client/src/core/storage/search_history_store.dart';
import 'package:hermes_client/src/core/theme/hermes_theme_tokens.dart';
import 'package:hermes_client/src/features/cinema/cinema_catalog_screen.dart';
import 'package:hermes_client/src/features/cinema/cinema_models.dart';
import 'package:hermes_client/src/features/cinema/cinema_service.dart';
import 'package:hermes_client/src/features/cinema/hermes_video_playback_controller.dart';
import 'package:hermes_client/src/features/cinema/hermes_video_player.dart';
import 'package:hermes_client/src/features/music/music_models.dart';
import 'package:hermes_client/src/features/music/music_playback_coordinator.dart';
import 'package:hermes_client/src/features/music/music_service.dart';
import 'package:hermes_client/src/features/music/music_shared_widgets.dart';
import 'package:hermes_client/src/features/music/music_world_screen.dart';
import 'package:hermes_client/src/features/music/now_playing_panel.dart';
import 'package:hermes_client/src/features/music/platform_media_bridge.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingAudioEngine implements AudioEngineAdapter {
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
  Future<void> stop() async {}
}

class _FakeConnectTransport implements ConnectTransport {
  _FakeConnectTransport(this._songs)
      : _queueIds = _songs.map((s) => s.id).toList();

  final List<SongModel> _songs;
  int _version = 1;
  PlaybackState _state = PlaybackState.playing;
  HermesRepeatMode _repeat = HermesRepeatMode.off;
  bool _shuffle = false;
  int _index = 0;
  int _positionMs = 0;
  List<String> _queueIds;

  PlaybackSessionState _snapshot() => PlaybackSessionState(
        sessionId: 'sess-pr30',
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

class _Pr30VideoPlaybackController implements HermesVideoPlaybackController {
  final positionController = StreamController<int>.broadcast();
  final durationController = StreamController<int>.broadcast();
  final playingController = StreamController<bool>.broadcast();
  final bufferingController = StreamController<bool>.broadcast();
  final completedController = StreamController<bool>.broadcast();
  final subtitleLinesController = StreamController<List<String>>.broadcast();
  final errorController = StreamController<String>.broadcast();

  final List<double> subtitleDelays = [];

  @override
  bool get hasVideoOutput => true;

  @override
  Stream<int> get positionMsStream => positionController.stream;

  @override
  Stream<int> get durationMsStream => durationController.stream;

  @override
  Stream<bool> get playingStream => playingController.stream;

  @override
  Stream<bool> get bufferingStream => bufferingController.stream;

  @override
  Stream<bool> get completedStream => completedController.stream;

  @override
  Stream<List<String>> get subtitleLinesStream => subtitleLinesController.stream;

  @override
  Stream<String> get errorStream => errorController.stream;

  @override
  Future<void> open(
    Uri streamUri, {
    int startPositionMs = 0,
    Uri? subtitleUri,
    String? subtitleTitle,
    String? subtitleLanguage,
    bool autoPlay = true,
  }) async {
    playingController.add(autoPlay);
  }

  @override
  Future<void> setExternalSubtitle(
    Uri? subtitleUri, {
    String? title,
    String? language,
  }) async {}

  @override
  Future<void> selectEmbeddedAudioTrack({
    required int streamIndex,
    required List<MediaStreamModel> availableAudioStreams,
  }) async {}

  @override
  Future<void> setSubtitleDelaySeconds(double seconds) async {
    subtitleDelays.add(seconds);
  }

  @override
  Future<void> play() async => playingController.add(true);

  @override
  Future<void> pause() async => playingController.add(false);

  @override
  Future<void> seek(int positionMs) async => positionController.add(positionMs);

  @override
  Future<void> setVolume(double volume0to100) async {}

  @override
  Future<void> stop() async => playingController.add(false);

  @override
  Widget buildVideoSurface(BuildContext context) =>
      const ColoredBox(color: Colors.black);

  @override
  Future<void> dispose() async {
    await positionController.close();
    await durationController.close();
    await playingController.close();
    await bufferingController.close();
    await completedController.close();
    await subtitleLinesController.close();
    await errorController.close();
  }
}

SongModel _song(String id, String title, {String artist = 'Daft Punk'}) =>
    SongModel(
      id: id,
      artistId: 'art-1',
      artistName: artist,
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

void main() {
  group('PR30 MobileNowPlayingPage Action Menu & Queue Placement', () {
    testWidgets(
      'replaces duplicate Up Next button with bottom-right queue icon and top-right 3-dot track menu',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final songs = [
          _song('song-1', 'One More Time'),
          _song('song-2', 'Aerodynamic'),
        ];
        String? addedPlaylistId;
        String? addedSongId;

        final client = MockClient((req) async {
          if (req.url.path == '/api/v1/auth/stream-tickets') {
            return http.Response(jsonEncode({'ticket': 'tkt-audio'}), 200);
          }
          if (req.url.path == '/api/v1/music/songs/song-1/lyrics') {
            return http.Response(
              jsonEncode({'songId': 'song-1', 'isSynced': false, 'lines': []}),
              200,
            );
          }
          if (req.url.path == '/api/v1/music/playlists') {
            return http.Response(
              jsonEncode([
                {
                  'id': 'pl-1',
                  'name': 'Night Drive',
                  'trackCount': 3,
                  'createdAtUtc': '2026-11-18T10:00:00Z',
                  'updatedAtUtc': '2026-11-18T10:00:00Z',
                },
              ]),
              200,
            );
          }
          if (req.url.path == '/api/v1/music/playlists/pl-1/tracks' &&
              req.method == 'POST') {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            addedPlaylistId = 'pl-1';
            addedSongId = body['songId'] as String?;
            return http.Response(
              jsonEncode({
                'id': 'pl-1',
                'name': 'Night Drive',
                'tracks': <Map<String, dynamic>>[],
                'createdAtUtc': '2026-11-18T10:00:00Z',
                'updatedAtUtc': '2026-11-18T10:00:00Z',
              }),
              200,
            );
          }
          return http.Response('{}', 200);
        });

        final service = MusicService(
          baseUri: Uri.parse('http://localhost:5258'),
          accessToken: 'jwt',
          httpClient: client,
        );
        final transport = _FakeConnectTransport(songs);
        final coordinator = MusicPlaybackCoordinator(
          localDeviceId: 'dev-phone',
          musicService: service,
          audioEngine: _RecordingAudioEngine(),
          mediaBridge: InMemoryPlatformMediaBridge(),
          transport: transport,
          catalogSongs: {for (final s in songs) s.id: s},
        );
        addTearDown(coordinator.dispose);
        await coordinator.applyServerSession(
          PlaybackSessionState(
            sessionId: 'sess-1',
            version: 1,
            activeRendererDeviceId: 'dev-phone',
            activeRendererDeviceName: 'Honor Phone',
            state: PlaybackState.playing,
            repeatMode: HermesRepeatMode.off,
            shuffle: false,
            volume: 1.0,
            currentIndex: 0,
            currentSongId: 'song-1',
            positionMs: 15000,
            queueSongIds: ['song-1', 'song-2'],
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: HermesThemeTokens.resolve().toThemeData(),
            home: Scaffold(
              body: MobileNowPlayingPage(
                coordinator: coordinator,
                musicService: service,
                localDeviceId: 'dev-phone',
                onClose: () {},
                onOpenDevices: () {},
                onNavigate: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('mobile-player-up-next-btn')), findsNothing);
        expect(find.text('Up Next'), findsNothing);
        expect(find.byKey(const Key('mobile-player-queue-toggle')), findsOneWidget);
        expect(find.byKey(const Key('mobile-player-more-menu')), findsOneWidget);

        // Open top-right 3-dot track menu & add song to playlist
        await tester.tap(find.byKey(const Key('mobile-player-more-menu')));
        await tester.pumpAndSettle();

        expect(find.text('Add to playlist'), findsOneWidget);
        expect(find.text('Add to queue'), findsOneWidget);
        expect(find.text('Play next'), findsOneWidget);
        expect(find.text('Go to album'), findsOneWidget);
        expect(find.text('Go to artist'), findsOneWidget);

        await tester.tap(find.text('Add to playlist'));
        await tester.pumpAndSettle();

        expect(find.text('Night Drive'), findsOneWidget);
        await tester.tap(find.text('Night Drive'));
        await tester.pumpAndSettle();

        expect(addedPlaylistId, 'pl-1');
        expect(addedSongId, 'song-1');
      },
    );
  });

  group('PR30 Spotify-style Swipe-to-Queue Gesture', () {
    testWidgets(
      'ignores short swipe under threshold and queues smoothly on rubber-band threshold drag without dismissing row',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final songs = [
          _song('song-1', 'One More Time'),
          _song('song-2', 'Digital Love'),
        ];
        final client = MockClient((req) async {
          if (req.url.path == '/api/v1/auth/stream-tickets') {
            return http.Response(jsonEncode({'ticket': 'tkt-audio'}), 200);
          }
          return http.Response('{}', 200);
        });
        final service = MusicService(
          baseUri: Uri.parse('http://localhost:5258'),
          accessToken: 'jwt',
          httpClient: client,
        );
        final coordinator = MusicPlaybackCoordinator(
          localDeviceId: 'dev-phone',
          musicService: service,
          audioEngine: _RecordingAudioEngine(),
          mediaBridge: InMemoryPlatformMediaBridge(),
          transport: _FakeConnectTransport(songs),
          catalogSongs: {for (final s in songs) s.id: s},
        );
        addTearDown(coordinator.dispose);
        await coordinator.startQueue(songs, 0, sourceLabel: 'Discovery');

        await tester.pumpWidget(
          MaterialApp(
            theme: HermesThemeTokens.resolve().toThemeData(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: MusicTrackTable(
                  songs: songs,
                  musicService: service,
                  coordinator: coordinator,
                  playlists: const [],
                  onPlayTrackAt: (_) {},
                  onToggleLike: (_) {},
                  onNavigate: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Short drag below threshold should NOT queue
        await tester.drag(find.text('Digital Love'), const Offset(24, 0));
        await tester.pumpAndSettle();
        expect(coordinator.upNext, isEmpty);

        // Full swipe across rubber-band threshold arms & queues immediately
        await tester.drag(find.text('Digital Love'), const Offset(140, 0));
        await tester.pumpAndSettle();
        expect(coordinator.upNext.map((s) => s.id), ['song-2']);
        expect(find.text('Digital Love'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('PR30 Cache 5 GB & 10 GB Options', () {
    testWidgets(
      'supports 5120 MB and 10240 MB caps while keeping RAM image cache capped at 1024 MB',
      (tester) async {
        expect(HermesCacheManager.capOptionsMb, containsAll([5120, 10240]));
        expect(HermesCacheManager.formatCapMb(5120), '5 GB');
        expect(HermesCacheManager.formatCapMb(10240), '10 GB');
        expect(
          HermesDevicePreferences.fromJson({'cacheCapMb': 10240}).cacheCapMb,
          10240,
        );

        final prevMaxBytes = PaintingBinding.instance.imageCache.maximumSizeBytes;
        final prevMaxCount = PaintingBinding.instance.imageCache.maximumSize;
        addTearDown(() {
          PaintingBinding.instance.imageCache.maximumSizeBytes = prevMaxBytes;
          PaintingBinding.instance.imageCache.maximumSize = prevMaxCount;
        });

        await tester.runAsync(() async {
          final tempDir = await Directory.systemTemp.createTemp('hermes_cache_pr30_');
          try {
            final manager = HermesCacheManager(diskCacheDir: tempDir);
            manager.applyCapMb(10240);
            expect(
              PaintingBinding.instance.imageCache.maximumSizeBytes,
              lessThanOrEqualTo(1024 * 1024 * 1024),
            );
            final snap = await manager.inspect(capMb: 10240);
            expect(snap.capBytes, 10240 * 1024 * 1024);
          } finally {
            await tempDir.delete(recursive: true);
          }
        });
      },
    );
  });

  group('PR30 Nuvio-Style Bounded Scrollable Subtitle Panel', () {
    MediaSourceModel buildManySubtitlesSource() {
      return MediaSourceModel(
        id: 'src-nuvio',
        sourceLabel: '4K REMUX',
        container: 'mkv',
        videoCodec: 'hevc',
        audioCodec: 'eac3',
        width: 3840,
        height: 2160,
        isHdr: true,
        bitrateBps: 24000000,
        durationMs: 180000,
        isAvailable: true,
        streams: [
          const MediaStreamModel(
            streamIndex: 1,
            kind: 1,
            codec: 'eac3',
            language: 'eng',
            title: 'English 5.1',
            isDefault: true,
          ),
          for (var i = 1; i <= 18; i++)
            MediaStreamModel(
              streamIndex: 100 + i,
              kind: 2,
              codec: 'subrip',
              language: 'l$i',
              title: 'Track $i Subtitle',
              isDefault: i == 1,
            ),
        ],
      );
    }

    testWidgets(
      'mobile landscape vp-panel never clips top bar, scrolls 18 subtitles, and updates Nuvio Style & Delay live',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(844, 390);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final client = MockClient((req) async {
          if (req.url.path == '/api/v1/auth/stream-tickets') {
            return http.Response(jsonEncode({'ticket': 'tkt-nuvio'}), 200);
          }
          return http.Response('{}', 200);
        });
        final cinemaService = CinemaService(
          baseUri: Uri.parse('http://localhost:5258'),
          accessToken: 'jwt',
          httpClient: client,
        );
        final tokens = HermesThemeTokens.resolve();
        late _Pr30VideoPlaybackController controller;

        await tester.pumpWidget(
          MaterialApp(
            theme: tokens.toThemeData(),
            home: HermesVideoPlayerScreen(
              title: 'Dune: Part Two',
              source: buildManySubtitlesSource(),
              initialQuality: VideoQualityPreset.directPlay,
              config: HermesVideoPlayerConfig.hdrSafeDefault(tokens: tokens),
              cinemaService: cinemaService,
              movieId: 'mov-dune',
              playbackControllerFactory: (_) {
                controller = _Pr30VideoPlaybackController();
                return controller;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('vp-tracks-btn')));
        await tester.pumpAndSettle();

        final panelFinder = find.byKey(const Key('vp-panel'));
        expect(panelFinder, findsOneWidget);
        final panelRect = tester.getRect(panelFinder);
        expect(panelRect.top, greaterThanOrEqualTo(0.0));
        expect(panelRect.bottom, lessThanOrEqualTo(390.0));

        // 18th subtitle scrolls cleanly into view inside bounded panel
        final lastSubFinder = find.text('L18 (Track 18 Subtitle)');
        await tester.scrollUntilVisible(
          lastSubFinder,
          120,
          scrollable: find.descendant(
            of: panelFinder,
            matching: find.byType(Scrollable),
          ).first,
        );
        expect(lastSubFinder, findsOneWidget);

        // Switch to Nuvio Style tab & test timing delay + position + appearance
        await tester.tap(find.text('Style'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('vp-sub-delay-plus')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('vp-sub-delay-plus')));
        await tester.pumpAndSettle();
        expect(find.text('+0.50s'), findsOneWidget);
        expect(controller.subtitleDelays, containsAll([0.25, 0.5]));

        await tester.tap(find.byKey(const Key('vp-sub-delay-reset')));
        await tester.pumpAndSettle();
        expect(find.text('0.00s'), findsOneWidget);
        expect(controller.subtitleDelays.last, 0.0);

        await tester.drag(
          find.byKey(const Key('vp-sub-offset-slider')),
          const Offset(40, 0),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Large'));
        await tester.tap(find.text('Large'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Box'));
        await tester.tap(find.text('Box'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Yellow'));
        await tester.tap(find.text('Yellow'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'desktop vp-panel opens 3 columns by default and switches to Subtitle Style view cleanly',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(1280, 800);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final client = MockClient((req) async {
          if (req.url.path == '/api/v1/auth/stream-tickets') {
            return http.Response(jsonEncode({'ticket': 'tkt-desk'}), 200);
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
            home: HermesVideoPlayerScreen(
              title: 'Dune: Part Two',
              source: buildManySubtitlesSource(),
              initialQuality: VideoQualityPreset.directPlay,
              config: HermesVideoPlayerConfig.hdrSafeDefault(tokens: tokens),
              cinemaService: cinemaService,
              movieId: 'mov-dune',
              playbackControllerFactory: (_) => _Pr30VideoPlaybackController(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('vp-tracks-btn')));
        await tester.pumpAndSettle();
        expect(find.text('Audio'), findsOneWidget);
        expect(find.text('Subtitles'), findsOneWidget);
        expect(find.text('Quality'), findsOneWidget);

        await tester.tap(find.text('Subtitle Style'));
        await tester.pumpAndSettle();
        expect(find.text('Timing delay'), findsOneWidget);
        expect(find.text('Vertical position'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('PR30 SearchHistoryStore & Music/Cinema Search History UI', () {
    test(
      'SharedPrefsSearchHistoryStore deduplicates, caps at 20, removes, and clears Music & Cinema history',
      () async {
        SharedPreferences.setMockInitialValues({});
        final store = SharedPrefsSearchHistoryStore();

        for (var i = 1; i <= 22; i++) {
          await store.addMusicItem(
            MusicSearchHistoryItem(
              id: 'song:s-$i',
              kind: MusicSearchHistoryKind.song,
              title: 'Track $i',
              subtitle: 'Song • Artist',
              targetId: 's-$i',
              timestampMs: i,
            ),
          );
        }
        // Re-adding Track 3 moves it to front cleanly
        final music = await store.addMusicItem(
          const MusicSearchHistoryItem(
            id: 'song:s-3',
            kind: MusicSearchHistoryKind.song,
            title: 'Track 3',
            subtitle: 'Song • Artist',
            targetId: 's-3',
            timestampMs: 99,
          ),
        );
        expect(music.length, 20);
        expect(music.first.title, 'Track 3');

        final afterRemoveMusic = await store.removeMusicItem('song:s-3');
        expect(afterRemoveMusic.any((e) => e.id == 'song:s-3'), isFalse);
        await store.clearMusicHistory();
        expect(await store.loadMusicHistory(), isEmpty);

        // Cinema plain-text queries (case-insensitive dedup + 20 limit)
        for (var i = 1; i <= 22; i++) {
          await store.addCinemaQuery('Movie $i');
        }
        final cinema = await store.addCinemaQuery('movie 5');
        expect(cinema.length, 20);
        expect(cinema.first, 'movie 5');
        expect(
          cinema.where((q) => q.toLowerCase() == 'movie 5').length,
          1,
        );

        final afterRemoveCinema = await store.removeCinemaQuery('Movie 5');
        expect(afterRemoveCinema, isNot(contains('movie 5')));
        await store.clearCinemaHistory();
        expect(await store.loadCinemaHistory(), isEmpty);
      },
    );

    MockClient createCatalogMockClient() {
      return MockClient((req) async {
        final p = req.url.path;
        if (p == '/api/v1/music/songs') {
          return http.Response(
            jsonEncode([
              {
                'id': 'song-1',
                'artistId': 'art-1',
                'artistName': 'Daft Punk',
                'albumId': 'alb-1',
                'albumTitle': 'Discovery',
                'title': 'One More Time',
                'trackNumber': 1,
                'discNumber': 1,
                'durationMs': 240000,
                'codec': 'flac',
                'bitrateBps': 1411000,
                'sampleRateHz': 44100,
                'bitDepth': 16,
                'isLiked': false,
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
        if (p == '/api/v1/music/artists') {
          return http.Response(
            jsonEncode([
              {'id': 'art-1', 'name': 'Daft Punk', 'albumCount': 1},
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
                'overview': 'Space exploration.',
                'genres': ['Sci-Fi'],
                'isInWatchlist': false,
                'cast': <Map<String, dynamic>>[],
                'sources': <Map<String, dynamic>>[],
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
        return http.Response('{}', 200);
      });
    }

    testWidgets(
      'MusicWorldScreen shows Spotify-style Recent searches on mobile Search tab and desktop focused search dropdown',
      (tester) async {
        final service = MusicService(
          baseUri: Uri.parse('http://localhost:5258'),
          accessToken: 'jwt',
          httpClient: createCatalogMockClient(),
        );
        final song = _song('song-1', 'One More Time');
        final coordinator = MusicPlaybackCoordinator(
          localDeviceId: 'dev-1',
          musicService: service,
          audioEngine: _RecordingAudioEngine(),
          mediaBridge: InMemoryPlatformMediaBridge(),
          transport: _FakeConnectTransport([song]),
          catalogSongs: {'song-1': song},
        );
        addTearDown(coordinator.dispose);

        final store = InMemorySearchHistoryStore(
          initialMusic: const [
            MusicSearchHistoryItem(
              id: 'song:song-1',
              kind: MusicSearchHistoryKind.song,
              title: 'One More Time',
              subtitle: 'Song • Daft Punk',
              targetId: 'song-1',
              timestampMs: 1,
            ),
            MusicSearchHistoryItem(
              id: 'query:discovery',
              kind: MusicSearchHistoryKind.query,
              title: 'Discovery',
              subtitle: 'Search',
              timestampMs: 2,
            ),
          ],
        );

        // 1) Mobile Search tab
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final nav = MusicNavigationController();
        nav.navigate(const MusicPageRoute.search());

        await tester.pumpWidget(
          MaterialApp(
            theme: HermesThemeTokens.resolve().toThemeData(),
            home: Scaffold(
              body: MusicWorldScreen(
                key: const Key('pr30-mobile-music'),
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

        expect(find.byKey(const Key('music-recent-searches')), findsOneWidget);
        expect(find.text('One More Time'), findsOneWidget);
        expect(find.text('Song • Daft Punk'), findsOneWidget);
        expect(find.text('Discovery'), findsOneWidget);

        // Remove individual entry
        await tester.tap(find.byTooltip('Remove from recent searches').first);
        await tester.pumpAndSettle();
        expect(find.text('Song • Daft Punk'), findsNothing);
        expect(find.text('Discovery'), findsOneWidget);

        // Clear all
        await tester.tap(find.byKey(const Key('music-clear-search-history')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('music-recent-searches')), findsNothing);

        // 2) Desktop focused search pill dropdown
        tester.view.physicalSize = const Size(1280, 800);
        await store.addMusicItem(
          const MusicSearchHistoryItem(
            id: 'query:daft',
            kind: MusicSearchHistoryKind.query,
            title: 'Daft',
            subtitle: 'Search',
            timestampMs: 3,
          ),
        );
        final deskNav = MusicNavigationController();
        await tester.pumpWidget(
          MaterialApp(
            theme: HermesThemeTokens.resolve().toThemeData(),
            home: Scaffold(
              body: MusicWorldScreen(
                key: const Key('pr30-desktop-music'),
                musicService: service,
                coordinator: coordinator,
                navigationController: deskNav,
                searchHistoryStore: store,
                externalMobileNav: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('music-recent-searches')), findsNothing);
        await tester.tap(find.byKey(const Key('music-search-input')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('music-recent-searches')), findsOneWidget);
        expect(find.text('Daft'), findsOneWidget);

        // Clicking dropdown entry filters catalog cleanly
        await tester.tap(find.text('Daft'));
        await tester.pumpAndSettle();
        expect(find.text('Daft Punk'), findsAtLeastNWidgets(1));
      },
    );

    testWidgets(
      'CinemaCatalogScreen shows Nuvio-style plain-text Recent searches on mobile Search tab and desktop dropdown',
      (tester) async {
        final tokens = HermesThemeTokens.resolve();
        final cinemaService = CinemaService(
          baseUri: Uri.parse('http://localhost:5258'),
          accessToken: 'jwt',
          httpClient: createCatalogMockClient(),
        );
        final store = InMemorySearchHistoryStore(
          initialCinema: const ['Interstellar'],
        );

        // 1) Mobile Search tab
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final cinemaNav = CinemaNavigationController();
        cinemaNav.selectMobileTab(CinemaMobileTab.search);

        await tester.pumpWidget(
          MaterialApp(
            theme: tokens.toThemeData(),
            home: Scaffold(
              body: CinemaCatalogScreen(
                key: const Key('pr30-mobile-cinema'),
                cinemaService: cinemaService,
                playerConfig: HermesVideoPlayerConfig.hdrSafeDefault(tokens: tokens),
                defaultQuality: VideoQualityPreset.directPlay,
                navigationController: cinemaNav,
                searchHistoryStore: store,
                externalMobileNav: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('cinema-recent-searches')), findsOneWidget);
        expect(find.text('Interstellar'), findsWidgets);

        await tester.tap(find.byKey(const Key('cinema-clear-search-history')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('cinema-recent-searches')), findsNothing);

        // 2) Desktop search submit + focused dropdown
        tester.view.physicalSize = const Size(1280, 800);
        await store.addCinemaQuery('sci-fi');

        await tester.pumpWidget(
          MaterialApp(
            theme: tokens.toThemeData(),
            home: Scaffold(
              body: CinemaCatalogScreen(
                key: const Key('pr30-desktop-cinema'),
                cinemaService: cinemaService,
                playerConfig: HermesVideoPlayerConfig.hdrSafeDefault(tokens: tokens),
                defaultQuality: VideoQualityPreset.directPlay,
                searchHistoryStore: store,
                externalMobileNav: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('cinema-recent-searches')), findsNothing);
        await tester.tap(find.byKey(const Key('cinema-search-input')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('cinema-recent-searches')), findsOneWidget);
        expect(find.text('sci-fi'), findsOneWidget);

        await tester.tap(find.text('sci-fi'));
        await tester.pumpAndSettle();
        expect(find.text('Movies & TV Shows'), findsOneWidget);
        expect(find.text('Interstellar'), findsWidgets);
      },
    );
  });
}
