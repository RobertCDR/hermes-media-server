import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'src/core/auth/auth_service.dart';
import 'src/core/auth/authenticated_http_client.dart';
import 'src/core/auth/session_store.dart';
import 'src/core/media/hermes_media_runtime.dart';
import 'src/core/network/endpoint_resolver.dart';
import 'src/core/network/hermes_sync_client.dart';
import 'src/core/settings/hermes_preferences.dart';
import 'src/core/theme/hermes_theme_tokens.dart';
import 'src/core/widgets/hermes_artwork_image.dart';
import 'src/core/widgets/hermes_icons.dart';
import 'src/core/widgets/hermes_search_pill.dart';
import 'src/features/admin/admin_dashboard_screen.dart';
import 'src/features/admin/admin_service.dart';
import 'src/features/auth/setup_and_login_screen.dart';
import 'src/features/cinema/cinema_catalog_screen.dart';
import 'src/features/cinema/cinema_models.dart';
import 'src/features/cinema/cinema_service.dart';
import 'src/features/cinema/hermes_video_player.dart';
import 'src/features/music/device_picker_sheet.dart';
import 'src/features/music/mini_player_bar.dart';
import 'src/features/music/music_models.dart';
import 'src/features/music/music_playback_coordinator.dart';
import 'src/features/music/music_service.dart';
import 'src/features/music/music_world_screen.dart';
import 'src/features/music/now_playing_panel.dart';
import 'src/features/music/platform_media_bridge.dart';
import 'src/features/settings/player_and_theme_settings_screen.dart';
import 'src/features/shell/dual_world_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  HermesMediaRuntime.ensureInitialized();
  runApp(const HermesApp());
}

typedef HermesSyncClientFactory = HermesSyncClient Function({
  required Uri baseUri,
  required http.Client httpClient,
  required String Function() getAccessToken,
  required String deviceId,
  required String deviceName,
  required String platform,
});

class HermesApp extends StatefulWidget {
  const HermesApp({
    super.key,
    this.sessionStore,
    this.preferencesStore,
    this.httpClient,
    this.syncClientFactory,
  });

  final SessionStore? sessionStore;
  final DevicePreferencesStore? preferencesStore;
  final http.Client? httpClient;
  final HermesSyncClientFactory? syncClientFactory;

  @override
  State<HermesApp> createState() => _HermesAppState();
}

class _HermesAppState extends State<HermesApp> {
  late final http.Client _rawHttpClient;
  late final bool _ownsHttpClient;
  late final SessionStore _sessionStore;
  late final DevicePreferencesStore _preferencesStore;
  final _mediaBridge = InMemoryPlatformMediaBridge();
  final _audioEngine = NoOpAudioEngineAdapter();
  late final EndpointResolver _endpointResolver;
  late final AuthService _authService;
  late final AuthenticatedHttpClient _apiHttpClient;
  late final AccountPreferencesService _accountPreferencesService;

  bool _bootstrapping = true;
  String _deviceId = 'hermes-${kIsWeb ? 'web' : Platform.operatingSystem}';
  String _initialPrimaryUrl = 'http://localhost:5258';
  String _initialLanUrl = '';
  HermesDevicePreferences _devicePrefs = const HermesDevicePreferences();
  HermesAccountPreferences _accountPrefs = const HermesAccountPreferences();
  HermesThemeTokens _tokens = HermesThemeTokens.resolve();
  VideoRendererBackend _rendererBackend = VideoRendererBackend.openGl;
  VideoQualityPreset _defaultVideoQuality = VideoQualityPreset.directPlay;
  bool _switchingServer = false;
  SettingsTabKind _settingsInitialTab = SettingsTabKind.device;
  HermesSession? _session;
  ResolvedEndpoint? _endpoint;
  MusicPlaybackCoordinator? _musicCoordinator;
  MusicService? _musicService;
  final ValueNotifier<HermesWorld> _worldNotifier = ValueNotifier<HermesWorld>(
    HermesWorld.cinema,
  );
  final MusicNavigationController _musicNav = MusicNavigationController();
  bool _connectPopoverOpen = false;
  List<OnlineDeviceModel> _connectDevices = const [];
  HermesSyncClient? _syncClient;
  StreamSubscription<PlaybackSessionState>? _syncSessionSub;
  StreamSubscription<List<OnlineDeviceModel>>? _syncDevicesSub;
  StreamSubscription<WatchProgressUpdatedEvent>? _syncWatchProgressSub;
  final StreamController<WatchProgressUpdatedEvent> _watchProgressController =
      StreamController<WatchProgressUpdatedEvent>.broadcast();

