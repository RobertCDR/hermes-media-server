import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_client/main.dart';
import 'package:hermes_client/src/core/auth/authenticated_http_client.dart';
import 'package:hermes_client/src/core/auth/session_store.dart';
import 'package:hermes_client/src/core/network/hermes_sync_client.dart';
import 'package:hermes_client/src/core/settings/hermes_preferences.dart';
import 'package:hermes_client/src/core/theme/hermes_theme_tokens.dart';
import 'package:hermes_client/src/features/cinema/cinema_catalog_screen.dart';
import 'package:hermes_client/src/features/cinema/cinema_models.dart';
import 'package:hermes_client/src/features/cinema/cinema_service.dart';
import 'package:hermes_client/src/features/cinema/hermes_video_player.dart';
import 'package:hermes_client/src/features/music/music_models.dart';
import 'package:hermes_client/src/features/music/music_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _FakeWebSocketSink extends Fake implements WebSocketSink {
  _FakeWebSocketSink({
    required this.onAdd,
    required this.onClose,
  });

  final void Function(dynamic data) onAdd;
  final Future<void> Function() onClose;
  final Completer<void> _done = Completer<void>();

  @override
  void add(dynamic data) => onAdd(data);

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    await onClose();
    if (!_done.isCompleted) {
      _done.complete();
    }
  }
}

class _FakeWebSocketChannel extends Fake implements WebSocketChannel {
  _FakeWebSocketChannel({Future<void>? readyFuture})
      : _readyFuture = readyFuture ?? Future<void>.value() {
    _sink = _FakeWebSocketSink(
      onAdd: (data) => sentMessages.add(data.toString()),
      onClose: () async {
        closed = true;
        if (!_incoming.isClosed) {
          await _incoming.close();
        }
      },
    );
  }

  final Future<void> _readyFuture;
  final StreamController<dynamic> _incoming = StreamController<dynamic>();
  final List<String> sentMessages = [];
  late final _FakeWebSocketSink _sink;
  bool closed = false;

  void pushServerText(String text) {
    if (!_incoming.isClosed) {
      _incoming.add(text);
    }
  }

  @override
  Future<void> get ready => _readyFuture;

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  String? get protocol => null;

  @override
  int? get closeCode => closed ? 1000 : null;

  @override
  String? get closeReason => null;
}

Map<String, dynamic> _sampleMovieJson({
  required String id,
  required String title,
  Map<String, dynamic>? watchProgress,
}) {
  return {
    'id': id,
    'title': title,
    'year': 2024,
    'overview': 'A sci-fi saga across desert worlds.',
    'watchProgress': watchProgress,
    'sources': [
      {
        'id': 'src-$id',
        'sourceLabel': '4K REMUX',
        'container': 'mkv',
        'videoCodec': 'hevc',
        'audioCodec': 'eac3',
        'width': 3840,
        'height': 2160,
        'isHdr': true,
        'bitrateBps': 25000000,
        'durationMs': 7200000,
        'isAvailable': true,
        'streams': const <Map<String, dynamic>>[],
      },
    ],
    'genres': ['Sci-Fi'],
    'runtimeMinutes': 120,
    'isInWatchlist': false,
    'cast': const <Map<String, dynamic>>[],
  };
}

