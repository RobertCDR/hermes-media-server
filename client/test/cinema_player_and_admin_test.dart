import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_client/src/core/theme/hermes_theme_tokens.dart';
import 'package:hermes_client/src/features/admin/admin_service.dart';
import 'package:hermes_client/src/features/admin/admin_dashboard_screen.dart';
import 'package:hermes_client/src/features/cinema/cinema_models.dart';
import 'package:hermes_client/src/features/cinema/cinema_service.dart';
import 'package:hermes_client/src/features/cinema/hermes_video_player.dart';
import 'package:hermes_client/src/features/cinema/source_selector_card.dart';
import 'package:hermes_client/src/features/settings/player_and_theme_settings_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('CinemaService & VideoQualityPreset', () {
    test('builds Direct Play, HLS quality, and WebVTT subtitle URLs cleanly', () {
      final service = CinemaService(
        baseUri: Uri.parse('https://hermes.tailnet.ts.net'),
        accessToken: 'jwt-1',
        httpClient: MockClient((_) async => http.Response('[]', 200)),
      );

      final direct = service.buildVideoStreamUri(
        mediaSourceId: 'src-1',
        ticket: 'tkt+abc',
        quality: VideoQualityPreset.directPlay,
      );
      expect(
        direct.toString(),
        'https://hermes.tailnet.ts.net/api/v1/streams/src-1/direct?ticket=tkt%2Babc',
      );

      final hls1080 = service.buildVideoStreamUri(
        mediaSourceId: 'src-1',
        ticket: 'tkt',
        quality: VideoQualityPreset.p1080,
        audioStreamIndex: 2,
      );
      expect(
        hls1080.toString(),
        'https://hermes.tailnet.ts.net/api/v1/streams/src-1/video/master.m3u8?quality=1080p&ticket=tkt&audioStreamIndex=2',
      );

      final vtt = service.buildSubtitleVttUri(
        mediaSourceId: 'src-1',
        streamIndex: 3,
        ticket: 'tkt',
      );
      expect(
        vtt.toString(),
        'https://hermes.tailnet.ts.net/api/v1/streams/src-1/subtitles/3.vtt?ticket=tkt',
      );
    });
  });

  group('HermesVideoPlayerConfig & WatchProgressReporter', () {
    test('defaults to OpenGL renderer and HDR-safe #D8D8D8 subtitle color', () {
      final tokens = HermesThemeTokens.resolve();
      final config = HermesVideoPlayerConfig.hdrSafeDefault(tokens: tokens);

      expect(config.rendererBackend, VideoRendererBackend.openGl);
      expect(config.mpvBackendProperties['gpu-api'], 'opengl');
      expect(config.subtitleColor, const Color(0xFFD8D8D8));
    });

    test('WatchProgressReporter sends progress payload on reportNow', () async {
      String? capturedBody;
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/cinema/progress' && request.method == 'PUT') {
          capturedBody = request.body;
          return http.Response(
            jsonEncode({
              'positionMs': 120000,
              'durationMs': 600000,
              'isWatched': false,
              'updatedAtUtc': '2026-11-15T20:00:00Z',
            }),
            200,
          );
        }
        return http.Response('[]', 200);
      });

      final service = CinemaService(
        baseUri: Uri.parse('http://localhost:5000'),
        accessToken: 'jwt',
        httpClient: client,
      );

      final reporter = WatchProgressReporter(
        cinemaService: service,
        movieId: 'mov-1',
        getPositionMs: () => 120000,
        getDurationMs: () => 600000,
      );

      await reporter.reportNow();
      reporter.dispose();

      expect(capturedBody, isNotNull);
      final decoded = jsonDecode(capturedBody!) as Map<String, dynamic>;
      expect(decoded['movieId'], 'mov-1');
      expect(decoded['positionMs'], 120000);
      expect(decoded['durationMs'], 600000);
    });
  });

  group('SourceSelectorCard', () {
    testWidgets('lists multiple 1:N sources with HDR badges and allows quality choice', (tester) async {
      MediaSourceModel? chosenSource;
      VideoQualityPreset? chosenQuality;

      const movie = MovieSummary(
        id: 'mov-1',
        title: 'Dune: Part Two',
        year: 2024,
        sources: [
          MediaSourceModel(
            id: 'src-4k',
            sourceLabel: '2160p HDR HEVC',
            container: 'mkv',
            videoCodec: 'hevc',
            audioCodec: 'truehd',
            width: 3840,
            height: 2160,
            isHdr: true,
            bitrateBps: 45000000,
            durationMs: 9960000,
            isAvailable: true,
            streams: [
              MediaStreamModel(streamIndex: 0, kind: 0, codec: 'hevc', language: 'und', title: 'Main', isDefault: true),
              MediaStreamModel(streamIndex: 1, kind: 1, codec: 'truehd', language: 'eng', title: 'English 7.1', isDefault: true),
              MediaStreamModel(streamIndex: 2, kind: 2, codec: 'subrip', language: 'eng', title: 'English SDH', isDefault: true),
            ],
          ),
          MediaSourceModel(
            id: 'src-1080',
            sourceLabel: '1080p H264',
            container: 'mp4',
            videoCodec: 'h264',
            audioCodec: 'aac',
            width: 1920,
            height: 1080,
            isHdr: false,
            bitrateBps: 8000000,
            durationMs: 9960000,
            isAvailable: true,
            streams: [],
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: HermesThemeTokens.resolve().toThemeData(),
          home: Scaffold(
            body: SourceSelectorCard(
              sources: movie.sources,
              initialQuality: VideoQualityPreset.directPlay,
              onPlaySource: (source, quality) {
                chosenSource = source;
                chosenQuality = quality;
              },
            ),
          ),
        ),
      );

      expect(find.text('2160p HDR HEVC'), findsOneWidget);
      expect(find.text('1080p H264'), findsOneWidget);
      expect(find.text('HDR'), findsOneWidget);

      await tester.tap(find.text('720p'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1080p H264'));
      await tester.pumpAndSettle();

      expect(chosenSource?.id, 'src-1080');
      expect(chosenQuality, VideoQualityPreset.p720);
    });
  });

  group('PlayerAndThemeSettingsScreen & AdminDashboardScreen', () {
    testWidgets('settings screen updates theme preset and OpenGL renderer option', (tester) async {
      HermesThemeTokens updatedTokens = HermesThemeTokens.resolve();
      VideoRendererBackend renderer = VideoRendererBackend.openGl;
      VideoQualityPreset defaultQuality = VideoQualityPreset.directPlay;

      await tester.pumpWidget(
        MaterialApp(
          theme: updatedTokens.toThemeData(),
          home: PlayerAndThemeSettingsScreen(
            tokens: updatedTokens,
            rendererBackend: renderer,
            defaultVideoQuality: defaultQuality,
            onThemeChanged: (next) => updatedTokens = next,
            onRendererChanged: (next) => renderer = next,
            onDefaultVideoQualityChanged: (next) => defaultQuality = next,
          ),
        ),
      );

      await tester.tap(find.text('OLED Black'));
      await tester.pumpAndSettle();
      expect(updatedTokens.surfacePreset, SurfacePreset.oledBlack);

      await tester.tap(find.text('Emerald'));
      await tester.pumpAndSettle();
      expect(updatedTokens.accentKind, HermesAccentKind.emerald);

      await tester.tap(find.text('1080p'));
      await tester.pumpAndSettle();
      expect(defaultQuality, VideoQualityPreset.p1080);
    });

    testWidgets('admin dashboard displays library roots, invites, users and triggers scan', (tester) async {
      var scannedLibraryId = '';
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/admin/libraries' && request.method == 'GET') {
          return http.Response(
            jsonEncode([
              {
                'id': 'lib-1',
                'name': 'Movies 4K',
                'mediaType': 0,
                'rootPath': '/media/movies',
                'watchEnabled': true,
                'createdAtUtc': '2026-11-15T10:00:00Z',
                'lastScanCompletedAtUtc': null,
              }
            ]),
            200,
          );
        }
        if (request.url.path == '/api/v1/admin/libraries/lib-1/scan' && request.method == 'POST') {
          scannedLibraryId = 'lib-1';
          return http.Response(
            jsonEncode({
              'libraryRootId': 'lib-1',
              'filesDiscovered': 12,
              'sourcesUpserted': 12,
              'sourcesMarkedMissing': 0,
              'completedAtUtc': '2026-11-15T11:00:00Z',
            }),
            200,
          );
        }
        if (request.url.path == '/api/v1/admin/invites' && request.method == 'GET') {
          return http.Response(
            jsonEncode([
              {
                'id': 'inv-1',
                'code': 'HRM-1234-ABCD',
                'maxUses': 3,
                'usedCount': 1,
                'expiresAtUtc': '2026-11-20T10:00:00Z',
                'isRevoked': false,
              }
            ]),
            200,
          );
        }
        if (request.url.path == '/api/v1/admin/users' && request.method == 'GET') {
          return http.Response(
            jsonEncode([
              {
                'id': 'u-1',
                'username': 'admin',
                'role': 'Admin',
                'isActive': true,
                'createdAtUtc': '2026-11-15T09:00:00Z',
              }
            ]),
            200,
          );
        }
        return http.Response('{}', 404);
      });

      final adminService = AdminService(
        baseUri: Uri.parse('http://localhost:5000'),
        accessToken: 'jwt-admin',
        httpClient: client,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: HermesThemeTokens.resolve().toThemeData(),
          home: AdminDashboardScreen(adminService: adminService),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Movies 4K'), findsOneWidget);
      expect(find.text('HRM-1234-ABCD'), findsOneWidget);
      expect(find.text('admin'), findsOneWidget);

      await tester.tap(find.text('Scan Now'));
      await tester.pumpAndSettle();
      expect(scannedLibraryId, 'lib-1');
    });
  });
}