  String get _deviceName => kIsWeb ? 'Web Browser' : Platform.localHostname;

  String get _platformName => kIsWeb
      ? 'Web'
      : switch (defaultTargetPlatform) {
          TargetPlatform.android => 'Android',
          TargetPlatform.iOS => 'iOS',
          TargetPlatform.windows => 'Windows',
          TargetPlatform.macOS => 'macOS',
          TargetPlatform.linux => 'Linux',
          _ => Platform.operatingSystem,
        };

  @override
  void initState() {
    super.initState();
    _rawHttpClient = widget.httpClient ?? http.Client();
    _ownsHttpClient = widget.httpClient == null;
    _sessionStore = widget.sessionStore ?? SharedPrefsSessionStore();
    _preferencesStore =
        widget.preferencesStore ?? SharedPrefsDevicePreferencesStore();
    _endpointResolver = EndpointResolver(httpClient: _rawHttpClient);
    _authService = AuthService(
      httpClient: _rawHttpClient,
      sessionStore: _sessionStore,
    );
    _apiHttpClient = AuthenticatedHttpClient(
      inner: _rawHttpClient,
      getAccessToken: () => _session?.accessToken,
      refreshAccessToken: _refreshActiveAccessToken,
      onSessionExpired: _signOut,
    );
    _accountPreferencesService =
        AccountPreferencesService(httpClient: _apiHttpClient);

    unawaited(_bootstrapApp());
  }

  Future<String?> _refreshActiveAccessToken() async {
    final endpoint = _endpoint;
    if (endpoint == null) return null;
    try {
      final refreshed =
          await _authService.refreshSession(endpoint.baseUri.toString());
      if (mounted) {
        setState(() {
          _session = refreshed;
        });
      }
      return refreshed.accessToken;
    } catch (_) {
      return null;
    }
  }

  Future<void> _bootstrapApp() async {
    try {
      final osTag = kIsWeb ? 'web' : Platform.operatingSystem;
      final loadedDeviceId =
          await _preferencesStore.getOrCreateDeviceId(osTag);
      final loadedPrefs = await _preferencesStore.load();
      SavedServerEndpoints? savedEndpoints;
      if (_sessionStore case final EndpointHistoryStore endpointHistory) {
        savedEndpoints = await endpointHistory.loadLastEndpoints();
      }
      final savedSession = await _sessionStore.load();

      if (!mounted) return;
      _applyDevicePreferencesState(loadedPrefs, persist: false);
      setState(() {
        _deviceId = loadedDeviceId;
        if (savedEndpoints != null) {
          _initialPrimaryUrl = savedEndpoints.primaryUrl;
          _initialLanUrl = savedEndpoints.lanFallbackUrl ?? '';
        }
      });

      if (savedSession != null) {
        try {
          final resolved = await _endpointResolver.resolve(
            primaryUrl: savedSession.serverPrimaryUrl,
            lanFallbackUrl: savedSession.serverLanFallbackUrl,
            expectedServerId: savedSession.serverId,
          );
          final refreshed = await _authService.refreshSession(
            resolved.baseUri.toString(),
          );
          if (!mounted) return;
          _onAuthenticated(refreshed, resolved);
          return;
        } on AuthException catch (authErr) {
          // Clear stale tokens only when the server explicitly rejects the refresh token.
          if (authErr.statusCode == 401 || authErr.statusCode == 403) {
            await _sessionStore.clear();
          }
        } catch (_) {
          // Server temporarily unreachable: show Connect screen with pre-filled URLs.
        }
      }
    } catch (_) {
      // Fall back to default interactive onboarding if persistence is unavailable.
    } finally {
      if (mounted) {
        setState(() => _bootstrapping = false);
      }
    }
  }

  void _applyDevicePreferencesState(
    HermesDevicePreferences next, {
    bool persist = true,
  }) {
    setState(() {
      _devicePrefs = next;
      _tokens = next.toThemeTokens();
      _rendererBackend = next.rendererBackend;
      _defaultVideoQuality = next.defaultVideoQuality;
    });
    _musicCoordinator?.updateQualityPolicy(next.toAudioQualityPolicy());
    if (persist) {
      unawaited(_preferencesStore.save(next));
    }
  }

