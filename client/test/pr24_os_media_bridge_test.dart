import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_client/src/features/music/music_models.dart';
import 'package:hermes_client/src/features/music/music_playback_coordinator.dart';
import 'package:hermes_client/src/features/music/music_service.dart';
import 'package:hermes_client/src/features/music/os_media_bridge.dart';
import 'package:hermes_client/src/features/music/platform_media_bridge.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeOsAudioHandler implements HermesOsAudioHandler {
  final List<
      ({
        String id,
        String title,
        String artist,
        String album,
        bool isPlaying,
        int positionMs,
        int durationMs,
        Uri? artUri,
      })> updates = [];
  int clearCalls = 0;
  FutureOr<void> Function(MediaButtonAction action)? onButton;
  FutureOr<void> Function(int positionMs)? onSeek;

  @override
  void attachBridgeCallbacks({
    required FutureOr<void> Function(MediaButtonAction action) onButton,
    required FutureOr<void> Function(int positionMs) onSeek,
  }) {
    this.onButton = onButton;
    this.onSeek = onSeek;
  }

  @override
  void detachBridgeCallbacks() {
    onButton = null;
    onSeek = null;
  }

  @override
  Future<void> updateMedia({
    required String id,
    required String title,
    required String artist,
    required String album,
    required bool isPlaying,
    required int positionMs,
    required int durationMs,
    Uri? artUri,
  }) async {
    updates.add((
      id: id,
      title: title,
      artist: artist,
      album: album,
      isPlaying: isPlaying,
      positionMs: positionMs,
      durationMs: durationMs,
      artUri: artUri,
    ));
  }

  @override
  Future<void> clearPlayback() async {
    clearCalls++;
  }
}

class _FakeAudioSession extends Fake implements AudioSession {
  final becomingNoisyController = StreamController<void>.broadcast();
  final interruptionController =
      StreamController<AudioInterruptionEvent>.broadcast();

  AudioSessionConfiguration? configuredWith;
  final List<bool> activeHistory = [];

  @override
  Stream<void> get becomingNoisyEventStream => becomingNoisyController.stream;

  @override
  Stream<AudioInterruptionEvent> get interruptionEventStream =>
      interruptionController.stream;

  @override
  Future<void> configure(AudioSessionConfiguration configuration) async {
    configuredWith = configuration;
  }

  @override
  Future<bool> setActive(
    bool active, {
    AVAudioSessionSetActiveOptions? avAudioSessionSetActiveOptions,
    AndroidAudioFocusGainType? androidAudioFocusGainType,
    AndroidAudioAttributes? androidAudioAttributes,
    bool? androidWillPauseWhenDucked,
    AudioSessionConfiguration fallbackConfiguration =
        const AudioSessionConfiguration.music(),
  }) async {
    activeHistory.add(active);
    return true;
  }

  Future<void> dispose() async {
    await becomingNoisyController.close();
    await interruptionController.close();
  }
}

class _SpyAudioEngine implements AudioEngineAdapter {
  final List<int> seekPositions = [];

  @override
  Future<void> loadAndPlay(
    Uri streamUri,
    SongModel track,
    int startPositionMs,
  ) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(int positionMs) async {
    seekPositions.add(positionMs);
  }

