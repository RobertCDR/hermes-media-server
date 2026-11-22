import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show AppExitResponse, PointerDeviceKind;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'src/core/auth/auth_service.dart';
import 'src/core/auth/authenticated_http_client.dart';
import 'src/core/auth/session_store.dart';
import 'src/core/media/hermes_media_runtime.dart';
import 'src/core/network/endpoint_resolver.dart';
import 'src/core/network/hermes_sync_client.dart';
import 'src/core/settings/hermes_preferences.dart';
import 'src/core/storage/hermes_cache_manager.dart';
import 'src/core/storage/search_history_store.dart';
import 'src/core/theme/hermes_theme_tokens.dart';
import 'src/core/widgets/hermes_artwork_image.dart';
import 'src/core/widgets/hermes_icons.dart';
import 'src/core/widgets/hermes_search_pill.dart';
import 'src/core/window/hermes_desktop_titlebar.dart';
import 'src/core/window/hermes_window_bridge.dart';
import 'src/features/admin/admin_dashboard_screen.dart';
import 'src/features/admin/admin_service.dart';
import 'src/features/auth/setup_and_login_screen.dart';
import 'src/features/cinema/cinema_catalog_screen.dart';
import 'src/features/cinema/cinema_models.dart';
import 'src/features/cinema/cinema_service.dart';
import 'src/features/cinema/hermes_video_player.dart';
import 'src/features/music/device_picker_sheet.dart';
import 'src/features/music/media_kit_audio_engine.dart';
import 'src/features/music/mini_player_bar.dart';
import 'src/features/music/music_models.dart';
import 'src/features/music/music_playback_coordinator.dart';
import 'src/features/music/music_service.dart';
import 'src/features/music/music_world_screen.dart';
import 'src/features/music/now_playing_panel.dart';
import 'src/features/music/os_media_bridge.dart';
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

class _HermesScrollBehavior extends MaterialScrollBehavior {
  const _HermesScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        ...super.dragDevices,
        PointerDeviceKind.mouse,
      };
}

class HermesApp extends StatefulWidget {
  const HermesApp({
    super.key,
    this.sessionStore,
    this.preferencesStore,
    this.httpClient,
    this.syncClientFactory,
    this.audioEngine,
    this.mediaBridge,
    @visibleForTesting this.isMobilePlatformOverride,
    @visibleForTesting this.windowBridge,
    @visibleForTesting this.showDesktopTitleBarOverride,
  });

  final SessionStore? sessionStore;
  final DevicePreferencesStore? preferencesStore;
  final http.Client? httpClient;
  final HermesSyncClientFactory? syncClientFactory;
  final AudioEngineAdapter? audioEngine;
  final PlatformMediaBridge? mediaBridge;
  final bool? isMobilePlatformOverride;
  final HermesWindowBridge? windowBridge;
  final bool? showDesktopTitleBarOverride;

  @override
  State<HermesApp> createState() => _HermesAppState();
}

class _HermesAppState extends State<HermesApp> {
  late final http.Client _rawHttpClient;
  late final bool _ownsHttpClient;
  late final SessionStore _sessionStore;
  late final DevicePreferencesStore _preferencesStore;
  late final PlatformMediaBridge _mediaBridge;
  late final bool _ownsMediaBridge;
  late final AudioEngineAdapter _audioEngine;
  late final bool _ownsAudioEngine;
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
  bool _signingOut = false;
  SettingsTabKind _settingsInitialTab = SettingsTabKind.device;
  HermesSession? _session;
  ResolvedEndpoint? _endpoint;
  String? _serverNameOverride;
  CinemaService? _cinemaService;
  AdminService? _adminService;
  MusicPlaybackCoordinator? _musicCoordinator;
  MusicService? _musicService;
  bool get _isMobileStartup =>
      widget.isMobilePlatformOverride ??
      (!kIsWeb && (Platform.isAndroid || Platform.isIOS));

  late final ValueNotifier<HermesWorld> _worldNotifier =
      ValueNotifier<HermesWorld>(
        _isMobileStartup ? HermesWorld.music : HermesWorld.cinema,
      );
  late HermesWorld _lastContentWorld = _worldNotifier.value;
  final MusicNavigationController _musicNav = MusicNavigationController();
  final CinemaNavigationController _cinemaNav = CinemaNavigationController();
  final HermesCacheManager _cacheManager = HermesCacheManager();
  bool _connectPopoverOpen = false;
  List<OnlineDeviceModel> _connectDevices = const [];
  final ValueNotifier<List<OnlineDeviceModel>> _connectDevicesNotifier =
      ValueNotifier<List<OnlineDeviceModel>>(const []);
  HermesSyncClient? _syncClient;
  StreamSubscription<PlaybackSessionState>? _syncSessionSub;
  StreamSubscription<List<OnlineDeviceModel>>? _syncDevicesSub;
  StreamSubscription<WatchProgressUpdatedEvent>? _syncWatchProgressSub;
  AppLifecycleListener? _lifecycleListener;
  final StreamController<WatchProgressUpdatedEvent> _watchProgressController =
      StreamController<WatchProgressUpdatedEvent>.broadcast();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final HermesWindowBridge _windowBridge =
      widget.windowBridge ?? HermesWindowBridge.instance;
  final Map<String, ({Uint8List bgra, int width, int height})>
      _flyoutArtCache = {};

