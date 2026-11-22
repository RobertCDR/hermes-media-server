import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_client/src/core/theme/hermes_theme_tokens.dart';
import 'package:hermes_client/src/core/widgets/hermes_icons.dart';
import 'package:hermes_client/src/features/cinema/cinema_catalog_screen.dart';
import 'package:hermes_client/src/features/cinema/cinema_detail_page.dart';
import 'package:hermes_client/src/features/cinema/cinema_models.dart';
import 'package:hermes_client/src/features/cinema/cinema_service.dart';
import 'package:hermes_client/src/features/cinema/hermes_video_playback_controller.dart';
import 'package:hermes_client/src/features/cinema/hermes_video_player.dart';
import 'package:hermes_client/src/features/music/music_detail_views.dart';
import 'package:hermes_client/src/features/music/music_models.dart';
import 'package:hermes_client/src/features/music/music_playback_coordinator.dart';
import 'package:hermes_client/src/features/music/music_service.dart';
import 'package:hermes_client/src/features/music/music_world_screen.dart';
import 'package:hermes_client/src/features/music/now_playing_panel.dart';
import 'package:hermes_client/src/features/music/platform_media_bridge.dart';
import 'package:hermes_client/src/features/settings/player_and_theme_settings_screen.dart';
import 'package:hermes_client/src/features/shell/dual_world_shell.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, dynamic> _songPayload({
  required String id,
  required String artistId,
  required String artistName,
  required String albumId,
  required String albumTitle,
  required String title,
  int durationMs = 210000,
  List<Map<String, String>>? artistCredits,
}) {
  return {
    'id': id,
    'artistId': artistId,
    'artistName': artistName,
    'artistCredits': ?artistCredits,
    'albumId': albumId,
    'albumTitle': albumTitle,
    'title': title,
    'trackNumber': 1,
    'discNumber': 1,
    'durationMs': durationMs,
    'codec': 'flac',
    'bitrateBps': 1411000,
    'sampleRateHz': 44100,
    'bitDepth': 16,
    'artworkHash': null,
    'isLiked': false,
    'isMissing': false,
  };
}

class _ControllableStubAudioEngine implements ControllableAudioEngine {
  final StreamController<int> positionController =
      StreamController<int>.broadcast();
  final StreamController<void> completedController =
      StreamController<void>.broadcast();

  @override
  Stream<int> get positionMsStream => positionController.stream;

  @override
  Stream<void> get trackCompletedStream => completedController.stream;

  @override
  Future<void> loadAndPlay(
    Uri streamUri,
    SongModel track,
    int startPositionMs,
  ) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> seek(int positionMs) async {}

  @override
  Future<void> setNormalizationEnabled(bool enabled) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> stop() async {}

  Future<void> dispose() async {
    await positionController.close();
    await completedController.close();
  }
}

class _StubVideoPlaybackController implements HermesVideoPlaybackController {
  final positionController = StreamController<int>.broadcast();
  final durationController = StreamController<int>.broadcast();
  final playingController = StreamController<bool>.broadcast();
  final bufferingController = StreamController<bool>.broadcast();
  final completedController = StreamController<bool>.broadcast();
  final subtitleLinesController = StreamController<List<String>>.broadcast();
  final errorController = StreamController<String>.broadcast();

  final List<int> seekCalls = [];
  int playCalls = 0;
  int pauseCalls = 0;
  double? lastVolume;
  bool disposed = false;

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
  }) async {}

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
  Future<void> setSubtitleDelaySeconds(double seconds) async {}

  @override
  Future<void> play() async {
    playCalls++;
    playingController.add(true);
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    playingController.add(false);
  }

  @override
  Future<void> seek(int positionMs) async {
    seekCalls.add(positionMs);
    positionController.add(positionMs);
  }

  @override
  Future<void> setVolume(double volume0to100) async {
    lastVolume = volume0to100;
  }

  @override
  Future<void> stop() async {}

  @override
  Widget buildVideoSurface(
    BuildContext context, {
    BoxFit fit = BoxFit.contain,
  }) =>
      const ColoredBox(color: Color(0xFF000000));

  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    await positionController.close();
    await durationController.close();
    await playingController.close();
    await bufferingController.close();
    await completedController.close();
    await subtitleLinesController.close();
    await errorController.close();
  }
}