  @override
  Future<void> stop() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PR24 WindowsSmtcMediaBridge', () {
    const channel = MethodChannel(hermesSmtcChannelName);

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('publishes metadata/artUrl, clears state, and forwards OS button events', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });

      final receivedButtons = <MediaButtonAction>[];
      final bridge = WindowsSmtcMediaBridge();
      bridge.setCommandHandler(receivedButtons.add);

      await bridge.publishState(
        MediaBridgeMetadata(
          title: 'Resonance',
          artist: 'HOME',
          album: 'Odyssey',
          isPlaying: true,
          positionMs: 12000,
          durationMs: 213000,
          artUri: Uri.parse('http://192.168.1.50:5258/api/v1/artwork/abc/thumb_400.webp'),
        ),
      );

      expect(calls.single.method, 'publishState');
      final args = calls.single.arguments as Map<Object?, Object?>;
      expect(args['title'], 'Resonance');
      expect(args['artist'], 'HOME');
      expect(args['album'], 'Odyssey');
      expect(args['isPlaying'], isTrue);
      expect(
        args['artUrl'],
        'http://192.168.1.50:5258/api/v1/artwork/abc/thumb_400.webp',
      );

      const codec = StandardMethodCodec();
      for (final name in ['pause', 'play', 'next', 'previous', 'stop']) {
        final encoded = codec.encodeMethodCall(MethodCall('onMediaButton', name));
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
          hermesSmtcChannelName,
          encoded,
          (_) {},
        );
      }

      expect(receivedButtons, [
        MediaButtonAction.pause,
        MediaButtonAction.play,
        MediaButtonAction.next,
        MediaButtonAction.previous,
        MediaButtonAction.stop,
      ]);

      await bridge.clearState();
      expect(calls.last.method, 'clearState');

      await bridge.dispose();
    });

    test('ignores MissingPluginException safely when native SMTC is unavailable', () async {
      final bridge = WindowsSmtcMediaBridge();
      await bridge.publishState(
        const MediaBridgeMetadata(
          title: 'Test',
          artist: 'Artist',
          album: 'Album',
          isPlaying: false,
          positionMs: 0,
          durationMs: 1000,
        ),
      );
      await bridge.clearState();
      await bridge.dispose();
    });
  });

  group('PR24 AndroidAudioServiceMediaBridge', () {
    test('configures audio session, updates lockscreen notification, and handles noisy/focus & seek', () async {
      final fakeHandler = _FakeOsAudioHandler();
      final fakeSession = _FakeAudioSession();
      final bridge = AndroidAudioServiceMediaBridge(
        handlerFactory: () async => fakeHandler,
        sessionProvider: () async => fakeSession,
      );

      final buttons = <MediaButtonAction>[];
      final seeks = <int>[];
      bridge.setCommandHandler(buttons.add);
      bridge.setSeekHandler(seeks.add);

      await bridge.publishState(
        MediaBridgeMetadata(
          title: 'Time',
          artist: 'Hans Zimmer',
          album: 'Inception',
          isPlaying: true,
          positionMs: 45000,
          durationMs: 275000,
          artUri: Uri.parse('https://hermes.example/api/v1/artwork/hash1/thumb_400.webp'),
        ),
      );

      expect(fakeSession.configuredWith, isNotNull);
      expect(fakeSession.activeHistory, [true]);
      expect(fakeHandler.updates.single.title, 'Time');
      expect(fakeHandler.updates.single.artist, 'Hans Zimmer');
      expect(fakeHandler.updates.single.isPlaying, isTrue);
      expect(
        fakeHandler.updates.single.artUri.toString(),
        contains('artwork/hash1/thumb_400.webp'),
      );

      // Headphone unplug (becoming noisy) pauses playback.
      fakeSession.becomingNoisyController.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(buttons.last, MediaButtonAction.pause);

      // Transient phone call / focus loss pauses then resumes after focus returns.
      fakeSession.interruptionController.add(
        AudioInterruptionEvent(true, AudioInterruptionType.pause),
      );
      await Future<void>.delayed(Duration.zero);
      expect(buttons.last, MediaButtonAction.pause);

      fakeSession.interruptionController.add(
        AudioInterruptionEvent(false, AudioInterruptionType.pause),
      );
      await Future<void>.delayed(Duration.zero);
      expect(buttons.last, MediaButtonAction.play);

      // OS notification scrub bar & skip buttons forward cleanly.
      await fakeHandler.onSeek?.call(91000);
      await fakeHandler.onButton?.call(MediaButtonAction.next);
      expect(seeks, [91000]);
      expect(buttons.last, MediaButtonAction.next);

      await bridge.clearState();
      expect(fakeHandler.clearCalls, 1);
      expect(fakeSession.activeHistory.last, isFalse);

      await bridge.dispose();
      await fakeSession.dispose();
    });

    test('MusicPlaybackCoordinator passes artwork artUri and lockscreen seek to OS bridge', () async {
      final spyEngine = _SpyAudioEngine();
      final fakeHandler = _FakeOsAudioHandler();
      final fakeSession = _FakeAudioSession();
      final bridge = AndroidAudioServiceMediaBridge(
        handlerFactory: () async => fakeHandler,
        sessionProvider: () async => fakeSession,
      );

      final musicService = MusicService(
        baseUri: Uri.parse('http://192.168.1.25:5258'),
        accessToken: 'jwt',
        httpClient: MockClient((_) async => http.Response('[]', 200)),
      );
      const track = SongModel(
        id: 'song-art',
        artistId: 'art-1',
        artistName: 'Daft Punk',
        albumId: 'alb-1',
        albumTitle: 'RAM',
        title: 'Giorgio by Moroder',
        trackNumber: 3,
        discNumber: 1,
        durationMs: 544000,
        codec: 'flac',
        bitrateBps: 1411000,
        sampleRateHz: 44100,
        bitDepth: 16,
        artworkHash: 'ramhash99',
        isLiked: false,
        isMissing: false,
      );

      final coordinator = MusicPlaybackCoordinator(
        localDeviceId: 'dev-android',
        musicService: musicService,
        audioEngine: spyEngine,
        mediaBridge: bridge,
        ticketIssuer: (_) async => 't1',
        catalogSongs: {track.id: track},
      );

      await coordinator.startQueue([track], 0);
      expect(
        fakeHandler.updates.single.artUri.toString(),
        'http://192.168.1.25:5258/api/v1/artwork/ramhash99/thumb_400.webp',
      );

      await fakeHandler.onSeek?.call(180000);
      expect(spyEngine.seekPositions, [180000]);

      coordinator.dispose();
      await bridge.dispose();
      await fakeSession.dispose();
    });
  });

  group('PR24 Android Manifest & Network Security Config', () {
    test('declares required permissions, hardened security config, and AudioService components', () {
      final manifestFile = File('android/app/src/main/AndroidManifest.xml');
      final netConfigFile =
          File('android/app/src/main/res/xml/network_security_config.xml');
      final mainActivityFile = File(
        'android/app/src/main/kotlin/dev/hermes/hermes_client/MainActivity.kt',
      );
      final v28StylesFile = File(
        'android/app/src/main/res/values-v28/styles.xml',
      );

      expect(manifestFile.existsSync(), isTrue);
      expect(netConfigFile.existsSync(), isTrue);
      expect(mainActivityFile.existsSync(), isTrue);
      expect(v28StylesFile.existsSync(), isTrue);

      final manifest = manifestFile.readAsStringSync();
      expect(manifest, contains('android.permission.INTERNET'));
      expect(manifest, contains('android.permission.WAKE_LOCK'));
      expect(manifest, contains('android.permission.FOREGROUND_SERVICE'));
      expect(
        manifest,
        contains('android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK'),
      );
      expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
      expect(manifest, contains('android:allowBackup="false"'));
      expect(manifest, isNot(contains('android:usesCleartextTraffic="true"')));
      expect(
        manifest,
        contains('android:networkSecurityConfig="@xml/network_security_config"'),
      );
      expect(
        manifest,
        contains('com.ryanheise.audioservice.AudioService'),
      );
      expect(manifest, contains('android:stopWithTask="false"'));
      expect(manifest, contains('android:foregroundServiceType="mediaPlayback"'));
      expect(
        manifest,
        contains('com.ryanheise.audioservice.MediaButtonReceiver'),
      );

      final netConfig = netConfigFile.readAsStringSync();
      expect(netConfig, contains('cleartextTrafficPermitted="true"'));
      expect(netConfig, contains('<certificates src="system"'));
      expect(netConfig, contains('<debug-overrides>'));
      expect(
        netConfig.indexOf('<certificates src="user"'),
        greaterThan(netConfig.indexOf('<debug-overrides>')),
      );

      final v28Styles = v28StylesFile.readAsStringSync();
      expect(v28Styles, contains('name="LaunchTheme"'));
      expect(v28Styles, contains('name="NormalTheme"'));
      expect(v28Styles, contains('windowLayoutInDisplayCutoutMode'));

      final mainActivity = mainActivityFile.readAsStringSync();
      expect(mainActivity, contains('AudioServiceActivity'));
      expect(mainActivity, contains('post_notifications_prompted'));
    });
  });
}
