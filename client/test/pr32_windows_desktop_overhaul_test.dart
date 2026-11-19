import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugDefaultTargetPlatformOverride;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_client/main.dart';
import 'package:hermes_client/src/core/auth/session_store.dart';
import 'package:hermes_client/src/core/network/hermes_sync_client.dart';
import 'package:hermes_client/src/core/settings/hermes_preferences.dart';
import 'package:hermes_client/src/core/theme/hermes_theme_tokens.dart';
import 'package:hermes_client/src/core/widgets/hermes_horizontal_shelf.dart';
import 'package:hermes_client/src/core/window/hermes_window_bridge.dart';
import 'package:hermes_client/src/features/cinema/cinema_models.dart';
import 'package:hermes_client/src/features/cinema/cinema_service.dart';
import 'package:hermes_client/src/features/cinema/hermes_video_playback_controller.dart';
import 'package:hermes_client/src/features/cinema/hermes_video_player.dart';
import 'package:hermes_client/src/features/music/mini_player_bar.dart';
import 'package:hermes_client/src/features/music/music_models.dart';
import 'package:hermes_client/src/features/music/music_playback_coordinator.dart';
import 'package:hermes_client/src/features/music/music_service.dart';
import 'package:hermes_client/src/features/music/music_world_screen.dart';
import 'package:hermes_client/src/features/music/platform_media_bridge.dart';
import 'package:hermes_client/src/features/settings/player_and_theme_settings_screen.dart';
import 'package:hermes_client/src/features/shell/dual_world_shell.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _NoopAudioEngine implements AudioEngineAdapter {
  @override
  Future<void> loadAndPlay(
    Uri streamUri,
    SongModel track,
    int startPositionMs,
  ) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(int positionMs) async {}

  @override
  Future<void> stop() async {}
}

class _FakeTransport implements ConnectTransport {
  _FakeTransport(this._songs);

  final List<SongModel> _songs;
  int _version = 1;

  @override
  Future<List<OnlineDeviceModel>> getOnlineDevices() async => const [];

  @override
  Future<PlaybackSessionState> startPlayback(
    List<String> queueSongIds,
    int startIndex,
  ) async {
    return PlaybackSessionState(
      sessionId: 'sess-pr32',
      version: ++_version,
      activeRendererDeviceId: 'dev-win',
      state: PlaybackState.playing,
      repeatMode: HermesRepeatMode.off,
      shuffle: false,
      volume: 1.0,
      currentIndex: startIndex,
      currentSongId: queueSongIds.isEmpty ? null : queueSongIds[startIndex],
      positionMs: 0,
      queueSongIds: List<String>.from(queueSongIds),
    );
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
    return PlaybackSessionState(
      sessionId: 'sess-pr32',
      version: ++_version,
      activeRendererDeviceId: 'dev-win',
      state: state,
      repeatMode: repeatMode ?? HermesRepeatMode.off,
      shuffle: shuffle ?? false,
      volume: volume ?? 1.0,
      currentIndex: currentIndex ?? 0,
      currentSongId: _songs.isNotEmpty ? _songs.first.id : null,
      positionMs: positionMs ?? 0,
      queueSongIds: queueSongIds ?? _songs.map((s) => s.id).toList(),
    );
  }

  @override
  Future<PlaybackSessionState> transferOutput(
    String targetDeviceId, {
    int? positionMs,
  }) async =>
      sendTransport(PlaybackState.paused);
}

class _SpyVideoPlaybackController implements HermesVideoPlaybackController {
  final positionController = StreamController<int>.broadcast();
  final durationController = StreamController<int>.broadcast();
  final playingController = StreamController<bool>.broadcast();
  final bufferingController = StreamController<bool>.broadcast();
  final completedController = StreamController<bool>.broadcast();
  final subtitleLinesController = StreamController<List<String>>.broadcast();
  final errorController = StreamController<String>.broadcast();