void main() {
  group('PR26 Models & Services (History, Custom Lists, Multi-Artist Credits)', () {
    test('SongModel parses artistCredits and falls back when omitted', () {
      final credited = SongModel.fromJson(
        _songPayload(
          id: 's-1',
          artistId: 'art-1',
          artistName: 'Daft Punk, Pharrell Williams',
          albumId: 'alb-1',
          albumTitle: 'Random Access Memories',
          title: 'Get Lucky',
          artistCredits: [
            {'artistId': 'art-1', 'name': 'Daft Punk'},
            {'artistId': 'art-2', 'name': 'Pharrell Williams'},
          ],
        ),
      );
      expect(credited.effectiveArtistCredits, hasLength(2));
      expect(credited.effectiveArtistCredits[0].artistId, 'art-1');
      expect(credited.effectiveArtistCredits[1].name, 'Pharrell Williams');

      final legacy = SongModel.fromJson(
        _songPayload(
          id: 's-2',
          artistId: 'art-3',
          artistName: 'Justice',
          albumId: 'alb-2',
          albumTitle: 'Cross',
          title: 'Genesis',
        ),
      );
      expect(legacy.effectiveArtistCredits, hasLength(1));
      expect(legacy.effectiveArtistCredits.single.artistId, 'art-3');
      expect(legacy.effectiveArtistCredits.single.name, 'Justice');
    });

    test('MusicService listHistory & recordListen hit expected endpoints', () async {
      final calls = <String>[];
      Map<String, dynamic>? recordedBody;
      final client = MockClient((req) async {
        calls.add('${req.method} ${req.url}');
        if (req.method == 'GET' && req.url.path == '/api/v1/music/history') {
          return _json([
            {
              'id': 'hist-1',
              'listenedAtUtc': '2026-11-18T00:15:00Z',
              'deviceId': 'win-desktop',
              'contextLabel': 'Random Access Memories',
              'song': _songPayload(
                id: 's-1',
                artistId: 'art-1',
                artistName: 'Daft Punk',
                albumId: 'alb-1',
                albumTitle: 'RAM',
                title: 'Instant Crush',
              ),
            },
          ]);
        }
        if (req.method == 'POST' && req.url.path == '/api/v1/music/history') {
          recordedBody = jsonDecode(req.body) as Map<String, dynamic>;
          return _json({'recorded': true, 'entryId': 'hist-2'});
        }
        return _json({});
      });

      final service = MusicService(
        baseUri: Uri.parse('http://localhost:5258'),
        accessToken: 'jwt',
        httpClient: client,
      );

      final history = await service.listHistory(limit: 15);
      expect(history, hasLength(1));
      expect(history.single.id, 'hist-1');
      expect(history.single.contextLabel, 'Random Access Memories');
      expect(history.single.song.title, 'Instant Crush');
      expect(calls.first, contains('/api/v1/music/history?limit=15'));

      await service.recordListen(
        songId: 's-1',
        positionMs: 42000,
        durationMs: 210000,
        deviceId: 'win-desktop',
        contextLabel: 'RAM',
      );
      expect(recordedBody?['songId'], 's-1');
      expect(recordedBody?['positionMs'], 42000);
      expect(recordedBody?['durationMs'], 210000);
      expect(recordedBody?['deviceId'], 'win-desktop');
      expect(recordedBody?['contextLabel'], 'RAM');
    });

    test('CinemaService custom list CRUD endpoints work end-to-end', () async {
      final calls = <String>[];
      final lists = <Map<String, dynamic>>[
        {
          'id': 'lst-1',
          'name': 'Late Night Noir',
          'description': 'Moody rain classics',
          'createdAtUtc': '2026-11-18T00:00:00Z',
          'updatedAtUtc': '2026-11-18T00:00:00Z',
          'items': [
            {
              'id': 'li-1',
              'movieId': 'mov-1',
              'mediaKind': 'movie',
              'title': 'Blade Runner',
              'year': 1982,
              'rating': 8.1,
              'position': 0,
              'addedAtUtc': '2026-11-18T00:00:00Z',
            },
          ],
        },
      ];

      final client = MockClient((req) async {
        calls.add('${req.method} ${req.url.path}${req.url.hasQuery ? '?${req.url.query}' : ''}');
        if (req.method == 'GET' && req.url.path == '/api/v1/cinema/lists') {
          return _json(lists);
        }
        if (req.method == 'POST' && req.url.path == '/api/v1/cinema/lists') {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          return _json({
            'id': 'lst-2',
            'name': body['name'],
            'description': body['description'],
            'createdAtUtc': '2026-11-18T00:10:00Z',
            'updatedAtUtc': '2026-11-18T00:10:00Z',
            'items': <Map<String, dynamic>>[],
          }, 201);
        }
        if (req.method == 'PUT' && req.url.path == '/api/v1/cinema/lists/lst-2') {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          return _json({
            'id': 'lst-2',
            'name': body['name'],
            'description': body['description'],
            'createdAtUtc': '2026-11-18T00:10:00Z',
            'updatedAtUtc': '2026-11-18T00:12:00Z',
            'items': <Map<String, dynamic>>[],
          });
        }
        if (req.method == 'POST' && req.url.path == '/api/v1/cinema/lists/lst-2/items') {
          return _json({
            'id': 'lst-2',
            'name': 'Renamed List',
            'createdAtUtc': '2026-11-18T00:10:00Z',
            'updatedAtUtc': '2026-11-18T00:15:00Z',
            'items': [
              {
                'id': 'li-2',
                'tvSeriesId': 'ser-1',
                'mediaKind': 'series',
                'title': 'Dark',
                'year': 2017,
                'position': 0,
                'addedAtUtc': '2026-11-18T00:15:00Z',
              },
            ],
          });
        }
        if (req.method == 'DELETE' && req.url.path == '/api/v1/cinema/lists/lst-2/items') {
          return _json({
            'id': 'lst-2',
            'name': 'Renamed List',
            'createdAtUtc': '2026-11-18T00:10:00Z',
            'updatedAtUtc': '2026-11-18T00:16:00Z',
            'items': <Map<String, dynamic>>[],
          });
        }
        if (req.method == 'DELETE' && req.url.path == '/api/v1/cinema/lists/lst-2') {
          return http.Response('', 204);
        }
        return _json({}, 404);
      });

      final service = CinemaService(
        baseUri: Uri.parse('http://localhost:5258'),
        accessToken: 'jwt',
        httpClient: client,
      );

      final loaded = await service.listCustomLists();
      expect(loaded.single.items.single.isMovie, isTrue);

      final created = await service.createCustomList(
        name: 'Sci-Fi Picks',
        description: 'Top picks',
      );
      expect(created.id, 'lst-2');

      final updated = await service.updateCustomList(
        listId: 'lst-2',
        name: 'Renamed List',
      );
      expect(updated.name, 'Renamed List');

      final withSeries = await service.addItemToCustomList(
        listId: 'lst-2',
        tvSeriesId: 'ser-1',
      );
      expect(withSeries.items.single.isMovie, isFalse);
      expect(withSeries.items.single.tvSeriesId, 'ser-1');

      final removed = await service.removeItemFromCustomList(
        listId: 'lst-2',
        tvSeriesId: 'ser-1',
      );
      expect(removed.items, isEmpty);

      await service.deleteCustomList('lst-2');
      expect(
        calls,
        containsAllInOrder([
          'GET /api/v1/cinema/lists',
          'POST /api/v1/cinema/lists',
          'PUT /api/v1/cinema/lists/lst-2',
          'POST /api/v1/cinema/lists/lst-2/items',
          'DELETE /api/v1/cinema/lists/lst-2/items?seriesId=ser-1',
          'DELETE /api/v1/cinema/lists/lst-2',
        ]),
      );
    });
  });

  group('PR26 MusicPlaybackCoordinator Listen History Recording', () {
    test('records listen once when engine playback position crosses threshold', () async {
      final recordedPayloads = <Map<String, dynamic>>[];
      final service = MusicService(
        baseUri: Uri.parse('http://localhost:5258'),
        accessToken: 'jwt',
        httpClient: MockClient((req) async {
          if (req.url.path == '/api/v1/auth/stream-tickets') {
            return _json({'ticket': 'tkt-aud'});
          }
          if (req.method == 'POST' && req.url.path == '/api/v1/music/history') {
            recordedPayloads.add(jsonDecode(req.body) as Map<String, dynamic>);
            return _json({'recorded': true, 'entryId': 'h-new'});
          }
          return _json({});
        }),
      );

      final engine = _ControllableStubAudioEngine();
      addTearDown(engine.dispose);

      final coordinator = MusicPlaybackCoordinator(
        localDeviceId: 'dev-win',
        musicService: service,
        audioEngine: engine,
        mediaBridge: InMemoryPlatformMediaBridge(),
      );
      addTearDown(coordinator.dispose);

      final song = SongModel.fromJson(
        _songPayload(
          id: 'song-threshold',
          artistId: 'art-1',
          artistName: 'Daft Punk',
          albumId: 'alb-1',
          albumTitle: 'Discovery',
          title: 'Voyager',
          durationMs: 210000,
        ),
      );

      await coordinator.startQueue([song], 0, sourceLabel: 'Discovery');

      engine.positionController.add(12000);
      await Future<void>.delayed(Duration.zero);
      expect(recordedPayloads, isEmpty);

      engine.positionController.add(32000);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(recordedPayloads, hasLength(1));
      expect(recordedPayloads.single['songId'], 'song-threshold');
      expect(recordedPayloads.single['contextLabel'], 'Discovery');

      // Further ticks on same song do not spam history endpoint.
      engine.positionController.add(75000);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(recordedPayloads, hasLength(1));
    });
  });

  group('PR26 MusicWorldScreen Listening History & Clickable Collaborator Credits', () {
    testWidgets('shows Recently played shelf, History page, and navigates via collaborator link', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 860));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final collabSong = _songPayload(
        id: 's-collab',
        artistId: 'art-daft',
        artistName: 'Daft Punk, Pharrell Williams',
        albumId: 'alb-ram',
        albumTitle: 'Random Access Memories',
        title: 'Get Lucky',
        artistCredits: [
          {'artistId': 'art-daft', 'name': 'Daft Punk'},
          {'artistId': 'art-pharrell', 'name': 'Pharrell Williams'},
        ],
      );

      final client = MockClient((req) async {
        return switch (req.url.path) {
          '/api/v1/music/artists' => _json([
              {'id': 'art-daft', 'name': 'Daft Punk', 'albumCount': 1, 'songCount': 1},
              {'id': 'art-pharrell', 'name': 'Pharrell Williams', 'albumCount': 0, 'songCount': 1},
            ]),
          '/api/v1/music/albums' => _json([
              {
                'id': 'alb-ram',
                'artistId': 'art-daft',
                'artistName': 'Daft Punk',
                'title': 'Random Access Memories',
                'year': 2013,
                'songCount': 1,
              },
            ]),
          '/api/v1/music/songs' => _json([collabSong]),
          '/api/v1/music/playlists' => _json([]),
          '/api/v1/music/history' => _json([
              {
                'id': 'hist-1',
                'listenedAtUtc': '2026-11-18T01:00:00Z',
                'deviceId': 'dev-win',
                'contextLabel': 'Random Access Memories',
                'song': collabSong,
              },
            ]),
          _ => _json([]),
        };
      });

      final service = MusicService(
        baseUri: Uri.parse('http://localhost:5258'),
        accessToken: 'jwt',
        httpClient: client,
      );
      final coordinator = MusicPlaybackCoordinator(
        localDeviceId: 'dev-win',
        musicService: service,
        audioEngine: NoOpAudioEngineAdapter(),
        mediaBridge: InMemoryPlatformMediaBridge(),
      );
      addTearDown(coordinator.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: HermesThemeTokens.resolve().toThemeData(),
          home: Scaffold(
            body: MusicWorldScreen(
              musicService: service,
              coordinator: coordinator,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Home displays the Recently played shelf from /api/v1/music/history.
      expect(find.text('Recently played'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);

      // Navigate via sidebar to History page.
      await tester.tap(find.text('History').first);
      await tester.pumpAndSettle();
      expect(find.text('Listening history'), findsOneWidget);
      expect(find.text('Get Lucky'), findsOneWidget);

      // Tapping artist text inside a song row plays the song and does NOT leave History.
      await tester.tap(find.text('Pharrell Williams').first);
      await tester.pumpAndSettle();

      expect(find.byType(MusicArtistPage), findsNothing);
      expect(find.text('Listening history'), findsOneWidget);
      expect(coordinator.currentSong?.id, 's-collab');

      // Collaborator credits inside the player remain clickable for artist navigation.
      MusicPageRoute? navigatedRoute;
      await tester.pumpWidget(
        MaterialApp(
          theme: HermesThemeTokens.resolve().toThemeData(),
          home: Scaffold(
            body: SizedBox(
              width: 520,
              height: 760,
              child: NowPlayingPanel(
                coordinator: coordinator,
                musicService: service,
                localDeviceId: 'dev-win',
                onClose: () {},
                onOpenDevices: () {},
                onNavigate: (route) => navigatedRoute = route,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pharrell Williams').first);
      await tester.pump();
      expect(navigatedRoute, const MusicPageRoute.artist('art-pharrell'));
      expect(tester.takeException(), isNull);
    });
  });

  group('PR26 CinemaCatalogScreen & CinemaDetailPage Custom Lists CRUD', () {
    testWidgets('creates, renames, populates from CinemaDetailPage, and deletes a custom list', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final movies = [
        {
          'id': 'mov-dune',
          'title': 'Dune',
          'year': 2021,
          'overview': 'Arrakis saga.',
          'tmdbId': 438631,
          'genres': ['Sci-Fi'],
          'isInWatchlist': false,
          'cast': <Map<String, dynamic>>[],
          'sources': [
            {
              'id': 'src-dune',
              'sourceLabel': '4K',
              'container': 'mkv',
              'videoCodec': 'hevc',
              'audioCodec': 'eac3',
              'width': 3840,
              'height': 2160,
              'isHdr': true,
              'bitrateBps': 20000000,
              'durationMs': 9000000,
              'isAvailable': true,
              'streams': <Map<String, dynamic>>[],
            },
          ],
        },
      ];
      final lists = <Map<String, dynamic>>[];

      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path == '/api/v1/cinema/movies') {
          return _json(movies);
        }
        if (req.method == 'GET' && req.url.path == '/api/v1/cinema/series') {
          return _json([]);
        }
        if (req.method == 'GET' && req.url.path == '/api/v1/cinema/lists') {
          return _json(lists);
        }
        if (req.method == 'POST' && req.url.path == '/api/v1/cinema/lists') {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          final created = {
            'id': 'lst-1',
            'name': body['name'],
            'description': body['description'],
            'createdAtUtc': '2026-11-18T01:00:00Z',
            'updatedAtUtc': '2026-11-18T01:00:00Z',
            'items': <Map<String, dynamic>>[],
          };
          lists.add(created);
          return _json(created, 201);
        }
        if (req.method == 'PUT' && req.url.path == '/api/v1/cinema/lists/lst-1') {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          lists[0]['name'] = body['name'];
          return _json(lists[0]);
        }
        if (req.method == 'POST' && req.url.path == '/api/v1/cinema/lists/lst-1/items') {
          lists[0]['items'] = [
            {
              'id': 'li-1',
              'movieId': 'mov-dune',
              'mediaKind': 'movie',
              'title': 'Dune',
              'year': 2021,
              'position': 0,
              'addedAtUtc': '2026-11-18T01:05:00Z',
            },
          ];
          return _json(lists[0]);
        }
        if (req.method == 'DELETE' && req.url.path == '/api/v1/cinema/lists/lst-1') {
          lists.clear();
          return http.Response('', 204);
        }
        return _json({});
      });

      final service = CinemaService(
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
              cinemaService: service,
              playerConfig: HermesVideoPlayerConfig.hdrSafeDefault(tokens: tokens),
              defaultQuality: VideoQualityPreset.directPlay,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Lists tab and create a new custom list.
      await tester.tap(find.byKey(const Key('cinema-tab-lists')));
      await tester.pumpAndSettle();
      expect(find.textContaining('No custom lists yet'), findsOneWidget);

      await tester.tap(find.text('New list'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ).first,
        'Weekend Sci-Fi',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create list'));
      await tester.pumpAndSettle();
      expect(find.text('Weekend Sci-Fi (0)'), findsOneWidget);

      // Rename the list.
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ).first,
        'All-Time Sci-Fi',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('All-Time Sci-Fi (0)'), findsOneWidget);

      // Watchlist view opens cleanly without extra custom lists badge header clutter.
      await tester.tap(find.byKey(const Key('cinema-tab-watchlist')));
      await tester.pumpAndSettle();
      expect(find.text('Watchlist'), findsAtLeastNWidgets(1));
      expect(find.text('Custom lists (1)'), findsNothing);

      // Open Dune detail page and add it to the custom list.
      await tester.tap(find.byKey(const Key('cinema-tab-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('hero-details-btn')));
      await tester.pumpAndSettle();

      expect(find.byType(CinemaDetailPage), findsOneWidget);
      await tester.tap(find.byKey(const Key('detail-add-list-btn')));
      await tester.pumpAndSettle();
      expect(find.text('Add "Dune" to list'), findsOneWidget);

      await tester.tap(find.text('All-Time Sci-Fi'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // Return to catalog -> Lists tab reflects Dune inside All-Time Sci-Fi (1).
      await tester.tap(find.byKey(const Key('detail-back-btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cinema-tab-lists')));
      await tester.pumpAndSettle();
      expect(find.text('All-Time Sci-Fi (1)'), findsOneWidget);
      expect(find.text('Dune'), findsWidgets);

      // Delete list cleanly.
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No custom lists yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('PR26 Vector Brand Emblem & Subtitle Preview Scene', () {
    testWidgets('HermesMarkIcon renders vector CustomPaint across sizes and SubtitlePreviewBox uses scene asset', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final tokens = HermesThemeTokens.resolve();

      await tester.pumpWidget(
        MaterialApp(
          theme: tokens.toThemeData(),
          home: Column(
            children: [
              HermesMarkIcon(size: 18, color: tokens.text2),
              HermesMarkIcon(size: 36, color: tokens.text),
              Expanded(
                child: PlayerAndThemeSettingsScreen(
                  tokens: tokens,
                  rendererBackend: VideoRendererBackend.openGl,
                  defaultVideoQuality: VideoQualityPreset.directPlay,
                  initialTab: SettingsTabKind.account,
                  onThemeChanged: (_) {},
                  onRendererChanged: (_) {},
                  onDefaultVideoQualityChanged: (_) {},
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(HermesMarkIcon),
          matching: find.byType(CustomPaint),
        ),
        findsWidgets,
      );

      final previewBox = find.byKey(const Key('subtitle-preview-box'));
      await tester.ensureVisible(previewBox);
      await tester.pumpAndSettle();
      expect(previewBox, findsOneWidget);

      final imageFinder = find.descendant(
        of: previewBox,
        matching: find.byType(Image),
      );
      expect(imageFinder, findsOneWidget);
      final imageWidget = tester.widget<Image>(imageFinder);
      expect(
        (imageWidget.image as AssetImage).assetName,
        'assets/images/subtitle_preview_scene.jpg',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('PR26 Keyboard Shortcuts (DualWorldShell & HermesVideoPlayerScreen)', () {
    testWidgets('DualWorldShell triggers search/playback shortcuts and respects text inputs', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final tokens = HermesThemeTokens.resolve();
      var searchCalls = 0;
      var playPauseCalls = 0;
      var muteCalls = 0;
      var nextCalls = 0;
      var prevCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: tokens.toThemeData(),
          home: DualWorldShell(
            username: 'robert',
            isAdmin: true,
            serverName: 'Hermes Home',
            endpointLabel: 'LAN',
            cinemaBuilder: (_) => const Center(
              child: SizedBox(
                width: 300,
                child: TextField(key: Key('shell-search-input')),
              ),
            ),
            musicBuilder: (_) => const SizedBox(),
            miniPlayerBuilder: (_) => const SizedBox(),
            onOpenSearch: () => searchCalls++,
            onTogglePlayPause: () => playPauseCalls++,
            onToggleMute: () => muteCalls++,
            onNextTrack: () => nextCalls++,
            onPreviousTrack: () => prevCalls++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.slash);
      expect(searchCalls, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(playPauseCalls, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      expect(muteCalls, 1);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(searchCalls, 2);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      expect(nextCalls, 1);
      expect(prevCalls, 1);

      // Focus text input: Space and M must NOT hijack typing, while Ctrl+K still triggers search.
      await tester.tap(find.byKey(const Key('shell-search-input')));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      expect(playPauseCalls, 1);
      expect(muteCalls, 1);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(searchCalls, 3);
    });

    testWidgets('HermesVideoPlayerScreen handles Space/K, Arrow/J/L seek, M mute, F fullscreen', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final client = MockClient((req) async {
        if (req.url.path == '/api/v1/auth/stream-tickets') {
          return _json({'ticket': 'tkt-vid'});
        }
        return _json({});
      });
      final service = CinemaService(
        baseUri: Uri.parse('http://localhost:5258'),
        accessToken: 'jwt',
        httpClient: client,
      );
      final tokens = HermesThemeTokens.resolve();
      const source = MediaSourceModel(
        id: 'src-kbd',
        sourceLabel: '1080p',
        container: 'mp4',
        videoCodec: 'h264',
        audioCodec: 'aac',
        width: 1920,
        height: 1080,
        isHdr: false,
        bitrateBps: 8000000,
        durationMs: 120000,
        isAvailable: true,
        streams: [],
      );

      late _StubVideoPlaybackController stubController;
      await tester.pumpWidget(
        MaterialApp(
          theme: tokens.toThemeData(),
          home: HermesVideoPlayerScreen(
            title: 'Interstellar',
            source: source,
            initialQuality: VideoQualityPreset.directPlay,
            config: HermesVideoPlayerConfig.hdrSafeDefault(tokens: tokens),
            cinemaService: service,
            movieId: 'mov-1',
            initialPositionMs: 30000,
            playbackControllerFactory: (_) {
              stubController = _StubVideoPlaybackController();
              return stubController;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      stubController.durationController.add(120000);
      stubController.positionController.add(30000);
      stubController.playingController.add(true);
      await tester.pumpAndSettle();

      // Space pauses; K resumes.
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(stubController.pauseCalls, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.pump();
      expect(stubController.playCalls, 1);

      // Right / L seek forward 10s; Left / J seek backward 10s.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(stubController.seekCalls.last, 40000);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      await tester.pump();
      expect(stubController.seekCalls.last, 50000);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(stubController.seekCalls.last, 40000);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.pump();
      expect(stubController.seekCalls.last, 30000);

      // M toggles mute on the video playback controller.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.pump();
      expect(stubController.lastVolume, 0.0);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.pump();
      expect(stubController.lastVolume, 80.0);

      // F toggles fullscreen mode cleanly.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}
