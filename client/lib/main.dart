import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:http/http.dart' as http;
import 'src/core/auth/auth_service.dart';
import 'src/core/auth/session_store.dart';
import 'src/core/network/endpoint_resolver.dart';
import 'src/core/theme/hermes_theme_tokens.dart';
import 'src/features/auth/setup_and_login_screen.dart';
import 'src/features/shell/dual_world_shell.dart';

void main() {
  runApp(const HermesApp());
}

class HermesApp extends StatefulWidget {
  const HermesApp({super.key});

  @override
  State<HermesApp> createState() => _HermesAppState();
}

class _HermesAppState extends State<HermesApp> {
  final _httpClient = http.Client();
  final _sessionStore = InMemorySessionStore();
  late final _endpointResolver = EndpointResolver(httpClient: _httpClient);
  late final _authService = AuthService(httpClient: _httpClient, sessionStore: _sessionStore);

  HermesThemeTokens _tokens = HermesThemeTokens.resolve();
  HermesSession? _session;

  @override
  void dispose() {
    _httpClient.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hermes Media Server',
      debugShowCheckedModeBanner: false,
      theme: _tokens.toThemeData(),
      home: _session == null
          ? SetupAndLoginScreen(
              endpointResolver: _endpointResolver,
              authService: _authService,
              deviceId: 'hermes-${Platform.operatingSystem}',
              deviceName: Platform.localHostname,
              onAuthenticated: (session, _) => setState(() => _session = session),
            )
          : DualWorldShell(
              username: _session!.username,
              isAdmin: _session!.isAdmin,
              onOpenSettings: () {
                setState(() {
                  final next = SurfacePreset.values[(_tokens.surfacePreset.index + 1) % SurfacePreset.values.length];
                  _tokens = HermesThemeTokens.resolve(
                    surfacePreset: next,
                    accentKind: _tokens.accentKind,
                  );
                });
              },
              cinemaBuilder: (_) => const Center(child: Text('Cinema Library')),
              musicBuilder: (_) => const Center(child: Text('Music Library')),
            ),
    );
  }
}
