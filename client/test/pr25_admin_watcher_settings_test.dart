import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_client/src/core/theme/hermes_theme_tokens.dart';
import 'package:hermes_client/src/features/admin/admin_dashboard_screen.dart';
import 'package:hermes_client/src/features/admin/admin_models.dart';
import 'package:hermes_client/src/features/admin/admin_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('PR25 AdminModels & AdminService', () {
    test('formatStorageBytes and HardwareAccelerationMode handle units and wire values', () {
      expect(formatStorageBytes(512), '512 B');
      expect(formatStorageBytes(45000), '45 KB');
      expect(formatStorageBytes(12000000), '12 MB');
      expect(formatStorageBytes(4500000000), '4.5 GB');
      expect(formatStorageBytes(2500000000000), '2.5 TB');

      expect(HardwareAccelerationMode.fromJson(0), HardwareAccelerationMode.none);
      expect(HardwareAccelerationMode.fromJson(2), HardwareAccelerationMode.nvenc);
      expect(HardwareAccelerationMode.fromJson('vaapi'), HardwareAccelerationMode.vaapi);
      expect(HardwareAccelerationMode.fromJson('qsv'), HardwareAccelerationMode.qsv);
      expect(HardwareAccelerationMode.fromJson('videotoolbox'), HardwareAccelerationMode.videoToolbox);

      final model = ServerSettingsModel.fromJson({
        'serverId': 'srv-1',
        'serverName': 'Hermes Home',
        'transcodingEnabled': true,
        'maxConcurrentVideoTranscodes': 3,
        'maxConcurrentAudioTranscodes': 6,
        'maxRemoteVideoBitrateBps': 15000000,
        'hardwareAccelerationMode': 3,
        'updatedAtUtc': '2026-11-18T00:00:00Z',
        'totalMediaSizeBytes': 12500000000,
        'libraryCount': 2,
        'totalMovies': 10,
        'totalSeries': 3,
        'totalEpisodes': 48,
        'totalSongs': 120,
      });
      expect(model.formattedTotalMediaSize, '12.5 GB');
      expect(model.hardwareAccelerationMode, HardwareAccelerationMode.vaapi);
      expect(model.totalEpisodes, 48);
    });

    test('AdminService executes updateLibrary, deleteLibrary, getServerSettings, updateServerSettings', () async {
      final log = <String>[];
      final client = MockClient((req) async {
        log.add('${req.method} ${req.url.path}');
        if (req.method == 'PUT' && req.url.path == '/api/v1/admin/libraries/lib-1') {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'id': 'lib-1',
              'name': body['name'],
              'mediaType': 0,
              'rootPath': body['rootPath'],
              'watchEnabled': body['watchEnabled'],
              'fetchMetadata': body['fetchMetadata'],
              'createdAtUtc': '2026-11-16T10:00:00Z',
              'lastScanCompletedAtUtc': '2026-11-17T10:00:00Z',
              'itemCount': 12,
              'totalSizeBytes': 6400000000,
            }),
            200,
          );
        }
        if (req.method == 'DELETE' && req.url.path == '/api/v1/admin/libraries/lib-1') {
          return http.Response('', 204);
        }
        if (req.method == 'GET' && req.url.path == '/api/v1/admin/settings') {
          return http.Response(
            jsonEncode({
              'serverId': 'srv-1',
              'serverName': 'Hermes Vault',
              'transcodingEnabled': true,
              'maxConcurrentVideoTranscodes': 2,
              'maxConcurrentAudioTranscodes': 4,
              'maxRemoteVideoBitrateBps': null,
              'hardwareAccelerationMode': 0,
              'updatedAtUtc': '2026-11-18T00:00:00Z',
              'totalMediaSizeBytes': 8000000000,
              'libraryCount': 1,
              'totalMovies': 5,
              'totalSeries': 0,
              'totalEpisodes': 0,
              'totalSongs': 0,
            }),
            200,
          );
        }
        if (req.method == 'PUT' && req.url.path == '/api/v1/admin/settings') {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'serverId': 'srv-1',
              'serverName': body['serverName'],
              'transcodingEnabled': body['transcodingEnabled'],
              'maxConcurrentVideoTranscodes': body['maxConcurrentVideoTranscodes'],
              'maxConcurrentAudioTranscodes': body['maxConcurrentAudioTranscodes'],
              'maxRemoteVideoBitrateBps': body['maxRemoteVideoBitrateBps'],
              'hardwareAccelerationMode': body['hardwareAccelerationMode'],
              'updatedAtUtc': '2026-11-18T01:00:00Z',
              'totalMediaSizeBytes': 8000000000,
              'libraryCount': 1,
              'totalMovies': 5,
              'totalSeries': 0,
              'totalEpisodes': 0,
              'totalSongs': 0,
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      });

      final service = AdminService(
        baseUri: Uri.parse('http://localhost:5258'),
        accessToken: 'jwt',
        httpClient: client,
      );

      final updatedLib = await service.updateLibrary(
        id: 'lib-1',
        name: 'Cinema 4K',
        rootPath: '/mnt/cinema',
        watchEnabled: false,
        fetchMetadata: false,
      );
      expect(updatedLib.name, 'Cinema 4K');
      expect(updatedLib.watchEnabled, isFalse);
      expect(updatedLib.fetchMetadata, isFalse);

      await service.deleteLibrary('lib-1');

      final fetched = await service.getServerSettings();
      expect(fetched.serverName, 'Hermes Vault');
      expect(fetched.formattedTotalMediaSize, '8.0 GB');

      final saved = await service.updateServerSettings(
        const UpdateServerSettingsInput(
          serverName: 'Hermes NAS',
          transcodingEnabled: false,
          maxConcurrentVideoTranscodes: 4,
          maxConcurrentAudioTranscodes: 8,
          maxRemoteVideoBitrateBps: 10000000,
          hardwareAccelerationMode: HardwareAccelerationMode.nvenc,
        ),
      );
      expect(saved.serverName, 'Hermes NAS');
      expect(saved.transcodingEnabled, isFalse);
      expect(saved.hardwareAccelerationMode, HardwareAccelerationMode.nvenc);
      expect(log, [
        'PUT /api/v1/admin/libraries/lib-1',
        'DELETE /api/v1/admin/libraries/lib-1',
        'GET /api/v1/admin/settings',
        'PUT /api/v1/admin/settings',
      ]);
    });
  });

  group('PR25 AdminDashboardScreen Server Settings & Library CRUD UI', () {
    MockClient buildDashboardMock({
      required List<Map<String, dynamic>> libraries,
      required Map<String, dynamic> settings,
      required List<String> calls,
    }) {
      return MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        if (req.method == 'GET' && req.url.path == '/api/v1/admin/libraries') {
          return http.Response(jsonEncode(libraries), 200);
        }
        if (req.method == 'PUT' && req.url.path.startsWith('/api/v1/admin/libraries/')) {
          final id = req.url.pathSegments.last;
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          final idx = libraries.indexWhere((l) => l['id'] == id);
          if (idx >= 0) {
            libraries[idx] = {
              ...libraries[idx],
              'name': body['name'],
              'rootPath': body['rootPath'],
              'watchEnabled': body['watchEnabled'],
              'fetchMetadata': body['fetchMetadata'],
            };
            return http.Response(jsonEncode(libraries[idx]), 200);
          }
        }
        if (req.method == 'DELETE' && req.url.path.startsWith('/api/v1/admin/libraries/')) {
          final id = req.url.pathSegments.last;
          libraries.removeWhere((l) => l['id'] == id);
          settings['libraryCount'] = libraries.length;
          return http.Response('', 204);
        }
        if (req.method == 'GET' && req.url.path == '/api/v1/admin/settings') {
          return http.Response(jsonEncode(settings), 200);
        }
        if (req.method == 'PUT' && req.url.path == '/api/v1/admin/settings') {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          settings.addAll({
            'serverName': body['serverName'],
            'transcodingEnabled': body['transcodingEnabled'],
            'maxConcurrentVideoTranscodes': body['maxConcurrentVideoTranscodes'],
            'maxConcurrentAudioTranscodes': body['maxConcurrentAudioTranscodes'],
            'maxRemoteVideoBitrateBps': body['maxRemoteVideoBitrateBps'],
            'hardwareAccelerationMode': body['hardwareAccelerationMode'],
            'updatedAtUtc': '2026-11-18T02:00:00Z',
          });
          return http.Response(jsonEncode(settings), 200);
        }
        if (req.url.path == '/api/v1/admin/users') {
          return http.Response(
            jsonEncode([
              {
                'id': 'u-1',
                'username': 'owner',
                'role': 'Admin',
                'isActive': true,
                'createdAtUtc': '2026-11-15T10:00:00Z',
              },
            ]),
            200,
          );
        }
        return http.Response('[]', 200);
      });
    }

    testWidgets('displays total media size, edits & deletes library, and saves ServerSettings on desktop', (tester) async {
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
          'fetchMetadata': true,
          'createdAtUtc': '2026-11-16T10:00:00Z',
          'lastScanCompletedAtUtc': '2026-11-17T08:00:00Z',
          'itemCount': 4,
          'totalSizeBytes': 12500000000,
        },
      ];
      final settings = <String, dynamic>{
        'serverId': 'srv-1',
        'serverName': 'Hermes Home',
        'transcodingEnabled': true,
        'maxConcurrentVideoTranscodes': 2,
        'maxConcurrentAudioTranscodes': 4,
        'maxRemoteVideoBitrateBps': null,
        'hardwareAccelerationMode': 0,
        'updatedAtUtc': '2026-11-18T00:00:00Z',
        'totalMediaSizeBytes': 12500000000,
        'libraryCount': 1,
        'totalMovies': 4,
        'totalSeries': 2,
        'totalEpisodes': 20,
        'totalSongs': 18,
      };
      final calls = <String>[];
      String? notifiedServerName;

      final service = AdminService(
        baseUri: Uri.parse('http://localhost:5258'),
        accessToken: 'jwt',
        httpClient: buildDashboardMock(libraries: libraries, settings: settings, calls: calls),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: HermesThemeTokens.resolve().toThemeData(),
          home: Scaffold(
            body: AdminDashboardScreen(
              adminService: service,
              onServerNameChanged: (name) => notifiedServerName = name,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Total storage: 12.5 GB'), findsOneWidget);
      expect(find.text('Server settings'), findsOneWidget);
      expect(find.text('Total media size: 12.5 GB • 4 movies • 2 series • 18 tracks'), findsOneWidget);

      // Edit library dialog pre-fills existing values and updates on save.
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Edit library'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Movies'), 'Cinema 4K');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(calls, contains('PUT /api/v1/admin/libraries/lib-1'));
      expect(find.text('Cinema 4K'), findsOneWidget);

      // Update server settings (scroll down first so controls are visible).
      final saveSettingsBtn = find.text('Save settings');
      await tester.ensureVisible(saveSettingsBtn);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Hermes Home'), 'Hermes NAS');
      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await tester.pump();
      await tester.tap(saveSettingsBtn);
      await tester.pumpAndSettle();
      expect(calls, contains('PUT /api/v1/admin/settings'));
      expect(notifiedServerName, 'Hermes NAS');
      expect(settings['maxConcurrentVideoTranscodes'], 3);

      // Delete library opens confirmation modal and executes DELETE.
      final deleteAction = find.text('Delete');
      await tester.ensureVisible(deleteAction);
      await tester.pumpAndSettle();
      await tester.tap(deleteAction);
      await tester.pumpAndSettle();
      expect(find.text('Delete "Cinema 4K"?'), findsOneWidget);
      await tester.tap(find.text('Delete library'));
      await tester.pumpAndSettle();
      expect(calls, contains('DELETE /api/v1/admin/libraries/lib-1'));
      expect(find.text('Cinema 4K'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders Server settings cleanly on mobile 400x800 without overflow', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(400, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final service = AdminService(
        baseUri: Uri.parse('http://localhost:5258'),
        accessToken: 'jwt',
        httpClient: buildDashboardMock(
          libraries: [
            {
              'id': 'lib-1',
              'name': 'Music',
              'mediaType': 2,
              'rootPath': '/media/Music',
              'watchEnabled': true,
              'createdAtUtc': '2026-11-16T10:00:00Z',
              'lastScanCompletedAtUtc': '2026-11-17T08:00:00Z',
              'itemCount': 9,
              'totalSizeBytes': 520000000,
            },
          ],
          settings: {
            'serverId': 'srv-1',
            'serverName': 'Hermes Mobile Test',
            'transcodingEnabled': true,
            'maxConcurrentVideoTranscodes': 2,
            'maxConcurrentAudioTranscodes': 4,
            'maxRemoteVideoBitrateBps': 8000000,
            'hardwareAccelerationMode': 1,
            'updatedAtUtc': '2026-11-18T00:00:00Z',
            'totalMediaSizeBytes': 520000000,
            'libraryCount': 1,
            'totalMovies': 0,
            'totalSeries': 0,
            'totalEpisodes': 0,
            'totalSongs': 9,
          },
          calls: [],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: HermesThemeTokens.resolve().toThemeData(),
          home: Scaffold(body: AdminDashboardScreen(adminService: service)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView).first, const Offset(0, -600));
      await tester.pumpAndSettle();

      expect(find.text('Server settings'), findsOneWidget);
      expect(find.text('Total media size: 520 MB • 0 movies • 0 series • 9 tracks'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
