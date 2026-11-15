import 'dart:async';
import 'dart:convert';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_client/src/core/auth/auth_service.dart';
import 'package:hermes_client/src/core/auth/session_store.dart';
import 'package:hermes_client/src/core/network/endpoint_resolver.dart';
import 'package:hermes_client/src/core/theme/hermes_theme_tokens.dart';
import 'package:hermes_client/src/features/shell/dual_world_shell.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('HermesThemeTokens', () {
    test('defaults to Obsidian Glow and Crimson with HDR-safe #D8D8D8 subtitles', () {
      final tokens = HermesThemeTokens.resolve();

      expect(tokens.surfacePreset, SurfacePreset.obsidianGlow);
      expect(tokens.accentKind, HermesAccentKind.crimson);
      expect(tokens.bgPrimary, const Color(0xFF090B12));
      expect(tokens.bgElevated, const Color(0xFF111522));
      expect(tokens.accentPrimary, const Color(0xFFE11D48));
      expect(tokens.subtitleSafeColor, const Color(0xFFD8D8D8));
    });

    test('supports OLED Black and Slate surface presets and curated accents', () {
      final oled = HermesThemeTokens.resolve(
        surfacePreset: SurfacePreset.oledBlack,
        accentKind: HermesAccentKind.emerald,
      );
      expect(oled.bgPrimary, const Color(0xFF000000));
      expect(oled.accentPrimary, const Color(0xFF10B981));

      final slate = HermesThemeTokens.resolve(
        surfacePreset: SurfacePreset.slate,
        accentKind: HermesAccentKind.violet,
      );
      expect(slate.bgPrimary, const Color(0xFF0F172A));
      expect(slate.accentPrimary, const Color(0xFF7C3AED));
    });

    test('clamps dark dynamic album-art accents to maintain >= 4.5:1 WCAG contrast', () {
      final tokens = HermesThemeTokens.resolve(
        surfacePreset: SurfacePreset.obsidianGlow,
        accentKind: HermesAccentKind.dynamicAlbumArt,
        dynamicSourceColor: const Color(0xFF0B0B14),
      );

      final ratio = HermesThemeTokens.wcagContrastRatio(tokens.accentPrimary, tokens.bgPrimary);
      expect(ratio, greaterThanOrEqualTo(4.5));
    });
  });

  group('EndpointResolver', () {
    test('uses primaryUrl when reachable and serverId matches', () async {
      final client = MockClient((request) async {
        expect(request.url.toString(), 'https://home.tailnet.ts.net/api/v1/system/info');
        return http.Response(
          jsonEncode({
            'serverId': 'srv-123',
            'serverName': 'Hermes Home',
            'version': '1.0.0',
            'setupCompleted': true,
          }),
          200,
        );
      });

      final resolver = EndpointResolver(httpClient: client);
      final resolved = await resolver.resolve(
        primaryUrl: 'https://home.tailnet.ts.net/',
        lanFallbackUrl: 'http://192.168.1.50:5000',
        expectedServerId: 'srv-123',
      );

      expect(resolved.baseUri.toString(), 'https://home.tailnet.ts.net');
      expect(resolved.usedFallback, isFalse);
      expect(resolved.info.serverName, 'Hermes Home');
    });

    test('falls back to lanFallbackUrl when primaryUrl times out or fails', () async {
      final client = MockClient((request) async {
        if (request.url.host == 'home.tailnet.ts.net') {
          throw TimeoutException('Tailscale probe timed out');
        }
        return http.Response(
          jsonEncode({
            'serverId': 'srv-123',
            'serverName': 'Hermes Home LAN',
            'version': '1.0.0',
            'setupCompleted': true,
          }),
          200,
        );
      });

      final resolver = EndpointResolver(
        httpClient: client,
        probeTimeout: const Duration(milliseconds: 500),
      );
      final resolved = await resolver.resolve(
        primaryUrl: 'https://home.tailnet.ts.net',
        lanFallbackUrl: 'http://192.168.1.50:5000/',
        expectedServerId: 'srv-123',
      );

      expect(resolved.baseUri.toString(), 'http://192.168.1.50:5000');
      expect(resolved.usedFallback, isTrue);
    });

    test('rejects endpoints whose serverId mismatches expectedServerId', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'serverId': 'wrong-server-999',
            'serverName': 'Stranger NAS',
            'version': '1.0.0',
            'setupCompleted': true,
          }),
          200,
        );
      });

      final resolver = EndpointResolver(httpClient: client);
      expect(
        () => resolver.resolve(
          primaryUrl: 'https://home.tailnet.ts.net',
          lanFallbackUrl: 'http://192.168.1.50:5000',
          expectedServerId: 'srv-123',
        ),
        throwsA(isA<HermesConnectionException>()),
      );
    });
  });

  group('AuthService single-flight refresh', () {
    test('deduplicates concurrent refresh calls into one network request', () async {
      var refreshCalls = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/auth/refresh') {
          refreshCalls++;
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return http.Response(
            jsonEncode({
              'accessToken': 'new-jwt-2',
              'refreshToken': 'new-rt-2',
              'userId': 'u1',
              'username': 'admin',
              'role': 'Admin',
            }),
            200,
          );
        }
        return http.Response('not found', 404);
      });

      final store = InMemorySessionStore();
      await store.save(
        const HermesSession(
          serverPrimaryUrl: 'http://localhost:5000',
          serverId: 'srv-1',
          deviceId: 'dev-win',
          deviceName: 'Windows PC',
          userId: 'u1',
          username: 'admin',
          role: 'Admin',
          accessToken: 'old-jwt',
          refreshToken: 'old-rt',
        ),
      );

      final auth = AuthService(httpClient: client, sessionStore: store);
      final results = await Future.wait([
        auth.refreshSession('http://localhost:5000'),
        auth.refreshSession('http://localhost:5000'),
        auth.refreshSession('http://localhost:5000'),
      ]);

      expect(refreshCalls, 1);
      expect(results.every((s) => s.accessToken == 'new-jwt-2'), isTrue);
    });
  });

  group('DualWorldShell', () {
    testWidgets('switches between Cinema and Music worlds on desktop and mobile viewports', (tester) async {
      final tokens = HermesThemeTokens.resolve();
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1280, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: tokens.toThemeData(),
          home: DualWorldShell(
            username: 'admin',
            isAdmin: true,
            cinemaBuilder: (_) => const Center(child: Text('Cinema Catalog View')),
            musicBuilder: (_) => const Center(child: Text('Music Library View')),
            miniPlayerBuilder: (_) => const Text('MiniPlayer Idle'),
          ),
        ),
      );

      expect(find.text('Cinema Catalog View'), findsOneWidget);
      expect(find.text('Music Library View'), findsNothing);
      expect(find.text('MiniPlayer Idle'), findsOneWidget);
      expect(find.byType(NavigationRail), findsOneWidget);

      await tester.tap(find.text('Music').first);
      await tester.pumpAndSettle();

      expect(find.text('Music Library View'), findsOneWidget);
      expect(find.text('Cinema Catalog View'), findsNothing);

      // Mobile viewport switches to bottom NavigationBar
      tester.view.physicalSize = const Size(400, 800);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
    });
  });
}
