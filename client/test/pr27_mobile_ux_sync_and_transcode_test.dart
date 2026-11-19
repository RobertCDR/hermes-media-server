import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_client/src/core/theme/hermes_theme_tokens.dart';
import 'package:hermes_client/src/features/admin/admin_dashboard_screen.dart';
import 'package:hermes_client/src/features/admin/admin_service.dart';
import 'package:hermes_client/src/features/cinema/cinema_models.dart';
import 'package:hermes_client/src/features/cinema/cinema_service.dart';
import 'package:hermes_client/src/features/cinema/hermes_video_playback_controller.dart';
import 'package:hermes_client/src/features/cinema/hermes_video_player.dart';
import 'package:hermes_client/src/features/music/mini_player_bar.dart';
import 'package:hermes_client/src/features/music/music_models.dart';
import 'package:hermes_client/src/features/music/music_playback_coordinator.dart';
import 'package:hermes_client/src/features/music/music_service.dart';
import 'package:hermes_client/src/features/music/music_shared_widgets.dart';
import 'package:hermes_client/src/features/music/now_playing_panel.dart';
import 'package:hermes_client/src/features/music/platform_media_bridge.dart';
import 'package:hermes_client/src/features/settings/player_and_theme_settings_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

class _RecordingAudioEngine implements AudioEngineAdapter {
  int loadCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;
  final List<int> seekCalls = [];

  @override
  Future<void> loadAndPlay(
    Uri streamUri,
    SongModel track,
    int startPositionMs,
  ) async {
    loadCalls++;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
  }

  @override
  Future<void> seek(int positionMs) async {
    seekCalls.add(positionMs);
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }
}

class _FakeConnectTransport implements ConnectTransport {
  _FakeConnectTransport(this._songs)
      : _queueIds = _songs.map((s) => s.id).toList();

  final List<SongModel> _songs;
  int _version = 1;
  PlaybackState _state = PlaybackState.playing;
  HermesRepeatMode _repeat = HermesRepeatMode.off;
  bool _shuffle = false;
  int _index = 0;
  int _positionMs = 0;
  List<String> _queueIds;

  PlaybackSessionState _snapshot() => PlaybackSessionState(
        sessionId: 'sess-pr27',
        version: _version,
        activeRendererDeviceId: 'dev-phone',
        activeRendererDeviceName: 'Honor Phone',
        state: _state,
        repeatMode: _repeat,
        shuffle: _shuffle,
        volume: 1.0,
        currentIndex: _index,
        currentSongId: _queueIds.isEmpty
            ? _songs[_index % _songs.length].id
            : _queueIds[_index.clamp(0, _queueIds.length - 1)],
        positionMs: _positionMs,
        queueSongIds: List<String>.from(_queueIds),
      );

  @override
  Future<List<OnlineDeviceModel>> getOnlineDevices() async => const [];

  @override
  Future<PlaybackSessionState> startPlayback(
    List<String> queueSongIds,
    int startIndex,
  ) async {
    _version++;
    _queueIds = List<String>.from(queueSongIds);
    _index = startIndex;
    _state = PlaybackState.playing;
    _positionMs = 0;
    return _snapshot();
  }

  @override
  Future<PlaybackSessionState> sendTransport(
    PlaybackState state, {
    int? currentIndex,
    int? positionMs,
    HermesRepeatMode? repeatMode,
    bool? shuffle,
    double? volume,
    List<String>? queueSongIds,
  }) async {
    _version++;
    _state = state;
    if (queueSongIds != null) _queueIds = List<String>.from(queueSongIds);
    if (currentIndex != null) _index = currentIndex;
    if (positionMs != null) _positionMs = positionMs;
    if (repeatMode != null) _repeat = repeatMode;
    if (shuffle != null) _shuffle = shuffle;
    return _snapshot();
  }

  @override
  Future<PlaybackSessionState> transferOutput(
    String targetDeviceId, {
    int? positionMs,
  }) async {
    _version++;
    if (positionMs != null) _positionMs = positionMs;
    return _snapshot();
  }
}

class _Pr27VideoPlaybackController implements HermesVideoPlaybackController {
  final positionController = StreamController<int>.broadcast();
  final durationController = StreamController<int>.broadcast();
  final playingController = StreamController<bool>.broadcast();
  final bufferingController = StreamController<bool>.broadcast();
  final completedController = StreamController<bool>.broadcast();
  final subtitleLinesController = StreamController<List<String>>.broadcast();
  final errorController = StreamController<String>.broadcast();

