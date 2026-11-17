import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_client/src/core/theme/hermes_theme_tokens.dart';
import 'package:hermes_client/src/features/admin/admin_dashboard_screen.dart';
import 'package:hermes_client/src/features/admin/admin_models.dart';
import 'package:hermes_client/src/features/admin/admin_service.dart';
import 'package:hermes_client/src/features/cinema/cinema_catalog_screen.dart';
import 'package:hermes_client/src/features/cinema/cinema_models.dart';
import 'package:hermes_client/src/features/cinema/cinema_service.dart';
import 'package:hermes_client/src/features/cinema/hermes_video_player.dart';
import 'package:hermes_client/src/features/music/music_models.dart';
import 'package:hermes_client/src/features/music/music_playback_coordinator.dart';
import 'package:hermes_client/src/features/music/music_service.dart';
import 'package:hermes_client/src/features/music/music_shared_widgets.dart';
import 'package:hermes_client/src/features/music/music_world_screen.dart';
import 'package:hermes_client/src/features/music/now_playing_panel.dart';
import 'package:hermes_client/src/features/music/platform_media_bridge.dart';
import 'package:hermes_client/src/features/settings/player_and_theme_settings_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

class _FakeAudioEngine implements AudioEngineAdapter {
  @override
  Future<void> loadAndPlay(Uri streamUri, SongModel track, int startPositionMs) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(int positionMs) async {}

  @override
  Future<void> stop() async {}
}

