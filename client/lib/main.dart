import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'src/core/auth/auth_service.dart';
import 'src/core/auth/session_store.dart';
import 'src/core/network/endpoint_resolver.dart';
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
                  onOpenSearch: () => unawaited(
                    _openLibrarySearchDialog(navContext, musicService, musicCoordinator),
                  ),
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
                          networkMode: musicCoordinator.networkMode,
                          audioQualityPolicy: musicCoordinator.audioQualityPolicy,
                          onThemeChanged: (next) => setState(() => _tokens = next),
                          onRendererChanged: (next) => setState(() => _rendererBackend = next),
                          onDefaultVideoQualityChanged: (next) =>
                              setState(() => _defaultVideoQuality = next),
                          onNetworkModeChanged: musicCoordinator.setNetworkMode,
                          onAudioQualityPolicyChanged: musicCoordinator.updateQualityPolicy,
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
                      artworkUri: musicService.buildArtworkUri(
                        musicCoordinator.currentSong?.artworkHash,
                      ),
                      onTogglePlayPause: () => unawaited(musicCoordinator.togglePlayPause()),
                      onSkipNext: () => unawaited(musicCoordinator.skipNext()),
                      onSkipPrevious: () => unawaited(musicCoordinator.skipPrevious()),
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