  final List<Uri> openedUris = [];
  final List<int> audioSelections = [];
  final List<double> subtitleDelays = [];

  @override
  bool get hasVideoOutput => true;

  @override
  Stream<int> get positionMsStream => positionController.stream;

  @override
  Stream<int> get durationMsStream => durationController.stream;

  @override
  Stream<bool> get playingStream => playingController.stream;

  @override
  Stream<bool> get bufferingStream => bufferingController.stream;

  @override
  Stream<bool> get completedStream => completedController.stream;

  @override
  Stream<List<String>> get subtitleLinesStream => subtitleLinesController.stream;

  @override
  Stream<String> get errorStream => errorController.stream;

  @override
  Future<void> open(
    Uri streamUri, {
    int startPositionMs = 0,
    Uri? subtitleUri,
    String? subtitleTitle,
    String? subtitleLanguage,
    bool autoPlay = true,
  }) async {
    openedUris.add(streamUri);
    playingController.add(autoPlay);
  }

  @override
  Future<void> setExternalSubtitle(
    Uri? subtitleUri, {
    String? title,
    String? language,
  }) async {}

  @override
  Future<void> selectEmbeddedAudioTrack({
    required int streamIndex,
    required List<MediaStreamModel> availableAudioStreams,
  }) async {
    audioSelections.add(streamIndex);
  }

  @override
  Future<void> setSubtitleDelaySeconds(double seconds) async {
    subtitleDelays.add(seconds);
  }

  @override
  Future<void> play() async => playingController.add(true);

  @override
  Future<void> pause() async => playingController.add(false);

  @override
  Future<void> seek(int positionMs) async => positionController.add(positionMs);

  @override
  Future<void> setVolume(double volume0to100) async {}

  @override
  Future<void> stop() async => playingController.add(false);

  @override
  Widget buildVideoSurface(BuildContext context) => const SizedBox.expand(
        key: Key('pr27-video-surface'),
      );

  @override
  Future<void> dispose() async {
    await positionController.close();
    await durationController.close();
    await playingController.close();
    await bufferingController.close();
    await completedController.close();
    await subtitleLinesController.close();
    await errorController.close();
  }
}

SongModel _song(String id, String title, {String artist = 'Daft Punk'}) =>
    SongModel(
      id: id,
      artistId: 'art-1',
      artistName: artist,
      albumId: 'alb-1',
      albumTitle: 'Discovery',
      title: title,
      trackNumber: 1,
      discNumber: 1,
      durationMs: 240000,
      codec: 'flac',
      bitrateBps: 1411000,
      sampleRateHz: 44100,
      bitDepth: 16,
      isLiked: false,
      isMissing: false,
    );

MusicService _buildMusicService({Set<String>? likedIds}) {
  final liked = likedIds ?? <String>{};
  return MusicService(
    baseUri: Uri.parse('http://localhost:5258'),
    accessToken: 'jwt',
    httpClient: MockClient((req) async {
      if (req.url.path == '/api/v1/auth/stream-tickets') {
        return http.Response(jsonEncode({'ticket': 'tkt-audio'}), 200);
      }
      if (req.url.path == '/api/v1/music/songs/song-1/lyrics') {
        return http.Response(
          jsonEncode({
            'songId': 'song-1',
            'isSynced': true,
            'source': 'sidecar',
            'lines': [
              {'timestampMs': 12000, 'text': 'Music sounds better with you'},
              {'timestampMs': 24000, 'text': 'Feel so right tonight'},
            ],
          }),
          200,
        );
      }
      if (req.url.path.startsWith('/api/v1/music/songs/') &&
          req.url.path.endsWith('/like')) {
        final id = req.url.pathSegments[4];
        if (req.method == 'POST') {
          if (!liked.remove(id)) {
            liked.add(id);
          }
        }
        return http.Response(
          jsonEncode({'songId': id, 'isLiked': liked.contains(id)}),
          200,
        );
      }
      return http.Response('{}', 200);
    }),
  );
}

