import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_client/src/core/settings/hermes_preferences.dart';
import 'package:hermes_client/src/core/theme/hermes_theme_tokens.dart';
import 'package:hermes_client/src/features/cinema/cinema_catalog_screen.dart';
import 'package:hermes_client/src/features/cinema/cinema_detail_page.dart';
import 'package:hermes_client/src/features/cinema/cinema_models.dart';
import 'package:hermes_client/src/features/cinema/cinema_service.dart';
import 'package:hermes_client/src/features/cinema/hermes_video_player.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('Cinema v4 Models, ResumePoint & Service Endpoints', () {
    test('deserializes rich metadata and computes series resumePoint modes + nextEpisodeAfter', () {
      final now = DateTime.now().toUtc();
      final seriesJson = {
        'id': 'ser-dark',
        'title': 'Dark',
        'year': 2017,
        'overview': 'Missing children set off a four-family mystery.',
        'tmdbId': 70523,
        'addedAtUtc': now.subtract(const Duration(days: 2)).toIso8601String(),
        'rating': 8.7,
        'genres': ['Sci-Fi', 'Mystery', 'Drama'],
        'isInWatchlist': true,
        'cast': [
          {'name': 'Louis Hofmann', 'role': 'Jonas Kahnwald'},
        ],
        'seasons': [
          {
            'id': 's1',
            'seasonNumber': 1,
            'title': 'Season 1',
            'expectedEpisodeCount': 10,
            'episodes': [
              {
                'id': 'e1',
                'episodeNumber': 1,
                'title': 'Secrets',
                'watchProgress': {
                  'positionMs': 3_000_000,
                  'durationMs': 3_000_000,
                  'isWatched': true,
                  'updatedAtUtc': now.toIso8601String(),
                },
                'sources': [
                  {
                    'id': 'src-1',
                    'sourceLabel': '1080p',
                    'container': 'mkv',
                    'videoCodec': 'h264',
                    'audioCodec': 'eac3',
                    'width': 1920,
                    'height': 1080,
                    'isHdr': false,
                    'bitrateBps': 8_000_000,
                    'durationMs': 3_000_000,
                    'isAvailable': true,
                    'streams': [],
                  },
                ],
              },
              {
                'id': 'e2',
                'episodeNumber': 2,
                'title': 'Lies',
                'sources': [
                  {
                    'id': 'src-2',
                    'sourceLabel': '1080p',
                    'container': 'mkv',
                    'videoCodec': 'h264',
                    'audioCodec': 'eac3',
                    'width': 1920,
                    'height': 1080,
                    'isHdr': false,
                    'bitrateBps': 8_000_000,
                    'durationMs': 2_700_000,
                    'isAvailable': true,
                    'streams': [],
                  },
                ],
              },
            ],
          },
          {
            'id': 's2',
            'seasonNumber': 2,
            'title': 'Season 2',
            'expectedEpisodeCount': 8,
            'episodes': [
              {
                'id': 'e3',
                'episodeNumber': 1,
                'title': 'Beginnings and Endings',
                'sources': [],
              },
            ],
          },
        ],
      };

      final series = TvSeriesSummary.fromJson(seriesJson);
      expect(series.rating, 8.7);
      expect(series.genres, ['Sci-Fi', 'Mystery', 'Drama']);
      expect(series.isInWatchlist, isTrue);
      expect(series.isNew, isTrue);
      expect(series.isPartial, isTrue);
      expect(series.availableEpisodeCount, 3);
      expect(series.expectedTotalEpisodeCount, 18);
      expect(series.cast.single.name, 'Louis Hofmann');

      // E1 watched -> Up next is S1 E2
      final nextResume = series.resumePoint!;
      expect(nextResume.mode, CinemaResumeMode.next);
      expect(nextResume.playLabel, 'Play S1 E2');
      expect(nextResume.episodeEntry!.episode.title, 'Lies');

      // Next across season boundary: S1 E2 -> S2 E1
      final crossed = series.nextEpisodeAfter(1, 2);
      expect(crossed?.code, 'S2 E1');
      expect(crossed?.episode.title, 'Beginnings and Endings');
    });

    test('CinemaService calls PUT /watchlist and PUT /series/{id}/watched and handles failures', () async {
      final calls = <(String, String, Map<String, dynamic>)>[];
      var fail = false;
      final client = MockClient((req) async {
        if (fail) return http.Response('err', 500);
        final decoded = req.body.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(req.body) as Map<String, dynamic>;
        calls.add((req.method, req.url.path, decoded));
        if (req.url.path == '/api/v1/cinema/watchlist') {
          return http.Response(
            jsonEncode({'inWatchlist': decoded['inWatchlist']}),
            200,
          );
        }
        return http.Response(jsonEncode({'watched': decoded['watched']}), 200);
      });

      final service = CinemaService(
        baseUri: Uri.parse('http://localhost:5258'),
        accessToken: 'jwt',
        httpClient: client,
      );

      final added = await service.setWatchlist(movieId: 'm1', inWatchlist: true);
      expect(added, isTrue);
      await service.setSeriesWatched(seriesId: 's1', watched: true);

      expect(calls[0].$1, 'PUT');
      expect(calls[0].$2, '/api/v1/cinema/watchlist');
      expect(calls[0].$3['movieId'], 'm1');
      expect(calls[1].$2, '/api/v1/cinema/series/s1/watched');
      expect(calls[1].$3['watched'], isTrue);

      fail = true;
      await expectLater(
        () => service.setWatchlist(movieId: 'm1', inWatchlist: false),
        throwsA(isA<CinemaApiException>()),
      );
      await expectLater(
        () => service.setSeriesWatched(seriesId: 's1', watched: false),
        throwsA(isA<CinemaApiException>()),
      );
    });
  });

  group('Cinema Nuvio Home, Dedicated Detail Page, Watchlist & Video Player', () {
    testWidgets('supports Hero Details/Watchlist buttons, Dedicated Detail Page with Nuvio toggles, Watchlist view, and mobile responsive check', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1280, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      bool? watchlistUpdatedTo;
      bool? seriesWatchedUpdatedTo;

      final client = MockClient((req) async {
        if (req.url.path == '/api/v1/cinema/watchlist' && req.method == 'PUT') {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          watchlistUpdatedTo = body['inWatchlist'] as bool;
          return http.Response(
            jsonEncode({'inWatchlist': watchlistUpdatedTo}),
            200,
          );
        }
        if (req.url.path == '/api/v1/cinema/series/ser-dark/watched' &&
            req.method == 'PUT') {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          seriesWatchedUpdatedTo = body['watched'] as bool;
          return http.Response(
            jsonEncode({'seriesId': 'ser-dark', 'watched': seriesWatchedUpdatedTo, 'episodesUpdated': 1}),
            200,
          );
        }
        if (req.url.path == '/api/v1/cinema/movies') {
          return http.Response(
            jsonEncode([
              {
                'id': 'mov-blade',
                'title': 'Blade Runner 2049',
                'year': 2017,
                'overview': 'Young Blade Runner K unearths a buried secret.',
                'rating': 8.0,
                'genres': ['Sci-Fi', 'Mystery'],
                'runtimeMinutes': 164,
                'isInWatchlist': false,
                'sources': [
                  {
                    'id': 'src-4k',
                    'sourceLabel': '2160p HDR Remux',
                    'container': 'mkv',
                    'videoCodec': 'hevc',
                    'audioCodec': 'truehd',
                    'width': 3840,
                    'height': 2160,
                    'isHdr': true,
                    'bitrateBps': 42_000_000,
                    'durationMs': 9_840_000,
                    'isAvailable': true,
                    'streams': [],
                  },
                ],
              },
            ]),
            200,
          );
        }
        if (req.url.path == '/api/v1/cinema/series') {
          return http.Response(
            jsonEncode([
              {
                'id': 'ser-dark',
                'title': 'Dark',
                'year': 2017,
                'overview': 'Four families uncover a sinister time cycle in Winden.',
                'rating': 8.7,
                'genres': ['Sci-Fi', 'Mystery'],
                'isInWatchlist': false,
                'cast': [
                  {'name': 'Louis Hofmann', 'role': 'Jonas Kahnwald'},
                ],
                'seasons': [
                  {
                    'id': 's1',
                    'seasonNumber': 1,
                    'title': 'Season 1',
                    'expectedEpisodeCount': 10,
                    'episodes': [
                      {
                        'id': 'ep-1',
                        'episodeNumber': 1,
                        'title': 'Secrets',
                        'overview': 'A missing boy exposes double lives.',
                        'watchProgress': {
                          'positionMs': 600_000,
                          'durationMs': 3_000_000,
                          'isWatched': false,
                          'updatedAtUtc': '2026-11-17T09:00:00Z',
                        },
                        'sources': [
                          {
                            'id': 'src-ep1-4k',
                            'sourceLabel': '2160p HDR',
                            'container': 'mkv',
                            'videoCodec': 'hevc',
                            'audioCodec': 'eac3',
                            'width': 3840,
                            'height': 2160,
                            'isHdr': true,
                            'bitrateBps': 24_000_000,
                            'durationMs': 3_000_000,
                            'isAvailable': true,
                            'streams': [],
                          },
                          {
                            'id': 'src-ep1-1080',
                            'sourceLabel': '1080p WebDL',
                            'container': 'mp4',
                            'videoCodec': 'h264',
                            'audioCodec': 'aac',
                            'width': 1920,
                            'height': 1080,
                            'isHdr': false,
                            'bitrateBps': 8_000_000,
                            'durationMs': 3_000_000,
                            'isAvailable': true,
                            'streams': [],
                          },
                        ],
                      },
                    ],
                  },
                ],
              },
            ]),
            200,
          );
        }
        return http.Response('[]', 200);
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
              accountPreferences: const HermesAccountPreferences(
                matchTitleColors: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Dark has in-progress watchProgress, so Hero spotlights Dark with Resume S1 E1 + Watchlist + Details
      expect(find.text('Resume S1 E1'), findsOneWidget);
      expect(find.byKey(const Key('hero-watchlist-btn')), findsOneWidget);
      expect(find.byKey(const Key('hero-details-btn')), findsOneWidget);

      // Tap Details -> opens Dedicated CinemaDetailPage (NO BottomSheet!)
      await tester.tap(find.byKey(const Key('hero-details-btn')));
      await tester.pumpAndSettle();

      expect(find.byType(CinemaDetailPage), findsOneWidget);
      expect(find.text('9 episodes aren\'t on the server'), findsOneWidget);

      // Toggle Nuvio Bookmark button -> adds Dark to Watchlist
      await tester.tap(find.byKey(const Key('detail-bookmark-btn')));
      await tester.pumpAndSettle();
      expect(watchlistUpdatedTo, isTrue);

      // Toggle Nuvio Mark-as-watched button -> marks Dark series watched
      await tester.tap(find.byKey(const Key('detail-watched-btn')));
      await tester.pumpAndSettle();
      expect(seriesWatchedUpdatedTo, isTrue);

      // Multi-source selector on Detail page updates Details table dynamically
      await tester.tap(find.text('2160p HDR (MKV)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1080p WebDL (MP4)').last);
      await tester.pumpAndSettle();

      // Scroll down to verify Cast, More like this, and updated Details container
      await tester.scrollUntilVisible(
        find.text('Louis Hofmann'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Louis Hofmann'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('More like this'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('More like this'), findsOneWidget);
      expect(find.text('Blade Runner 2049'), findsWidgets);

      await tester.scrollUntilVisible(
        find.text('MP4'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('MP4'), findsOneWidget);

      // Go back -> switch to dedicated Watchlist tab -> Dark is saved!
      await tester.scrollUntilVisible(
        find.byKey(const Key('detail-back-btn')),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byKey(const Key('detail-back-btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('detail-back-btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cinema-tab-watchlist')));
      await tester.pumpAndSettle();

      expect(find.text('1 show'), findsOneWidget);
      expect(find.text('Dark'), findsWidgets);

      // Mobile layout verification (400x800) with zero overflow
      tester.view.physicalSize = const Size(400, 800);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('HermesVideoPlayerScreen applies subtitle Size/Box and renders Up Next 20s countdown', (
      tester,
    ) async {
      var playedNext = false;
      final client = MockClient((req) async {
        if (req.url.path == '/api/v1/auth/stream-tickets') {
          return http.Response(jsonEncode({'ticket': 'tkt-next'}), 200);
        }
        if (req.url.path == '/api/v1/cinema/progress') {
          return http.Response(
            jsonEncode({
              'positionMs': 108_000,
              'durationMs': 120_000,
              'isWatched': false,
              'updatedAtUtc': '2026-11-17T10:00:00Z',
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      final service = CinemaService(
        baseUri: Uri.parse('http://localhost:5258'),
        accessToken: 'jwt',
        httpClient: client,
      );
      final tokens = HermesThemeTokens.resolve();
      const source = MediaSourceModel(
        id: 'src-ep1',
        sourceLabel: '1080p',
        container: 'mkv',
        videoCodec: 'hevc',
        audioCodec: 'eac3',
        width: 1920,
        height: 1080,
        isHdr: false,
        bitrateBps: 8_000_000,
        durationMs: 120_000,
        isAvailable: true,
        streams: [
          MediaStreamModel(
            streamIndex: 2,
            kind: 2,
            codec: 'subrip',
            language: 'eng',
            title: 'English',
            isDefault: true,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: tokens.toThemeData(),
          home: HermesVideoPlayerScreen(
            title: 'Dark',
            subtitleLabel: 'S1 E1 · Secrets',
            source: source,
            initialQuality: VideoQualityPreset.directPlay,
            config: HermesVideoPlayerConfig.hdrSafeDefault(tokens: tokens),
            cinemaService: service,
            episodeId: 'ep-1',
            initialPositionMs: 108_000, // 12s remaining -> shows Up Next!
            accountPreferences: const HermesAccountPreferences(
              autoplayNextEpisode: true,
              subtitleSize: SubtitleSizePreset.xl,
              subtitleBackground: SubtitleBackgroundStyle.box,
            ),
            nextEpisodeCode: 'S1 E2',
            nextEpisodeTitle: 'Lies',
            onPlayNextEpisode: () => playedNext = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('vp-upnext-card')), findsOneWidget);
      expect(find.text('Next episode in 12s'), findsOneWidget);
      expect(find.text('S1 E2 · Lies'), findsOneWidget);

      await tester.tap(find.text('Play now'));
      await tester.pump();
      expect(playedNext, isTrue);

      await tester.tap(find.text('Watch credits'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vp-upnext-card')), findsNothing);
    });
  });
}