  bool get _isWindowsDesktop =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  bool get _showDesktopTitleBar =>
      widget.showDesktopTitleBarOverride ??
      (!(widget.isMobilePlatformOverride ?? false) && _isWindowsDesktop);

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
    if (widget.mediaBridge != null) {
      _mediaBridge = widget.mediaBridge!;
      _ownsMediaBridge = false;
    } else if (HermesMediaRuntime.isInitialized) {
      _mediaBridge = createDefaultPlatformMediaBridge();
      _ownsMediaBridge = true;
    } else {
      _mediaBridge = InMemoryPlatformMediaBridge();
      _ownsMediaBridge = true;
    }
    if (widget.audioEngine != null) {
      _audioEngine = widget.audioEngine!;
      _ownsAudioEngine = false;
    } else if (HermesMediaRuntime.isInitialized) {
      _audioEngine = MediaKitAudioEngineAdapter();
      _ownsAudioEngine = true;
    } else {
      _audioEngine = NoOpAudioEngineAdapter();
      _ownsAudioEngine = false;
    }
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

    if (!kIsWeb) {
      _lifecycleListener = AppLifecycleListener(
        onDetach: () {
          unawaited(_shutdownLocalPlayback());
        },
        onExitRequested: () async {
          await _saveWindowBoundsSafely();
          await _shutdownLocalPlayback();
          await _stopSyncClient();
          return AppExitResponse.exit;
        },
      );
    }

    if (_isWindowsDesktop || widget.windowBridge != null) {
      _windowBridge.onTrayAction = _handleDesktopTrayAction;
      _windowBridge.onFlyoutAction = _handleDesktopFlyoutAction;
      _windowBridge.onAppCommand = _handleDesktopAppCommand;
    }

    _applyDevicePreferencesState(_devicePrefs, persist: false);
    _worldNotifier.addListener(_onShellNavChanged);
    _musicNav.currentRouteNotifier.addListener(_onShellNavChanged);
    _cinemaNav.mobileTabNotifier.addListener(_onShellNavChanged);