  @override
  void dispose() {
    unawaited(_stopSyncClient());
    unawaited(_watchProgressController.close());
    _worldNotifier.dispose();
    _musicCoordinator?.dispose();
    if (_ownsHttpClient) {
      _rawHttpClient.close();
    }
    super.dispose();
  }

  Future<void> _stopSyncClient() {
    final sessionSub = _syncSessionSub;
    final devicesSub = _syncDevicesSub;
    final watchSub = _syncWatchProgressSub;
    final syncClient = _syncClient;
    _syncSessionSub = null;
    _syncDevicesSub = null;
    _syncWatchProgressSub = null;
    _syncClient = null;
    final disposeFuture = syncClient?.dispose();
    return Future.wait([
      ?sessionSub?.cancel(),
      ?devicesSub?.cancel(),
      ?watchSub?.cancel(),
      ?disposeFuture,
    ]);
  }

  HermesSyncClient _defaultSyncClientFactory({
    required Uri baseUri,
    required http.Client httpClient,
    required String Function() getAccessToken,
    required String deviceId,
    required String deviceName,
    required String platform,
  }) {
    return HermesSyncClient(
      baseUri: baseUri,
      httpClient: httpClient,
      getAccessToken: getAccessToken,
      deviceId: deviceId,
      deviceName: deviceName,
      platform: platform,
    );
  }

  void _openMusicRoute(MusicPageRoute route) {
    _worldNotifier.value = HermesWorld.music;
    _musicNav.navigate(route);
  }

