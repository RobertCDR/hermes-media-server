import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_client/src/core/theme/hermes_theme_tokens.dart';
import 'package:hermes_client/src/core/widgets/hermes_icons.dart';
import 'package:hermes_client/src/features/music/device_picker_sheet.dart';
import 'package:hermes_client/src/features/music/mini_player_bar.dart';
import 'package:hermes_client/src/features/music/music_models.dart';
import 'package:hermes_client/src/features/music/music_playback_coordinator.dart';
import 'package:hermes_client/src/features/music/music_service.dart';
import 'package:hermes_client/src/features/music/music_world_screen.dart';
import 'package:hermes_client/src/features/music/now_playing_panel.dart';
import 'package:hermes_client/src/features/music/platform_media_bridge.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

class _TrackingAudioEngine implements AudioEngineAdapter {
  int seekCount = 0;
  int? lastSeekMs;

  @override
  Future<void> loadAndPlay(Uri streamUri, SongModel track, int startPositionMs) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(int positionMs) async {
    seekCount++;
    lastSeekMs = positionMs;
  }

  @override
  Future<void> stop() async {}
}

Map<String, dynamic> _songJson({
  required String id,
  required String artistId,
  required String artistName,
  required String albumId,
  required String albumTitle,
  required String title,
  int trackNumber = 1,
  int discNumber = 1,
  int durationMs = 210000,
  String codec = 'flac',
  bool isLiked = false,
  String? modifiedUtc,
}) {
  return {
    'id': id,
    'artistId': artistId,
    'artistName': artistName,
    'albumId': albumId,
    'albumTitle': albumTitle,
    'title': title,
    'trackNumber': trackNumber,
    'discNumber': discNumber,
    'durationMs': durationMs,
    'codec': codec,
    'bitrateBps': 1411000,
    'sampleRateHz': 44100,
    'bitDepth': 16,
    'artworkHash': null,
    'isLiked': isLiked,
    'isMissing': false,
    'fileLastWriteUtc': ?modifiedUtc,
  };
}