  final List<BoxFit> renderedFits = [];
  final List<double> volumeChanges = [];

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
  }) async {}

  @override
  Future<void> setSubtitleDelaySeconds(double seconds) async {}

  @override
  Future<void> play() async => playingController.add(true);

  @override
  Future<void> pause() async => playingController.add(false);

  @override
  Future<void> seek(int positionMs) async => positionController.add(positionMs);

  @override
  Future<void> setVolume(double volume0to100) async {
    volumeChanges.add(volume0to100);
  }

  @override
  Future<void> stop() async => playingController.add(false);

  @override
  Widget buildVideoSurface(
    BuildContext context, {
    BoxFit fit = BoxFit.contain,
  }) {
    renderedFits.add(fit);
    return ColoredBox(
      key: const Key('spy-video-surface'),
      color: Colors.black,
    );
  }

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

class _FakeSink extends Fake implements WebSocketSink {
  final Completer<void> _done = Completer<void>();

  @override
  void add(dynamic data) {}

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    if (!_done.isCompleted) _done.complete();
  }
}

class _FakeChannel extends Fake implements WebSocketChannel {
  final _incoming = StreamController<dynamic>.broadcast();
  late final _sink = _FakeSink();

  @override
  Future<void> get ready => Future<void>.value();

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _sink;
}

