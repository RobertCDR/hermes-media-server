import 'dart:convert';

import 'package:hermes_client/src/core/auth/auth_service.dart';
import 'package:hermes_client/src/core/auth/session_store.dart';
import 'package:hermes_client/src/core/network/endpoint_resolver.dart';
import 'package:hermes_client/src/core/settings/hermes_preferences.dart';
import 'package:hermes_client/src/core/theme/hermes_theme_tokens.dart';
import 'package:hermes_client/src/core/widgets/hermes_icons.dart';
import 'package:hermes_client/src/features/auth/setup_and_login_screen.dart';
import 'package:hermes_client/src/features/cinema/cinema_models.dart';
import 'package:hermes_client/src/features/cinema/hermes_video_player.dart';
import 'package:hermes_client/src/features/music/music_models.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HermesPreferences & AccountPreferencesService', () {
    test('roundtrips HermesDevicePreferences JSON cleanly', () {
      const prefs = HermesDevicePreferences(
        themeId: HermesThemeId.amethyst,
        pureBlack: true,
        textSize: HermesTextSize.larger,
        reduceMotion: true,
        defaultVideoQuality: VideoQualityPreset.p1080,
        rendererBackend: VideoRendererBackend.auto,
        wifiAudioPreset: AudioQualityPreset.veryHigh320,
        cellularAudioPreset: AudioQualityPreset.medium96,
      );

      final decoded = HermesDevicePreferences.fromJson(prefs.toJson());
      expect(decoded.themeId, HermesThemeId.amethyst);
      expect(decoded.pureBlack, isTrue);
      expect(decoded.textSize, HermesTextSize.larger);
      expect(decoded.reduceMotion, isTrue);
      expect(decoded.defaultVideoQuality, VideoQualityPreset.p1080);
      expect(decoded.rendererBackend, VideoRendererBackend.auto);
      expect(decoded.wifiAudioPreset, AudioQualityPreset.veryHigh320);
      expect(decoded.cellularAudioPreset, AudioQualityPreset.medium96);

      final tokens = decoded.toThemeTokens();
      expect(tokens.bg, const Color(0xFF000000));
      expect(tokens.accent, const Color(0xFFA678FF));
    });

    test('fetches and saves HermesAccountPreferences with Bearer auth', () async {
      String? capturedMethod;
      String? capturedAuth;
      Map<String, dynamic>? savedPayload;

      final client = MockClient((request) async {
        capturedMethod = request.method;
        capturedAuth = request.headers['Authorization'];

        if (request.method == 'GET' &&
            request.url.path == '/api/v1/auth/me/preferences') {
          return http.Response(
            jsonEncode({
              'autoplayNextEpisode': false,
              'normalizeVolume': true,
              'matchTitleColors': false,
              'subtitleSize': 'xl',
              'subtitleBackground': 'box',
            }),
            200,
          );
        }

        if (request.method == 'PUT' &&
            request.url.path == '/api/v1/auth/me/preferences') {
          savedPayload = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(request.body, 200);
        }

        return http.Response('unexpected', 500);
      });

      final service = AccountPreferencesService(httpClient: client);
      final fetched = await service.fetch(
        baseUrl: 'https://hermes.tailnet.ts.net/',
        accessToken: 'jwt-1',
      );

      expect(capturedMethod, 'GET');
      expect(capturedAuth, 'Bearer jwt-1');
      expect(fetched.autoplayNextEpisode, isFalse);
      expect(fetched.normalizeVolume, isTrue);
      expect(fetched.matchTitleColors, isFalse);
      expect(fetched.subtitleSize, SubtitleSizePreset.xl);
      expect(fetched.subtitleBackground, SubtitleBackgroundStyle.box);

      final updated = fetched.copyWith(
        autoplayNextEpisode: true,
        subtitleSize: SubtitleSizePreset.large,
      );
      final saved = await service.save(
        baseUrl: 'https://hermes.tailnet.ts.net',
        accessToken: 'jwt-1',
        preferences: updated,
      );

      expect(capturedMethod, 'PUT');
      expect(savedPayload?['autoplayNextEpisode'], isTrue);
      expect(savedPayload?['subtitleSize'], 'large');
      expect(saved, updated);
    });

    test('AccountPreferencesService throws StateError on non-200 response', () async {
      final client = MockClient((_) async => http.Response('forbidden', 403));
      final service = AccountPreferencesService(httpClient: client);

      await expectLater(
        () => service.fetch(baseUrl: 'http://localhost:5258', accessToken: 'bad'),
        throwsStateError,
      );
      await expectLater(
        () => service.save(
          baseUrl: 'http://localhost:5258',
          accessToken: 'bad',
          preferences: const HermesAccountPreferences(),
        ),
        throwsStateError,
      );
    });
  });

  group('AuthService changePassword & signOut', () {
    test('sends password change payload and clears session on signOut', () async {
      final sessionStore = InMemorySessionStore();
      await sessionStore.save(
        const HermesSession(
          serverPrimaryUrl: 'https://hermes.tailnet.ts.net',
          serverId: 'srv-1',
          accessToken: 'tok-abc',
          refreshToken: 'ref-abc',
          userId: 'u1',
          username: 'robert',
          role: 'Admin',
          deviceId: 'dev-1',
          deviceName: 'Win',
        ),
      );

      Map<String, dynamic>? body;
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/auth/change-password');
        expect(request.headers['Authorization'], 'Bearer tok-abc');
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'changed': true}), 200);
      });

      final auth = AuthService(httpClient: client, sessionStore: sessionStore);
      await auth.changePassword(
        baseUrl: 'https://hermes.tailnet.ts.net',
        accessToken: 'tok-abc',
        currentPassword: 'old-password',
        newPassword: 'new-strong-password',
      );

      expect(body, {
        'currentPassword': 'old-password',
        'newPassword': 'new-strong-password',
      });

      await auth.signOut();
      expect(await sessionStore.load(), isNull);
    });
  });

  group('SetupAndLoginScreen v4 flow', () {
    testWidgets('connects uninitialized server, runs First setup, and logs in', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      var setupCalled = false;
      HermesSession? authenticatedSession;
      ResolvedEndpoint? authenticatedEndpoint;

      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/system/info') {
          return http.Response(
            jsonEncode({
              'serverId': 'srv-hermes',
              'serverName': 'Hermes Home',
              'version': '1.0.0',
              'setupCompleted': false,
            }),
            200,
          );
        }
        if (request.url.path == '/api/v1/setup') {
          setupCalled = true;
          return http.Response(jsonEncode({'ok': true}), 200);
        }
        if (request.url.path == '/api/v1/auth/login') {
          return http.Response(
            jsonEncode({
              'accessToken': 'acc-1',
              'refreshToken': 'ref-1',
              'userId': 'u-1',
              'username': 'robert',
              'role': 'Admin',
            }),
            200,
          );
        }
        return http.Response('not found', 404);
      });

      final resolver = EndpointResolver(httpClient: client);
      final auth = AuthService(
        httpClient: client,
        sessionStore: InMemorySessionStore(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: HermesThemeTokens.resolve().toThemeData(),
          home: SetupAndLoginScreen(
            endpointResolver: resolver,
            authService: auth,
            deviceId: 'dev-win',
            deviceName: 'Windows',
            onAuthenticated: (session, endpoint) {
              authenticatedSession = session;
              authenticatedEndpoint = endpoint;
            },
          ),
        ),
      );

      expect(find.text('Connect to server'), findsOneWidget);
      await tester.tap(find.text('Connect server'));
      await tester.pumpAndSettle();

      expect(find.text('Hermes Home'), findsNWidgets(2));
      expect(find.text('Initialize server'), findsOneWidget);

      await tester.enterText(
        find.byType(TextField).at(1),
        'robert',
      );
      await tester.enterText(
        find.byType(TextField).at(2),
        'StrongPass123!',
      );
      await tester.tap(find.text('Initialize server & sign in'));
      await tester.pumpAndSettle();

      expect(setupCalled, isTrue);
      expect(authenticatedSession?.username, 'robert');
      expect(authenticatedEndpoint?.info.serverId, 'srv-hermes');
    });

    testWidgets('defaults initialized server to Sign in and supports Invite code & Switch server on mobile', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'serverId': 'srv-hermes',
            'serverName': 'Living Room Hermes',
            'version': '1.0.0',
            'setupCompleted': true,
          }),
          200,
        );
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: HermesThemeTokens.resolve().toThemeData(),
          home: SetupAndLoginScreen(
            endpointResolver: EndpointResolver(httpClient: client),
            authService: AuthService(
              httpClient: client,
              sessionStore: InMemorySessionStore(),
            ),
            deviceId: 'dev-phone',
            deviceName: 'Pixel',
            onAuthenticated: (_, _) {},
          ),
        ),
      );

      await tester.tap(find.text('Connect server'));
      await tester.pumpAndSettle();

      expect(find.text('Sign in to Hermes'), findsOneWidget);
      expect(find.text('Living Room Hermes'), findsOneWidget);

      await tester.tap(find.text('Invite code'));
      await tester.pumpAndSettle();
      expect(find.text('Create account'), findsOneWidget);
      expect(find.text('Redeem invite & sign in'), findsOneWidget);

      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      expect(find.text('Connect to server'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Hermes v4 vector icons & flat controls', () {
    testWidgets('renders optical Play, Pause, Bookmark, Mark icons and segmented/dropdown controls', (
      tester,
    ) async {
      HermesTextSize selectedSize = HermesTextSize.standard;
      AudioQualityPreset selectedAudio = AudioQualityPreset.high160;

      await tester.pumpWidget(
        MaterialApp(
          theme: HermesThemeTokens.resolve().toThemeData(),
          home: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          HermesMarkIcon(),
                          HermesPlayIcon(),
                          HermesPauseIcon(),
                          HermesBookmarkIcon(filled: true),
                        ],
                      ),
                      HermesSegmentedControl<HermesTextSize>(
                        options: HermesTextSize.values
                            .map((s) => HermesSegmentOption(value: s, label: s.label))
                            .toList(),
                        selected: selectedSize,
                        onChanged: (next) => setState(() => selectedSize = next),
                      ),
                      HermesFlatDropdown<AudioQualityPreset>(
                        value: selectedAudio,
                        options: AudioQualityPreset.values
                            .map((a) => HermesDropdownOption(value: a, label: a.label))
                            .toList(),
                        onChanged: (next) => setState(() => selectedAudio = next),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Larger'));
      await tester.pumpAndSettle();
      expect(selectedSize, HermesTextSize.larger);
      expect(find.byType(HermesPlayIcon), findsOneWidget);
      expect(find.byType(HermesBookmarkIcon), findsOneWidget);
    });
  });
}
