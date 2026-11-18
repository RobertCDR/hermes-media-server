import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_client/src/core/theme/hermes_theme_tokens.dart';
import 'package:hermes_client/src/features/music/device_picker_sheet.dart';
import 'package:hermes_client/src/features/music/mini_player_bar.dart';
import 'package:hermes_client/src/features/music/music_models.dart';
import 'package:hermes_client/src/features/music/music_playback_coordinator.dart';
import 'package:hermes_client/src/features/music/music_service.dart';
import 'package:hermes_client/src/features/music/platform_media_bridge.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

class _FakeAudioEngine implements AudioEngineAdapter {
  int playCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;
  Uri? lastUri;
  int lastStartPositionMs = 0;

  @override
  Future<void> loadAndPlay(Uri streamUri, SongModel track, int startPositionMs) async {
    playCalls++;
    lastUri = streamUri;
    lastStartPositionMs = startPositionMs;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
  }

  @override
  Future<void> seek(int positionMs) async {}

  @override
  Future<void> stop() async {
    stopCalls++;
  }
}

class _FakeConnectTransport implements ConnectTransport {
  final List<String> sentCommands = [];
  String? lastTransferredTarget;

  @override
  Future<List<OnlineDeviceModel>> getOnlineDevices() async => const [];

  @override
  Future<PlaybackSessionState> sendTransport(
    PlaybackState state, {
    int? currentIndex,
    int? positionMs,
    HermesRepeatMode? repeatMode,
    bool? shuffle,
    double? volume,
  }) async {
    sentCommands.add('${state.name}:$currentIndex');
    return PlaybackSessionState(
      sessionId: 'sess-1',
      version: 3,
      activeRendererDeviceId: 'device-desktop',
      activeRendererDeviceName: 'Workstation PC',
      state: state,
      repeatMode: HermesRepeatMode.off,
      shuffle: false,
      volume: 1.0,
      currentIndex: currentIndex ?? 0,
      currentSongId: 'song-1',
      positionMs: positionMs ?? 0,
      queueSongIds: const ['song-1', 'song-2'],
    );
  }

  @override
  Future<PlaybackSessionState> startPlayback(List<String> queueSongIds, int startIndex) async {
    return PlaybackSessionState(
      sessionId: 'sess-1',
      version: 1,
      activeRendererDeviceId: 'device-phone',
      activeRendererDeviceName: 'Pixel 9',
      state: PlaybackState.playing,
      repeatMode: HermesRepeatMode.off,
      shuffle: false,
      volume: 1.0,
      currentIndex: startIndex,
      currentSongId: queueSongIds[startIndex],
      positionMs: 0,
      queueSongIds: queueSongIds,
    );
  }

  @override
  Future<PlaybackSessionState> transferOutput(
    String targetDeviceId, {
    int? positionMs,
  }) async {
    lastTransferredTarget = targetDeviceId;
    return PlaybackSessionState(
      sessionId: 'sess-1',
      version: 4,
      activeRendererDeviceId: targetDeviceId,
      activeRendererDeviceName: 'Target',
      state: PlaybackState.playing,
      repeatMode: HermesRepeatMode.off,
      shuffle: false,
      volume: 1.0,
      currentIndex: 0,
      currentSongId: 'song-1',
      positionMs: 0,
      queueSongIds: const ['song-1', 'song-2'],
    );
  }
}

