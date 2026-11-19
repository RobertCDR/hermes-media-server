import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_client/src/core/media/hermes_media_runtime.dart';
import 'package:hermes_client/src/core/settings/hermes_preferences.dart';
import 'package:hermes_client/src/core/theme/hermes_theme_tokens.dart';
import 'package:hermes_client/src/features/cinema/cinema_models.dart';
import 'package:hermes_client/src/features/cinema/cinema_service.dart';
import 'package:hermes_client/src/features/cinema/hermes_video_playback_controller.dart';
import 'package:hermes_client/src/features/cinema/hermes_video_player.dart';
import 'package:hermes_client/src/features/music/media_kit_audio_engine.dart';
import 'package:hermes_client/src/features/music/music_models.dart';
import 'package:hermes_client/src/features/music/music_playback_coordinator.dart';
import 'package:hermes_client/src/features/music/music_service.dart';
import 'package:hermes_client/src/features/music/platform_media_bridge.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class _FakeNativePlatformPlayer extends Fake implements NativePlayer {
  _FakeNativePlatformPlayer() {
    _stream = PlayerStream(
      playlistController.stream,
      playingController.stream,
      completedController.stream,
      positionController.stream,
      durationController.stream,
      volumeController.stream,
      rateController.stream,
      pitchController.stream,
      bufferingController.stream,
      bufferingPercentageController.stream,
      bufferController.stream,
      playlistModeController.stream,
      shuffleController.stream,
      audioParamsController.stream,
      videoParamsController.stream,
      audioBitrateController.stream,
      audioDeviceController.stream,
      audioDevicesController.stream,
      trackController.stream,
      tracksController.stream,
      widthController.stream,
      heightController.stream,
      subtitleController.stream,
      logController.stream,
      errorController.stream,
    );
  }

  @override
  final playlistController = StreamController<Playlist>.broadcast();
  @override
  final playingController = StreamController<bool>.broadcast();
  @override
  final completedController = StreamController<bool>.broadcast();
  @override
  final positionController = StreamController<Duration>.broadcast();
  @override
  final durationController = StreamController<Duration>.broadcast();
  @override
  final volumeController = StreamController<double>.broadcast();
  @override
  final rateController = StreamController<double>.broadcast();
  @override
  final pitchController = StreamController<double>.broadcast();
  @override
  final bufferingController = StreamController<bool>.broadcast();
  @override
  final bufferingPercentageController = StreamController<double>.broadcast();
  @override
  final bufferController = StreamController<Duration>.broadcast();
  @override
  final playlistModeController = StreamController<PlaylistMode>.broadcast();
  @override
  final shuffleController = StreamController<bool>.broadcast();
  @override
  final audioParamsController = StreamController<AudioParams>.broadcast();
  @override
  final videoParamsController = StreamController<VideoParams>.broadcast();
  @override
  final audioBitrateController = StreamController<double?>.broadcast();
  @override
  final audioDeviceController = StreamController<AudioDevice>.broadcast();
  @override
  final audioDevicesController =
      StreamController<List<AudioDevice>>.broadcast();
  @override
  final trackController = StreamController<Track>.broadcast();
  @override
  final tracksController = StreamController<Tracks>.broadcast();
  @override
  final widthController = StreamController<int?>.broadcast();
  @override
  final heightController = StreamController<int?>.broadcast();
  @override
  final subtitleController = StreamController<List<String>>.broadcast();
  @override
  final logController = StreamController<PlayerLog>.broadcast();
  @override
  final errorController = StreamController<String>.broadcast();

  late final PlayerStream _stream;
  @override
  PlayerState state = const PlayerState();

  final List<Media> openedMedia = [];
  final List<bool> openedPlayFlags = [];
  final Map<String, String> setProperties = {};
  final List<Duration> soughtDurations = [];
  final List<AudioTrack> selectedAudioTracks = [];
  final List<SubtitleTrack> selectedSubtitleTracks = [];
  int playCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;
  double? lastVolume;
  @override
  bool disposed = false;

  @override
  PlayerStream get stream => _stream;

  @override
  Future<void> open(
    Playable playable, {
    bool play = true,
    bool synchronized = true,
  }) async {
    if (playable is Media) {
      openedMedia.add(playable);
    }
    openedPlayFlags.add(play);
  }

  @override
  Future<void> play({bool synchronized = true}) async {
    playCalls++;
    state = state.copyWith(playing: true);
    playingController.add(true);
  }

  @override
  Future<void> pause({bool synchronized = true}) async {
    pauseCalls++;
    state = state.copyWith(playing: false);
    playingController.add(false);
  }

  @override
  Future<void> stop({
    bool open = false,
    bool notify = true,
    bool synchronized = true,
  }) async {
    stopCalls++;
    state = state.copyWith(playing: false);
    playingController.add(false);
  }

  @override
  Future<void> seek(Duration duration, {bool synchronized = true}) async {
    soughtDurations.add(duration);
  }

  @override
  Future<void> setVolume(double volume, {bool synchronized = true}) async {
    lastVolume = volume;
    state = state.copyWith(volume: volume);
  }

  @override
  Future<void> setAudioTrack(
    AudioTrack track, {
    bool synchronized = true,
  }) async {
    selectedAudioTracks.add(track);
  }

  @override
  Future<void> setSubtitleTrack(
    SubtitleTrack track, {
    bool synchronized = true,
  }) async {
    selectedSubtitleTracks.add(track);
  }

  @override
  Future<void> setProperty(
    String property,
    String value, {
    bool waitForInitialization = true,
  }) async {
    setProperties[property] = value;
  }

  @override
  Future<void> dispose({bool synchronized = true}) async {
    disposed = true;
    await Future.wait([
      playlistController.close(),
      playingController.close(),
      completedController.close(),
      positionController.close(),
      durationController.close(),
      volumeController.close(),
      rateController.close(),
      pitchController.close(),
      bufferingController.close(),
      bufferingPercentageController.close(),
      bufferController.close(),
      playlistModeController.close(),
      shuffleController.close(),
      audioParamsController.close(),
      videoParamsController.close(),
      audioBitrateController.close(),
      audioDeviceController.close(),
      audioDevicesController.close(),
      trackController.close(),
      tracksController.close(),
      widthController.close(),
      heightController.close(),
      subtitleController.close(),
      logController.close(),
      errorController.close(),
    ]);
  }
}