void main() {
  group('PR22 Persistence stores', () {
    test('SharedPrefsSessionStore round-trips session and retains endpoints after clear', () async {
      SharedPreferences.setMockInitialValues({});
      final writerStore = SharedPrefsSessionStore();

      const session = HermesSession(
        serverPrimaryUrl: 'https://hermes.tailnet.ts.net',
        serverLanFallbackUrl: 'http://192.168.1.50:5258',
        serverId: 'srv-001',
        deviceId: 'hermes-windows-abc12345',
        deviceName: 'Desktop-PC',
        userId: 'usr-1',
        username: 'robert',
        role: 'Admin',
        accessToken: 'jwt-initial',
        refreshToken: 'refresh-initial',
      );

      await writerStore.save(session);

      final readerStore = SharedPrefsSessionStore();
      final restored = await readerStore.load();
      expect(restored, isNotNull);
      expect(restored!.serverPrimaryUrl, 'https://hermes.tailnet.ts.net');
      expect(restored.serverLanFallbackUrl, 'http://192.168.1.50:5258');
      expect(restored.serverId, 'srv-001');
      expect(restored.deviceId, 'hermes-windows-abc12345');
      expect(restored.username, 'robert');
      expect(restored.isAdmin, isTrue);
      expect(restored.accessToken, 'jwt-initial');
      expect(restored.refreshToken, 'refresh-initial');

      await readerStore.clear();
      expect(await SharedPrefsSessionStore().load(), isNull);

      final endpointsAfterClear =
          await SharedPrefsSessionStore().loadLastEndpoints();
      expect(endpointsAfterClear, isNotNull);
      expect(endpointsAfterClear!.primaryUrl, 'https://hermes.tailnet.ts.net');
      expect(
        endpointsAfterClear.lanFallbackUrl,
        'http://192.168.1.50:5258',
      );
    });

    test('SharedPrefsDevicePreferencesStore persists unique deviceId and all prefs', () async {
      SharedPreferences.setMockInitialValues({});
      final firstStore = SharedPrefsDevicePreferencesStore();
      final id1 = await firstStore.getOrCreateDeviceId('Windows');
      final id2 = await SharedPrefsDevicePreferencesStore().getOrCreateDeviceId(
        'Windows',
      );

      expect(id1, startsWith('hermes-windows-'));
      expect(id2, id1);

      const customPrefs = HermesDevicePreferences(
        themeId: HermesThemeId.midnight,
        pureBlack: true,
        textSize: HermesTextSize.large,
        reduceMotion: true,
        defaultVideoQuality: VideoQualityPreset.p1080,
        rendererBackend: VideoRendererBackend.auto,
        wifiAudioPreset: AudioQualityPreset.high160,
        cellularAudioPreset: AudioQualityPreset.medium96,
      );
      await firstStore.save(customPrefs);

      final restored = await SharedPrefsDevicePreferencesStore().load();
      expect(restored.themeId, HermesThemeId.midnight);
      expect(restored.pureBlack, isTrue);
      expect(restored.textSize, HermesTextSize.large);
      expect(restored.reduceMotion, isTrue);
      expect(restored.defaultVideoQuality, VideoQualityPreset.p1080);
      expect(restored.rendererBackend, VideoRendererBackend.auto);
      expect(restored.wifiAudioPreset, AudioQualityPreset.high160);
      expect(restored.cellularAudioPreset, AudioQualityPreset.medium96);
    });
  });

  group('PR22 AuthenticatedHttpClient 401 refresh', () {
    test('refreshes JWT once on 401, replays request, and injects updated token afterward', () async {
      var activeToken = 'expired-jwt';
      var refreshCalls = 0;
      final seenAuthHeaders = <String>[];

      final mockInner = MockClient((request) async {
        seenAuthHeaders.add(request.headers['Authorization'] ?? '');
        if (request.headers['Authorization'] == 'Bearer expired-jwt') {
          return http.Response('Unauthorized', 401);
        }
        return http.Response(jsonEncode({'ok': true}), 200);
      });

      final client = AuthenticatedHttpClient(
        inner: mockInner,
        getAccessToken: () => activeToken,
        refreshAccessToken: () async {
          refreshCalls++;
          activeToken = 'refreshed-jwt';
          return activeToken;
        },
      );

      final res1 = await client.post(
        Uri.parse('https://hermes.example/api/v1/cinema/watch-progress'),
        headers: {
          'Authorization': 'Bearer expired-jwt',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'movieId': 'mov-1', 'positionMs': 1234}),
      );

      expect(res1.statusCode, 200);
      expect(refreshCalls, 1);

      // Even if a service holds an old token reference, client injects the freshest token.
      final res2 = await client.get(
        Uri.parse('https://hermes.example/api/v1/movies'),
        headers: {'Authorization': 'Bearer expired-jwt'},
      );
      expect(res2.statusCode, 200);
      expect(refreshCalls, 1);
      expect(seenAuthHeaders, [
        'Bearer expired-jwt',
        'Bearer refreshed-jwt',
        'Bearer refreshed-jwt',
      ]);

      client.close();
    });

    test('invokes onSessionExpired when refresh fails and ignores /auth/login 401', () async {
      var expiredCount = 0;
      var refreshAttempts = 0;

      final mockInner = MockClient((request) async {
        return http.Response('Unauthorized', 401);
      });

      final client = AuthenticatedHttpClient(
        inner: mockInner,
        getAccessToken: () => 'expired-jwt',
        refreshAccessToken: () async {
          refreshAttempts++;
          return null;
        },
        onSessionExpired: () {
          expiredCount++;
        },
      );

      final loginRes = await client.post(
        Uri.parse('https://hermes.example/api/v1/auth/login'),
        body: '{}',
      );
      expect(loginRes.statusCode, 401);
      expect(refreshAttempts, 0);
      expect(expiredCount, 0);

      final protectedRes = await client.get(
        Uri.parse('https://hermes.example/api/v1/movies'),
      );
      expect(protectedRes.statusCode, 401);
      expect(refreshAttempts, 1);
      expect(expiredCount, 1);

      client.close();
    });
  });

  group('PR22 SignalR /hubs/sync HermesSyncClient & Transport', () {
    test('negotiates, handshakes, streams events, and invokes StartPlayback & TransferOutput', () async {
      Uri? capturedNegotiateUri;
      Uri? capturedWsUri;
      late _FakeWebSocketChannel fakeChannel;

      final mockHttp = MockClient((request) async {
        if (request.url.path == '/hubs/sync/negotiate') {
          capturedNegotiateUri = request.url;
          expect(request.method, 'POST');
          expect(request.headers['Authorization'], 'Bearer token-42');
          return http.Response(
            jsonEncode({
              'negotiateVersion': 1,
              'connectionToken': 'conn-xyz',
              'connectionId': 'conn-xyz',
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final syncClient = HermesSyncClient(
        baseUri: Uri.parse('https://hermes.local:5258'),
        httpClient: mockHttp,
        getAccessToken: () => 'token-42',
        deviceId: 'dev-win',
        deviceName: 'Workstation',
        platform: 'Windows',
        channelFactory: (uri) {
          capturedWsUri = uri;
          fakeChannel = _FakeWebSocketChannel();
          return fakeChannel;
        },
      );

      final sessions = <PlaybackSessionState>[];
      final deviceBatches = <List<OnlineDeviceModel>>[];
      final progressEvents = <WatchProgressUpdatedEvent>[];
      final sub1 = syncClient.sessionStream.listen(sessions.add);
      final sub2 = syncClient.devicesStream.listen(deviceBatches.add);
      final sub3 = syncClient.watchProgressStream.listen(progressEvents.add);

      syncClient.start();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(capturedNegotiateUri, isNotNull);
      expect(capturedNegotiateUri!.queryParameters['negotiateVersion'], '1');
      expect(capturedNegotiateUri!.queryParameters['deviceId'], 'dev-win');

      expect(capturedWsUri, isNotNull);
      expect(capturedWsUri!.scheme, 'wss');
      expect(capturedWsUri!.path, '/hubs/sync');
      expect(capturedWsUri!.queryParameters['id'], 'conn-xyz');
      expect(capturedWsUri!.queryParameters['access_token'], 'token-42');
      expect(capturedWsUri!.queryParameters['deviceName'], 'Workstation');
      expect(capturedWsUri!.queryParameters['platform'], 'Windows');

      expect(fakeChannel.sentMessages, ['{"protocol":"json","version":1}\u001E']);

      // Simulate SignalR server sending batched handshake + DevicesUpdated + WatchProgressUpdated.
      fakeChannel.pushServerText(
        '{}\u001E'
        '{"type":1,"target":"DevicesUpdated","arguments":[[{"deviceId":"dev-win","deviceName":"Workstation","platform":"Windows","connectedAtUtc":"2026-11-17T12:00:00Z"},{"deviceId":"dev-phone","deviceName":"Pixel","platform":"Android","connectedAtUtc":"2026-11-17T12:01:00Z"}]]}\u001E'
        '{"type":1,"target":"WatchProgressUpdated","arguments":[{"movieId":"mov-9","positionMs":90000,"durationMs":360000,"isWatched":false,"updatedAtUtc":"2026-11-17T12:02:00Z"}]}\u001E',
      );
      await Future<void>.delayed(Duration.zero);

      expect(syncClient.isConnected, isTrue);
      expect(deviceBatches.single, hasLength(2));
      expect(deviceBatches.single.last.deviceName, 'Pixel');
      expect(progressEvents.single.movieId, 'mov-9');
      expect(progressEvents.single.positionMs, 90000);

      final transport = SignalRConnectTransport(
        syncClient: syncClient,
        musicService: MusicService(
          baseUri: Uri.parse('https://hermes.local:5258'),
          accessToken: 'token-42',
          httpClient: mockHttp,
        ),
        localDeviceId: 'dev-win',
      );

      final startFuture = transport.startPlayback(['song-a', 'song-b'], 1);
      await Future<void>.delayed(Duration.zero);

      final sentRpc = jsonDecode(
        fakeChannel.sentMessages.last.replaceAll('\u001E', ''),
      ) as Map<String, dynamic>;
      expect(sentRpc['target'], 'StartPlayback');
      expect(sentRpc['arguments'], [
        {
          'queueSongIds': ['song-a', 'song-b'],
          'startIndex': 1,
        },
      ]);

      final invId = sentRpc['invocationId'] as String;
      fakeChannel.pushServerText(
        '{"type":3,"invocationId":"$invId","result":{"sessionId":"ses-1","version":2,"activeRendererDeviceId":"dev-win","activeRendererDeviceName":"Workstation","state":1,"repeatMode":0,"shuffle":false,"volume":1.0,"currentIndex":1,"currentSongId":"song-b","positionMs":0,"queueSongIds":["song-a","song-b"]}}\u001E',
      );

      final session = await startFuture;
      expect(session.version, 2);
      expect(session.state, PlaybackState.playing);
      expect(session.currentSongId, 'song-b');

      await sub1.cancel();
      await sub2.cancel();
      await sub3.cancel();
      await syncClient.dispose();
    });
  });

  group('PR22 Integration UI: Auto-login & live WatchProgressUpdated', () {
    testWidgets('HermesApp auto-logs in via LAN fallback and receives live Cinema progress', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final sessionStore = InMemorySessionStore();
      await sessionStore.save(
        const HermesSession(
          serverPrimaryUrl: 'https://primary-offline.example',
          serverLanFallbackUrl: 'http://192.168.1.50:5258',
          serverId: 'srv-lan',
          deviceId: 'dev-win-1',
          deviceName: 'Test-PC',
          userId: 'usr-1',
          username: 'robert',
          role: 'Admin',
          accessToken: 'old-jwt',
          refreshToken: 'old-refresh',
        ),
      );

      final prefsStore = InMemoryDevicePreferencesStore();
      late _FakeWebSocketChannel appWsChannel;

      final mockHttp = MockClient((request) async {
        if (request.url.host == 'primary-offline.example') {
          throw const SocketException('Tailscale host unreachable');
        }
        if (request.url.path == '/api/v1/system/info') {
          return http.Response(
            jsonEncode({
              'serverId': 'srv-lan',
              'serverName': 'Home Theater',
              'version': '1.0.0',
              'setupCompleted': true,
            }),
            200,
          );
        }
        if (request.url.path == '/api/v1/auth/refresh') {
          return http.Response(
            jsonEncode({
              'accessToken': 'fresh-jwt',
              'refreshToken': 'fresh-refresh',
              'role': 'Admin',
            }),
            200,
          );
        }
        if (request.url.path == '/api/v1/auth/me/preferences') {
          return http.Response(
            jsonEncode(const HermesAccountPreferences().toJson()),
            200,
          );
        }
        if (request.url.path == '/api/v1/cinema/movies') {
          return http.Response(
            jsonEncode([
              _sampleMovieJson(id: 'mov-dune', title: 'Dune: Part Two'),
            ]),
            200,
          );
        }
        if (request.url.path == '/api/v1/cinema/series') {
          return http.Response('[]', 200);
        }
        if (request.url.path == '/hubs/sync/negotiate') {
          return http.Response(
            jsonEncode({
              'negotiateVersion': 1,
              'connectionToken': 'ws-token-1',
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      await tester.pumpWidget(
        HermesApp(
          sessionStore: sessionStore,
          preferencesStore: prefsStore,
          httpClient: mockHttp,
          syncClientFactory: ({
            required baseUri,
            required httpClient,
            required getAccessToken,
            required deviceId,
            required deviceName,
            required platform,
          }) {
            return HermesSyncClient(
              baseUri: baseUri,
              httpClient: httpClient,
              getAccessToken: getAccessToken,
              deviceId: deviceId,
              deviceName: deviceName,
              platform: platform,
              channelFactory: (_) {
                appWsChannel = _FakeWebSocketChannel();
                return appWsChannel;
              },
            );
          },
        ),
      );

      await tester.pumpAndSettle();

      // Auto-logged straight into DualWorldShell via LAN fallback (no SetupAndLoginScreen).
      expect(find.text('Dune: Part Two'), findsWidgets);
      expect(find.text('Continue Watching'), findsNothing);

      // Open account popover to verify server name & LAN fallback indicator.
      await tester.tap(find.text('R'));
      await tester.pumpAndSettle();
      expect(find.text('Home Theater · LAN fallback'), findsOneWidget);

      // Dismiss popover by tapping top-left corner before checking Continue Watching.
      await tester.tapAt(const Offset(400, 40));
      await tester.pumpAndSettle();

      // Push SignalR handshake + live WatchProgressUpdated from another device.
      appWsChannel.pushServerText(
        '{}\u001E'
        '{"type":1,"target":"WatchProgressUpdated","arguments":[{"movieId":"mov-dune","positionMs":1800000,"durationMs":7200000,"isWatched":false,"updatedAtUtc":"2026-11-17T13:00:00Z"}]}\u001E',
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Continue Watching'), findsOneWidget);
    });

    testWidgets('CinemaCatalogScreen updates TV episode progress immediately from WatchProgressUpdated stream', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final watchProgressController =
          StreamController<WatchProgressUpdatedEvent>.broadcast();
      addTearDown(watchProgressController.close);

      final mockHttp = MockClient((request) async {
        if (request.url.path == '/api/v1/cinema/movies') {
          return http.Response('[]', 200);
        }
        if (request.url.path == '/api/v1/cinema/series') {
          return http.Response(
            jsonEncode([
              {
                'id': 'ser-1',
                'title': 'Severance',
                'year': 2022,
                'seasons': [
                  {
                    'id': 'sn-1',
                    'seasonNumber': 1,
                    'title': 'Season 1',
                    'episodes': [
                      {
                        'id': 'ep-101',
                        'episodeNumber': 1,
                        'title': 'Good News About Hell',
                        'sources': [
                          {
                            'id': 'src-ep-1',
                            'sourceLabel': '1080p WEB',
                            'container': 'mkv',
                            'videoCodec': 'h264',
                            'audioCodec': 'aac',
                            'width': 1920,
                            'height': 1080,
                            'isHdr': false,
                            'bitrateBps': 8000000,
                            'durationMs': 3400000,
                            'isAvailable': true,
                            'streams': const <Map<String, dynamic>>[],
                          },
                        ],
                      },
                    ],
                  },
                ],
                'genres': ['Sci-Fi'],
                'isInWatchlist': false,
                'cast': const <Map<String, dynamic>>[],
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
        httpClient: mockHttp,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CinemaCatalogScreen(
              cinemaService: service,
              playerConfig: HermesVideoPlayerConfig.hdrSafeDefault(
                tokens: HermesThemeTokens.resolve(),
              ),
              defaultQuality: VideoQualityPreset.directPlay,
              watchProgressUpdates: watchProgressController.stream,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Severance'), findsWidgets);
      expect(find.text('Continue Watching'), findsNothing);

      watchProgressController.add(
        WatchProgressUpdatedEvent(
          episodeId: 'ep-101',
          positionMs: 1200000,
          durationMs: 3400000,
          isWatched: false,
          updatedAtUtc: DateTime.utc(2026, 11, 17, 14, 0),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Continue Watching'), findsOneWidget);
      expect(find.text('S1 E1 · 37m left'), findsOneWidget);
    });
  });
}