SongModel _song(String id, String title, {String albumId = 'alb-1'}) =>
    SongModel(
      id: id,
      artistId: 'art-1',
      artistName: 'Daft Punk',
      albumId: albumId,
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

Map<String, dynamic> _songJson(SongModel s) => {
      'id': s.id,
      'artistId': s.artistId,
      'artistName': s.artistName,
      'albumId': s.albumId,
      'albumTitle': s.albumTitle,
      'title': s.title,
      'trackNumber': s.trackNumber,
      'discNumber': s.discNumber,
      'durationMs': s.durationMs,
      'codec': s.codec,
      'bitrateBps': s.bitrateBps,
      'sampleRateHz': s.sampleRateHz,
      'bitDepth': s.bitDepth,
      'isLiked': s.isLiked,
      'isMissing': s.isMissing,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PR32 HermesWindowBridge & Frameless TitleBar', () {
    test('MethodChannel roundtrips fullscreen, tray, title, flyout & incoming events', () async {
      const channel = MethodChannel('hermes.window/test_pr32');
      final recorded = <(String, Object?)>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        recorded.add((call.method, call.arguments));
        return null;
      });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final bridge = HermesWindowBridge(channel: channel);
      String? trayAction;
      String? flyoutAction;
      String? appCmd;
      bridge.onTrayAction = (a) => trayAction = a;
      bridge.onFlyoutAction = (a) => flyoutAction = a;
      bridge.onAppCommand = (d) => appCmd = d;

      await bridge.setFullscreen(true);
      await bridge.setTitle('Granite · Sleep Token — Hermes');
      await bridge.setCloseToTray(true);
      await bridge.updateTrayState(
        title: 'Granite',
        artist: 'Sleep Token',
        isPlaying: true,
      );
      await bridge.showMediaFlyout(
        const HermesMediaFlyoutData(
          title: 'Granite',
          artist: 'Sleep Token',
          isPlaying: true,
        ),
      );

      expect(bridge.isFullscreen.value, isTrue);
      expect(bridge.activeTrackSummary.value, 'Granite · Sleep Token');
      expect(recorded.map((r) => r.$1), [
        'setFullscreen',
        'setTitle',
        'setCloseToTray',
        'updateTrayState',
        'showMediaFlyout',
      ]);

      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const codec = StandardMethodCodec();
      Future<void> simulateIncoming(String method, Object? args) async {
        await messenger.handlePlatformMessage(
          channel.name,
          codec.encodeMethodCall(MethodCall(method, args)),
          (_) {},
        );
      }

      await simulateIncoming('onWindowStateChanged', {
        'isMaximized': true,
        'isFullscreen': false,
      });
      await simulateIncoming('onTrayAction', 'next');
      await simulateIncoming('onFlyoutAction', 'playPause');
      await simulateIncoming('onAppCommand', 'back');

      expect(bridge.isMaximized.value, isTrue);
      expect(bridge.isFullscreen.value, isFalse);
      expect(trayAction, 'next');
      expect(flyoutAction, 'playPause');
      expect(appCmd, 'back');
    });

    testWidgets(
      'HermesDesktopTitleBar invokes caption actions, opens shortcuts dialog, and hides in fullscreen inside HermesApp',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        const channel = MethodChannel('hermes.window/test_titlebar_ui');
        final calls = <String>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return null;
        });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );

        final bridge = HermesWindowBridge(channel: channel);
        final sessionStore = InMemorySessionStore();
        await sessionStore.save(
          const HermesSession(
            serverPrimaryUrl: 'http://127.0.0.1:5258',
            serverLanFallbackUrl: 'http://127.0.0.1:5258',
            serverId: 'srv-1',
            deviceId: 'dev-win',
            deviceName: 'Desktop',
            userId: 'usr-1',
            username: 'robert',
            role: 'Admin',
            accessToken: 'jwt-1',
            refreshToken: 'ref-1',
          ),
        );

        final mockHttp = MockClient((req) async {
          final p = req.url.path;
          if (p == '/api/v1/system/info') {
            return http.Response(
              jsonEncode({
                'serverId': 'srv-1',
                'serverName': 'Hermes Home',
                'version': '1.0.0',
                'setupCompleted': true,
              }),
              200,
            );
          }
          if (p == '/api/v1/auth/refresh') {
            return http.Response(
              jsonEncode({
                'accessToken': 'jwt-2',
                'refreshToken': 'ref-2',
                'role': 'Admin',
              }),
              200,
            );
          }
          if (p == '/api/v1/auth/me/preferences') {
            return http.Response(
              jsonEncode(const HermesAccountPreferences().toJson()),
              200,
            );
          }
          if (p == '/hubs/sync/negotiate') {
            return http.Response(
              jsonEncode({'negotiateVersion': 1, 'connectionToken': 'tok'}),
              200,
            );
          }
          return http.Response('[]', 200);
        });

        await tester.pumpWidget(
          HermesApp(
            sessionStore: sessionStore,
            preferencesStore: InMemoryDevicePreferencesStore(),
            httpClient: mockHttp,
            windowBridge: bridge,
            showDesktopTitleBarOverride: true,
            syncClientFactory: ({
              required baseUri,
              required httpClient,
              required getAccessToken,
              required deviceId,
              required deviceName,
              required platform,
            }) =>
                HermesSyncClient(
              baseUri: baseUri,
              httpClient: httpClient,
              getAccessToken: getAccessToken,
              deviceId: deviceId,
              deviceName: deviceName,
              platform: platform,
              channelFactory: (_) => _FakeChannel(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('hermes-desktop-titlebar')), findsOneWidget);

        await tester.tap(find.byKey(const Key('win-btn-minimize')));
        await tester.tap(find.byKey(const Key('win-btn-maximize')));
        await tester.tap(find.byKey(const Key('win-btn-close')));
        expect(calls, containsAll(['minimize', 'toggleMaximize', 'closeWindow']));

        await tester.tap(find.byKey(const Key('desktop-shortcuts-btn')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('desktop-shortcuts-dialog')), findsOneWidget);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();

        // Entering fullscreen hides the desktop title bar completely.
        await bridge.setFullscreen(true);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('hermes-desktop-titlebar')), findsNothing);

        await bridge.setFullscreen(false);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('hermes-desktop-titlebar')), findsOneWidget);
      },
    );
  });

  group('PR32 Cinema Video Player Fit/Cover/Stretch, Wheel/Arrow Volume & Fullscreen', () {
    testWidgets(
      'supports aspect cycling (Fit/Cover/Stretch), HUD feedback, wheel & arrow volume, and F11 fullscreen',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        const channel = MethodChannel('hermes.window/test_video_pr32');
        final fsCalls = <Object?>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'setFullscreen') fsCalls.add(call.arguments);
          return null;
        });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );

        final bridge = HermesWindowBridge(channel: channel);
        final client = MockClient((req) async {
          if (req.url.path == '/api/v1/auth/stream-tickets') {
            return http.Response(jsonEncode({'ticket': 'tkt-pr32'}), 200);
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
          id: 'src-pr32',
          sourceLabel: '4K',
          container: 'mkv',
          videoCodec: 'hevc',
          audioCodec: 'aac',
          width: 3840,
          height: 2160,
          isHdr: false,
          bitrateBps: 14000000,
          durationMs: 120000,
          isAvailable: true,
          streams: [],
        );

        late _SpyVideoPlaybackController spy;
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: tokens.toThemeData(),
              home: HermesVideoPlayerScreen(
                title: 'Severance',
                source: source,
                initialQuality: VideoQualityPreset.directPlay,
                config: HermesVideoPlayerConfig.hdrSafeDefault(tokens: tokens),
                cinemaService: service,
                movieId: 'mov-1',
                windowBridge: bridge,
                playbackControllerFactory: (_) {
                  spy = _SpyVideoPlaybackController();
                  return spy;
                },
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(spy.renderedFits.last, BoxFit.contain);

          // Aspect button cycles Fit -> Cover.
          await tester.tap(find.byKey(const Key('vp-aspect-btn')));
          await tester.pump();
          expect(spy.renderedFits.last, BoxFit.cover);
          expect(find.byKey(const Key('vp-hud-pill')), findsOneWidget);
          expect(find.text('Display: Cover'), findsOneWidget);

          // Key 'A' cycles Cover -> Stretch.
          await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
          await tester.pump();
          expect(spy.renderedFits.last, BoxFit.fill);
          expect(find.text('Display: Stretch'), findsOneWidget);

          // Open desktop tracks panel and pick Fit chip directly.
          await tester.tap(find.byKey(const Key('vp-tracks-btn')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('vp-aspect-fit')));
          await tester.pump();
          expect(spy.renderedFits.last, BoxFit.contain);
          await tester.tap(find.byTooltip('Close panel'));
          await tester.pumpAndSettle();

          // ArrowUp (+5%) & mouse wheel down (-5%) adjust volume cleanly.
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
          await tester.pump();
          expect(spy.volumeChanges.last, 85.0);
          expect(find.text('Volume 85%'), findsOneWidget);

          final surfaceCenter = tester.getCenter(
            find.byKey(const Key('spy-video-surface')),
          );
          final pointer = TestPointer(1, PointerDeviceKind.mouse);
          await tester.sendEventToBinding(pointer.hover(surfaceCenter));
          await tester.sendEventToBinding(
            pointer.scroll(const Offset(0, 120)),
          );
          await tester.pump();
          expect(spy.volumeChanges.last, 80.0);

          // F11 toggles native fullscreen bridge cleanly.
          await tester.sendKeyEvent(LogicalKeyboardKey.f11);
          await tester.pump();
          expect(bridge.isFullscreen.value, isTrue);
          expect(fsCalls, contains(true));

          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pump();
          expect(bridge.isFullscreen.value, isFalse);

          // Double-clicking the empty video canvas toggles desktop fullscreen.
          await tester.tapAt(const Offset(200, 300));
          await tester.pump(const Duration(milliseconds: 50));
          await tester.tapAt(const Offset(200, 300));
          await tester.pumpAndSettle();
          expect(bridge.isFullscreen.value, isTrue);

          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pump();
          expect(bridge.isFullscreen.value, isFalse);

          // Flush pending HUD timer cleanly.
          await tester.pump(const Duration(seconds: 4));
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  });

  group('PR32 Horizontal Shelf, Forward Nav, MiniPlayer Wheel, Mouse4/5 & Prefs', () {
    testWidgets('HermesHorizontalShelf shows arrows on hover and scrolls on click', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 320));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HermesHorizontalShelf(
              height: 220,
              itemCount: 12,
              itemBuilder: (_, idx) => SizedBox(
                width: 160,
                child: ColoredBox(
                  color: Colors.blueGrey,
                  child: Center(child: Text('Item $idx')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollState = tester.state<ScrollableState>(
        find.byType(Scrollable),
      );
      expect(scrollState.position.pixels, 0);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(
        tester.getCenter(find.byType(HermesHorizontalShelf)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('shelf-scroll-right')));
      await tester.pumpAndSettle();
      expect(scrollState.position.pixels, greaterThan(100));
    });

    testWidgets('MusicWorldScreen Back & Forward restore scroll positions cleanly', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final albumsJson = [
        for (var i = 1; i <= 24; i++)
          {
            'id': 'alb-$i',
            'artistId': 'art-1',
            'artistName': 'Artist One',
            'title': 'Album $i',
            'year': 2000 + i,
            'songCount': 1,
          },
      ];
      final songs = [
        for (var i = 1; i <= 24; i++)
          _song('s-$i', 'Track $i', albumId: 'alb-$i'),
      ];

      final client = MockClient((req) async {
        if (req.url.path == '/api/v1/music/albums') {
          return http.Response(jsonEncode(albumsJson), 200);
        }
        if (req.url.path == '/api/v1/music/songs') {
          return http.Response(
            jsonEncode(songs.map(_songJson).toList()),
            200,
          );
        }
        if (req.url.path == '/api/v1/music/artists') {
          return http.Response(
            jsonEncode([
              {'id': 'art-1', 'name': 'Artist One', 'albumCount': 24},
            ]),
            200,
          );
        }
        return http.Response('[]', 200);
      });

      final service = MusicService(
        baseUri: Uri.parse('http://localhost:5258'),
        accessToken: 'jwt',
        httpClient: client,
      );
      final coordinator = MusicPlaybackCoordinator(
        localDeviceId: 'dev-win',
        musicService: service,
        audioEngine: _NoopAudioEngine(),
        mediaBridge: InMemoryPlatformMediaBridge(),
        transport: _FakeTransport(songs),
        catalogSongs: {for (final s in songs) s.id: s},
      );
      addTearDown(coordinator.dispose);

      final nav = MusicNavigationController()
        ..navigate(const MusicPageRoute.albums());
      await tester.pumpWidget(
        MaterialApp(
          theme: HermesThemeTokens.resolve().toThemeData(),
          home: Scaffold(
            body: MusicWorldScreen(
              musicService: service,
              coordinator: coordinator,
              navigationController: nav,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollFinder = find.byType(Scrollable).last;
      final scrollState = tester.state<ScrollableState>(scrollFinder);
      scrollState.position.jumpTo(260);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Album 8').last);
      await tester.pumpAndSettle();
      expect(find.text('Album 8'), findsWidgets);

      await tester.tap(find.byKey(const Key('music-topbar-back')));
      await tester.pumpAndSettle();
      expect(scrollState.position.pixels, closeTo(260, 2));

      await tester.tap(find.byKey(const Key('music-topbar-forward')));
      await tester.pumpAndSettle();
      expect(find.text('Track 8'), findsWidgets);
    });

    testWidgets('MiniPlayerBar scroll wheel nudges volume ±5%', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final song = _song('s-1', 'Granite');
      double? reportedVolume;
      await tester.pumpWidget(
        MaterialApp(
          theme: HermesThemeTokens.resolve().toThemeData(),
          home: Scaffold(
            body: MiniPlayerBar(
              session: const PlaybackSessionState(
                sessionId: 'sess-wheel',
                version: 1,
                activeRendererDeviceId: 'dev-win',
                state: PlaybackState.playing,
                repeatMode: HermesRepeatMode.off,
                shuffle: false,
                volume: 0.50,
                currentIndex: 0,
                currentSongId: 's-1',
                positionMs: 1000,
                queueSongIds: ['s-1'],
              ),
              currentSong: song,
              localDeviceId: 'dev-win',
              onTogglePlayPause: () {},
              onSkipNext: () {},
              onOpenDevicePicker: () {},
              onVolumeChanged: (v) => reportedVolume = v,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final sliderCenter = tester.getCenter(find.byType(Slider).last);
      final pointer = TestPointer(2, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(sliderCenter));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -120)));
      await tester.pump();
      expect(reportedVolume, closeTo(0.55, 0.001));
    });

    testWidgets(
      'DualWorldShell handles Mouse4/Mouse5 navigation, F11, ?, and MediaPlayPause',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        var backCalls = 0;
        var forwardCalls = 0;
        var fullscreenCalls = 0;
        var shortcutCalls = 0;
        var playPauseCalls = 0;
        final mediaActions = <String>[];

        await tester.pumpWidget(
          MaterialApp(
            theme: HermesThemeTokens.resolve().toThemeData(),
            home: DualWorldShell(
              username: 'robert',
              isAdmin: true,
              cinemaBuilder: (_) => const SizedBox.expand(),
              musicBuilder: (_) => const SizedBox.expand(),
              miniPlayerBuilder: (_) => const SizedBox(),
              onHandleBack: () {
                backCalls++;
                return true;
              },
              onHandleForward: () {
                forwardCalls++;
                return true;
              },
              onToggleFullscreen: () => fullscreenCalls++,
              onOpenShortcuts: () => shortcutCalls++,
              onTogglePlayPause: () => playPauseCalls++,
              onMediaKeyAction: mediaActions.add,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final center = tester.getCenter(find.byType(DualWorldShell));
        final p = TestPointer(3, PointerDeviceKind.mouse);
        await tester.sendEventToBinding(
          p.down(center, buttons: kBackMouseButton),
        );
        await tester.sendEventToBinding(p.up());
        await tester.sendEventToBinding(
          p.down(center, buttons: kForwardMouseButton),
        );
        await tester.sendEventToBinding(p.up());
        expect(backCalls, 1);
        expect(forwardCalls, 1);

        await tester.sendKeyEvent(LogicalKeyboardKey.f11);
        expect(fullscreenCalls, 1);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.slash);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        expect(shortcutCalls, 1);

        await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
        expect(playPauseCalls, 1);
        expect(mediaActions, ['playPause']);
      },
    );

    testWidgets(
      'HermesDevicePreferences & Settings persist closeToTray and showMediaFlyout on Windows',
      (tester) async {
        const original = HermesDevicePreferences(
          closeToTray: false,
          showMediaFlyout: false,
        );
        final roundtrip = HermesDevicePreferences.fromJson(original.toJson());
        expect(roundtrip.closeToTray, isFalse);
        expect(roundtrip.showMediaFlyout, isFalse);

        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        try {
          HermesDevicePreferences? updated;
          final tokens = HermesThemeTokens.resolve();
          await tester.pumpWidget(
            MaterialApp(
              theme: tokens.toThemeData(),
              home: Scaffold(
                body: PlayerAndThemeSettingsScreen(
                  tokens: tokens,
                  rendererBackend: VideoRendererBackend.openGl,
                  defaultVideoQuality: VideoQualityPreset.directPlay,
                  onThemeChanged: (_) {},
                  onRendererChanged: (_) {},
                  onDefaultVideoQualityChanged: (_) {},
                  onDevicePreferencesChanged: (p) => updated = p,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final traySwitch = find.byKey(
            const Key('setting-close-to-tray-switch'),
          );
          await tester.ensureVisible(traySwitch);
          await tester.pumpAndSettle();
          expect(traySwitch, findsOneWidget);
          expect(
            find.byKey(const Key('setting-media-flyout-switch')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('setting-shortcuts-btn')),
            findsOneWidget,
          );

          await tester.tap(traySwitch);
          await tester.pumpAndSettle();
          expect(updated?.closeToTray, isFalse);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  });
}
