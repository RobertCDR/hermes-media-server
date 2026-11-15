import 'dart:async';
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
import 'src/features/music/device_picker_sheet.dart';
import 'src/features/music/mini_player_bar.dart';
import 'src/features/music/music_playback_coordinator.dart';
import 'src/features/music/music_service.dart';
import 'src/features/music/music_world_screen.dart';
import 'src/features/music/platform_media_bridge.dart';
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
  final _mediaBridge = InMemoryPlatformMediaBridge();
  final _audioEngine = NoOpAudioEngineAdapter();
  late final _endpointResolver = EndpointResolver(httpClient: _httpClient);
  late final _authService = AuthService(httpClient: _httpClient, sessionStore: _sessionStore);

  HermesThemeTokens _tokens = HermesThemeTokens.resolve();
  VideoRendererBackend _rendererBackend = VideoRendererBackend.openGl;
  VideoQualityPreset _defaultVideoQuality = VideoQualityPreset.directPlay;
  HermesSession? _session;
  ResolvedEndpoint? _endpoint;
  MusicPlaybackCoordinator? _musicCoordinator;
  MusicService? _musicService;

  @override
  void dispose() {
    _musicCoordinator?.dispose();
    _httpClient.close();
    super.dispose();
  }

  void _onAuthenticated(HermesSession nextSession, ResolvedEndpoint nextEndpoint) {
    final musicService = MusicService(
      baseUri: nextEndpoint.baseUri,
      accessToken: nextSession.accessToken,
      httpClient: _httpClient,
    );
    final coordinator = MusicPlaybackCoordinator(
      localDeviceId: nextSession.deviceId,
      musicService: musicService,
      audioEngine: _audioEngine,
      mediaBridge: _mediaBridge,
    );

    setState(() {
      _musicCoordinator?.dispose();
      _session = nextSession;
      _endpoint = nextEndpoint;
      _musicService = musicService;
      _musicCoordinator = coordinator;
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final endpoint = _endpoint;
    final musicService = _musicService;
    final musicCoordinator = _musicCoordinator;

    return MaterialApp(
      title: 'Hermes Media Server',
      debugShowCheckedModeBanner: false,
      theme: _tokens.toThemeData(),
      home: session == null || endpoint == null || musicService == null || musicCoordinator == null
          ? SetupAndLoginScreen(
              endpointResolver: _endpointResolver,
              authService: _authService,
              deviceId: 'hermes-${Platform.operatingSystem}',
              deviceName: Platform.localHostname,
              onAuthenticated: _onAuthenticated,
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
                  musicBuilder: (_) => MusicWorldScreen(
                    musicService: musicService,
                    coordinator: musicCoordinator,
                  ),
                  miniPlayerBuilder: (ctx) => AnimatedBuilder(
                    animation: musicCoordinator,
                    builder: (context, _) => MiniPlayerBar(
                      session: musicCoordinator.session,
                      currentSong: musicCoordinator.currentSong,
                      localDeviceId: session.deviceId,
                      onTogglePlayPause: () => unawaited(musicCoordinator.togglePlayPause()),
                      onSkipNext: () => unawaited(musicCoordinator.skipNext()),
                      onOpenDevicePicker: () async {
                        final devices = await musicService.getOnlineDevices();
                        if (!ctx.mounted) {
                          return;
                        }
                        await showModalBottomSheet<void>(
                          context: ctx,
                          builder: (sheetCtx) => DevicePickerSheet(
                            devices: devices,
                            activeRendererDeviceId: musicCoordinator.session?.activeRendererDeviceId,
                            localDeviceId: session.deviceId,
                            onSelectDevice: (id) {
                              Navigator.of(sheetCtx).pop();
                              unawaited(musicCoordinator.transferOutputTo(id));
                            },
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}