  Future<void> _openDevicePicker(
    BuildContext ctx,
    MusicService musicService,
    MusicPlaybackCoordinator coordinator,
    HermesSession session,
  ) async {
    List<OnlineDeviceModel> devices = _connectDevices;
    try {
      devices = await (coordinator.transport?.getOnlineDevices() ??
          musicService.getOnlineDevices());
    } catch (_) {
      devices = _connectDevices;
    }
    if (!ctx.mounted) return;

    final isDesktop = MediaQuery.sizeOf(ctx).width >= 840;
    if (isDesktop) {
      setState(() {
        _connectDevices = devices;
        _connectPopoverOpen = !_connectPopoverOpen;
      });
      return;
    }

    await showModalBottomSheet<void>(
      context: ctx,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: DevicePickerSheet(
            devices: devices,
            activeRendererDeviceId:
                coordinator.session?.activeRendererDeviceId,
            localDeviceId: session.deviceId,
            onSelectDevice: (id) {
              Navigator.of(sheetCtx).pop();
              unawaited(coordinator.transferOutputTo(id));
            },
          ),
        ),
      ),
    );
  }

  Future<void> _openMobileNowPlaying(
    BuildContext ctx,
    MusicPlaybackCoordinator coordinator,
    MusicService musicService,
    HermesSession session,
  ) async {
    await showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => FractionallySizedBox(
        heightFactor: 0.88,
        child: NowPlayingPanel(
          coordinator: coordinator,
          musicService: musicService,
          localDeviceId: session.deviceId,
          isModal: true,
          onClose: () => Navigator.of(sheetCtx).pop(),
          onOpenDevices: () {
            Navigator.of(sheetCtx).pop();
            unawaited(
              _openDevicePicker(ctx, musicService, coordinator, session),
            );
          },
          onNavigate: (route) {
            Navigator.of(sheetCtx).pop();
            _openMusicRoute(route);
          },
        ),
      ),
    );
  }

  void _onAuthenticated(HermesSession nextSession, ResolvedEndpoint nextEndpoint) {
    unawaited(_stopSyncClient());

    final musicService = MusicService(
      baseUri: nextEndpoint.baseUri,
      accessToken: nextSession.accessToken,
      httpClient: _apiHttpClient,
    );
    final syncClient = (widget.syncClientFactory ?? _defaultSyncClientFactory)(
      baseUri: nextEndpoint.baseUri,
      httpClient: _apiHttpClient,
      getAccessToken: () => _session?.accessToken ?? '',
      deviceId: nextSession.deviceId,
      deviceName: _deviceName,
      platform: _platformName,
    );
    final connectTransport = SignalRConnectTransport(
      syncClient: syncClient,
      musicService: musicService,
      localDeviceId: nextSession.deviceId,
      localDeviceName: _deviceName,
    );
    final coordinator = MusicPlaybackCoordinator(
      localDeviceId: nextSession.deviceId,
      musicService: musicService,
      audioEngine: _audioEngine,
      mediaBridge: _mediaBridge,
      transport: connectTransport,
    );

    coordinator.updateQualityPolicy(_devicePrefs.toAudioQualityPolicy());

    _syncClient = syncClient;
    _syncSessionSub = syncClient.sessionStream.listen((remoteState) {
      if (!mounted || _musicCoordinator != coordinator) return;
      unawaited(coordinator.applyServerSession(remoteState));
    });
    _syncDevicesSub = syncClient.devicesStream.listen((devices) {
      if (!mounted || _syncClient != syncClient) return;
      setState(() {
        _connectDevices = devices;
      });
    });
    _syncWatchProgressSub = syncClient.watchProgressStream.listen((event) {
      if (!_watchProgressController.isClosed) {
        _watchProgressController.add(event);
      }
    });

    setState(() {
      _musicCoordinator?.dispose();
      _bootstrapping = false;
      _session = nextSession;
      _endpoint = nextEndpoint;
      _initialPrimaryUrl = nextSession.serverPrimaryUrl;
      _initialLanUrl = nextSession.serverLanFallbackUrl ?? '';
      _switchingServer = false;
      _connectDevices = const [];
      _musicService = musicService;
      _musicCoordinator = coordinator;
    });

    syncClient.start();
    unawaited(_loadAccountPreferences(nextSession, nextEndpoint));
  }

  Future<void> _loadAccountPreferences(
    HermesSession session,
    ResolvedEndpoint endpoint,
  ) async {
    try {
      final prefs = await _accountPreferencesService.fetch(
        baseUrl: endpoint.baseUri.toString(),
        accessToken: session.accessToken,
      );
      if (!mounted || _session?.accessToken != session.accessToken) return;
      setState(() {
        _accountPrefs = prefs;
      });
    } catch (_) {
      // Keep defaults when server is offline or preferences endpoint is unavailable.
    }
  }

  Future<void> _syncAccountPreferences(HermesAccountPreferences next) async {
    setState(() {
      _accountPrefs = next;
    });
    final session = _session;
    final endpoint = _endpoint;
    if (session == null || endpoint == null) return;
    try {
      await _accountPreferencesService.save(
        baseUrl: endpoint.baseUri.toString(),
        accessToken: session.accessToken,
        preferences: next,
      );
    } catch (_) {
      // Local state already updated; retry on next change or login.
    }
  }

  Future<void> _changePassword(String currentPassword, String newPassword) async {
    final session = _session;
    final endpoint = _endpoint;
    if (session == null || endpoint == null) return;
    await _authService.changePassword(
      baseUrl: endpoint.baseUri.toString(),
      accessToken: session.accessToken,
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
  }

  Future<void> _signOut() async {
    await _stopSyncClient();
    await _authService.signOut();
    _musicCoordinator?.dispose();
    if (!mounted) return;
    setState(() {
      _session = null;
      _switchingServer = false;
      _connectPopoverOpen = false;
      _connectDevices = const [];
      _musicCoordinator = null;
      _musicService = null;
      _accountPrefs = const HermesAccountPreferences();
    });
  }

  Future<void> _openLibrarySearchDialog(
    BuildContext navContext,
    MusicService musicService,
    MusicPlaybackCoordinator musicCoordinator,
  ) {
    return showDialog<void>(
      context: navContext,
      builder: (_) => _LibrarySearchDialog(
        musicService: musicService,
        musicCoordinator: musicCoordinator,
        onOpenMusicRoute: _openMusicRoute,
      ),
    );
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
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final suppressDesktopTooltips =
            !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
        // Disable Material Tooltip OverlayPortal mounting on Windows desktop to
        // prevent Flutter #182444 AXTree desync across scrolling/hovering UIs.
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(_devicePrefs.textSize.scaleFactor),
            disableAnimations: _devicePrefs.reduceMotion,
          ),
          child: TooltipVisibility(
            visible: !suppressDesktopTooltips,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: _bootstrapping
          ? Scaffold(
              backgroundColor: _tokens.bgSunken,
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HermesMarkIcon(size: 38, color: _tokens.accent),
                    const SizedBox(height: 12),
                    Text(
                      'Hermes',
                      style: TextStyle(
                        fontFamily: 'Figtree',
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: _tokens.text,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : (_switchingServer ||
                  session == null ||
                  endpoint == null ||
                  musicService == null ||
                  musicCoordinator == null)
              ? SetupAndLoginScreen(
                  endpointResolver: _endpointResolver,
                  authService: _authService,
                  deviceId: _deviceId,
                  deviceName: _deviceName,
                  initialPrimaryUrl:
                      session?.serverPrimaryUrl ?? _initialPrimaryUrl,
                  initialLanUrl:
                      session?.serverLanFallbackUrl ?? _initialLanUrl,
                  onAuthenticated: _onAuthenticated,
                  onCancel: session != null && endpoint != null
                      ? () => setState(() => _switchingServer = false)
                      : null,
                )
              : Builder(
                  builder: (navContext) {
                    final cinemaService = CinemaService(
                      baseUri: endpoint.baseUri,
                      accessToken: session.accessToken,
                      httpClient: _apiHttpClient,
                    );
                    final adminService = AdminService(
                      baseUri: endpoint.baseUri,
                      accessToken: session.accessToken,
                      httpClient: _apiHttpClient,
                    );
                    final playerConfig = HermesVideoPlayerConfig.hdrSafeDefault(
                      tokens: _tokens,
                      rendererBackend: _rendererBackend,
                    );

                    return DualWorldShell(
                      worldNotifier: _worldNotifier,
                      username: session.username,
                      isAdmin: session.isAdmin,
                      serverName: endpoint.info.serverName,
                      endpointLabel: endpoint.usedFallback ? 'LAN fallback' : 'Tailscale',
                      onOpenSearch: () => unawaited(
                        _openLibrarySearchDialog(navContext, musicService, musicCoordinator),
                      ),
                      onOpenSettings: () => setState(
                        () => _settingsInitialTab = SettingsTabKind.device,
                      ),
                      onOpenAccountSettings: () => setState(
                        () => _settingsInitialTab = SettingsTabKind.account,
                      ),
                      onSwitchServer: () => setState(() => _switchingServer = true),
                      onSignOut: () => unawaited(_signOut()),
                      adminBuilder: (_) => AdminDashboardScreen(adminService: adminService),
                      settingsBuilder: (_) => PlayerAndThemeSettingsScreen(
                        tokens: _tokens,
                        rendererBackend: _rendererBackend,
                        defaultVideoQuality: _defaultVideoQuality,
                        networkMode: musicCoordinator.networkMode,
                        audioQualityPolicy: musicCoordinator.audioQualityPolicy,
                        devicePreferences: _devicePrefs,
                        accountPreferences: _accountPrefs,
                        username: session.username,
                        deviceName: kIsWeb ? 'Web Browser' : Platform.localHostname,
                        initialTab: _settingsInitialTab,
                        onThemeChanged: (next) => setState(() => _tokens = next),
                        onRendererChanged: (next) =>
                            setState(() => _rendererBackend = next),
                        onDefaultVideoQualityChanged: (next) =>
                            setState(() => _defaultVideoQuality = next),
                        onNetworkModeChanged: musicCoordinator.setNetworkMode,
                        onAudioQualityPolicyChanged: (policy) =>
                            _applyDevicePreferencesState(
                          _devicePrefs.copyWith(
                            wifiAudioPreset: policy.wifiPreset,
                            cellularAudioPreset: policy.cellularPreset,
                          ),
                        ),
                        onDevicePreferencesChanged: _applyDevicePreferencesState,
                        onAccountPreferencesChanged: (next) =>
                            unawaited(_syncAccountPreferences(next)),
                        onChangePassword: _changePassword,
                        onSwitchServer: () => setState(() => _switchingServer = true),
                        onSignOut: () => unawaited(_signOut()),
                      ),
                  cinemaBuilder: (_) => CinemaCatalogScreen(
                    cinemaService: cinemaService,
                    playerConfig: playerConfig,
                    defaultQuality: _defaultVideoQuality,
                    accountPreferences: _accountPrefs,
                    reduceMotion: _devicePrefs.reduceMotion,
                    watchProgressUpdates: _watchProgressController.stream,
                  ),
                  musicBuilder: (_) => MusicWorldScreen(
                    musicService: musicService,
                    coordinator: musicCoordinator,
                    navigationController: _musicNav,
                    reduceMotion: _devicePrefs.reduceMotion,
                  ),
                  sidePanelBuilder: (_) => AnimatedBuilder(
                    animation: musicCoordinator,
                    builder: (context, _) {
                      if (!musicCoordinator.nowPlayingOpen ||
                          musicCoordinator.currentSong == null) {
                        return const SizedBox.shrink();
                      }
                      return NowPlayingPanel(
                        coordinator: musicCoordinator,
                        musicService: musicService,
                        localDeviceId: session.deviceId,
                        onClose: () => musicCoordinator.toggleNowPlaying(false),
                        onOpenDevices: () => unawaited(
                          _openDevicePicker(
                            navContext,
                            musicService,
                            musicCoordinator,
                            session,
                          ),
                        ),
                        onNavigate: _openMusicRoute,
                      );
                    },
                  ),
                  floatingOverlayBuilder: (_) {
                    if (!_connectPopoverOpen) {
                      return const SizedBox.shrink();
                    }
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: () =>
                                setState(() => _connectPopoverOpen = false),
                          ),
                        ),
                        Positioned(
                          right: 16,
                          bottom: 92,
                          child: AnimatedBuilder(
                            animation: musicCoordinator,
                            builder: (context, _) => DevicePickerSheet(
                              devices: _connectDevices,
                              activeRendererDeviceId: musicCoordinator
                                  .session?.activeRendererDeviceId,
                              localDeviceId: session.deviceId,
                              onSelectDevice: (id) {
                                setState(() => _connectPopoverOpen = false);
                                unawaited(musicCoordinator.transferOutputTo(id));
                              },
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                  miniPlayerBuilder: (ctx) => AnimatedBuilder(
                    animation: musicCoordinator,
                    builder: (context, _) => MiniPlayerBar(
                      session: musicCoordinator.session,
                      currentSong: musicCoordinator.currentSong,
                      localDeviceId: session.deviceId,
                      artworkUri: musicService.buildArtworkUri(
                        musicCoordinator.currentSong?.artworkHash,
                      ),
                      nowPlayingOpen: musicCoordinator.nowPlayingOpen,
                      onTogglePlayPause: () =>
                          unawaited(musicCoordinator.togglePlayPause()),
                      onSkipNext: () =>
                          unawaited(musicCoordinator.skipNext()),
                      onSkipPrevious: () =>
                          unawaited(musicCoordinator.skipPrevious()),
                      onToggleShuffle: () =>
                          unawaited(musicCoordinator.toggleShuffle()),
                      onCycleRepeat: () =>
                          unawaited(musicCoordinator.cycleRepeatMode()),
                      onSeekMs: (ms) =>
                          unawaited(musicCoordinator.seekTo(ms)),
                      onVolumeChanged: (v) =>
                          unawaited(musicCoordinator.setVolume(v)),
                      onToggleMute: () =>
                          unawaited(musicCoordinator.toggleMute()),
                      onToggleLike: () {
                        final song = musicCoordinator.currentSong;
                        if (song != null) {
                          unawaited(musicCoordinator.toggleLikeSong(song.id));
                        }
                      },
                      onToggleNowPlaying: () {
                        if (MediaQuery.sizeOf(ctx).width >= 840) {
                          musicCoordinator.toggleNowPlaying();
                        } else {
                          unawaited(
                            _openMobileNowPlaying(
                              ctx,
                              musicCoordinator,
                              musicService,
                              session,
                            ),
                          );
                        }
                      },
                      onTapTitle: () {
                        final song = musicCoordinator.currentSong;
                        if (song != null) {
                          _openMusicRoute(MusicPageRoute.album(song.albumId));
                        }
                      },
                      onTapArtist: () {
                        final song = musicCoordinator.currentSong;
                        if (song != null) {
                          _openMusicRoute(MusicPageRoute.artist(song.artistId));
                        }
                      },
                      onOpenDevicePicker: () => unawaited(
                        _openDevicePicker(
                          ctx,
                          musicService,
                          musicCoordinator,
                          session,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _LibrarySearchDialog extends StatefulWidget {
  const _LibrarySearchDialog({
    required this.musicService,
    required this.musicCoordinator,
    required this.onOpenMusicRoute,
  });

  final MusicService musicService;
  final MusicPlaybackCoordinator musicCoordinator;
  final ValueChanged<MusicPageRoute> onOpenMusicRoute;

  @override
  State<_LibrarySearchDialog> createState() => _LibrarySearchDialogState();
}

class _LibrarySearchDialogState extends State<_LibrarySearchDialog> {
  final TextEditingController _queryController = TextEditingController();
  UnifiedSearchResult? _result;
  bool _searching = false;
  String? _error;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    final q = _queryController.text.trim();
    if (q.isEmpty) {
      setState(() {
        _result = null;
        _error = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final next = await widget.musicService.searchLibrary(q);
      if (!mounted) return;
      setState(() {
        _result = next;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _searching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Search Hermes Library'),
      content: SizedBox(
        width: 560,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: HermesSearchPill(
                    controller: _queryController,
                    autofocus: true,
                    hintText:
                        'Search movies, TV series, artists, albums, songs...',
                    hasQuery: _queryController.text.isNotEmpty,
                    onChanged: (_) => setState(() {}),
                    onClear: () {
                      _queryController.clear();
                      setState(() {
                        _result = null;
                        _error = null;
                      });
                    },
                    onSubmitted: (_) => unawaited(_runSearch()),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _searching ? null : () => unawaited(_runSearch()),
                  child: const Text('Search'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: _searching
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Text('Search failed: $_error')
                      : _result == null
                          ? const Center(
                              child: Text(
                                'Enter a title, artist, album, or song to search.',
                              ),
                            )
                          : _result!.isEmpty
                              ? const Center(child: Text('No matches found.'))
                              : ListView(
                                  children: [
                                    for (final movie in _result!.movies)
                                      ListTile(
                                        leading: HermesArtworkImage(
                                          uri: widget.musicService
                                              .buildArtworkUri(
                                            movie.artworkHash,
                                          ),
                                          fallbackTitle: movie.title,
                                          fallbackIcon: Icons.movie_outlined,
                                          width: 40,
                                          height: 54,
                                          showFallbackLabel: false,
                                        ),
                                        title: Text(movie.title),
                                        subtitle: Text(
                                          movie.year == null
                                              ? 'Movie'
                                              : 'Movie • ${movie.year}',
                                        ),
                                        onTap: () => Navigator.of(context).pop(),
                                      ),
                                    for (final show in _result!.series)
                                      ListTile(
                                        leading: HermesArtworkImage(
                                          uri: widget.musicService
                                              .buildArtworkUri(
                                            show.artworkHash,
                                          ),
                                          fallbackTitle: show.title,
                                          fallbackIcon: Icons.tv_outlined,
                                          width: 40,
                                          height: 54,
                                          showFallbackLabel: false,
                                        ),
                                        title: Text(show.title),
                                        subtitle: Text(
                                          show.year == null
                                              ? 'TV Series'
                                              : 'TV Series • ${show.year}',
                                        ),
                                        onTap: () => Navigator.of(context).pop(),
                                      ),
                                    for (final album in _result!.albums)
                                      ListTile(
                                        leading: HermesArtworkImage(
                                          uri: widget.musicService
                                              .buildArtworkUri(
                                            album.artworkHash,
                                          ),
                                          fallbackTitle: album.title,
                                          fallbackIcon: Icons.album_outlined,
                                          width: 44,
                                          height: 44,
                                          showFallbackLabel: false,
                                        ),
                                        title: Text(album.title),
                                        subtitle:
                                            Text('Album • ${album.artistName}'),
                                        onTap: () {
                                          Navigator.of(context).pop();
                                          widget.onOpenMusicRoute(
                                            MusicPageRoute.album(album.id),
                                          );
                                        },
                                      ),
                                    for (final song in _result!.songs)
                                      ListTile(
                                        leading: HermesArtworkImage(
                                          uri: widget.musicService
                                              .buildArtworkUri(
                                            song.artworkHash,
                                          ),
                                          fallbackTitle: song.albumTitle,
                                          fallbackIcon:
                                              Icons.music_note_outlined,
                                          width: 44,
                                          height: 44,
                                          showFallbackLabel: false,
                                        ),
                                        title: Text(song.title),
                                        subtitle:
                                            Text('Song • ${song.artistName}'),
                                        onTap: () {
                                          Navigator.of(context).pop();
                                          unawaited(
                                            widget.musicCoordinator
                                                .startQueue([song], 0),
                                          );
                                        },
                                      ),
                                  ],
                                ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
