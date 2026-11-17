import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_client/src/core/theme/hermes_theme_tokens.dart';
import 'package:hermes_client/src/core/widgets/hermes_icons.dart';
import 'package:hermes_client/src/features/admin/admin_dashboard_screen.dart';
import 'package:hermes_client/src/features/admin/admin_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

http.Response _json(Object data, [int statusCode = 200]) => http.Response(
      jsonEncode(data),
      statusCode,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  group('M4 Admin Models & Service Endpoints', () {
    test('formats library sizes, contents labels, and invokes session/unmatched/revoke/deactivate endpoints', () async {
      final calls = <String>[];
      final client = MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        if (req.url.path == '/api/v1/admin/libraries') {
          return http.Response(
            jsonEncode([
              {
                'id': 'lib-1',
                'name': 'Cinema 4K',
                'mediaType': 0,
                'rootPath': '/media/Movies',
                'watchEnabled': true,
                'createdAtUtc': '2026-11-16T10:00:00Z',
                'lastScanCompletedAtUtc': '2026-11-17T08:30:00Z',
                'itemCount': 42,
                'totalSizeBytes': 1500000000000,
                'isScanning': false,
              },
              {
                'id': 'lib-2',
                'name': 'Lossless Music',
                'mediaType': 2,
                'rootPath': '/media/Music',
                'watchEnabled': true,
                'createdAtUtc': '2026-11-16T10:00:00Z',
                'itemCount': 0,
                'totalSizeBytes': 0,
              },
            ]),
            200,
          );
        }
        if (req.url.path == '/api/v1/admin/libraries/lib-1/scan/queue') {
          return http.Response('', 202);
        }
        if (req.url.path == '/api/v1/admin/sessions' && req.method == 'GET') {
          return _json([
            {
              'sessionId': 'music:s-1',
              'kind': 'music',
              'userId': 'u-1',
              'username': 'alice',
              'deviceName': 'Pixel 9',
              'title': 'Midnight City',
              'subtitle': 'M83',
              'progress': 0.5,
              'mode': 'Direct Play · FLAC',
              'bitrate': '1411 kbps',
              'isPaused': false,
              'canStop': true,
            },
          ]);
        }
        if (req.url.path.startsWith('/api/v1/admin/sessions/') && req.method == 'DELETE') {
          return http.Response('', 204);
        }
        if (req.url.path == '/api/v1/admin/media/unmatched') {
          return http.Response(
            jsonEncode([
              {
                'id': 'mov-99',
                'mediaType': 0,
                'title': 'Seven (1995)',
                'year': 1995,
                'libraryName': 'Cinema 4K',
                'filePath': '/media/Movies/Se7en.1995.mkv',
              },
            ]),
            200,
          );
        }
        if (req.url.path == '/api/v1/admin/media/tmdb-search') {
          return http.Response(
            jsonEncode([
              {'tmdbId': 807, 'title': 'Se7en', 'year': 1995, 'overview': 'Two detectives...'},
            ]),
            200,
          );
        }
        if (req.url.path == '/api/v1/admin/invites/inv-1/revoke') {
          return http.Response(
            jsonEncode({
              'id': 'inv-1',
              'code': 'HRM-9999-ABCD',
              'maxUses': 3,
              'usedCount': 0,
              'expiresAtUtc': '2026-11-24T10:00:00Z',
              'isRevoked': true,
            }),
            200,
          );
        }
        if (req.url.path == '/api/v1/admin/users/u-2' && req.method == 'DELETE') {
          return http.Response('', 204);
        }
        return http.Response('[]', 200);
      });

      final service = AdminService(
        baseUri: Uri.parse('http://localhost:5000'),
        accessToken: 'jwt',
        httpClient: client,
      );

      final libs = await service.listLibraries();
      expect(libs.first.contentsLabel, '42 movies');
      expect(libs.first.formattedSize, '1.5 TB');
      expect(libs.last.contentsLabel, 'Not scanned yet');
      expect(libs.last.formattedSize, '—');

      await service.queueLibraryScan('lib-1');
      final sessions = await service.listActiveSessions();
      expect(sessions.single.title, 'Midnight City');
      expect(sessions.single.isMusic, isTrue);

      await service.stopSession('music:s-1');
      final unmatched = await service.listUnmatchedMedia();
      expect(unmatched.single.filePath, '/media/Movies/Se7en.1995.mkv');

      final hits = await service.searchTmdb(query: 'Se7en', mediaType: 0);
      expect(hits.single.tmdbId, 807);

      final revoked = await service.revokeInvite('inv-1');
      expect(revoked.isRevoked, isTrue);

      await service.deactivateUser('u-2');
      expect(calls, contains('DELETE /api/v1/admin/users/u-2'));
    });
  });

  group('M4 Flat Server Admin UI & Modals', () {
    MockClient makeServerClient({
      required List<Map<String, dynamic>> libraries,
      required List<Map<String, dynamic>> sessions,
      required List<Map<String, dynamic>> unmatched,
      required List<Map<String, dynamic>> users,
      required List<Map<String, dynamic>> invites,
      List<String>? actionsLog,
    }) {
      return MockClient((req) async {
        actionsLog?.add('${req.method} ${req.url.path}');
        if (req.url.path == '/api/v1/admin/libraries' && req.method == 'GET') {
          return http.Response(jsonEncode(libraries), 200);
        }
        if (req.url.path == '/api/v1/admin/libraries' && req.method == 'POST') {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          final added = {
            'id': 'lib-new',
            'name': body['name'],
            'mediaType': body['mediaType'],
            'rootPath': body['rootPath'],
            'watchEnabled': body['watchEnabled'],
            'createdAtUtc': '2026-11-17T10:00:00Z',
            'lastScanCompletedAtUtc': '2026-11-17T10:01:00Z',
            'itemCount': 5,
            'totalSizeBytes': 5200000000,
          };
          libraries.add(added);
          return http.Response(jsonEncode(added), 201);
        }
        if (req.url.path.endsWith('/scan') && req.method == 'POST') {
          return http.Response(
            jsonEncode({
              'libraryRootId': 'lib-1',
              'filesDiscovered': 12,
              'sourcesUpserted': 4,
              'sourcesMarkedMissing': 0,
              'completedAtUtc': '2026-11-17T12:00:00Z',
            }),
            200,
          );
        }
        if (req.url.path == '/api/v1/admin/sessions' && req.method == 'GET') {
          return http.Response(jsonEncode(sessions), 200);
        }
        if (req.url.path.startsWith('/api/v1/admin/sessions/') && req.method == 'DELETE') {
          sessions.clear();
          return http.Response('', 204);
        }
        if (req.url.path == '/api/v1/admin/media/unmatched') {
          return http.Response(jsonEncode(unmatched), 200);
        }
        if (req.url.path == '/api/v1/admin/media/tmdb-search') {
          return http.Response(
            jsonEncode([
              {'tmdbId': 807, 'title': 'Se7en', 'year': 1995},
            ]),
            200,
          );
        }
        if (req.url.path == '/api/v1/admin/media/mov-unmatched/identify') {
          unmatched.clear();
          return http.Response(
            jsonEncode({
              'id': 'mov-unmatched',
              'tmdbId': 807,
              'title': 'Se7en',
              'year': 1995,
              'isMetadataLocked': true,
            }),
            200,
          );
        }
        if (req.url.path == '/api/v1/admin/invites' && req.method == 'GET') {
          return http.Response(jsonEncode(invites), 200);
        }
        if (req.url.path == '/api/v1/admin/invites' && req.method == 'POST') {
          final created = {
            'id': 'inv-new',
            'code': 'HRM-5555-WXYZ',
            'maxUses': 3,
            'usedCount': 0,
            'expiresAtUtc': '2026-11-24T10:00:00Z',
            'isRevoked': false,
          };
          invites.insert(0, created);
          return http.Response(jsonEncode(created), 201);
        }
        if (req.url.path == '/api/v1/admin/invites/inv-1/revoke') {
          invites[0] = {...invites[0], 'isRevoked': true};
          return http.Response(jsonEncode(invites[0]), 200);
        }
        if (req.url.path == '/api/v1/admin/users' && req.method == 'GET') {
          return http.Response(jsonEncode(users), 200);
        }
        if (req.url.path == '/api/v1/admin/users/u-2' && req.method == 'DELETE') {
          users.removeWhere((u) => u['id'] == 'u-2');
          return http.Response('', 204);
        }
        return http.Response('[]', 200);
      });
    }

    testWidgets('renders flat Server tables, stops session, fixes TMDb match, manages invites/users, and opens flat AddLibraryDialog without ChoiceChips', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1280, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final libraries = <Map<String, dynamic>>[
        {
          'id': 'lib-1',
          'name': 'Movies',
          'mediaType': 0,
          'rootPath': '/media/Movies',
          'watchEnabled': true,
          'createdAtUtc': '2026-11-16T10:00:00Z',
          'lastScanCompletedAtUtc': '2026-11-17T08:00:00Z',
          'itemCount': 24,
          'totalSizeBytes': 124000000000,
        },
      ];
      final sessions = <Map<String, dynamic>>[
        {
          'sessionId': 'transcode:tr-1',
          'kind': 'video',
          'userId': 'u-2',
          'username': 'bob',
          'deviceName': 'Pixel 9',
          'title': 'Blade Runner',
          'subtitle': '1982',
          'progress': 0.35,
          'mode': 'Converting to 1080p',
          'bitrate': '8.0 Mbps',
          'isPaused': true,
          'canStop': true,
        },
      ];
      final unmatched = <Map<String, dynamic>>[
        {
          'id': 'mov-unmatched',
          'mediaType': 0,
          'title': 'Se7en',
          'year': 1995,
          'libraryName': 'Movies',
          'filePath': '/media/Movies/Seven.Unknown.mkv',
        },
      ];
      final users = <Map<String, dynamic>>[
        {
          'id': 'u-1',
          'username': 'owner',
          'role': 'Admin',
          'isActive': true,
          'createdAtUtc': '2026-11-15T10:00:00Z',
        },
        {
          'id': 'u-2',
          'username': 'bob',
          'role': 'Member',
          'isActive': true,
          'createdAtUtc': '2026-11-16T10:00:00Z',
        },
      ];
      final invites = <Map<String, dynamic>>[
        {
          'id': 'inv-1',
          'code': 'HRM-1111-AAAA',
          'maxUses': 3,
          'usedCount': 1,
          'expiresAtUtc': '2026-11-24T10:00:00Z',
          'isRevoked': false,
        },
      ];

      final log = <String>[];
      final service = AdminService(
        baseUri: Uri.parse('http://localhost:5000'),
        accessToken: 'jwt',
        httpClient: makeServerClient(
          libraries: libraries,
          sessions: sessions,
          unmatched: unmatched,
          users: users,
          invites: invites,
          actionsLog: log,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: HermesThemeTokens.resolve().toThemeData(),
          home: Scaffold(body: AdminDashboardScreen(adminService: service)),
        ),
      );
      await tester.pumpAndSettle();

      // Zero Material ChoiceChip pills or boxy Card hero lists
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.text('Server'), findsOneWidget);
      expect(find.text('Now streaming'), findsOneWidget);
      expect(find.text('Blade Runner'), findsOneWidget);
      expect(find.text('Paused'), findsOneWidget);
      expect(find.text('24 movies'), findsOneWidget);
      expect(find.text('124.0 GB'), findsOneWidget);
      expect(find.text('Needs attention'), findsOneWidget);
      expect(find.text('/media/Movies/Seven.Unknown.mkv'), findsOneWidget);
      expect(find.text('owner'), findsOneWidget);
      expect(find.text('Owner'), findsOneWidget);
      expect(find.text('bob'), findsOneWidget);

      // Stop active session
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();
      expect(find.text('Nobody is streaming right now.'), findsOneWidget);

      // Fix match opens live TMDb candidate picker -> clicking candidate locks match
      await tester.tap(find.text('Fix match'));
      await tester.pumpAndSettle();
      expect(find.text('Se7en'), findsWidgets);
      await tester.tap(find.text('Movie • 1995'));
      await tester.pumpAndSettle();
      expect(find.text('Needs attention'), findsNothing);

      // Create invite -> shows Invite ready modal with copy link
      await tester.tap(find.text('Create invite'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Create invite'));
      await tester.pumpAndSettle();
      expect(find.text('Invite ready'), findsOneWidget);
      expect(find.text('HRM-5555-WXYZ'), findsWidgets);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // Revoke existing invite & Remove non-admin member
      await tester.tap(find.text('Revoke').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(find.text('bob'), findsNothing);

      // Open Add library dialog uses flat HermesSegmentedControl (zero ChoiceChips)
      await tester.tap(find.text('Add library'));
      await tester.pumpAndSettle();
      expect(find.byType(HermesSegmentedControl<int>), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
      await tester.tap(find.text('TV Shows'));
      await tester.pumpAndSettle();
      expect(find.text('/media/Series'), findsOneWidget);
      await tester.tap(find.text('Add & scan library'));
      await tester.pumpAndSettle();
      expect(log, contains('POST /api/v1/admin/libraries'));
      expect(log, contains('POST /api/v1/admin/libraries/lib-new/scan'));
      expect(find.text('TV Shows'), findsWidgets);
      expect(find.text('5 series'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders responsively on narrow 400x800 mobile screen without overflow', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(400, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final service = AdminService(
        baseUri: Uri.parse('http://localhost:5000'),
        accessToken: 'jwt',
        httpClient: makeServerClient(
          libraries: [
            {
              'id': 'lib-1',
              'name': 'Movies',
              'mediaType': 0,
              'rootPath': '/media/Movies',
              'watchEnabled': true,
              'createdAtUtc': '2026-11-16T10:00:00Z',
              'lastScanCompletedAtUtc': '2026-11-17T08:00:00Z',
              'itemCount': 12,
              'totalSizeBytes': 32000000000,
            },
          ],
          sessions: [],
          unmatched: [
            {
              'id': 'mov-unmatched',
              'mediaType': 0,
              'title': 'Zodiac',
              'libraryName': 'Movies',
              'filePath': '/media/Movies/Zodiac.2007.mkv',
            },
          ],
          users: [
            {
              'id': 'u-1',
              'username': 'admin',
              'role': 'Admin',
              'isActive': true,
              'createdAtUtc': '2026-11-15T10:00:00Z',
            },
          ],
          invites: [
            {
              'id': 'inv-1',
              'code': 'HRM-1234-ABCD',
              'maxUses': 3,
              'usedCount': 0,
              'expiresAtUtc': '2026-11-24T10:00:00Z',
              'isRevoked': false,
            },
          ],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: HermesThemeTokens.resolve().toThemeData(),
          home: Scaffold(body: AdminDashboardScreen(adminService: service)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Server'), findsOneWidget);
      expect(find.text('Movies'), findsWidgets);
      expect(find.text('Fix match'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