void main() {
  const track1 = SongModel(
    id: 'song-1',
    artistId: 'art-1',
    artistName: 'M83',
    albumId: 'alb-1',
    albumTitle: 'Hurry Up, Were Dreaming',
    title: 'Midnight City',
    trackNumber: 2,
    discNumber: 1,
    durationMs: 244000,
    codec: 'flac',
    bitrateBps: 1411000,
    sampleRateHz: 44100,
    bitDepth: 16,
    isLiked: true,
    isMissing: false,
  );

  const track2 = SongModel(
    id: 'song-2',
    artistId: 'art-1',
    artistName: 'M83',
    albumId: 'alb-1',
    albumTitle: 'Hurry Up, Were Dreaming',
    title: 'Intro',
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

  MusicService makeMusicService() {
    return MusicService(
      baseUri: Uri.parse('https://hermes.tailnet.ts.net'),
      accessToken: 'jwt-music',
      httpClient: MockClient((_) async => http.Response('[]', 200)),
    );
  }

  group('AudioQualityPolicy & MusicService URLs', () {
    test('selects Wi-Fi vs Cellular preset and builds quality audio URL', () {
      const policy = AudioQualityPolicy(
        wifiPreset: AudioQualityPreset.lossless,
        cellularPreset: AudioQualityPreset.high160,
      );

      expect(policy.presetFor(NetworkTransportMode.wifi), AudioQualityPreset.lossless);
      expect(policy.presetFor(NetworkTransportMode.cellular), AudioQualityPreset.high160);

      final svc = makeMusicService();
      final uri = svc.buildAudioStreamUri(
        songId: 'song-1',
        ticket: 'tkt-audio',
        quality: policy.presetFor(NetworkTransportMode.cellular),
      );
      expect(
        uri.toString(),
        'https://hermes.tailnet.ts.net/api/v1/streams/song-1/audio?quality=High160&ticket=tkt-audio',
      );
    });
  });

  group('MusicPlaybackCoordinator monotonic Connect & PlatformMediaBridge', () {
    test('drops stale versions, honors Remote Control vs Local Renderer, and handles OS buttons', () async {
      final engine = _FakeAudioEngine();
      final bridge = InMemoryPlatformMediaBridge();
      final transport = _FakeConnectTransport();

      final coordinator = MusicPlaybackCoordinator(
        localDeviceId: 'device-phone',
        musicService: makeMusicService(),
        audioEngine: engine,
        mediaBridge: bridge,
        transport: transport,
        ticketIssuer: (_) async => 'tkt-1',
        catalogSongs: {track1.id: track1, track2.id: track2},
      );
      coordinator.setNetworkMode(NetworkTransportMode.cellular);

      // 1. Server says Desktop is ActiveRenderer (Version 2) -> Phone acts as Remote Control ONLY.
      await coordinator.applyServerSession(
        const PlaybackSessionState(
          sessionId: 'sess-1',
          version: 2,
          activeRendererDeviceId: 'device-desktop',
          activeRendererDeviceName: 'Workstation PC',
          state: PlaybackState.playing,
          repeatMode: HermesRepeatMode.off,
          shuffle: false,
          volume: 1.0,
          currentIndex: 0,
          currentSongId: 'song-1',
          positionMs: 10000,
          queueSongIds: ['song-1', 'song-2'],
        ),
      );

      expect(coordinator.lastAppliedVersion, 2);
      expect(coordinator.isLocalRenderer, isFalse);
      expect(engine.playCalls, 0);
      expect(engine.stopCalls, 1);

      // 2. Stale Version 2 / Version 1 packet arrives out of order -> MUST be ignored.
      await coordinator.applyServerSession(
        const PlaybackSessionState(
          sessionId: 'sess-1',
          version: 1,
          activeRendererDeviceId: 'device-phone',
          activeRendererDeviceName: 'Pixel 9',
          state: PlaybackState.playing,
          repeatMode: HermesRepeatMode.off,
          shuffle: false,
          volume: 1.0,
          currentIndex: 0,
          currentSongId: 'song-1',
          positionMs: 0,
          queueSongIds: ['song-1', 'song-2'],
        ),
      );

      expect(coordinator.lastAppliedVersion, 2);
      expect(coordinator.isLocalRenderer, isFalse);
      expect(engine.playCalls, 0);

      // 3. Hardware OS Next Track key dispatches remote transport without stealing audio.
      await bridge.simulateMediaButton(MediaButtonAction.next);
      expect(transport.sentCommands, contains('playing:1'));

      // 4. TransferOutput switches ActiveRenderer to device-phone (Version 4) -> local engine starts at cellular preset!
      await coordinator.applyServerSession(
        const PlaybackSessionState(
          sessionId: 'sess-1',
          version: 4,
          activeRendererDeviceId: 'device-phone',
          activeRendererDeviceName: 'Pixel 9',
          state: PlaybackState.playing,
          repeatMode: HermesRepeatMode.off,
          shuffle: false,
          volume: 1.0,
          currentIndex: 0,
          currentSongId: 'song-1',
          positionMs: 15000,
          queueSongIds: ['song-1', 'song-2'],
        ),
      );

      expect(coordinator.isLocalRenderer, isTrue);
      expect(engine.playCalls, 1);
      expect(engine.lastStartPositionMs, 15000);
      expect(engine.lastUri.toString(), contains('quality=High160'));
      expect(bridge.lastPublished?.title, 'Midnight City');
      expect(bridge.lastPublished?.isPlaying, isTrue);

      // 5. Renderer disconnect transitions session to Paused & null ActiveRenderer (Version 5).
      await coordinator.applyServerSession(
        const PlaybackSessionState(
          sessionId: 'sess-1',
          version: 5,
          activeRendererDeviceId: null,
          activeRendererDeviceName: null,
          state: PlaybackState.paused,
          repeatMode: HermesRepeatMode.off,
          shuffle: false,
          volume: 1.0,
          currentIndex: 0,
          currentSongId: 'song-1',
          positionMs: 25000,
          queueSongIds: ['song-1', 'song-2'],
        ),
      );

      expect(coordinator.isLocalRenderer, isFalse);
      expect(coordinator.session?.state, PlaybackState.paused);
    });
  });

  group('MiniPlayerBar & DevicePickerSheet', () {
    testWidgets('shows remote renderer banner and allows selecting target device', (tester) async {
      String? pickedDevice;
      const session = PlaybackSessionState(
        sessionId: 'sess-1',
        version: 2,
        activeRendererDeviceId: 'device-desktop',
        activeRendererDeviceName: 'Workstation PC',
        state: PlaybackState.playing,
        repeatMode: HermesRepeatMode.off,
        shuffle: false,
        volume: 1.0,
        currentIndex: 0,
        currentSongId: 'song-1',
        positionMs: 12000,
        queueSongIds: ['song-1'],
      );

      final devices = [
        OnlineDeviceModel(
          deviceId: 'device-desktop',
          deviceName: 'Workstation PC',
          platform: 'Windows',
          connectedAtUtc: DateTime.utc(2026, 11, 15),
        ),
        OnlineDeviceModel(
          deviceId: 'device-phone',
          deviceName: 'Pixel 9',
          platform: 'Android',
          connectedAtUtc: DateTime.utc(2026, 11, 15),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: HermesThemeTokens.resolve().toThemeData(),
          home: Scaffold(
            body: Column(
              children: [
                MiniPlayerBar(
                  session: session,
                  currentSong: track1,
                  localDeviceId: 'device-phone',
                  onTogglePlayPause: () {},
                  onSkipNext: () {},
                  onOpenDevicePicker: () {},
                ),
                Expanded(
                  child: DevicePickerSheet(
                    devices: devices,
                    activeRendererDeviceId: 'device-desktop',
                    localDeviceId: 'device-phone',
                    onSelectDevice: (id) => pickedDevice = id,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Midnight City'), findsOneWidget);
      expect(find.textContaining('Playing on Workstation PC'), findsOneWidget);
      expect(find.textContaining('Pixel 9'), findsOneWidget);

      await tester.tap(find.textContaining('Pixel 9'));
      await tester.pumpAndSettle();

      expect(pickedDevice, 'device-phone');
    });
  });
}