void main() {
  group('PR27 MobileNowPlayingPage & MiniPlayerBar', () {
    testWidgets(
      'renders Spotify-style mobile player, transport, seek, Queue, and Lyrics views',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final songs = [
          _song('song-1', 'One More Time'),
          _song('song-2', 'Aerodynamic'),
        ];
        final engine = _RecordingAudioEngine();
        final service = _buildMusicService();
        final transport = _FakeConnectTransport(songs);
        final coordinator = MusicPlaybackCoordinator(
          localDeviceId: 'dev-phone',
          musicService: service,
          audioEngine: engine,
          mediaBridge: InMemoryPlatformMediaBridge(),
          transport: transport,
          catalogSongs: {for (final s in songs) s.id: s},
        );
        await coordinator.startQueue(songs, 0, sourceLabel: 'Discovery');
        coordinator.addToQueue(songs[1]);

        var closedCount = 0;
        var openDevicesCount = 0;

        await tester.pumpWidget(
          MaterialApp(
            theme: HermesThemeTokens.resolve().toThemeData(),
            home: Scaffold(
              body: MobileNowPlayingPage(
                coordinator: coordinator,
                musicService: service,
                localDeviceId: 'dev-phone',
                onClose: () => closedCount++,
                onOpenDevices: () => openDevicesCount++,
                onNavigate: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('mobile-now-playing-page')), findsOneWidget);
        expect(find.text('One More Time'), findsOneWidget);
        expect(find.text('Daft Punk'), findsOneWidget);
        expect(find.byKey(const Key('mobile-player-devices')), findsOneWidget);

        // Toggle shuffle, repeat, like, play/pause, and seek
        await tester.tap(find.byKey(const Key('mobile-player-shuffle')));
        await tester.pumpAndSettle();
        expect(coordinator.session?.shuffle, isTrue);

        await tester.tap(find.byKey(const Key('mobile-player-repeat')));
        await tester.pumpAndSettle();
        expect(coordinator.session?.repeatMode, HermesRepeatMode.all);

        await tester.tap(find.byKey(const Key('mobile-player-like')));
        await tester.pumpAndSettle();
        expect(coordinator.currentSong?.isLiked, isTrue);

        await tester.tap(find.byKey(const Key('mobile-player-play-pause')));
        await tester.pumpAndSettle();
        expect(coordinator.session?.state, PlaybackState.paused);

        final slider = tester.widget<Slider>(
          find.byKey(const Key('mobile-player-seek')),
        );
        slider.onChangeEnd?.call(45000);
        await tester.pumpAndSettle();
        expect(engine.seekCalls, contains(45000));

        // Open Devices picker callback
        await tester.tap(find.byKey(const Key('mobile-player-devices')));
        await tester.pumpAndSettle();
        expect(openDevicesCount, 1);

        // Toggle Queue view and remove queued track
        await tester.tap(find.byKey(const Key('mobile-player-queue-toggle')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('mobile-player-queue-view')), findsOneWidget);
        expect(find.text('Aerodynamic'), findsAtLeastNWidgets(1));

        await tester.tap(find.byTooltip('Remove from queue').first);
        await tester.pumpAndSettle();
        expect(coordinator.upNext, isEmpty);

        // Return to player and switch to Lyrics view, then tap synced lyric line
        await tester.tap(find.byKey(const Key('mobile-player-queue-toggle')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('mobile-player-lyrics-toggle')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('mobile-player-lyrics-view')), findsOneWidget);

        await tester.tap(find.text('Music sounds better with you'));
        await tester.pumpAndSettle();
        expect(engine.seekCalls, contains(12000));

        // Close button
        await tester.tap(find.byKey(const Key('mobile-player-close')));
        await tester.pumpAndSettle();
        expect(closedCount, 1);
      },
    );

    testWidgets('mobile MiniPlayerBar tap opens fullscreen player callback', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final song = _song('song-1', 'One More Time');
      final session = PlaybackSessionState(
        sessionId: 'sess-1',
        version: 1,
        activeRendererDeviceId: 'dev-phone',
        activeRendererDeviceName: 'Phone',
        state: PlaybackState.playing,
        repeatMode: HermesRepeatMode.off,
        shuffle: false,
        volume: 1.0,
        currentIndex: 0,
        currentSongId: song.id,
        positionMs: 10000,
        queueSongIds: [song.id],
      );

      var openedNowPlaying = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: HermesThemeTokens.resolve().toThemeData(),
          home: Scaffold(
            body: MiniPlayerBar(
              session: session,
              currentSong: song,
              localDeviceId: 'dev-phone',
              onTogglePlayPause: () {},
              onSkipNext: () {},
              onOpenDevicePicker: () {},
              onToggleNowPlaying: () => openedNowPlaying++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('One More Time'));
      await tester.pumpAndSettle();
      expect(openedNowPlaying, 1);
    });
  });

  group('PR27 Swipe-to-queue on MusicTrackTable', () {
    testWidgets(
      'swiping a track row startToEnd on narrow viewport adds to queue without dismissing row',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(400, 800);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final songs = [
          _song('song-1', 'One More Time'),
          _song('song-2', 'Digital Love'),
        ];
        final engine = _RecordingAudioEngine();
        final service = _buildMusicService();
        final coordinator = MusicPlaybackCoordinator(
          localDeviceId: 'dev-phone',
          musicService: service,
          audioEngine: engine,
          mediaBridge: InMemoryPlatformMediaBridge(),
          transport: _FakeConnectTransport(songs),
          catalogSongs: {for (final s in songs) s.id: s},
        );
        await coordinator.startQueue(songs, 0, sourceLabel: 'Discovery');

        await tester.pumpWidget(
          MaterialApp(
            theme: HermesThemeTokens.resolve().toThemeData(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: MusicTrackTable(
                  songs: songs,
                  musicService: service,
                  coordinator: coordinator,
                  playlists: const [],
                  onPlayTrackAt: (_) {},
                  onToggleLike: (_) {},
                  onNavigate: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(coordinator.upNext, isEmpty);
        await tester.drag(find.text('Digital Love'), const Offset(240, 0));
        await tester.pumpAndSettle();

        expect(coordinator.upNext.map((s) => s.id), contains('song-2'));
        expect(find.text('Digital Love'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('PR27 Mobile Video HUD & Subtitle HTML Tag Sanitization', () {
    testWidgets(
      'strips HTML tags while preserving italic, supports mobile tabbed vp-panel & vp-fullscreen-btn without overflow',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(400, 800);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final client = MockClient((req) async {
          if (req.url.path == '/api/v1/auth/stream-tickets') {
            return http.Response(jsonEncode({'ticket': 'tkt-vid'}), 200);
          }
          return http.Response('{}', 200);
        });
        final cinemaService = CinemaService(
          baseUri: Uri.parse('http://localhost:5258'),
          accessToken: 'jwt',
          httpClient: client,
        );
        final tokens = HermesThemeTokens.resolve();
        const source = MediaSourceModel(
          id: 'src-mov',
          sourceLabel: '1080p BluRay',
          container: 'mkv',
          videoCodec: 'h264',
          audioCodec: 'ac3',
          width: 1920,
          height: 1080,
          isHdr: false,
          bitrateBps: 9000000,
          durationMs: 180000,
          isAvailable: true,
          streams: [
            MediaStreamModel(
              streamIndex: 1,
              kind: 1,
              codec: 'ac3',
              language: 'eng',
              title: 'English 5.1',
              isDefault: true,
            ),
            MediaStreamModel(
              streamIndex: 1000,
              kind: 2,
              codec: 'subrip',
              language: 'rum',
              title: 'Primal.Fear.1996.Romanian.srt',
              isDefault: true,
            ),
          ],
        );

        late _Pr27VideoPlaybackController controller;
        await tester.pumpWidget(
          MaterialApp(
            theme: tokens.toThemeData(),
            home: HermesVideoPlayerScreen(
              title: 'Primal Fear',
              source: source,
              initialQuality: VideoQualityPreset.directPlay,
              config: HermesVideoPlayerConfig.hdrSafeDefault(tokens: tokens),
              cinemaService: cinemaService,
              movieId: 'mov-1',
              playbackControllerFactory: (_) {
                controller = _Pr27VideoPlaybackController();
                return controller;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Italic HTML tags stripped, FontStyle.italic preserved
        controller.subtitleLinesController.add(['<i>Înțeleg, șefule!</i>']);
        await tester.pumpAndSettle();
        expect(find.text('Înțeleg, șefule!'), findsOneWidget);
        expect(find.textContaining('<i>'), findsNothing);
        final italicWidget = tester.widget<Text>(
          find.text('Înțeleg, șefule!'),
        );
        expect(italicWidget.style?.fontStyle, FontStyle.italic);

        // Font/bold tags stripped cleanly
        controller.subtitleLinesController.add([
          '<b>Atenție</b> <font color="#ffffff">acum!</font>',
        ]);
        await tester.pumpAndSettle();
        expect(find.text('Atenție acum!'), findsOneWidget);
        expect(find.textContaining('<font'), findsNothing);

        // Explicit fullscreen button exists on bottom bar
        expect(find.byKey(const Key('vp-fullscreen-btn')), findsOneWidget);
        await tester.tap(find.byKey(const Key('vp-fullscreen-btn')));
        await tester.pumpAndSettle();

        // Mobile < 640px segmented panel opens and switches tabs cleanly without overflow
        await tester.tap(find.byKey(const Key('vp-tracks-btn')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('vp-panel')), findsOneWidget);
        expect(find.text('Subtitles'), findsOneWidget);
        expect(find.text('Audio'), findsOneWidget);
        expect(find.text('Quality'), findsOneWidget);

        await tester.tap(find.text('Quality'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('720p'));
        await tester.pumpAndSettle();

        expect(
          controller.openedUris.any(
            (u) => u.queryParameters['quality'] == '720p',
          ),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('PR27 Platform-Aware Settings & Admin Host Transcode Copy', () {
    testWidgets(
      'PlayerAndThemeSettingsScreen adapts icon & labels between Android and Windows',
      (tester) async {
        final tokens = HermesThemeTokens.resolve();

        // 1) Android (flutter_test defaultTargetPlatform == TargetPlatform.android)
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: tokens.toThemeData(),
              home: PlayerAndThemeSettingsScreen(
                tokens: tokens,
                rendererBackend: VideoRendererBackend.openGl,
                defaultVideoQuality: VideoQualityPreset.directPlay,
                deviceName: 'Android Phone',
                onThemeChanged: (_) {},
                onRendererChanged: (_) {},
                onDefaultVideoQualityChanged: (_) {},
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byIcon(Icons.smartphone_rounded), findsOneWidget);
          expect(find.text('OpenGL ES'), findsOneWidget);
          expect(find.text('MediaCodec (Auto)'), findsOneWidget);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }

        // 2) Windows desktop
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: tokens.toThemeData(),
              home: PlayerAndThemeSettingsScreen(
                tokens: tokens,
                rendererBackend: VideoRendererBackend.openGl,
                defaultVideoQuality: VideoQualityPreset.directPlay,
                deviceName: 'Workstation',
                onThemeChanged: (_) {},
                onRendererChanged: (_) {},
                onDefaultVideoQualityChanged: (_) {},
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byIcon(Icons.laptop_mac_outlined), findsOneWidget);
          expect(find.text('OpenGL'), findsOneWidget);
          expect(find.text('Automatic'), findsOneWidget);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'AdminDashboardScreen labels transcoding GPU setting as server host',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(1280, 900);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final client = MockClient((req) async {
          if (req.url.path == '/api/v1/admin/libraries') {
            return http.Response(jsonEncode([]), 200);
          }
          if (req.url.path == '/api/v1/admin/invites') {
            return http.Response(jsonEncode([]), 200);
          }
          if (req.url.path == '/api/v1/admin/users') {
            return http.Response(jsonEncode([]), 200);
          }
          if (req.url.path == '/api/v1/admin/sessions') {
            return http.Response(jsonEncode([]), 200);
          }
          if (req.url.path == '/api/v1/admin/unmatched') {
            return http.Response(jsonEncode([]), 200);
          }
          if (req.url.path == '/api/v1/admin/settings') {
            return http.Response(
              jsonEncode({
                'serverName': 'Hermes Server',
                'transcodingEnabled': true,
                'hardwareAccelerationMode': 0,
                'maxVideoTranscodes': 2,
                'maxAudioTranscodes': 4,
              }),
              200,
            );
          }
          return http.Response('{}', 200);
        });

        final adminService = AdminService(
          baseUri: Uri.parse('http://localhost:5258'),
          accessToken: 'jwt-admin',
          httpClient: client,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: HermesThemeTokens.resolve().toThemeData(),
            home: AdminDashboardScreen(adminService: adminService),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Server transcode GPU (host)'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