void main() {
  group('M5 Search Focus & Input Polish', () {
    testWidgets('Cinema search retains focus while typing multiple characters across hero transition', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final tokens = HermesThemeTokens.resolve(themeId: HermesThemeId.crimson);
      final mockClient = MockClient((req) async {
        if (req.url.path == '/api/v1/cinema/movies') {
          return _json([
            {
              'id': 'mov-1',
              'title': 'Dune',
              'year': 2021,
              'overview': 'Desert planet sci-fi epic.',
              'genres': ['Sci-Fi'],
              'cast': <Map<String, dynamic>>[],
              'sources': [
                {
                  'id': 'src-1',
                  'sourceLabel': '4K HDR',
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
            {
              'id': 'mov-2',
              'title': 'Blade Runner',
              'year': 1982,
              'overview': 'Replicants in neon rain.',
              'genres': ['Sci-Fi'],
              'cast': <Map<String, dynamic>>[],
              'sources': <Map<String, dynamic>>[],
            },
          ]);
        }
        if (req.url.path == '/api/v1/cinema/series') {
          return _json([]);
        }
        return _json([]);
      });

      final service = CinemaService(
        baseUri: Uri.parse('http://localhost:5258'),
        accessToken: 'jwt',
        httpClient: mockClient,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: tokens.toThemeData(),
          home: CinemaCatalogScreen(
            cinemaService: service,
            playerConfig: HermesVideoPlayerConfig.hdrSafeDefault(tokens: tokens),
            defaultQuality: VideoQualityPreset.directPlay,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final searchField = find.byKey(const Key('cinema-search-input'));
      expect(searchField, findsOneWidget);

      await tester.tap(searchField);
      await tester.pump();

      // First character collapses the hero -> field must stay focused!
      tester.testTextInput.enterText('b');
      await tester.pump();
      expect(tester.testTextInput.hasAnyClients, isTrue);
      expect(FocusManager.instance.primaryFocus?.hasFocus, isTrue);

      // Continue typing multi-character query without tapping again
      tester.testTextInput.enterText('blade');
      await tester.pump();
      expect(tester.testTextInput.hasAnyClients, isTrue);
      expect(find.text('Blade Runner'), findsWidgets);
      expect(find.text('Dune'), findsNothing);

      // Clear icon clears text and keeps search input focused
      await tester.tap(find.byKey(const Key('cinema-search-clear')));
      await tester.pump();
      expect(find.text('Dune'), findsWidgets);
      expect(tester.testTextInput.hasAnyClients, isTrue);
    });

    testWidgets('Music search pill strips inner sharp InputDecorationTheme borders on focus', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final tokens = HermesThemeTokens.resolve(themeId: HermesThemeId.crimson);
      final song = {
        'id': 's-1',
        'artistId': 'art-1',
        'artistName': 'M83',
        'albumId': 'alb-1',
        'albumTitle': 'Hurry Up, We\'re Dreaming',
        'title': 'Midnight City',
        'trackNumber': 1,
        'discNumber': 1,
        'durationMs': 243000,
        'codec': 'flac',
        'bitrateBps': 1411000,
        'sampleRateHz': 44100,
        'bitDepth': 16,
        'isLiked': false,
        'isMissing': false,
      };
      final mockClient = MockClient((req) async {
        return switch (req.url.path) {
          '/api/v1/music/songs' => _json([song]),
          '/api/v1/music/albums' => _json([
              {
                'id': 'alb-1',
                'artistId': 'art-1',
                'artistName': 'M83',
                'title': 'Hurry Up, We\'re Dreaming',
                'year': 2011,
                'songCount': 1,
              },
            ]),
          '/api/v1/music/artists' => _json([
              {'id': 'art-1', 'name': 'M83', 'albumCount': 1},
            ]),
          '/api/v1/music/playlists' => _json([]),
          '/api/v1/music/playlists/pl-1' => _json({
              'id': 'pl-1',
              'name': 'Late Night',
              'description': '',
              'tracks': <Map<String, dynamic>>[],
            }),
          _ => _json([]),
        };
      });

      final service = MusicService(
        baseUri: Uri.parse('http://localhost:5258'),
        accessToken: 'jwt',
        httpClient: mockClient,
      );
      final coordinator = MusicPlaybackCoordinator(
        localDeviceId: 'dev-1',
        musicService: service,
        audioEngine: _FakeAudioEngine(),
        mediaBridge: InMemoryPlatformMediaBridge(),
      );
      addTearDown(coordinator.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: tokens.toThemeData(),
          home: Scaffold(
            body: MusicWorldScreen(
              musicService: service,
              coordinator: coordinator,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final musicInput = find.byKey(const Key('music-search-input'));
      expect(musicInput, findsOneWidget);
      await tester.tap(musicInput);
      await tester.pump();

      final tf = tester.widget<TextField>(musicInput);
      final dec = tf.decoration!;
      expect(dec.filled, isFalse);
      expect(dec.border, InputBorder.none);
      expect(dec.enabledBorder, InputBorder.none);
      expect(dec.focusedBorder, InputBorder.none);

      final ctx = tester.element(musicInput);
      final localInputTheme = Theme.of(ctx).inputDecorationTheme;
      expect(localInputTheme.focusedBorder, InputBorder.none);
      expect(localInputTheme.border, InputBorder.none);

      await tester.enterText(musicInput, 'midnight');
      await tester.pump();
      expect(find.text('Midnight City'), findsWidgets);
    });
  });

  group('M5 Libraries 0-Items Bug & Scanning Feedback', () {
    test('enriches missing itemCount from legacy server responses and renders Scanning… cleanly', () async {
      final legacyServer = MockClient((req) async {
        return switch (req.url.path) {
          '/api/v1/admin/libraries' => _json([
              {
                'id': 'lib-mov',
                'name': 'Movies',
                'mediaType': 'Movies',
                'rootPath': '/media/Movies',
                'watchEnabled': true,
                'createdAtUtc': '2026-11-16T08:00:00Z',
                'lastScanCompletedAtUtc': '2026-11-17T08:00:00Z',
                // Deliberately omit itemCount to simulate older API payload
              },
              {
                'id': 'lib-ser',
                'name': 'Series',
                'mediaType': 1,
                'rootPath': '/media/Series',
                'watchEnabled': true,
                'createdAtUtc': '2026-11-16T08:00:00Z',
                'lastScanCompletedAtUtc': '2026-11-17T08:00:00Z',
              },
              {
                'id': 'lib-mus',
                'name': 'Music',
                'mediaType': 2,
                'rootPath': '/media/Music',
                'watchEnabled': true,
                'createdAtUtc': '2026-11-16T08:00:00Z',
                'lastScanCompletedAtUtc': '2026-11-17T08:00:00Z',
              },
            ]),
          '/api/v1/cinema/movies' => _json([
              {'id': 'm1'},
              {'id': 'm2'},
            ]),
          '/api/v1/cinema/series' => _json([
              {'id': 's1'},
            ]),
          '/api/v1/music/songs' => _json([
              {'id': 'a1'},
              {'id': 'a2'},
              {'id': 'a3'},
            ]),
          '/api/v1/music/playlists/pl-1' => _json({
              'id': 'pl-1',
              'name': 'Late Night',
              'description': '',
              'tracks': <Map<String, dynamic>>[],
            }),
          _ => _json([]),
        };
      });

      final service = AdminService(
        baseUri: Uri.parse('http://localhost:5258'),
        accessToken: 'jwt',
        httpClient: legacyServer,
      );
      final libs = await service.listLibraries();
      expect(libs[0].contentsLabel, '2 movies');
      expect(libs[1].contentsLabel, '1 series');
      expect(libs[2].contentsLabel, '3 tracks');

      final scanningModel = LibraryRootModel.fromJson({
        'id': 'lib-scan',
        'name': 'Movies',
        'mediaType': 0,
        'rootPath': '/media/Movies',
        'watchEnabled': true,
        'createdAtUtc': '2026-11-17T08:00:00Z',
        'itemCount': 0,
        'isScanning': true,
        'scanProcessedFiles': 2,
        'scanTotalFiles': 10,
      });
      expect(scanningModel.contentsLabel, 'Scanning…');

      final omittedFailedFallback = LibraryRootModel.fromJson({
        'id': 'lib-old',
        'name': 'Music',
        'mediaType': 2,
        'rootPath': '/media/Music',
        'watchEnabled': true,
        'createdAtUtc': '2026-11-17T08:00:00Z',
        'lastScanCompletedAtUtc': '2026-11-17T09:00:00Z',
      });
      expect(omittedFailedFallback.contentsLabel, 'Scanned');
    });

    testWidgets('Mobile Libraries row shows live processed file count during scan', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final tokens = HermesThemeTokens.resolve(themeId: HermesThemeId.crimson);
      final client = MockClient((req) async {
        if (req.url.path == '/api/v1/admin/libraries') {
          return _json([
            {
              'id': 'lib-1',
              'name': 'Cinema',
              'mediaType': 0,
              'rootPath': '/media/Movies',
              'watchEnabled': true,
              'createdAtUtc': '2026-11-17T08:00:00Z',
              'itemCount': 0,
              'isScanning': true,
              'scanProcessedFiles': 3,
              'scanTotalFiles': 10,
            },
          ]);
        }
        return _json([]);
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: tokens.toThemeData(),
          home: AdminDashboardScreen(
            adminService: AdminService(
              baseUri: Uri.parse('http://localhost:5258'),
              accessToken: 'jwt',
              httpClient: client,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Scanning 3 / 10…'), findsOneWidget);
    });
  });

  group('M5 Music Right-Click Context Menus & Queue Fixes', () {
    Future<void> secondaryClick(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(
        finder,
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('opens right-click context menu on track rows and collection cards to queue songs', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 860));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final tokens = HermesThemeTokens.resolve(themeId: HermesThemeId.midnight);
      final songs = [
        {
          'id': 's-1',
          'artistId': 'art-1',
          'artistName': 'M83',
          'albumId': 'alb-1',
          'albumTitle': 'Midnight City Album',
          'title': 'Midnight City',
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
        {
          'id': 's-2',
          'artistId': 'art-1',
          'artistName': 'M83',
          'albumId': 'alb-1',
          'albumTitle': 'Midnight City Album',
          'title': 'Wait',
          'trackNumber': 2,
          'discNumber': 1,
          'durationMs': 340000,
          'codec': 'flac',
          'bitrateBps': 1411000,
          'sampleRateHz': 44100,
          'bitDepth': 16,
          'isLiked': true,
          'isMissing': false,
        },
      ];
      final mockClient = MockClient((req) async {
        return switch (req.url.path) {
          '/api/v1/music/songs' => _json(songs),
          '/api/v1/music/albums' => _json([
              {
                'id': 'alb-1',
                'artistId': 'art-1',
                'artistName': 'M83',
                'title': 'Midnight City Album',
                'year': 2011,
                'songCount': 2,
              },
            ]),
          '/api/v1/music/artists' => _json([
              {'id': 'art-1', 'name': 'M83', 'albumCount': 1},
            ]),
          '/api/v1/music/playlists' => _json([
              {
                'id': 'pl-1',
                'name': 'Late Night',
                'description': '',
                'trackCount': 0,
                'createdAtUtc': '2026-11-17T00:00:00Z',
                'updatedAtUtc': '2026-11-17T00:00:00Z',
              },
            ]),
          '/api/v1/music/playlists/pl-1' => _json({
              'id': 'pl-1',
              'name': 'Late Night',
              'description': '',
              'tracks': <Map<String, dynamic>>[],
            }),
          _ => _json([]),
        };
      });

      final service = MusicService(
        baseUri: Uri.parse('http://localhost:5258'),
        accessToken: 'jwt',
        httpClient: mockClient,
      );
      final coordinator = MusicPlaybackCoordinator(
        localDeviceId: 'dev-1',
        musicService: service,
        audioEngine: _FakeAudioEngine(),
        mediaBridge: InMemoryPlatformMediaBridge(),
      );
      addTearDown(coordinator.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: tokens.toThemeData(),
          home: Scaffold(
            body: MusicWorldScreen(
              musicService: service,
              coordinator: coordinator,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Right-click a track row
      final trackTitle = find.text('Midnight City').first;
      await tester.ensureVisible(trackTitle);
      await secondaryClick(tester, trackTitle);
      expect(find.text('Play now'), findsOneWidget);
      expect(find.text('Add to queue'), findsOneWidget);
      expect(find.text('Add to Late Night'), findsOneWidget);

      await tester.tap(find.text('Add to queue'));
      await tester.pumpAndSettle();
      expect(coordinator.upNext.map((s) => s.id), ['s-1']);

      // 2. Right-click an Album row in sidebar
      final sidebarAlbum = find.text('Midnight City Album').first;
      await secondaryClick(tester, sidebarAlbum);
      expect(find.text('Open album'), findsOneWidget);
      await tester.tap(find.text('Add to queue'));
      await tester.pumpAndSettle();
      expect(coordinator.upNext.length, 3);

      // 3. Right-click an Album browse card in Home grid
      await secondaryClick(tester, find.byType(MusicBrowseCard).first);
      expect(find.text('Open album'), findsOneWidget);
      await tester.tap(find.text('Add to queue'));
      await tester.pumpAndSettle();
      expect(coordinator.upNext.length, 5);

      // 4. Right-click a Playlist shortcut tile -> shows Rename & Delete actions
      await secondaryClick(tester, find.text('Late Night').last);
      expect(find.text('Open playlist'), findsOneWidget);
      expect(find.text('Rename playlist'), findsOneWidget);
      expect(find.text('Delete playlist'), findsOneWidget);
      await tester.tap(find.text('Open playlist'));
      await tester.pumpAndSettle();
      expect(find.text('Playlist'), findsWidgets);
    });

    testWidgets('NowPlayingPanel plays exact tapped Next-in-queue item and supports right-click removal', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 860));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final tokens = HermesThemeTokens.resolve(themeId: HermesThemeId.crimson);
      final service = MusicService(
        baseUri: Uri.parse('http://localhost:5258'),
        accessToken: 'jwt',
        httpClient: MockClient((req) async {
          if (req.url.path == '/api/v1/auth/stream-tickets') {
            return _json({
              'ticket': 'tkt-1',
              'expiresAtUtc': '2026-11-18T00:00:00Z',
            });
          }
          if (req.url.path.endsWith('/lyrics')) {
            return _json({
              'songId': 's-1',
              'isSynced': false,
              'source': 'none',
              'lines': <Map<String, dynamic>>[],
            });
          }
          return _json([]);
        }),
      );
      final coordinator = MusicPlaybackCoordinator(
        localDeviceId: 'dev-1',
        musicService: service,
        audioEngine: _FakeAudioEngine(),
        mediaBridge: InMemoryPlatformMediaBridge(),
      );
      addTearDown(coordinator.dispose);

      const s1 = SongModel(
        id: 's-1',
        artistId: 'art-1',
        artistName: 'Artist',
        albumId: 'alb-1',
        albumTitle: 'Album',
        title: 'First Song',
        trackNumber: 1,
        discNumber: 1,
        durationMs: 180000,
        codec: 'flac',
        bitrateBps: 1411000,
        sampleRateHz: 44100,
        bitDepth: 16,
        isLiked: false,
        isMissing: false,
      );
      const s2 = SongModel(
        id: 's-2',
        artistId: 'art-1',
        artistName: 'Artist',
        albumId: 'alb-1',
        albumTitle: 'Album',
        title: 'Second Queued',
        trackNumber: 2,
        discNumber: 1,
        durationMs: 190000,
        codec: 'flac',
        bitrateBps: 1411000,
        sampleRateHz: 44100,
        bitDepth: 16,
        isLiked: false,
        isMissing: false,
      );
      const s3 = SongModel(
        id: 's-3',
        artistId: 'art-1',
        artistName: 'Artist',
        albumId: 'alb-1',
        albumTitle: 'Album',
        title: 'Third Queued',
        trackNumber: 3,
        discNumber: 1,
        durationMs: 200000,
        codec: 'flac',
        bitrateBps: 1411000,
        sampleRateHz: 44100,
        bitDepth: 16,
        isLiked: false,
        isMissing: false,
      );

      await coordinator.startQueue([s1], 0);
      coordinator.addToQueue(s2);
      coordinator.addToQueue(s3);

      await tester.pumpWidget(
        MaterialApp(
          theme: tokens.toThemeData(),
          home: Scaffold(
            body: AnimatedBuilder(
              animation: coordinator,
              builder: (_, _) => NowPlayingPanel(
                coordinator: coordinator,
                musicService: service,
                localDeviceId: 'dev-1',
                onClose: () {},
                onOpenDevices: () {},
                onNavigate: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Secondary-click Second Queued -> remove from queue
      await secondaryClick(tester, find.text('Second Queued'));
      expect(find.text('Remove from queue'), findsOneWidget);
      await tester.tap(find.text('Remove from queue'));
      await tester.pumpAndSettle();
      expect(coordinator.upNext.map((s) => s.id), ['s-3']);

      // Re-add s2 and tap Third Queued? Wait: verify tapping s2 directly when s3 is first plays s2!
      coordinator.addToQueue(s2);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Second Queued'));
      await tester.pumpAndSettle();
      expect(coordinator.currentSong?.id, 's-2');
    });
  });

  group('M5 Settings Dialog Disposal & Error Cleanup', () {
    testWidgets('Change password dialog formats error cleanly and disposes controllers on cancel', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final tokens = HermesThemeTokens.resolve(themeId: HermesThemeId.crimson);
      await tester.pumpWidget(
        MaterialApp(
          theme: tokens.toThemeData(),
          home: PlayerAndThemeSettingsScreen(
            tokens: tokens,
            rendererBackend: VideoRendererBackend.openGl,
            defaultVideoQuality: VideoQualityPreset.directPlay,
            initialTab: SettingsTabKind.account,
            onThemeChanged: (_) {},
            onRendererChanged: (_) {},
            onDefaultVideoQualityChanged: (_) {},
            onChangePassword: (_, _) async {
              throw Exception('Current password mismatch');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Change password'));
      await tester.tap(find.text('Change password'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'wrongpass');
      await tester.enterText(find.byType(TextField).last, 'NewValidPass123');
      await tester.tap(find.text('Save password'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Current password mismatch'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Save password'), findsNothing);
    });
  });
}
