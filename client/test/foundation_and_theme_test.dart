import 'dart:async';
import 'dart:convert';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_client/src/core/auth/auth_service.dart';
import 'package:hermes_client/src/core/auth/session_store.dart';
import 'package:hermes_client/src/core/network/endpoint_resolver.dart';
import 'package:hermes_client/src/core/theme/hermes_theme_tokens.dart';
import 'package:hermes_client/src/core/widgets/hermes_icons.dart';
import 'package:hermes_client/src/features/shell/dual_world_shell.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('HermesThemeTokens', () {
    test('defaults to Crimson v4 palette with HDR-safe #D8D8D8 subtitles', () {
      final tokens = HermesThemeTokens.resolve();

      expect(tokens.themeId, HermesThemeId.crimson);
      expect(tokens.pureBlack, isFalse);
      expect(tokens.bg, const Color(0xFF130A0C));
      expect(tokens.bgRail, const Color(0xFF0F0708));
      expect(tokens.bgSunken, const Color(0xFF0B0506));
      expect(tokens.surface, const Color(0xFF1C1012));
      expect(tokens.accent, const Color(0xFFDC143C));
      expect(tokens.subtitleSafeColor, const Color(0xFFD8D8D8));
      expect(tokens.toThemeData().scaffoldBackgroundColor, const Color(0xFF130A0C));
    });

    test('resolves all 6 v4 themes and Pure black background OLED override', () {
      final expected = {
        HermesThemeId.crimson: (const Color(0xFF130A0C), const Color(0xFFDC143C)),
        HermesThemeId.midnight: (const Color(0xFF0B0E15), const Color(0xFF5B8CFF)),
        HermesThemeId.forest: (const Color(0xFF0A110D), const Color(0xFF3DD68C)),
        HermesThemeId.amethyst: (const Color(0xFF100C16), const Color(0xFFA678FF)),
        HermesThemeId.amber: (const Color(0xFF120E09), const Color(0xFFF2A93B)),
        HermesThemeId.graphite: (const Color(0xFF0F0F10), const Color(0xFFF2F2F3)),
      };

      for (final entry in expected.entries) {
        final tokens = HermesThemeTokens.resolve(themeId: entry.key);
        expect(tokens.bg, entry.value.$1);
        expect(tokens.accent, entry.value.$2);

        final oled = HermesThemeTokens.resolve(
          themeId: entry.key,
          pureBlack: true,
        );
        expect(oled.bg, const Color(0xFF000000));
        expect(oled.bgSunken, const Color(0xFF000000));
        expect(oled.bgRail, const Color(0xFF000000));
        expect(oled.surface, tokens.surface);
      }
    });

    test('clamps dark title tints to maintain >= 4.5:1 WCAG contrast', () {
      final base = HermesThemeTokens.resolve();
      final tinted = base.withTitleTint(const Color(0xFF0B0B14));

      final ratio = HermesThemeTokens.wcagContrastRatio(
        tinted.accent,
        tinted.bg,
      );
      expect(ratio, greaterThanOrEqualTo(4.5));
      expect(tinted.titleTint, const Color(0xFF0B0B14));
      expect(tinted.pageWash, isNot(tinted.bg));

      final washOnly = base.withTitleTint(
        const Color(0xFF0B0B14),
        overrideAccent: false,
      );
      expect(washOnly.accent, base.accent);
      expect(washOnly.titleTint, const Color(0xFF0B0B14));
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
    testWidgets('renders v4 Obsidian rail, account popover, inline destinations, and mobile NavigationBar', (tester) async {
      final tokens = HermesThemeTokens.resolve();
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1280, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var switchServerTapped = false;
      var signOutTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: tokens.toThemeData(),
          home: DualWorldShell(
            username: 'robert',
            isAdmin: true,
            serverName: 'Hermes Home',
            endpointLabel: 'Tailscale',
            cinemaBuilder: (_) => const Center(child: Text('Cinema Catalog View')),
            musicBuilder: (_) => const Center(child: Text('Music Library View')),
            adminBuilder: (_) => const Center(child: Text('Server Admin View')),
            settingsBuilder: (_) => const Center(child: Text('Settings Inline View')),
            miniPlayerBuilder: (_) => const Text('MiniPlayer Idle'),
            onSwitchServer: () => switchServerTapped = true,
            onSignOut: () => signOutTapped = true,
          ),
        ),
      );

      expect(find.text('Cinema Catalog View'), findsOneWidget);
      expect(find.text('Music Library View'), findsNothing);
      expect(find.text('MiniPlayer Idle'), findsOneWidget);
      expect(find.byType(HermesMarkIcon), findsOneWidget);
      expect(find.text('Server'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);

      await tester.tap(find.text('Music').first);
      await tester.pumpAndSettle();

      expect(find.text('Music Library View'), findsOneWidget);
      expect(find.text('Cinema Catalog View'), findsNothing);

      // Account popover triggers Account settings, Switch server, and Sign out.
      await tester.tap(find.byKey(const Key('rail-avatar-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('account-popover')), findsOneWidget);
      expect(find.text('robert · Owner'), findsOneWidget);

      await tester.tap(find.text('Account settings'));
      await tester.pumpAndSettle();
      expect(find.text('Settings Inline View'), findsOneWidget);

      await tester.tap(find.byKey(const Key('rail-avatar-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Switch server / Setup UI'));
      await tester.pumpAndSettle();
      expect(switchServerTapped, isTrue);

      await tester.tap(find.byKey(const Key('rail-avatar-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(signOutTapped, isTrue);

      // Mobile viewport switches to bottom NavigationBar cleanly
      tester.view.physicalSize = const Size(400, 800);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
    });
  });
}