class _FakeVideoController extends Fake implements VideoController {
  _FakeVideoController(this.player);

  @override
  final Player player;
}

class _RecordingVideoPlaybackController
    implements HermesVideoPlaybackController {
  final positionController = StreamController<int>.broadcast();
  final durationController = StreamController<int>.broadcast();
  final playingController = StreamController<bool>.broadcast();
  final bufferingController = StreamController<bool>.broadcast();
  final completedController = StreamController<bool>.broadcast();
  final subtitleLinesController = StreamController<List<String>>.broadcast();
  final errorController = StreamController<String>.broadcast();

  final List<({Uri uri, int startPositionMs, Uri? subtitleUri, bool autoPlay})>
      openCalls = [];
  final List<Uri?> subtitleUriChanges = [];
  final List<int> audioStreamSelections = [];
  final List<double> subtitleDelayChanges = [];
  final List<int> seekCalls = [];
  int playCalls = 0;
  int pauseCalls = 0;
  double? lastVolume;
  bool disposed = false;

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
    openCalls.add((
      uri: streamUri,
      startPositionMs: startPositionMs,
      subtitleUri: subtitleUri,
      autoPlay: autoPlay,
    ));
  }

  @override
  Future<void> setExternalSubtitle(
    Uri? subtitleUri, {
    String? title,
    String? language,
  }) async {
    subtitleUriChanges.add(subtitleUri);
  }

  @override
  Future<void> selectEmbeddedAudioTrack({
    required int streamIndex,
    required List<MediaStreamModel> availableAudioStreams,
  }) async {
    audioStreamSelections.add(streamIndex);
  }

  @override
  Future<void> setSubtitleDelaySeconds(double seconds) async {
    subtitleDelayChanges.add(seconds);
  }

  @override
  Future<void> play() async {
    playCalls++;
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
  Future<void> setVolume(double volume0to100) async {
    lastVolume = volume0to100;
  }

  @override
  Future<void> stop() async {}

  @override
  Widget buildVideoSurface(
    BuildContext context, {
    BoxFit fit = BoxFit.contain,
  }) {
    return Container(
      key: const Key('fake-video-surface'),
      color: const Color(0xFF0A0A0A),
    );
  }

  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    await Future.wait([
      positionController.close(),
      durationController.close(),
      playingController.close(),
      bufferingController.close(),
      completedController.close(),
      subtitleLinesController.close(),
      errorController.close(),
    ]);
  }
}

