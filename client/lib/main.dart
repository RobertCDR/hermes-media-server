import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'src/core/auth/auth_service.dart';
import 'src/core/auth/session_store.dart';
import 'src/core/network/endpoint_resolver.dart';
import 'src/core/theme/hermes_theme_tokens.dart';
import 'src/features/admin/admin_dashboard_screen.dart';
import 'src/features/admin/admin_service.dart';
import 'src/features/auth/setup_and_login_screen.dart';
import 'src/features/cinema/cinema_catalog_screen.dart';
import 'src/features/cinema/cinema_models.dart';
import 'src/features/cinema/cinema_service.dart';
import 'src/features/cinema/hermes_video_player.dart';
import 'src/features/settings/player_and_theme_settings_screen.dart';
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
  VideoRendererBackend _rendererBackend = VideoRendererBackend.openGl;
  VideoQualityPreset _defaultVideoQuality = VideoQualityPreset.directPlay;
  HermesSession? _session;
  ResolvedEndpoint? _endpoint;

  @override
  void dispose() {
    _httpClient.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final endpoint = _endpoint;

    return MaterialApp(
      title: 'Hermes Media Server',
      debugShowCheckedModeBanner: false,
      theme: _tokens.toThemeData(),
      home: session == null || endpoint == null
          ? SetupAndLoginScreen(
              endpointResolver: _endpointResolver,
              authService: _authService,
              deviceId: 'hermes-${Platform.operatingSystem}',
              deviceName: Platform.localHostname,
              onAuthenticated: (nextSession, nextEndpoint) => setState(() {
                _session = nextSession;
                _endpoint = nextEndpoint;
              }),
            )
          : Builder(
              builder: (navContext) {
                final cinemaService = CinemaService(
                  baseUri: endpoint.baseUri,
                  accessToken: session.accessToken,
                  httpClient: _httpClient,
                );
                final adminService = AdminService(
                  baseUri: endpoint.baseUri,
                  accessToken: session.accessToken,
                  httpClient: _httpClient,
                );
                final playerConfig = HermesVideoPlayerConfig.hdrSafeDefault(
                  tokens: _tokens,
                  rendererBackend: _rendererBackend,
                );

                return DualWorldShell(
                  username: session.username,
                  isAdmin: session.isAdmin,
                  onOpenAdmin: () {
                    Navigator.of(navContext).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AdminDashboardScreen(adminService: adminService),
                      ),
                    );
                  },
                  onOpenSettings: () {
                    Navigator.of(navContext).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PlayerAndThemeSettingsScreen(
                          tokens: _tokens,
                          rendererBackend: _rendererBackend,
                          defaultVideoQuality: _defaultVideoQuality,
                          onThemeChanged: (next) => setState(() => _tokens = next),
                          onRendererChanged: (next) => setState(() => _rendererBackend = next),
                          onDefaultVideoQualityChanged: (next) =>
                              setState(() => _defaultVideoQuality = next),
                        ),
                      ),
                    );
                  },
                  cinemaBuilder: (_) => CinemaCatalogScreen(
                    cinemaService: cinemaService,
                    playerConfig: playerConfig,
                    defaultQuality: _defaultVideoQuality,
                  ),
                  musicBuilder: (_) => const Center(child: Text('Music Library')),
                );
              },
            ),
    );
  }
}
