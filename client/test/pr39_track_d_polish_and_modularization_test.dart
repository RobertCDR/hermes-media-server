import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_client/src/core/storage/search_history_store.dart';
import 'package:hermes_client/src/core/theme/hermes_theme_tokens.dart';
import 'package:hermes_client/src/core/widgets/hermes_horizontal_shelf.dart';
import 'package:hermes_client/src/core/widgets/hermes_marquee_text.dart';
import 'package:hermes_client/src/features/cinema/cinema_catalog_screen.dart';
import 'package:hermes_client/src/features/cinema/cinema_detail_page.dart';
import 'package:hermes_client/src/features/cinema/cinema_models.dart';
import 'package:hermes_client/src/features/cinema/cinema_service.dart';
import 'package:hermes_client/src/features/cinema/cinema_shared_widgets.dart';
import 'package:hermes_client/src/features/cinema/hermes_video_player.dart';
import 'package:hermes_client/src/features/music/music_models.dart';
import 'package:hermes_client/src/features/shell/dual_world_shell.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers/hermes_test_fakes.dart';

void main() {
  group('Track D Shared Test Helpers & Models', () {
    test('AudioQualityPolicy implements value equality and hashCode', () {
      const a = AudioQualityPolicy(
        wifiPreset: AudioQualityPreset.lossless,
        cellularPreset: AudioQualityPreset.high160,
      );
      const b = AudioQualityPolicy(
        wifiPreset: AudioQualityPreset.lossless,
        cellularPreset: AudioQualityPreset.high160,
      );
      const c = AudioQualityPolicy(
        wifiPreset: AudioQualityPreset.veryHigh320,
        cellularPreset: AudioQualityPreset.high160,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('TvSeriesSummary.resumePoint selects most recently updated in-progress episode', () {
      final show = TvSeriesSummary(
        id: 'ser-1',
        title: 'Severance',
        overview: 'Lumon',
        isInWatchlist: false,
        seasons: [
          TvSeasonModel(
            id: 'sn-1',
            seasonNumber: 1,
            title: 'Season 1',
            episodes: [
              EpisodeSummary(
                id: 'ep-1',
                episodeNumber: 1,
                title: 'Good News',
                overview: '',
                sources: const [],
                watchProgress: WatchProgressModel(
                  positionMs: 120000,
                  durationMs: 3000000,
                  isWatched: false,
                  updatedAtUtc: DateTime.utc(2026, 11, 20, 10, 0),
                ),
              ),
              EpisodeSummary(
                id: 'ep-2',
                episodeNumber: 2,
                title: 'Half Loop',
                overview: '',
                sources: const [],
                watchProgress: WatchProgressModel(
                  positionMs: 350000,
                  durationMs: 3000000,
                  isWatched: false,
                  updatedAtUtc: DateTime.utc(2026, 11, 22, 18, 0),
                ),
              ),
            ],
          ),
        ],
      );

      final resume = show.resumePoint;
      expect(resume, isNotNull);
      expect(resume!.episodeEntry?.episode.id, 'ep-2');
      expect(resume.mode, CinemaResumeMode.resume);
    });

    test('SpyAudioEngine & FakeWebSocketChannel smoke cleanly', () async {
      final engine = SpyAudioEngine();
      final channel = FakeWebSocketChannel();
      await engine.warmUp();
      expect(engine.warmUpCalls, 1);
      channel.sink.add('ping');
      expect(channel.sentMessages, ['ping']);
      await engine.dispose();
      await channel.dispose();
    });
  });

  group('Track D UI Polish: DualWorldShell, Shelf & Marquee', () {
    testWidgets(
      'DualWorldShell handles ?, Escape overlay dismissal, and single onOpenSettings call',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        var shortcutOpens = 0;
        var settingsOpens = 0;
        var overlayOpen = true;
        var dismissCalls = 0;

        await tester.pumpWidget(
          MaterialApp(
            theme: HermesThemeTokens.resolve().toThemeData(),
            home: DualWorldShell(
              username: 'admin',
              isAdmin: true,
              cinemaBuilder: (_) => const Center(child: Text('Cinema Body')),
              musicBuilder: (_) => const Center(child: Text('Music Body')),
              onOpenShortcuts: () => shortcutOpens++,
              onOpenSettings: () => settingsOpens++,
              onDismissOverlay: () {
                dismissCalls++;
                if (!overlayOpen) return false;
                overlayOpen = false;
                return true;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.slash);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        expect(shortcutOpens, 1);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(dismissCalls, 1);
        expect(overlayOpen, isFalse);

        // Open account popover via rail avatar and dismiss with Escape.
        await tester.tap(find.byKey(const Key('rail-avatar-button')));
        await tester.pumpAndSettle();
        expect(find.textContaining('admin'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.textContaining('admin'), findsNothing);

        // Tap Settings in rail -> settingsBuilder is null so onOpenSettings fires ONCE.
        await tester.tap(find.text('Settings').first);
        await tester.pump();
        expect(settingsOpens, 1);
      },
    );

    testWidgets(
      'HermesHorizontalShelf Shift+Wheel claims pointer signal and leaves parent vertical scroll untouched',
      (tester) async {
        final verticalController = ScrollController();
        addTearDown(verticalController.dispose);

        await tester.pumpWidget(
          MaterialApp(
            theme: HermesThemeTokens.resolve().toThemeData(),
            home: Scaffold(
              body: SingleChildScrollView(
                controller: verticalController,
                child: Column(
                  children: [
                    HermesHorizontalShelf(
                      height: 180,
                      itemCount: 20,
                      itemBuilder: (_, i) => SizedBox(
                        width: 140,
                        child: Text('Item $i'),
                      ),
                    ),
                    const SizedBox(height: 1200),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final shelfCenter = tester.getCenter(find.byType(HermesHorizontalShelf));
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        final pointer = TestPointer(1, PointerDeviceKind.mouse);
        await tester.sendEventToBinding(pointer.hover(shelfCenter));
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();

        expect(verticalController.offset, 0.0);
        final scrollable = tester.widget<ListView>(
          find.descendant(
            of: find.byType(HermesHorizontalShelf),
            matching: find.byType(ListView),
          ),
        );
        expect(scrollable.controller?.offset, greaterThan(0.0));
      },
    );

    testWidgets(
      'HermesMarqueeText restarts cleanly after toggling MediaQuery disableAnimations',
      (tester) async {
        Widget buildSubject({required bool disableAnimations}) {
          return MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: disableAnimations),
              child: const Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 80,
                    child: HermesMarqueeText(
                      'Very Long Song Title That Exceeds Eighty Pixels',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        await tester.pumpWidget(buildSubject(disableAnimations: true));
        await tester.pump(const Duration(milliseconds: 50));

        await tester.pumpWidget(buildSubject(disableAnimations: false));
        await tester.pump(const Duration(milliseconds: 1700));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Track D CinemaCatalogScreen search isolation, rollback & navigation controller', () {
    testWidgets(
      'keeps mobile Library unfiltered by Search query, rolls back watchlist failure, and opens pending movie via CinemaNavigationController',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(412, 860));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        var watchlistCalls = 0;
        final mockHttp = MockClient((req) async {
          if (req.url.path == '/api/v1/cinema/movies') {
            return http.Response(
              jsonEncode([
                {
                  'id': 'mov-dune',
                  'title': 'Dune',
                  'year': 2021,
                  'overview': 'Arrakis',
                  'genres': ['Sci-Fi'],
                  'isInWatchlist': true,
                  'cast': <Map<String, dynamic>>[],
                  'sources': <Map<String, dynamic>>[],
                },
                {
                  'id': 'mov-heat',
                  'title': 'Heat',
                  'year': 1995,
                  'overview': 'Heist',
                  'genres': ['Crime'],
                  'isInWatchlist': false,
                  'cast': <Map<String, dynamic>>[],
                  'sources': <Map<String, dynamic>>[],
                },
              ]),
              200,
            );
          }
          if (req.url.path == '/api/v1/cinema/watchlist') {
            watchlistCalls++;
            return http.Response('{"error":"server_error"}', 500);
          }
          return http.Response('[]', 200);
        });

        final cinemaService = CinemaService(
          baseUri: Uri.parse('http://localhost:5258'),
          accessToken: 'jwt',
          httpClient: mockHttp,
        );
        final nav = CinemaNavigationController();
        addTearDown(nav.dispose);

        await tester.pumpWidget(
          MaterialApp(
            theme: HermesThemeTokens.resolve().toThemeData(),
            home: Scaffold(
              body: CinemaCatalogScreen(
                cinemaService: cinemaService,
                playerConfig: HermesVideoPlayerConfig.hdrSafeDefault(
                  tokens: HermesThemeTokens.resolve(),
                ),
                defaultQuality: VideoQualityPreset.directPlay,
                navigationController: nav,
                searchHistoryStore: InMemorySearchHistoryStore(),
                externalMobileNav: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Search tab query 'Heat' should NOT hide Watchlist item 'Dune' on Library tab.
        nav.selectMobileTab(CinemaMobileTab.search);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'Heat');
        await tester.pumpAndSettle();

        nav.selectMobileTab(CinemaMobileTab.library);
        await tester.pumpAndSettle();
        expect(find.byType(CinemaPosterCard), findsOneWidget);
        expect(find.text('Dune'), findsWidgets);
        expect(find.text('Heat'), findsNothing);

        // Open mov-heat via CinemaNavigationController -> renders CinemaDetailPage.
        nav.openMovie('mov-heat');
        await tester.pumpAndSettle();
        expect(find.byType(CinemaDetailPage), findsOneWidget);
        expect(find.text('Heat'), findsWidgets);

        // Watchlist mutation error rolls back cleanly on Dune in Library Watchlist.
        nav.selectMobileTab(CinemaMobileTab.library);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('poster-bookmark-mov-dune')));
        await tester.pumpAndSettle();
        expect(watchlistCalls, 1);
        // Rolled back: 'Dune' stays in Watchlist (not removed into empty state).
        expect(find.byType(CinemaPosterCard), findsOneWidget);
        expect(find.text('Dune'), findsWidgets);
      },
    );
  });
}