void main() {
  group('PR23 HermesMediaRuntime', () {
    test('handles initialization success and failures gracefully', () {
      HermesMediaRuntime.setInitializedForTest(false);
      expect(HermesMediaRuntime.isInitialized, isFalse);

      final failed = HermesMediaRuntime.ensureInitialized(
        initializer: ({String? libmpv}) => throw StateError('no libmpv'),
      );
      expect(failed, isFalse);
      expect(HermesMediaRuntime.isInitialized, isFalse);

      var initCount = 0;
      final ok1 = HermesMediaRuntime.ensureInitialized(
        initializer: ({String? libmpv}) => initCount++,
      );
      final ok2 = HermesMediaRuntime.ensureInitialized(
        initializer: ({String? libmpv}) => initCount++,
      );
      expect(ok1, isTrue);
      expect(ok2, isTrue);
      expect(initCount, 1);

      HermesMediaRuntime.setInitializedForTest(false);
    });
  });

  group('PR23 MediaKitAudioEngineAdapter & Coordinator', () {
    const song1 = SongModel(
      id: 'song-1',
      artistId: 'art-1',
      artistName: 'Daft Punk',
      albumId: 'alb-1',
      albumTitle: 'Discovery',
      title: 'One More Time',
      trackNumber: 1,
      discNumber: 1,
      durationMs: 320000,
      codec: 'flac',
      bitrateBps: 1411000,
      sampleRateHz: 44100,
      bitDepth: 16,
      isLiked: false,
      isMissing: false,
    );
    const song2 = SongModel(
      id: 'song-2',
      artistId: 'art-1',
      artistName: 'Daft Punk',
      albumId: 'alb-1',
      albumTitle: 'Discovery',
      title: 'Aerodynamic',
      trackNumber: 2,
      discNumber: 1,
      durationMs: 212000,
      codec: 'flac',
      bitrateBps: 1411000,
      sampleRateHz: 44100,
      bitDepth: 16,
      isLiked: false,
      isMissing: false,
    );

    test('configures mpv audio output, normalization, volume, and telemetry streams', () async {
      late _FakeNativePlatformPlayer fakePlatform;
      final adapter = MediaKitAudioEngineAdapter(
        playerFactory: () {
          fakePlatform = _FakeNativePlatformPlayer();
          return Player(platformPlayer: fakePlatform);
        },
      );

      await adapter.setVolume(0.45);
      await adapter.setNormalizationEnabled(true);

      final positions = <int>[];
      var completedCount = 0;
      final posSub = adapter.positionMsStream.listen(positions.add);
      final doneSub = adapter.trackCompletedStream.listen((_) => completedCount++);

      await adapter.loadAndPlay(
        Uri.parse('https://hermes.local/api/v1/streams/song-1/audio?quality=Lossless&ticket=t1'),
        song1,
        15000,
      );

      expect(fakePlatform.openedMedia.single.uri, contains('song-1/audio'));
      expect(
        fakePlatform.openedMedia.single.start,
        const Duration(milliseconds: 15000),
      );
      expect(fakePlatform.openedPlayFlags.single, isTrue);
      expect(fakePlatform.lastVolume, closeTo(45.0, 0.01));
      expect(fakePlatform.setProperties['af'], 'dynaudnorm=f=150:g=15');

      fakePlatform.positionController.add(const Duration(milliseconds: 22500));
      fakePlatform.completedController.add(true);
      fakePlatform.completedController.add(true); // Duplicate true does not re-fire
      await Future<void>.delayed(Duration.zero);

      expect(positions, [22500]);
      expect(completedCount, 1);

      await adapter.pause();
      await adapter.resume();
      await adapter.seek(45000);
      await adapter.setNormalizationEnabled(false);

      expect(fakePlatform.pauseCalls, 1);
      expect(fakePlatform.playCalls, 1);
      expect(fakePlatform.soughtDurations.single, const Duration(milliseconds: 45000));
      expect(fakePlatform.setProperties['af'], '');

      await posSub.cancel();
      await doneSub.cancel();
      await adapter.dispose();
      expect(fakePlatform.disposed, isTrue);
    });

    test('MusicPlaybackCoordinator resumes without re-opening and advances on track end', () async {
      late _FakeNativePlatformPlayer fakePlatform;
      final adapter = MediaKitAudioEngineAdapter(
        playerFactory: () {
          fakePlatform = _FakeNativePlatformPlayer();
          return Player(platformPlayer: fakePlatform);
        },
      );
      final musicService = MusicService(
        baseUri: Uri.parse('http://localhost:5258'),
        accessToken: 'jwt',
        httpClient: MockClient((_) async => http.Response('[]', 200)),
      );
      final heartbeats = <int>[];
      final coordinator = MusicPlaybackCoordinator(
        localDeviceId: 'dev-win',
        musicService: musicService,
        audioEngine: adapter,
        mediaBridge: InMemoryPlatformMediaBridge(),
        ticketIssuer: (id) async => 'tkt-$id',
        catalogSongs: {song1.id: song1, song2.id: song2},
        onProgressHeartbeat: (ms) async => heartbeats.add(ms),
      );

      await coordinator.startQueue([song1, song2], 0);
      expect(fakePlatform.openedMedia, hasLength(1));

      // Changing volume & pause -> resume must reuse the active stream.
      await coordinator.setVolume(0.6);
      await coordinator.togglePlayPause();
      await coordinator.togglePlayPause();
      expect(fakePlatform.openedMedia, hasLength(1));
      expect(fakePlatform.pauseCalls, 1);
      expect(fakePlatform.playCalls, 1);
      expect(fakePlatform.lastVolume, closeTo(60.0, 0.01));

      // Live position pushes into coordinator & throttled SignalR heartbeat.
      fakePlatform.positionController.add(const Duration(milliseconds: 6200));
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.currentPositionMs, 6200);
      expect(heartbeats, [6200]);

      // Track completes naturally -> auto-advances to song-2.
      fakePlatform.completedController.add(true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(coordinator.session?.currentSongId, 'song-2');
      expect(fakePlatform.openedMedia, hasLength(2));
      expect(fakePlatform.openedMedia.last.uri, contains('song-2/audio'));

      coordinator.dispose();
      await adapter.dispose();
    });
  });

  group('PR23 MediaKitVideoPlaybackController', () {
    test('applies OpenGL HDR mpv props, attaches deferred WebVTT subtitles, and maps audio tracks', () async {
      late _FakeNativePlatformPlayer fakePlatform;
      final config = HermesVideoPlayerConfig.hdrSafeDefault(
        tokens: HermesThemeTokens.resolve(),
        rendererBackend: VideoRendererBackend.openGl,
      );

      final controller = MediaKitVideoPlaybackController(
        config: config,
        playerFactory: (_) {
          fakePlatform = _FakeNativePlatformPlayer();
          return Player(platformPlayer: fakePlatform);
        },
        videoControllerFactory: (player, _) => _FakeVideoController(player),
      );

      final subUri = Uri.parse('http://localhost:5258/api/v1/streams/src-1/subtitles/3.vtt?ticket=tkt');
      await controller.open(
        Uri.parse('http://localhost:5258/api/v1/streams/src-1/direct?ticket=tkt'),
        startPositionMs: 42000,
        subtitleUri: subUri,
        subtitleTitle: 'English SDH',
        subtitleLanguage: 'eng',
      );

      expect(fakePlatform.setProperties['gpu-api'], 'opengl');
      expect(fakePlatform.setProperties['sub-color'], '#D8D8D8');
      expect(fakePlatform.openedMedia.single.start, const Duration(milliseconds: 42000));
      // Deferred until demuxer emits tracks.
      expect(fakePlatform.selectedSubtitleTracks, isEmpty);

      final track1 = const AudioTrack('1', 'English 7.1', 'eng');
      final track2 = const AudioTrack('2', 'Japanese', 'jpn');
      fakePlatform.state = fakePlatform.state.copyWith(
        tracks: Tracks(
          audio: [AudioTrack.auto(), AudioTrack.no(), track1, track2],
        ),
      );
      fakePlatform.tracksController.add(fakePlatform.state.tracks);
      await Future<void>.delayed(Duration.zero);

      expect(fakePlatform.selectedSubtitleTracks.single.uri, isTrue);
      expect(fakePlatform.selectedSubtitleTracks.single.id, subUri.toString());

      await controller.selectEmbeddedAudioTrack(
        streamIndex: 2,
        availableAudioStreams: const [
          MediaStreamModel(streamIndex: 1, kind: 1, codec: 'truehd', language: 'eng', title: 'English 7.1', isDefault: true),
          MediaStreamModel(streamIndex: 2, kind: 1, codec: 'aac', language: 'jpn', title: 'Japanese', isDefault: false),
        ],
      );
      expect(fakePlatform.selectedAudioTracks.single.id, '2');

      await controller.setExternalSubtitle(null);
      expect(fakePlatform.selectedSubtitleTracks.last.id, 'no');

      await controller.dispose();
      expect(fakePlatform.disposed, isTrue);
    });
  });

  group('PR23 HermesVideoPlayerScreen live integration', () {
    testWidgets('renders video surface, live HDR subtitles, in-place DirectPlay audio & HLS anchor', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final recordedProgress = <Map<String, dynamic>>[];
      var playedNext = false;
      final client = MockClient((req) async {
        if (req.url.path == '/api/v1/auth/stream-tickets') {
          return http.Response(jsonEncode({'ticket': 'tkt-live'}), 200);
        }
        if (req.url.path == '/api/v1/cinema/progress') {
          recordedProgress.add(jsonDecode(req.body) as Map<String, dynamic>);
          return http.Response(
            jsonEncode({
              'positionMs': 60000,
              'durationMs': 120000,
              'isWatched': false,
              'updatedAtUtc': '2026-11-17T16:00:00Z',
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      final service = CinemaService(
        baseUri: Uri.parse('http://localhost:5258'),
        accessToken: 'jwt',
        httpClient: client,
      );
      final tokens = HermesThemeTokens.resolve();
      const source = MediaSourceModel(
        id: 'src-live',
        sourceLabel: '4K HDR REMUX',
        container: 'mkv',
        videoCodec: 'hevc',
        audioCodec: 'truehd',
        width: 3840,
        height: 2160,
        isHdr: true,
        bitrateBps: 45000000,
        durationMs: 120000,
        isAvailable: true,
        streams: [
          MediaStreamModel(streamIndex: 1, kind: 1, codec: 'truehd', language: 'eng', title: 'English', isDefault: true),
          MediaStreamModel(streamIndex: 2, kind: 1, codec: 'ac3', language: 'jpn', title: 'Japanese', isDefault: false),
          MediaStreamModel(streamIndex: 3, kind: 2, codec: 'subrip', language: 'eng', title: 'SDH', isDefault: true),
        ],
      );

      late _RecordingVideoPlaybackController fakeController;
      await tester.pumpWidget(
        MaterialApp(
          theme: tokens.toThemeData(),
          home: HermesVideoPlayerScreen(
            title: 'Blade Runner 2049',
            subtitleLabel: 'S1 E1 · Pilot',
            source: source,
            initialQuality: VideoQualityPreset.directPlay,
            config: HermesVideoPlayerConfig.hdrSafeDefault(tokens: tokens),
            cinemaService: service,
            episodeId: 'ep-1',
            initialPositionMs: 25000,
            accountPreferences: const HermesAccountPreferences(
              autoplayNextEpisode: true,
              subtitleSize: SubtitleSizePreset.xl,
              subtitleBackground: SubtitleBackgroundStyle.box,
            ),
            nextEpisodeCode: 'S1 E2',
            nextEpisodeTitle: 'Sapience',
            onPlayNextEpisode: () => playedNext = true,
            playbackControllerFactory: (_) {
              fakeController = _RecordingVideoPlaybackController();
              return fakeController;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Surface rendered and DirectPlay opened at resume position 25s with VTT sub.
      expect(find.byKey(const Key('fake-video-surface')), findsOneWidget);
      expect(fakeController.openCalls.single.uri.path, '/api/v1/streams/src-live/direct');
      expect(fakeController.openCalls.single.startPositionMs, 25000);
      expect(
        fakeController.openCalls.single.subtitleUri?.path,
        '/api/v1/streams/src-live/subtitles/3.vtt',
      );

      // Push live WebVTT cue lines from mpv and advance playback to 65s.
      fakeController.durationController.add(120000);
      fakeController.positionController.add(65000);
      fakeController.subtitleLinesController.add(['All those moments will be lost in time']);
      await tester.pumpAndSettle();

      expect(find.text('All those moments will be lost in time'), findsOneWidget);
      expect(find.text('1:05'), findsOneWidget);

      // Open panel: switch DirectPlay audio -> updates in-place without reopening stream!
      await tester.tap(find.byKey(const Key('vp-tracks-btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('JPN (ac3)'));
      await tester.pumpAndSettle();
      expect(fakeController.audioStreamSelections, [2]);
      expect(fakeController.openCalls, hasLength(1));

      // Turn subtitles off -> updates in-place without reopening stream and clears caption.
      await tester.tap(find.text('Off'));
      await tester.pumpAndSettle();
      expect(fakeController.subtitleUriChanges.last, isNull);
      expect(find.text('All those moments will be lost in time'), findsNothing);

      // Switch quality to 720p -> opens HLS master.m3u8 anchored at startSeconds=65 with startPositionMs=0!
      await tester.tap(find.text('720p'));
      await tester.pumpAndSettle();
      expect(fakeController.openCalls, hasLength(2));
      final hlsOpen = fakeController.openCalls.last;
      expect(hlsOpen.uri.path, '/api/v1/streams/src-live/video/master.m3u8');
      expect(hlsOpen.uri.queryParameters['quality'], '720p');
      expect(hlsOpen.uri.queryParameters['audioStreamIndex'], '2');
      expect(hlsOpen.uri.queryParameters['startSeconds'], '65');
      expect(hlsOpen.startPositionMs, 0);

      // Simulate HLS advancing 10s -> UI clock shows 65s + 10s = 1:15.
      fakeController.positionController.add(10000);
      await tester.pumpAndSettle();
      expect(find.text('1:15'), findsOneWidget);

      // Complete playback -> marks watched & triggers autoplay next episode.
      fakeController.completedController.add(true);
      await tester.pumpAndSettle();
      expect(playedNext, isTrue);
      expect(recordedProgress.any((p) => p['markWatched'] == true), isTrue);
    });
  });
}