void main() {
  group('M3 MusicService extensions & tint derivation', () {
    test('calls album, artist, playlist CRUD and lyrics endpoints accurately', () async {
      final methods = <String>[];
      final trackA = _songJson(
        id: 'song-1',
        artistId: 'art-1',
        artistName: 'Daft Punk',
        albumId: 'alb-1',
        albumTitle: 'Discovery',
        title: 'One More Time',
        modifiedUtc: '2026-11-16T12:00:00Z',
      );

      final client = MockClient((req) async {
        methods.add('${req.method} ${req.url.path}');
        if (req.url.path == '/api/v1/music/albums/alb-1') {
          return http.Response(
            jsonEncode({
              'id': 'alb-1',
              'artistId': 'art-1',
              'artistName': 'Daft Punk',
              'title': 'Discovery',
              'year': 2001,
              'songs': [trackA],
            }),
            200,
          );
        }
        if (req.url.path == '/api/v1/music/artists/art-1') {
          return http.Response(
            jsonEncode({
              'id': 'art-1',
              'name': 'Daft Punk',
              'albums': [
                {
                  'id': 'alb-1',
                  'artistId': 'art-1',
                  'artistName': 'Daft Punk',
                  'title': 'Discovery',
                  'year': 2001,
                  'songCount': 1,
                },
              ],
              'songs': [trackA],
            }),
            200,
          );
        }
        if (req.url.path == '/api/v1/music/playlists/pl-1' && req.method == 'PUT') {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'id': 'pl-1',
              'name': body['name'],
              'tracks': [
                {'position': 0, 'song': trackA},
              ],
            }),
            200,
          );
        }
        if (req.url.path == '/api/v1/music/playlists/pl-1' && req.method == 'DELETE') {
          return http.Response('', 204);
        }
        if (req.url.path == '/api/v1/music/playlists/pl-1/tracks') {
          return http.Response(
            jsonEncode({
              'id': 'pl-1',
              'name': 'Club',
              'tracks': [
                {'position': 0, 'song': trackA},
              ],
            }),
            200,
          );
        }
        if (req.url.path == '/api/v1/music/playlists/pl-1/tracks/0' && req.method == 'DELETE') {
          return http.Response(
            jsonEncode({
              'id': 'pl-1',
              'name': 'Club',
              'tracks': [],
            }),
            200,
          );
        }
        if (req.url.path == '/api/v1/music/songs/song-1/lyrics') {
          return http.Response(
            jsonEncode({
              'songId': 'song-1',
              'isSynced': true,
              'source': 'sidecar',
              'lines': [
                {'timestampMs': 5000, 'text': 'One more time'},
                {'timestampMs': 12000, 'text': "We're gonna celebrate"},
              ],
            }),
            200,
          );
        }
        return http.Response('[]', 200);
      });

      final service = MusicService(
        baseUri: Uri.parse('http://localhost:5000'),
        accessToken: 'jwt',
        httpClient: client,
      );

      final album = await service.getAlbum('alb-1');
      expect(album.title, 'Discovery');
      expect(album.songs.single.fileLastWriteUtc, DateTime.utc(2026, 11, 16, 12));

      final artist = await service.getArtist('art-1');
      expect(artist.name, 'Daft Punk');
      expect(artist.albums.single.id, 'alb-1');

      final added = await service.addTrackToPlaylist(playlistId: 'pl-1', songId: 'song-1');
      expect(added.tracks, hasLength(1));

      final removed = await service.removePlaylistTrack(playlistId: 'pl-1', position: 0);
      expect(removed.tracks, isEmpty);

      final renamed = await service.renamePlaylist(playlistId: 'pl-1', name: 'Midnight');
      expect(renamed.name, 'Midnight');

      await service.deletePlaylist('pl-1');

      final lyrics = await service.getSongLyrics('song-1');
      expect(lyrics.isSynced, isTrue);
      expect(lyrics.lines, hasLength(2));
      expect(lyrics.lines.first.timestampMs, 5000);

      expect(deriveMusicTint('Discovery'), deriveMusicTint('Discovery'));
      expect(deriveMusicTint('Discovery'), isNot(deriveMusicTint('Random Access Memories')));
      expect(methods, contains('DELETE /api/v1/music/playlists/pl-1'));
    });
  });

  group('M3 Coordinator Queue, Shuffle, Repeat, Seek, Volume & Like sync', () {
    const s1 = SongModel(
      id: 's1',
      artistId: 'a1',
      artistName: 'Artist',
      albumId: 'alb1',
      albumTitle: 'Album',
      title: 'Track 1',
      trackNumber: 1,
      discNumber: 1,
      durationMs: 180000,
      codec: 'flac',
      bitrateBps: 1411000,
      sampleRateHz: 44100,
      bitDepth: 16,
      isLiked: false,
      isMissing: false,
    );
    const s2 = SongModel(
      id: 's2',
      artistId: 'a1',
      artistName: 'Artist',
      albumId: 'alb1',
      albumTitle: 'Album',
      title: 'Track 2',
      trackNumber: 2,
      discNumber: 1,
      durationMs: 200000,
      codec: 'flac',
      bitrateBps: 1411000,
      sampleRateHz: 44100,
      bitDepth: 16,
      isLiked: false,
      isMissing: false,
    );
    const s3 = SongModel(
      id: 's3',
      artistId: 'a1',
      artistName: 'Artist',
      albumId: 'alb2',
      albumTitle: 'Single',
      title: 'Up Next Song',
      trackNumber: 1,
      discNumber: 1,
      durationMs: 150000,
      codec: 'flac',
      bitrateBps: 1411000,
      sampleRateHz: 44100,
      bitDepth: 16,
      isLiked: true,
      isMissing: false,
    );

    test('consumes upNext before source queue and handles shuffle/repeat/volume/like', () async {
      final engine = _TrackingAudioEngine();
      final svc = MusicService(
        baseUri: Uri.parse('http://localhost:5000'),
        accessToken: 'jwt',
        httpClient: MockClient((req) async {
          if (req.url.path == '/api/v1/music/songs/s1/like') {
            return http.Response(jsonEncode({'songId': 's1', 'isLiked': true}), 200);
          }
          if (req.url.path == '/api/v1/auth/stream-tickets') {
            return http.Response(jsonEncode({'ticket': 'aud-tkt'}), 200);
          }
          return http.Response('[]', 200);
        }),
      );

      final coordinator = MusicPlaybackCoordinator(
        localDeviceId: 'dev-local',
        musicService: svc,
        audioEngine: engine,
        mediaBridge: InMemoryPlatformMediaBridge(),
      );

      await coordinator.startQueue([s1, s2], 0, sourceLabel: 'Album');
      expect(coordinator.currentSong?.id, 's1');
      expect(coordinator.upcomingFromSource.map((s) => s.id), ['s2']);

      coordinator.addToQueue(s3);
      expect(coordinator.upNext.map((s) => s.id), ['s3']);

      await coordinator.skipNext();
      expect(coordinator.currentSong?.id, 's3');
      expect(coordinator.upNext, isEmpty);

      await coordinator.seekTo(65000);
      expect(engine.seekCount, 1);
      expect(engine.lastSeekMs, 65000);
      expect(coordinator.session?.positionMs, 65000);

      // Past 4 seconds -> skipPrevious seeks back to 0 first
      await coordinator.skipPrevious();
      expect(coordinator.session?.positionMs, 0);

      await coordinator.toggleShuffle();
      expect(coordinator.session?.shuffle, isTrue);

      await coordinator.cycleRepeatMode();
      expect(coordinator.session?.repeatMode, HermesRepeatMode.all);
      await coordinator.cycleRepeatMode();
      expect(coordinator.session?.repeatMode, HermesRepeatMode.one);
      await coordinator.cycleRepeatMode();
      expect(coordinator.session?.repeatMode, HermesRepeatMode.off);

      await coordinator.setVolume(0.45);
      expect(coordinator.session?.volume, closeTo(0.45, 0.001));
      await coordinator.toggleMute();
      expect(coordinator.session?.volume, 0.0);
      await coordinator.toggleMute();
      expect(coordinator.session?.volume, closeTo(0.45, 0.001));

      await coordinator.toggleLikeSong('s1');
      expect(coordinator.songById('s1')?.isLiked, isTrue);

      coordinator.toggleNowPlaying();
      expect(coordinator.nowPlayingOpen, isTrue);
    });
  });

  group('M3 Spotify-style MusicWorldScreen navigation, playlists & responsive layout', () {
    MusicService makeCatalogService(List<Map<String, dynamic>> playlists) {
      final songs = [
        _songJson(
          id: 's1',
          artistId: 'art-1',
          artistName: 'M83',
          albumId: 'alb-1',
          albumTitle: 'Hurry Up, Were Dreaming',
          title: 'Intro',
          discNumber: 1,
          trackNumber: 1,
        ),
        _songJson(
          id: 's2',
          artistId: 'art-1',
          artistName: 'M83',
          albumId: 'alb-1',
          albumTitle: 'Hurry Up, Were Dreaming',
          title: 'Midnight City',
          discNumber: 2,
          trackNumber: 1,
          isLiked: true,
        ),
      ];
      return MusicService(
        baseUri: Uri.parse('http://localhost:5000'),
        accessToken: 'jwt',
        httpClient: MockClient((req) async {
          if (req.url.path == '/api/v1/music/artists') {
            return http.Response(
              jsonEncode([
                {'id': 'art-1', 'name': 'M83', 'albumCount': 1},
              ]),
              200,
            );
          }
          if (req.url.path == '/api/v1/music/albums') {
            return http.Response(
              jsonEncode([
                {
                  'id': 'alb-1',
                  'artistId': 'art-1',
                  'artistName': 'M83',
                  'title': 'Hurry Up, Were Dreaming',
                  'year': 2011,
                  'songCount': 2,
                },
              ]),
              200,
            );
          }
          if (req.url.path == '/api/v1/music/songs') {
            return http.Response(jsonEncode(songs), 200);
          }
          if (req.url.path == '/api/v1/music/playlists' && req.method == 'GET') {
            return http.Response(jsonEncode(playlists), 200);
          }
          if (req.url.path == '/api/v1/music/playlists' && req.method == 'POST') {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            final created = {
              'id': 'pl-new',
              'name': body['name'],
              'trackCount': 0,
              'createdAtUtc': '2026-11-17T10:00:00Z',
              'updatedAtUtc': '2026-11-17T10:00:00Z',
            };
            playlists.add(created);
            return http.Response(
              jsonEncode({
                'id': 'pl-new',
                'name': body['name'],
                'tracks': [],
              }),
              201,
            );
          }
          if (req.url.path == '/api/v1/music/playlists/pl-new' && req.method == 'GET') {
            return http.Response(
              jsonEncode({'id': 'pl-new', 'name': playlists.last['name'], 'tracks': []}),
              200,
            );
          }
          if (req.url.path == '/api/v1/music/playlists/pl-new' && req.method == 'PUT') {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode({'id': 'pl-new', 'name': body['name'], 'tracks': []}),
              200,
            );
          }
          if (req.url.path == '/api/v1/music/playlists/pl-new' && req.method == 'DELETE') {
            playlists.clear();
            return http.Response('', 204);
          }
          return http.Response('[]', 200);
        }),
      );
    }

    testWidgets('navigates Home -> Album (Disc grouping) -> Artist -> Liked -> Search on desktop without overflow', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1280, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final playlists = <Map<String, dynamic>>[];
      final service = makeCatalogService(playlists);
      final coordinator = MusicPlaybackCoordinator(
        localDeviceId: 'dev-1',
        musicService: service,
        audioEngine: NoOpAudioEngineAdapter(),
        mediaBridge: InMemoryPlatformMediaBridge(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: HermesThemeTokens.resolve().toThemeData(),
          home: Scaffold(
            body: MusicWorldScreen(
              musicService: service,
              coordinator: coordinator,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Sidebar & Home shelves render cleanly
      expect(find.text('Your Library'), findsOneWidget);
      expect(find.text('Recently added'), findsWidgets);
      expect(find.text('Made from your library'), findsOneWidget);
      expect(find.text('Your artists'), findsOneWidget);

      // Navigate into Album detail page (multi-disc renders Disc 1 & Disc 2)
      await tester.tap(find.text('Hurry Up, Were Dreaming').first);
      await tester.pumpAndSettle();
      expect(find.text('Album'), findsWidgets);
      expect(find.text('Disc 1'), findsOneWidget);
      expect(find.text('Disc 2'), findsOneWidget);
      expect(find.text('Released 2011'), findsOneWidget);

      // Click artist name on Album page -> navigates inline to Artist banner page
      await tester.tap(find.text('M83').first);
      await tester.pumpAndSettle();
      expect(find.text('Popular'), findsOneWidget);
      expect(find.text('Discography'), findsOneWidget);

      // Navigate to Liked Songs via sidebar
      await tester.tap(find.text('Liked Songs').first);
      await tester.pumpAndSettle();
      expect(find.text('Songs you saved • 1 song'), findsOneWidget);

      // Search filters live and handles empty state cleanly
      await tester.enterText(find.byType(TextField), 'NonexistentXYZ');
      await tester.pumpAndSettle();
      expect(find.textContaining('No results for "NonexistentXYZ"'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('supports playlist create, rename, and delete cleanly + narrow 400x800 mobile layout', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(400, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final playlists = <Map<String, dynamic>>[];
      final service = makeCatalogService(playlists);
      final coordinator = MusicPlaybackCoordinator(
        localDeviceId: 'dev-1',
        musicService: service,
        audioEngine: NoOpAudioEngineAdapter(),
        mediaBridge: InMemoryPlatformMediaBridge(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: HermesThemeTokens.resolve().toThemeData(),
          home: Scaffold(
            body: MusicWorldScreen(
              musicService: service,
              coordinator: coordinator,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Mobile nav strip visible cleanly with zero overflow
      final libraryTab = find.text('Library').first;
      await tester.ensureVisible(libraryTab);
      await tester.pumpAndSettle();
      await tester.tap(libraryTab);
      await tester.pumpAndSettle();

      await tester.tap(find.text('New playlist'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Drive');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(find.text('Drive'), findsWidgets);

      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Afterglow');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Afterglow'), findsWidgets);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Afterglow'), findsNothing);

      expect(tester.takeException(), isNull);
    });
  });

  group('M3 MiniPlayerBar Alignment, NowPlayingPanel & Compact DevicePickerSheet', () {
    const song = SongModel(
      id: 'song-1',
      artistId: 'art-1',
      artistName: 'Kavinsky',
      albumId: 'alb-1',
      albumTitle: 'OutRun',
      title: 'Nightcall',
      trackNumber: 1,
      discNumber: 1,
      durationMs: 258000,
      codec: 'flac',
      bitrateBps: 1411000,
      sampleRateHz: 44100,
      bitDepth: 16,
      isLiked: false,
      isMissing: false,
    );

    const session = PlaybackSessionState(
      sessionId: 'sess-1',
      version: 1,
      activeRendererDeviceId: 'dev-remote',
      activeRendererDeviceName: 'Studio Speakers',
      state: PlaybackState.paused,
      repeatMode: HermesRepeatMode.one,
      shuffle: true,
      volume: 0.72,
      currentIndex: 0,
      currentSongId: 'song-1',
      positionMs: 12000,
      queueSongIds: ['song-1'],
    );

    testWidgets('aligns Shuffle/Prev/Play(HermesPlayIcon)/Next/Repeat centers horizontally and renders remote strip', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1280, 300);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: HermesThemeTokens.resolve().toThemeData(),
          home: Scaffold(
            body: MiniPlayerBar(
              session: session,
              currentSong: song,
              localDeviceId: 'dev-local',
              onTogglePlayPause: () {},
              onSkipNext: () {},
              onSkipPrevious: () {},
              onToggleShuffle: () {},
              onCycleRepeat: () {},
              onSeekMs: (_) {},
              onVolumeChanged: (_) {},
              onToggleMute: () {},
              onToggleLike: () {},
              onToggleNowPlaying: () {},
              onOpenDevicePicker: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Optical HermesPlayIcon rendered inside circular Play button
      expect(find.byType(HermesPlayIcon), findsOneWidget);
      expect(find.text('1'), findsOneWidget); // Repeat One badge
      expect(find.text('Playing on Studio Speakers'), findsWidgets);

      final shuffleY = tester.getCenter(find.byIcon(Icons.shuffle_rounded)).dy;
      final prevY = tester.getCenter(find.byIcon(Icons.skip_previous_rounded)).dy;
      final playY = tester.getCenter(find.byType(HermesPlayIcon)).dy;
      final nextY = tester.getCenter(find.byIcon(Icons.skip_next_rounded)).dy;
      final repeatY = tester.getCenter(find.byIcon(Icons.repeat_rounded)).dy;

      expect((shuffleY - playY).abs(), lessThanOrEqualTo(2.0));
      expect((prevY - playY).abs(), lessThanOrEqualTo(2.0));
      expect((nextY - playY).abs(), lessThanOrEqualTo(2.0));
      expect((repeatY - playY).abs(), lessThanOrEqualTo(2.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('NowPlayingPanel shows Queue & synced Lyrics (click to seek) and compact DevicePickerSheet works cleanly', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 820);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final engine = _TrackingAudioEngine();
      final service = MusicService(
        baseUri: Uri.parse('http://localhost:5000'),
        accessToken: 'jwt',
        httpClient: MockClient((req) async {
          if (req.url.path == '/api/v1/music/songs/song-1/lyrics') {
            return http.Response(
              jsonEncode({
                'songId': 'song-1',
                'isSynced': true,
                'source': 'sidecar',
                'lines': [
                  {'timestampMs': 5000, 'text': "I'm giving you a night call"},
                  {'timestampMs': 18000, 'text': 'To tell you how I feel'},
                ],
              }),
              200,
            );
          }
          if (req.url.path == '/api/v1/auth/stream-tickets') {
            return http.Response(jsonEncode({'ticket': 'aud-tkt'}), 200);
          }
          return http.Response('[]', 200);
        }),
      );

      final coordinator = MusicPlaybackCoordinator(
        localDeviceId: 'dev-local',
        musicService: service,
        audioEngine: engine,
        mediaBridge: InMemoryPlatformMediaBridge(),
      );
      await coordinator.startQueue([song], 0, sourceLabel: 'OutRun');

      String? selectedDevice;
      await tester.pumpWidget(
        MaterialApp(
          theme: HermesThemeTokens.resolve().toThemeData(),
          home: Scaffold(
            body: Row(
              children: [
                Expanded(
                  child: NowPlayingPanel(
                    coordinator: coordinator,
                    musicService: service,
                    localDeviceId: 'dev-local',
                    onClose: () {},
                    onOpenDevices: () {},
                    onNavigate: (_) {},
                  ),
                ),
                SizedBox(
                  width: 310,
                  child: DevicePickerSheet(
                    devices: [
                      OnlineDeviceModel(
                        deviceId: 'dev-local',
                        deviceName: 'Desktop',
                        platform: 'Windows',
                        connectedAtUtc: DateTime.utc(2026, 11, 17),
                      ),
                      OnlineDeviceModel(
                        deviceId: 'dev-tv',
                        deviceName: 'Living Room TV',
                        platform: 'Android',
                        connectedAtUtc: DateTime.utc(2026, 11, 17),
                      ),
                    ],
                    activeRendererDeviceId: 'dev-local',
                    localDeviceId: 'dev-local',
                    onSelectDevice: (id) => selectedDevice = id,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Now playing'), findsOneWidget);
      expect(find.text('Next from OutRun'), findsOneWidget);
      expect(find.text('Current device'), findsOneWidget);
      expect(find.text('Select another device'), findsOneWidget);

      await tester.tap(find.text('Living Room TV'));
      await tester.pumpAndSettle();
      expect(selectedDevice, 'dev-tv');

      await tester.tap(find.text('Lyrics'));
      await tester.pumpAndSettle();
      expect(find.text("I'm giving you a night call"), findsOneWidget);

      await tester.tap(find.text('To tell you how I feel'));
      await tester.pumpAndSettle();
      expect(engine.lastSeekMs, 18000);
      expect(tester.takeException(), isNull);
    });
  });
}