    unawaited(_bootstrapApp());
  }

  void _onShellNavChanged() {
    final w = _worldNotifier.value;
    if (w == HermesWorld.music || w == HermesWorld.cinema) {
      _lastContentWorld = w;
    }
    if (mounted) {
      setState(() {});
    }
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
    } on AuthException catch (e) {
      if (e.statusCode == null || e.statusCode == 401 || e.statusCode == 403) {
        return null;
      }
      rethrow;
    }
  }

  Future<void> _bootstrapApp() async {
    try {
      if (_isWindowsDesktop) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await _windowBridge.restoreSavedBounds(prefs);
        } catch (_) {}
      }
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
    _cacheManager.applyCapMb(next.cacheCapMb);
    setState(() {
      _devicePrefs = next;
      _tokens = next.toThemeTokens();
      _rendererBackend = next.rendererBackend;
      _defaultVideoQuality = next.defaultVideoQuality;
    });
    _musicCoordinator?.updateQualityPolicy(next.toAudioQualityPolicy());
    if (_isWindowsDesktop || widget.windowBridge != null) {
      unawaited(_windowBridge.setCloseToTray(next.closeToTray));
    }
    if (persist) {
      unawaited(_preferencesStore.save(next));
    }
  }

  Future<void> _saveWindowBoundsSafely() async {
    if (!_isWindowsDesktop) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await _windowBridge.saveCurrentBounds(prefs);
    } catch (_) {}
  }

  void _handleDesktopTrayAction(String action) {
    final coordinator = _musicCoordinator;
    switch (action) {
      case 'playPause':
        if (coordinator != null) {
          unawaited(coordinator.togglePlayPause());
          unawaited(_triggerMediaFlyout());
        }
      case 'next':
        if (coordinator != null) {
          unawaited(coordinator.skipNext());
          unawaited(_triggerMediaFlyout());
        }
      case 'previous':
        if (coordinator != null) {
          unawaited(coordinator.skipPrevious());
          unawaited(_triggerMediaFlyout());
        }
      case 'quit':
        unawaited(_quitFromTray());
    }
  }

  void _handleDesktopFlyoutAction(String action) {
    final coordinator = _musicCoordinator;
    if (coordinator == null) return;
    switch (action) {
      case 'playPause':
        unawaited(coordinator.togglePlayPause());
      case 'next':
        unawaited(coordinator.skipNext());
      case 'previous':
        unawaited(coordinator.skipPrevious());
    }
    unawaited(_triggerMediaFlyout());
  }

  void _handleDesktopAppCommand(String direction) {
    final activeContentWorld =
        (_worldNotifier.value == HermesWorld.music ||
                _worldNotifier.value == HermesWorld.cinema)
            ? _worldNotifier.value
            : _lastContentWorld;
    if (direction == 'back') {
      final navState = _navigatorKey.currentState;
      if (navState != null && navState.canPop()) {
        unawaited(navState.maybePop());
        return;
      }
      if (activeContentWorld == HermesWorld.music) {
        _musicNav.handleBack();
      } else {
        _cinemaNav.handleBack();
      }
    } else if (direction == 'forward' &&
        activeContentWorld == HermesWorld.music) {
      _musicNav.handleForward();
    }
  }

  Future<void> _quitFromTray() async {
    await _saveWindowBoundsSafely();
    await _shutdownLocalPlayback();
    await _stopSyncClient();
    await _windowBridge.quitApp();
  }

  void _syncWindowTrackChrome() {
    if (!_isWindowsDesktop && widget.windowBridge == null) return;
    final coordinator = _musicCoordinator;
    final song = coordinator?.currentSong;
    final isPlaying = coordinator?.session?.state == PlaybackState.playing;
    if (song == null) {
      unawaited(_windowBridge.setTitle('Hermes'));
      unawaited(
        _windowBridge.updateTrayState(
          title: '',
          artist: '',
          isPlaying: false,
        ),
      );
      return;
    }
    final windowTitle =
        isPlaying ? '${song.title} · ${song.artistName} — Hermes' : 'Hermes';
    unawaited(_windowBridge.setTitle(windowTitle));
    unawaited(
      _windowBridge.updateTrayState(
        title: song.title,
        artist: song.artistName,
        isPlaying: isPlaying,
      ),
    );
  }

  Future<void> _triggerMediaFlyout() async {
    if ((!_isWindowsDesktop && widget.windowBridge == null) ||
        !_devicePrefs.showMediaFlyout) {
      return;
    }
    final coordinator = _musicCoordinator;
    final song = coordinator?.currentSong;
    if (song == null) return;
    final isPlaying = coordinator?.session?.state == PlaybackState.playing;
    final artHash = song.artworkHash;
    final cached = artHash != null ? _flyoutArtCache[artHash] : null;

    await _windowBridge.showMediaFlyout(
      HermesMediaFlyoutData(
        title: song.title,
        artist: song.artistName,
        isPlaying: isPlaying,
        artBgra: cached?.bgra,
        artWidth: cached?.width ?? 0,
        artHeight: cached?.height ?? 0,
      ),
    );

    if (cached != null || artHash == null || artHash.isEmpty) {
      return;
    }
    final musicService = _musicService;
    if (musicService == null) return;
    final artUri = musicService.buildArtworkUri(artHash, variant: 'thumb_400');
    if (artUri == null) return;
    try {
      final resp = await _apiHttpClient.get(artUri);
      if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) return;
      final decoded = await HermesWindowBridge.decodeArtworkBgra(
        resp.bodyBytes,
      );
      if (decoded == null || !mounted) return;
      if (_flyoutArtCache.length >= 24) {
        _flyoutArtCache.remove(_flyoutArtCache.keys.first);
      }
      _flyoutArtCache[artHash] = decoded;
      if (_musicCoordinator?.currentSong?.artworkHash == artHash) {
        await _windowBridge.showMediaFlyout(
          HermesMediaFlyoutData(
            title: song.title,
            artist: song.artistName,
            isPlaying: _musicCoordinator?.session?.state == PlaybackState.playing,
            artBgra: decoded.bgra,
            artWidth: decoded.width,
            artHeight: decoded.height,
          ),
        );
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _lifecycleListener?.dispose();
    if (_windowBridge.onTrayAction == _handleDesktopTrayAction) {
      _windowBridge.onTrayAction = null;
    }
    if (_windowBridge.onFlyoutAction == _handleDesktopFlyoutAction) {
      _windowBridge.onFlyoutAction = null;
    }
    if (_windowBridge.onAppCommand == _handleDesktopAppCommand) {
      _windowBridge.onAppCommand = null;
    }
    _worldNotifier.removeListener(_onShellNavChanged);
    _musicNav.currentRouteNotifier.removeListener(_onShellNavChanged);
    _cinemaNav.mobileTabNotifier.removeListener(_onShellNavChanged);
    unawaited(_stopSyncClient());
    unawaited(_watchProgressController.close());
    _worldNotifier.dispose();
    _musicNav.dispose();
    _cinemaNav.dispose();
    _connectDevicesNotifier.dispose();
    _musicCoordinator?.removeListener(_syncWindowTrackChrome);
    _musicCoordinator?.dispose();
    final audioEngine = _audioEngine;
    if (_ownsAudioEngine && audioEngine is MediaKitAudioEngineAdapter) {
      unawaited(audioEngine.dispose());
    }
    final mediaBridge = _mediaBridge;
    if (_ownsMediaBridge && mediaBridge is DisposableMediaBridge) {
      unawaited(mediaBridge.dispose());
    }
    if (_ownsHttpClient) {
      _rawHttpClient.close();
    }
    super.dispose();
  }

  Future<void> _shutdownLocalPlayback() async {
    final coordinator = _musicCoordinator;
    if (coordinator != null) {
      await coordinator.stopLocalForShutdown();
      return;
    }
    try {
      await _audioEngine.stop();
    } catch (_) {}
    try {
      await _mediaBridge.clearState();
    } catch (_) {}
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
    final isDesktop = MediaQuery.sizeOf(ctx).width >= 840;
    void refreshDevicesInBackground() {
      unawaited(() async {
        try {
          final devices = await (coordinator.transport?.getOnlineDevices() ??
              musicService.getOnlineDevices());
          if (!mounted) return;
          setState(() {
            _connectDevices = devices;
          });
          _connectDevicesNotifier.value = devices;
        } catch (_) {
          // Keep cached devices on transient network errors.
        }
      }());
    }

    if (isDesktop) {
      final opening = !_connectPopoverOpen;
      setState(() {
        _connectPopoverOpen = opening;
      });
      if (opening) {
        refreshDevicesInBackground();
      }
      return;
    }

    refreshDevicesInBackground();
    await showModalBottomSheet<void>(
      context: ctx,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: ValueListenableBuilder<List<OnlineDeviceModel>>(
            valueListenable: _connectDevicesNotifier,
            builder: (context, devices, _) => AnimatedBuilder(
              animation: coordinator,
              builder: (context, _) {
                final activeId = coordinator.session?.activeRendererDeviceId;
                final activeName = devices
                    .where((d) => d.deviceId == activeId)
                    .firstOrNull
                    ?.deviceName;
                return DevicePickerSheet(
                  devices: devices,
                  activeRendererDeviceId: activeId,
                  localDeviceId: session.deviceId,
                  volume: coordinator.effectiveVolume,
                  volumeTargetLabel: coordinator.isControllingRemoteDevice
                      ? (activeName != null
                          ? 'Volume · $activeName'
                          : 'Remote device volume')
                      : 'Volume · This device',
                  onVolumeChanged: (v) => unawaited(
                    coordinator.setVolume(v, immediate: false),
                  ),
                  onVolumeChangeEnd: (v) => unawaited(
                    coordinator.setVolume(v, immediate: true),
                  ),
                  onToggleMute: () => unawaited(coordinator.toggleMute()),
                  onSelectDevice: (id) {
                    Navigator.of(sheetCtx).pop();
                    unawaited(coordinator.transferOutputTo(id));
                  },
                );
              },
            ),
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
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => FractionallySizedBox(
        heightFactor: 0.96,
        child: MobileNowPlayingPage(
          coordinator: coordinator,
          musicService: musicService,
          localDeviceId: session.deviceId,
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
      onProgressHeartbeat: (posMs) => syncClient.reportProgress(posMs),
      onExternalMediaCommand: (_) => unawaited(_triggerMediaFlyout()),
    );

    coordinator.updateQualityPolicy(_devicePrefs.toAudioQualityPolicy());
    unawaited(coordinator.setNormalizationEnabled(_accountPrefs.normalizeVolume));

    _syncClient = syncClient;
    _syncSessionSub = syncClient.sessionStream.listen((remoteState) {
      if (!mounted || _musicCoordinator != coordinator) return;
      unawaited(coordinator.applyServerSession(remoteState));
    });
    _syncDevicesSub = syncClient.devicesStream.listen((devices) {
      if (!mounted || _syncClient != syncClient) return;
      _connectDevicesNotifier.value = devices;
      setState(() {
        _connectDevices = devices;
      });
    });
    _syncWatchProgressSub = syncClient.watchProgressStream.listen((event) {
      if (!_watchProgressController.isClosed) {
        _watchProgressController.add(event);
      }
    });

    _cinemaService = null;
    _adminService = null;
    _connectDevicesNotifier.value = const [];

    setState(() {
      _musicCoordinator?.removeListener(_syncWindowTrackChrome);
      _musicCoordinator?.dispose();
      _bootstrapping = false;
      _session = nextSession;
      _endpoint = nextEndpoint;
      _serverNameOverride = null;
      _initialPrimaryUrl = nextSession.serverPrimaryUrl;
      _initialLanUrl = nextSession.serverLanFallbackUrl ?? '';
      _switchingServer = false;
      _connectDevices = const [];
      _musicService = musicService;
      _musicCoordinator = coordinator;
      _musicCoordinator?.addListener(_syncWindowTrackChrome);
    });
    _syncWindowTrackChrome();

    syncClient.start();
    unawaited(_loadAccountPreferences(nextSession, nextEndpoint));
    unawaited(_preloadMusicCatalog(musicService, coordinator));
  }

  Future<void> _preloadMusicCatalog(
    MusicService musicService,
    MusicPlaybackCoordinator coordinator,
  ) async {
    try {
      final songs = await musicService.listSongs();
      if (!mounted || _musicCoordinator != coordinator) return;
      coordinator.indexSongs(songs, notify: false);
    } catch (_) {
      // Lazy fallback in MusicPlaybackCoordinator loads on demand if needed.
    }
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
      unawaited(
        _musicCoordinator?.setNormalizationEnabled(prefs.normalizeVolume) ??
            Future<void>.value(),
      );
    } catch (_) {
      // Keep defaults when server is offline or preferences endpoint is unavailable.
    }
  }

  Future<void> _syncAccountPreferences(HermesAccountPreferences next) async {
    setState(() {
      _accountPrefs = next;
    });
    unawaited(
      _musicCoordinator?.setNormalizationEnabled(next.normalizeVolume) ??
          Future<void>.value(),
    );
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
      client: _apiHttpClient,
    );
  }

  Future<void> _signOut() async {
    if (_signingOut) return;
    _signingOut = true;
    try {
      await _stopSyncClient();
      await _authService.signOut();
      unawaited(_audioEngine.stop());
      unawaited(_mediaBridge.clearState());
      _musicCoordinator?.removeListener(_syncWindowTrackChrome);
      _musicCoordinator?.dispose();
      _cinemaService = null;
      _adminService = null;
      _connectDevicesNotifier.value = const [];
      if (!mounted) return;
      setState(() {
        _session = null;
        _serverNameOverride = null;
        _switchingServer = false;
        _connectPopoverOpen = false;
        _connectDevices = const [];
        _musicCoordinator = null;
        _musicService = null;
        _accountPrefs = const HermesAccountPreferences();
      });
      _syncWindowTrackChrome();
    } finally {
      _signingOut = false;
    }
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
        searchHistoryStore: _searchHistoryStore,
        onOpenMusicRoute: _openMusicRoute,
      ),
    );
  }

  final SearchHistoryStore _searchHistoryStore = SharedPrefsSearchHistoryStore();

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final endpoint = _endpoint;
    final musicService = _musicService;
    final musicCoordinator = _musicCoordinator;

    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Hermes',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const _HermesScrollBehavior(),
      theme: _tokens.toThemeData(),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final suppressDesktopTooltips =
            !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
        // Disable Material Tooltip OverlayPortal mounting on Windows desktop to
        // prevent Flutter #182444 AXTree desync across scrolling/hovering UIs.
        Widget appBody = TooltipVisibility(
          visible: !suppressDesktopTooltips,
          child: child ?? const SizedBox.shrink(),
        );
        if (_showDesktopTitleBar) {
          appBody = ValueListenableBuilder<bool>(
            valueListenable: _windowBridge.isFullscreen,
            builder: (context, isFullscreen, body) {
              final bodyChild = body ?? const SizedBox.shrink();
              if (isFullscreen) {
                return bodyChild;
              }
              return Column(
                children: [
                  HermesDesktopTitleBar(
                    bridge: _windowBridge,
                    onOpenShortcuts: () {
                      final navCtx = _navigatorKey.currentContext;
                      if (navCtx != null) {
                        unawaited(showHermesKeyboardShortcutsDialog(navCtx));
                      }
                    },
                  ),
                  Expanded(child: bodyChild),
                ],
              );
            },
            child: appBody,
          );
        }
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(_devicePrefs.textSize.scaleFactor),
            disableAnimations: _devicePrefs.reduceMotion,
          ),
          child: appBody,
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
                    final cinemaService = _cinemaService ??= CinemaService(
                      baseUri: endpoint.baseUri,
                      accessToken: session.accessToken,
                      httpClient: _apiHttpClient,
                    );
                    final adminService = _adminService ??= AdminService(
                      baseUri: endpoint.baseUri,
                      accessToken: session.accessToken,
                      httpClient: _apiHttpClient,
                    );
                    final playerConfig = HermesVideoPlayerConfig.hdrSafeDefault(
                      tokens: _tokens,
                      rendererBackend: _rendererBackend,
                    );
                    final activeContentWorld =
                        (_worldNotifier.value == HermesWorld.music ||
                                _worldNotifier.value == HermesWorld.cinema)
                            ? _worldNotifier.value
                            : _lastContentWorld;
                    final activeMobileTabIndex =
                        activeContentWorld == HermesWorld.music
                            ? switch (_musicNav.currentRouteNotifier.value.kind) {
                                MusicPageKind.home => 0,
                                MusicPageKind.search => 1,
                                _ => 2,
                              }
                            : _cinemaNav.mobileTabNotifier.value.index;

                    return DualWorldShell(
                      worldNotifier: _worldNotifier,
                      initialWorld: _isMobileStartup
                          ? HermesWorld.music
                          : HermesWorld.cinema,
                      activeMobileTabIndex: activeMobileTabIndex,
                      onSelectMobileTab: (idx) {
                        if (activeContentWorld == HermesWorld.music) {
                          final target = switch (idx) {
                            0 => const MusicPageRoute.home(),
                            1 => const MusicPageRoute.search(),
                            _ => const MusicPageRoute.library(),
                          };
                          _musicNav.navigate(target);
                        } else {
                          final tab = CinemaMobileTab
                              .values[idx.clamp(0, CinemaMobileTab.values.length - 1)];
                          _cinemaNav.selectMobileTab(tab);
                        }
                      },
                      onHandleBack: () {
                        if (activeContentWorld == HermesWorld.music) {
                          return _musicNav.handleBack();
                        }
                        return _cinemaNav.handleBack();
                      },
                      onHandleForward: () {
                        if (activeContentWorld == HermesWorld.music) {
                          return _musicNav.handleForward();
                        }
                        return false;
                      },
                      onToggleFullscreen: () => unawaited(
                        _windowBridge.setFullscreen(
                          !_windowBridge.isFullscreen.value,
                        ),
                      ),
                      onOpenShortcuts: () => unawaited(
                        showHermesKeyboardShortcutsDialog(navContext),
                      ),
                      onMediaKeyAction: (_) =>
                          unawaited(_triggerMediaFlyout()),
                      username: session.username,
                      isAdmin: session.isAdmin,
                      serverName: _serverNameOverride ?? endpoint.info.serverName,
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
                      onTogglePlayPause: () =>
                          unawaited(musicCoordinator.togglePlayPause()),
                      onNextTrack: () => unawaited(musicCoordinator.skipNext()),
                      onPreviousTrack: () =>
                          unawaited(musicCoordinator.skipPrevious()),
                      onToggleMute: () =>
                          unawaited(musicCoordinator.toggleMute()),
                      adminBuilder: (_) => AdminDashboardScreen(
                        adminService: adminService,
                        onServerNameChanged: (name) =>
                            setState(() => _serverNameOverride = name),
                      ),
                      settingsBuilder: (_) => PlayerAndThemeSettingsScreen(
                        tokens: _tokens,
                        rendererBackend: _rendererBackend,
                        defaultVideoQuality: _defaultVideoQuality,
                        audioQualityPolicy: musicCoordinator.audioQualityPolicy,
                        devicePreferences: _devicePrefs,
                        accountPreferences: _accountPrefs,
                        username: session.username,
                        deviceName: kIsWeb
                            ? 'Web Browser'
                            : switch (defaultTargetPlatform) {
                                TargetPlatform.android => 'Android Phone',
                                TargetPlatform.iOS => 'iPhone',
                                _ => Platform.localHostname,
                              },
                        initialTab: _settingsInitialTab,
                        onThemeChanged: (next) => setState(() => _tokens = next),
                        onRendererChanged: (next) =>
                            setState(() => _rendererBackend = next),
                        onDefaultVideoQualityChanged: (next) =>
                            setState(() => _defaultVideoQuality = next),
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
                        cacheManager: _cacheManager,
                        onClearCatalogCaches: () {
                          musicService.clearCache();
                          cinemaService.clearCache();
                        },
                      ),
                  cinemaBuilder: (_) => CinemaCatalogScreen(
                    cinemaService: cinemaService,
                    playerConfig: playerConfig,
                    defaultQuality: _defaultVideoQuality,
                    accountPreferences: _accountPrefs,
                    reduceMotion: _devicePrefs.reduceMotion,
                    watchProgressUpdates: _watchProgressController.stream,
                    navigationController: _cinemaNav,
                    searchHistoryStore: _searchHistoryStore,
                    externalMobileNav: true,
                    onBeforeStartVideo: () =>
                        unawaited(musicCoordinator.pauseIfPlaying()),
                  ),
                  musicBuilder: (_) => MusicWorldScreen(
                    musicService: musicService,
                    coordinator: musicCoordinator,
                    navigationController: _musicNav,
                    searchHistoryStore: _searchHistoryStore,
                    reduceMotion: _devicePrefs.reduceMotion,
                    externalMobileNav: true,
                  ),
                  sidePanelBuilder: (_) => AnimatedBuilder(
                    animation: musicCoordinator,
                    child: NowPlayingPanel(
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
                    ),
                    builder: (context, child) {
                      if (!musicCoordinator.nowPlayingOpen ||
                          musicCoordinator.currentSong == null) {
                        return const SizedBox.shrink();
                      }
                      return child!;
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
                            builder: (context, _) {
                              final activeId = musicCoordinator
                                  .session?.activeRendererDeviceId;
                              final activeName = _connectDevices
                                  .where((d) => d.deviceId == activeId)
                                  .firstOrNull
                                  ?.deviceName;
                              return DevicePickerSheet(
                                devices: _connectDevices,
                                activeRendererDeviceId: activeId,
                                localDeviceId: session.deviceId,
                                volume: musicCoordinator.effectiveVolume,
                                volumeTargetLabel:
                                    musicCoordinator.isControllingRemoteDevice
                                        ? (activeName != null
                                            ? 'Volume · $activeName'
                                            : 'Remote device volume')
                                        : 'Volume · This device',
                                onVolumeChanged: (v) => unawaited(
                                  musicCoordinator.setVolume(
                                    v,
                                    immediate: false,
                                  ),
                                ),
                                onVolumeChangeEnd: (v) => unawaited(
                                  musicCoordinator.setVolume(
                                    v,
                                    immediate: true,
                                  ),
                                ),
                                onToggleMute: () =>
                                    unawaited(musicCoordinator.toggleMute()),
                                onSelectDevice: (id) {
                                  setState(() => _connectPopoverOpen = false);
                                  unawaited(
                                    musicCoordinator.transferOutputTo(id),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                  miniPlayerBuilder: (ctx) => AnimatedBuilder(
                    animation: musicCoordinator,
                    builder: (context, _) {
                      final activeId =
                          musicCoordinator.session?.activeRendererDeviceId;
                      final remoteDeviceName =
                          musicCoordinator.isControllingRemoteDevice
                              ? (_connectDevices
                                      .where((d) => d.deviceId == activeId)
                                      .firstOrNull
                                      ?.deviceName ??
                                  'Remote device')
                              : null;
                      return MiniPlayerBar(
                        session: musicCoordinator.session,
                        currentSong: musicCoordinator.currentSong,
                      localDeviceId: session.deviceId,
                      artworkUri: musicService.buildArtworkUri(
                        musicCoordinator.currentSong?.artworkHash,
                      ),
                      nowPlayingOpen: musicCoordinator.nowPlayingOpen,
                      positionMs: musicCoordinator.currentPositionMs,
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
                      volumeOverride: musicCoordinator.effectiveVolume,
                      remoteDeviceName: remoteDeviceName,
                      onVolumeChanged: (v) => unawaited(
                        musicCoordinator.setVolume(v, immediate: false),
                      ),
                      onVolumeChangeEnd: (v) => unawaited(
                        musicCoordinator.setVolume(v, immediate: true),
                      ),
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
                    );
                  },
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
    required this.searchHistoryStore,
    required this.onOpenMusicRoute,
  });

  final MusicService musicService;
  final MusicPlaybackCoordinator musicCoordinator;
  final SearchHistoryStore searchHistoryStore;
  final ValueChanged<MusicPageRoute> onOpenMusicRoute;

  @override
  State<_LibrarySearchDialog> createState() => _LibrarySearchDialogState();
}

class _LibrarySearchDialogState extends State<_LibrarySearchDialog> {
  final TextEditingController _queryController = TextEditingController();
  UnifiedSearchResult? _result;
  List<MusicSearchHistoryItem> _recent = const [];
  bool _searching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRecent());
  }

  Future<void> _loadRecent() async {
    final loaded = await widget.searchHistoryStore.loadMusicHistory();
    if (!mounted) return;
    setState(() => _recent = loaded);
  }

  Future<void> _record(MusicSearchHistoryItem item) async {
    final updated = await widget.searchHistoryStore.addMusicItem(item);
    if (!mounted) return;
    setState(() => _recent = updated);
  }

  Future<void> _removeRecent(String id) async {
    final updated = await widget.searchHistoryStore.removeMusicItem(id);
    if (!mounted) return;
    setState(() => _recent = updated);
  }

  Future<void> _clearRecent() async {
    await widget.searchHistoryStore.clearMusicHistory();
    if (!mounted) return;
    setState(() => _recent = const []);
  }

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
      unawaited(
        _record(
          MusicSearchHistoryItem(
            id: 'query:${q.toLowerCase()}',
            kind: MusicSearchHistoryKind.query,
            title: q,
            subtitle: 'Search',
            timestampMs: DateTime.now().millisecondsSinceEpoch,
          ),
        ),
      );
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
                          ? (_recent.isEmpty
                              ? const Center(
                                  child: Text(
                                    'Enter a title, artist, album, or song to search.',
                                  ),
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        const Expanded(
                                          child: Text(
                                            'Recent searches',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              unawaited(_clearRecent()),
                                          child: const Text('Clear'),
                                        ),
                                      ],
                                    ),
                                    Expanded(
                                      child: ListView(
                                        children: [
                                          for (final item in _recent)
                                            ListTile(
                                              leading: item.kind ==
                                                      MusicSearchHistoryKind.query
                                                  ? const CircleAvatar(
                                                      radius: 20,
                                                      child: Icon(
                                                        Icons.history_rounded,
                                                        size: 18,
                                                      ),
                                                    )
                                                  : HermesArtworkImage(
                                                      uri: widget.musicService
                                                          .buildArtworkUri(
                                                        item.artworkHash,
                                                      ),
                                                      fallbackTitle: item.title,
                                                      fallbackIcon: Icons
                                                          .music_note_outlined,
                                                      width: 40,
                                                      height: 40,
                                                      showFallbackLabel: false,
                                                    ),
                                              title: Text(item.title),
                                              subtitle: Text(item.subtitle),
                                              trailing: IconButton(
                                                tooltip: 'Remove',
                                                icon: const Icon(
                                                  Icons.close_rounded,
                                                  size: 18,
                                                ),
                                                onPressed: () => unawaited(
                                                  _removeRecent(item.id),
                                                ),
                                              ),
                                              onTap: () {
                                                _queryController.text =
                                                    item.title;
                                                if (item.kind ==
                                                        MusicSearchHistoryKind
                                                            .album &&
                                                    item.targetId != null) {
                                                  Navigator.of(context).pop();
                                                  widget.onOpenMusicRoute(
                                                    MusicPageRoute.album(
                                                      item.targetId!,
                                                    ),
                                                  );
                                                } else if (item.kind ==
                                                        MusicSearchHistoryKind
                                                            .artist &&
                                                    item.targetId != null) {
                                                  Navigator.of(context).pop();
                                                  widget.onOpenMusicRoute(
                                                    MusicPageRoute.artist(
                                                      item.targetId!,
                                                    ),
                                                  );
                                                } else if (item.kind ==
                                                        MusicSearchHistoryKind
                                                            .playlist &&
                                                    item.targetId != null) {
                                                  Navigator.of(context).pop();
                                                  widget.onOpenMusicRoute(
                                                    MusicPageRoute.playlist(
                                                      item.targetId!,
                                                    ),
                                                  );
                                                } else {
                                                  unawaited(_runSearch());
                                                }
                                              },
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ))
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
                                          unawaited(
                                            _record(
                                              MusicSearchHistoryItem(
                                                id: 'album:${album.id}',
                                                kind: MusicSearchHistoryKind
                                                    .album,
                                                title: album.title,
                                                subtitle:
                                                    'Album • ${album.artistName}',
                                                artworkHash: album.artworkHash,
                                                targetId: album.id,
                                                timestampMs: DateTime.now()
                                                    .millisecondsSinceEpoch,
                                              ),
                                            ),
                                          );
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
                                          unawaited(
                                            _record(
                                              MusicSearchHistoryItem(
                                                id: 'song:${song.id}',
                                                kind: MusicSearchHistoryKind
                                                    .song,
                                                title: song.title,
                                                subtitle:
                                                    'Song • ${song.artistName}',
                                                artworkHash: song.artworkHash,
                                                targetId: song.id,
                                                timestampMs: DateTime.now()
                                                    .millisecondsSinceEpoch,
                                              ),
                                            ),
                                          );
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
