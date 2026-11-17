import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'src/core/auth/auth_service.dart';
import 'src/core/auth/session_store.dart';
import 'src/core/network/endpoint_resolver.dart';
import 'src/core/settings/hermes_preferences.dart';
import 'src/core/theme/hermes_theme_tokens.dart';
import 'src/core/widgets/hermes_artwork_image.dart';
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

  late final _accountPreferencesService =
      AccountPreferencesService(httpClient: _httpClient);

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

  @override
  void dispose() {
    _worldNotifier.dispose();
    _musicCoordinator?.dispose();
    _httpClient.close();
    super.dispose();
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
    List<OnlineDeviceModel> devices = const [];
    try {
      devices = await musicService.getOnlineDevices();
    } catch (_) {
      devices = const [];
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

    coordinator.updateQualityPolicy(_devicePrefs.toAudioQualityPolicy());

    setState(() {
      _musicCoordinator?.dispose();
      _session = nextSession;
      _endpoint = nextEndpoint;
      _switchingServer = false;
      _musicService = musicService;
      _musicCoordinator = coordinator;
    });

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
    await _authService.signOut();
    _musicCoordinator?.dispose();
    if (!mounted) return;
    setState(() {
      _session = null;
      _switchingServer = false;
      _musicCoordinator = null;
      _musicService = null;
      _accountPrefs = const HermesAccountPreferences();
    });
  }

  Future<void> _openLibrarySearchDialog(
    BuildContext navContext,
    MusicService musicService,
    MusicPlaybackCoordinator musicCoordinator,
  ) async {
    final queryController = TextEditingController();
    UnifiedSearchResult? result;
    var searching = false;
    String? error;

    await showDialog<void>(
      context: navContext,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> runSearch() async {
            final q = queryController.text.trim();
            if (q.isEmpty) {
              setDialogState(() {
                result = null;
                error = null;
              });
              return;
            }
            setDialogState(() {
              searching = true;
              error = null;
            });
            try {
              final next = await musicService.searchLibrary(q);
              if (!ctx.mounted) {
                return;
              }
              setDialogState(() {
                result = next;
                searching = false;
              });
            } catch (e) {
              if (!ctx.mounted) {
                return;
              }
              setDialogState(() {
                error = e.toString();
                searching = false;
              });
            }
          }

          return AlertDialog(
            title: const Text('Search Hermes Library'),
            content: SizedBox(
              width: 560,
              height: 420,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: queryController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Search movies, TV series, artists, albums, songs...',
                      suffixIcon: IconButton(
                        tooltip: 'Search',
                        icon: const Icon(Icons.search),
                        onPressed: runSearch,
                      ),
                    ),
                    onSubmitted: (_) => unawaited(runSearch()),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: searching
                        ? const Center(child: CircularProgressIndicator())
                        : error != null
                            ? Text('Search failed: $error')
                            : result == null
                                ? const Center(
                                    child: Text('Enter a title, artist, album, or song to search.'),
                                  )
                                : result!.isEmpty
                                    ? const Center(child: Text('No matches found.'))
                                    : ListView(
                                        children: [
                                          for (final movie in result!.movies)
                                            ListTile(
                                              leading: HermesArtworkImage(
                                                uri: musicService.buildArtworkUri(movie.artworkHash),
                                                fallbackTitle: movie.title,
                                                fallbackIcon: Icons.movie_outlined,
                                                width: 40,
                                                height: 54,
                                                showFallbackLabel: false,
                                              ),
                                              title: Text(movie.title),
                                              subtitle: Text(movie.year == null ? 'Movie' : 'Movie • ${movie.year}'),
                                              onTap: () => Navigator.of(ctx).pop(),
                                            ),
                                          for (final show in result!.series)
                                            ListTile(
                                              leading: HermesArtworkImage(
                                                uri: musicService.buildArtworkUri(show.artworkHash),
                                                fallbackTitle: show.title,
                                                fallbackIcon: Icons.tv_outlined,
                                                width: 40,
                                                height: 54,
                                                showFallbackLabel: false,
                                              ),
                                              title: Text(show.title),
                                              subtitle: Text(show.year == null ? 'TV Series' : 'TV Series • ${show.year}'),
                                              onTap: () => Navigator.of(ctx).pop(),
                                            ),
                                          for (final album in result!.albums)
                                            ListTile(
                                              leading: HermesArtworkImage(
                                                uri: musicService.buildArtworkUri(album.artworkHash),
                                                fallbackTitle: album.title,
                                                fallbackIcon: Icons.album_outlined,
                                                width: 44,
                                                height: 44,
                                                showFallbackLabel: false,
                                              ),
                                              title: Text(album.title),
                                              subtitle: Text('Album • ${album.artistName}'),
                                              onTap: () => Navigator.of(ctx).pop(),
                                            ),
                                          for (final song in result!.songs)
                                            ListTile(
                                              leading: HermesArtworkImage(
                                                uri: musicService.buildArtworkUri(song.artworkHash),
                                                fallbackTitle: song.albumTitle,
                                                fallbackIcon: Icons.music_note_outlined,
                                                width: 44,
                                                height: 44,
                                                showFallbackLabel: false,
                                              ),
                                              title: Text(song.title),
                                              subtitle: Text('Song • ${song.artistName}'),
                                              onTap: () {
                                                Navigator.of(ctx).pop();
                                                unawaited(musicCoordinator.startQueue([song], 0));
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
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );

    queryController.dispose();
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
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(_devicePrefs.textSize.scaleFactor),
            disableAnimations: _devicePrefs.reduceMotion,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: _switchingServer ||
              session == null ||
              endpoint == null ||
              musicService == null ||
              musicCoordinator == null
          ? SetupAndLoginScreen(
              endpointResolver: _endpointResolver,
              authService: _authService,
              deviceId: 'hermes-${Platform.operatingSystem}',
              deviceName: Platform.localHostname,
              initialPrimaryUrl: endpoint?.baseUri.toString() ?? 'http://localhost:5000',
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
                    deviceName: Platform.localHostname,
                    initialTab: _settingsInitialTab,
                    onThemeChanged: (next) => setState(() => _tokens = next),
                    onRendererChanged: (next) =>
                        setState(() => _rendererBackend = next),
                    onDefaultVideoQualityChanged: (next) =>
                        setState(() => _defaultVideoQuality = next),
                    onNetworkModeChanged: musicCoordinator.setNetworkMode,
                    onAudioQualityPolicyChanged: musicCoordinator.updateQualityPolicy,
                    onDevicePreferencesChanged: (next) {
                      setState(() {
                        _devicePrefs = next;
                        _tokens = next.toThemeTokens();
                        _rendererBackend = next.rendererBackend;
                        _defaultVideoQuality = next.defaultVideoQuality;
                      });
                    },
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
