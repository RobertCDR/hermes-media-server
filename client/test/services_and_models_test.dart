import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_client/src/core/auth/auth_service.dart';
import 'package:hermes_client/src/core/auth/session_store.dart';
import 'package:hermes_client/src/core/theme/hermes_theme_tokens.dart';
import 'package:hermes_client/src/features/admin/admin_service.dart';
import 'package:hermes_client/src/features/cinema/cinema_models.dart';
import 'package:hermes_client/src/features/cinema/cinema_service.dart';
import 'package:hermes_client/src/features/cinema/hermes_video_player.dart';
import 'package:hermes_client/src/features/music/music_models.dart';
import 'package:hermes_client/src/features/music/music_playback_coordinator.dart';
import 'package:hermes_client/src/features/music/music_service.dart';
import 'package:hermes_client/src/features/music/platform_media_bridge.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('AuthService & SessionStore comprehensive paths', () {
    test('covers setup, invite register, session copyWith, refresh de-duplication, and failures', () async {
      var refreshCalls = 0;
      var failNext = false;

      final client = MockClient((req) async {
        if (failNext) {
          return http.Response('{"error":"fail"}', 401);
        }

        return switch (req.url.path) {
          '/api/v1/setup' => http.Response('{}', 201),
          '/api/v1/auth/register' => http.Response('{}', 201),
          '/api/v1/auth/login' => http.Response(
              jsonEncode({
                'userId': 'u-1',
                'username': 'admin',
                'role': 'Admin',
                'accessToken': 'jwt-1',
                'refreshToken': 'ref-1',
              }),
              200,
            ),
          '/api/v1/auth/refresh' => () {
              refreshCalls++;
              return http.Response(
                jsonEncode({
                  'accessToken': 'jwt-2',
                  'refreshToken': 'ref-2',
                  'role': 'Admin',
                }),
                200,
              );
            }(),
          _ => http.Response('not found', 404),
        };
      });

      final store = InMemorySessionStore();
      final auth = AuthService(httpClient: client, sessionStore: store);

      await auth.setupServer(
        baseUrl: 'http://localhost:5258',
        adminUsername: 'admin',
        adminPassword: 'Password123!',
        serverName: 'Hermes',
      );
      await auth.registerWithInvite(
        baseUrl: 'http://localhost:5258',
        username: 'bob',
        password: 'Password123!',
        inviteCode: 'HRM-1234',
      );

      final loggedIn = await auth.login(
        primaryUrl: 'https://hermes.ts.net',
        lanFallbackUrl: 'http://192.168.1.10:5258',
        resolvedBaseUrl: 'http://localhost:5258',
        serverId: 'srv-1',
        username: 'admin',
        password: 'Password123!',
        deviceId: 'dev-1',
        deviceName: 'Edge Web',
      );
      expect(loggedIn.isAdmin, isTrue);

      final copied = loggedIn.copyWith(serverPrimaryUrl: 'https://new.ts.net');
      expect(copied.serverPrimaryUrl, 'https://new.ts.net');

      // Concurrent refreshes share one in-flight HTTP call
      final results = await Future.wait([
        auth.refreshSession('http://localhost:5258'),
        auth.refreshSession('http://localhost:5258'),
      ]);
      expect(refreshCalls, 1);
      expect(results[0].accessToken, 'jwt-2');

      // Failing requests throw AuthException cleanly and clear session on refresh failure
      failNext = true;
      await expectLater(
        () => auth.setupServer(
          baseUrl: 'http://localhost:5258',
          adminUsername: 'a',
          adminPassword: 'b',
          serverName: 'c',
        ),
        throwsA(isA<AuthException>()),
      );
      await expectLater(
        () => auth.registerWithInvite(
          baseUrl: 'http://localhost:5258',
          username: 'a',
          password: 'b',
          inviteCode: 'c',
        ),
        throwsA(isA<AuthException>()),
      );
      await expectLater(
        () => auth.refreshSession('http://localhost:5258'),
        throwsA(isA<AuthException>()),
      );
      expect(await store.load(), isNull);
      await expectLater(
        () => auth.refreshSession('http://localhost:5258'),
        throwsA(isA<AuthException>()),
      );
      expect(const AuthException('err', statusCode: 401).toString(), contains('401'));
    });
  });

  group('CinemaService & Cinema models deserialization + Player Screen', () {
    test('deserializes movies, series, seasons, episodes, sources, streams, and progress', () async {
      var shouldFail = false;
      final client = MockClient((req) async {
        if (shouldFail) {
          return http.Response('err', 500);
        }
        if (req.url.path == '/api/v1/cinema/movies') {
          return http.Response(
            jsonEncode([
              {
                'id': 'mov-1',
                'title': 'Dune: Part Two',
                'year': 2024,
                'overview': 'Paul Atreides',
                'tmdbId': 693134,
                'artworkHash': 'hash1',
                'backdropHash': 'bg1',
                'watchProgress': {
                  'positionMs': 500,
                  'durationMs': 1000,
                  'isWatched': false,
                  'updatedAtUtc': '2026-11-15T12:00:00Z',
                },
                'sources': [
                  {
                    'id': 'src-1',
                    'sourceLabel': '4K HDR',
                    'container': 'mkv',
                    'videoCodec': 'hevc',
                    'audioCodec': 'eac3',
                    'width': 3840,
                    'height': 2160,
                    'isHdr': true,
                    'bitrateBps': 20000000,
                    'durationMs': 120000,
                    'isAvailable': true,
                    'streams': [
                      {
                        'streamIndex': 0,
                        'kind': 0,
                        'codec': 'hevc',
                        'language': 'und',
                        'title': 'Video',
                        'isDefault': true,
                      },
                      {
                        'streamIndex': 1,
                        'kind': 1,
                        'codec': 'eac3',
                        'language': 'eng',
                        'title': 'English 5.1',
                        'isDefault': true,
                      },
                      {
                        'streamIndex': 2,
                        'kind': 2,
                        'codec': 'subrip',
                        'language': 'eng',
                        'title': 'English',
                        'isDefault': true,
                      },
                    ],
                  },
                ],
              },
            ]),
            200,
          );
        }
        if (req.url.path == '/api/v1/cinema/series') {
          return http.Response(
            jsonEncode([
              {
                'id': 'ser-1',
                'title': 'Severance',
                'year': 2022,
                'seasons': [
                  {
                    'id': 'sea-1',
                    'seasonNumber': 1,
                    'title': 'Season 1',
                    'episodes': [
                      {
                        'id': 'ep-1',
                        'episodeNumber': 1,
                        'title': 'Pilot',
                        'sources': [],
                      },
                    ],
                  },
                ],
              },
            ]),
            200,
          );
        }
        if (req.url.path == '/api/v1/auth/stream-tickets') {
          return http.Response(jsonEncode({'ticket': 'tkt-vid-1'}), 200);
        }
        return http.Response('[]', 200);
      });

      final service = CinemaService(
        baseUri: Uri.parse('http://localhost:5258'),
        accessToken: 'jwt',
        httpClient: client,
      );

      final movies = await service.listMovies();
      expect(movies, hasLength(1));
      expect(movies[0].watchProgress!.completionRatio, 0.5);
      expect(
        WatchProgressModel(
          positionMs: 0,
          durationMs: 0,
          isWatched: false,
          updatedAtUtc: DateTime.utc(2026),
        ).completionRatio,
        0,
      );

      final series = await service.listSeries();
      expect(series.single.seasons.single.episodes.single.title, 'Pilot');
      expect(await service.issueStreamTicket('src-1'), 'tkt-vid-1');
      expect(service.buildArtworkUri(null), isNull);
      expect(service.buildArtworkUri('abc')?.path, '/api/v1/artwork/abc/poster_800.webp');

      shouldFail = true;
      await expectLater(() => service.listMovies(), throwsA(isA<CinemaApiException>()));
      await expectLater(() => service.listSeries(), throwsA(isA<CinemaApiException>()));
      await expectLater(() => service.issueStreamTicket('src-1'), throwsA(isA<CinemaApiException>()));
      await expectLater(
        () => service.updateWatchProgress(movieId: 'm', positionMs: 1, durationMs: 2),
        throwsA(isA<CinemaApiException>()),
      );
      expect(const CinemaApiException('boom', statusCode: 500).toString(), contains('500'));
    });

    testWidgets('HermesVideoPlayerScreen loads ticket and updates quality/audio/subtitle controls', (tester) async {
      final client = MockClient((req) async {
        if (req.url.path == '/api/v1/auth/stream-tickets') {
          return http.Response(jsonEncode({'ticket': 'tkt-player'}), 200);
        }
        if (req.url.path == '/api/v1/cinema/progress') {
          return http.Response(
            jsonEncode({
              'positionMs': 30000,
              'durationMs': 120000,
              'isWatched': false,
              'updatedAtUtc': '2026-11-15T12:00:00Z',
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
        id: 'src-play',
        sourceLabel: '1080p BluRay',
        container: 'mkv',
        videoCodec: 'h264',
        audioCodec: 'aac',
        width: 1920,
        height: 1080,
        isHdr: false,
        bitrateBps: 8000000,
        durationMs: 120000,
        isAvailable: true,
        streams: [
          MediaStreamModel(
            streamIndex: 1,
            kind: 1,
            codec: 'aac',
            language: 'eng',
            title: 'English Stereo',
            isDefault: true,
          ),
          MediaStreamModel(
            streamIndex: 2,
            kind: 1,
            codec: 'ac3',
            language: 'jpn',
            title: 'Japanese',
            isDefault: false,
          ),
          MediaStreamModel(
            streamIndex: 3,
            kind: 2,
            codec: 'subrip',
            language: 'eng',
            title: 'SDH',
            isDefault: true,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: tokens.toThemeData(),
          home: HermesVideoPlayerScreen(
            title: 'Blade Runner',
            source: source,
            initialQuality: VideoQualityPreset.directPlay,
            config: HermesVideoPlayerConfig.hdrSafeDefault(tokens: tokens),
            cinemaService: service,
            movieId: 'mov-1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Blade Runner'), findsOneWidget);
      expect(find.text('OpenGL HDR'), findsOneWidget);
      expect(find.textContaining('WebVTT Subtitles Ready'), findsOneWidget);

      // Toggle play/pause
      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump();
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);

      // Change quality dropdown to 720p
      await tester.tap(find.text('Direct Play'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('720p').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('quality=720p'), findsOneWidget);

      // Change audio stream dropdown
      await tester.tap(find.text('Audio: ENG (aac)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Audio: JPN (ac3)').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('audioStreamIndex=2'), findsOneWidget);

      // Turn off subtitles via dropdown
      await tester.tap(find.text('Sub: ENG (SDH)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Subtitles: Off').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('WebVTT Subtitles Ready'), findsNothing);
    });
  });

  group('MusicService, Music models & Coordinator remaining paths', () {
    test('deserializes all music DTOs, playlists, devices, session state, and handles errors', () async {
      var fail = false;
      final songJson = {
        'id': 'song-1',
        'artistId': 'art-1',
        'artistName': 'Kavinsky',
        'albumId': 'alb-1',
        'albumTitle': 'OutRun',
        'title': 'Nightcall',
        'trackNumber': 1,
        'discNumber': 1,
        'durationMs': 258000,
        'codec': 'flac',
        'bitrateBps': 1411000,
        'sampleRateHz': 44100,
        'bitDepth': 16,
        'artworkHash': 'art-hash',
        'isLiked': true,
        'isMissing': false,
      };

      final client = MockClient((req) async {
        if (fail) {
          return http.Response('err', 500);
        }
        return switch (req.url.path) {
          '/api/v1/music/artists' => http.Response(
              jsonEncode([
                {'id': 'art-1', 'name': 'Kavinsky', 'artworkHash': 'a1', 'albumCount': 1},
              ]),
              200,
            ),
          '/api/v1/music/albums' => http.Response(
              jsonEncode([
                {'id': 'alb-1', 'artistId': 'art-1', 'artistName': 'Kavinsky', 'title': 'OutRun', 'year': 2013, 'songCount': 1},
              ]),
              200,
            ),
          '/api/v1/music/songs' || '/api/v1/music/songs/liked' => http.Response(jsonEncode([songJson]), 200),
          '/api/v1/music/songs/song-1/like' => http.Response(jsonEncode({'songId': 'song-1', 'isLiked': false}), 200),
          '/api/v1/music/playlists' when req.method == 'GET' => http.Response(
              jsonEncode([
                {
                  'id': 'pl-1',
                  'name': 'Synth',
                  'description': 'Night',
                  'trackCount': 1,
                  'createdAtUtc': '2026-11-15T10:00:00Z',
                  'updatedAtUtc': '2026-11-15T11:00:00Z',
                },
              ]),
              200,
            ),
          '/api/v1/music/playlists' when req.method == 'POST' => http.Response(
              jsonEncode({
                'id': 'pl-1',
                'name': 'Synth',
                'description': 'Night',
                'tracks': [
                  {'position': 0, 'song': songJson},
                ],
              }),
              201,
            ),
          '/api/v1/auth/stream-tickets' => http.Response(jsonEncode({'ticket': 'aud-tkt'}), 200),
          '/api/v1/music/devices' => http.Response(
              jsonEncode([
                {
                  'deviceId': 'dev-1',
                  'deviceName': 'Desktop',
                  'platform': 'Windows',
                  'connectedAtUtc': '2026-11-15T10:00:00Z',
                },
              ]),
              200,
            ),
          _ => http.Response('[]', 200),
        };
      });

      final service = MusicService(
        baseUri: Uri.parse('http://localhost:5258'),
        accessToken: 'jwt',
        httpClient: client,
      );

      expect((await service.listArtists()).single.name, 'Kavinsky');
      expect((await service.listAlbums()).single.title, 'OutRun');
      final songs = await service.listSongs();
      expect(songs.single.copyWith(isLiked: false).isLiked, isFalse);
      expect(await service.listLikedSongs(), hasLength(1));
      expect(await service.toggleLikeSong('song-1'), isFalse);
      expect((await service.listPlaylists()).single.name, 'Synth');
      expect((await service.createPlaylist(name: 'Synth', description: 'Night')).tracks, hasLength(1));
      expect(await service.issueAudioTicket('song-1'), 'aud-tkt');
      expect((await service.getOnlineDevices()).single.platform, 'Windows');

      final sessionFromJson = PlaybackSessionState.fromJson({
        'sessionId': 's-1',
        'version': 7,
        'activeRendererDeviceId': 'dev-1',
        'activeRendererDeviceName': 'Desktop',
        'state': 1,
        'repeatMode': 2,
        'shuffle': true,
        'volume': 0.85,
        'currentIndex': 0,
        'currentSongId': 'song-1',
        'positionMs': 4200,
        'queueSongIds': ['song-1'],
      });
      expect(sessionFromJson.state, PlaybackState.playing);
      expect(sessionFromJson.repeatMode, HermesRepeatMode.one);
      expect(PlaybackState.fromApiInt(2), PlaybackState.paused);
      expect(PlaybackState.fromApiInt(0), PlaybackState.stopped);
      expect(HermesRepeatMode.fromApiInt(1), HermesRepeatMode.all);
      expect(HermesRepeatMode.fromApiInt(0), HermesRepeatMode.off);

      // Coordinator local mode (no transport): startQueue, skipNext/Prev, togglePlayPause, stop
      final noOpEngine = NoOpAudioEngineAdapter();
      await noOpEngine.seek(100);
      final bridge = InMemoryPlatformMediaBridge();
      final coordinator = MusicPlaybackCoordinator(
        localDeviceId: 'dev-1',
        musicService: service,
        audioEngine: noOpEngine,
        mediaBridge: bridge,
      );
      await coordinator.startQueue(songs, 0);
      expect(coordinator.currentSong?.id, 'song-1');
      await coordinator.togglePlayPause();
      expect(coordinator.session?.state, PlaybackState.paused);
      await coordinator.skipNext();
      await coordinator.skipPrevious();
      coordinator.updateQualityPolicy(const AudioQualityPolicy(wifiPreset: AudioQualityPreset.veryHigh320));
      await bridge.simulateMediaButton(MediaButtonAction.stop);
      expect(coordinator.session?.state, PlaybackState.stopped);

      fail = true;
      await expectLater(() => service.listArtists(), throwsA(isA<MusicApiException>()));
      await expectLater(() => service.listAlbums(), throwsA(isA<MusicApiException>()));
      await expectLater(() => service.listSongs(), throwsA(isA<MusicApiException>()));
      await expectLater(() => service.listLikedSongs(), throwsA(isA<MusicApiException>()));
      await expectLater(() => service.toggleLikeSong('s'), throwsA(isA<MusicApiException>()));
      await expectLater(() => service.listPlaylists(), throwsA(isA<MusicApiException>()));
      await expectLater(() => service.createPlaylist(name: 'x'), throwsA(isA<MusicApiException>()));
      await expectLater(() => service.issueAudioTicket('s'), throwsA(isA<MusicApiException>()));
      await expectLater(() => service.getOnlineDevices(), throwsA(isA<MusicApiException>()));
      expect(const MusicApiException('bad', statusCode: 500).toString(), contains('500'));
    });
  });

  group('AdminService & Admin models all methods + errors', () {
    test('covers createLibrary, scanLibrary, createInvite, issueResetCode, identifyMedia, and errors', () async {
      var fail = false;
      final client = MockClient((req) async {
        if (fail) {
          return http.Response('err', 400);
        }
        return switch (req.url.path) {
          '/api/v1/admin/libraries' when req.method == 'POST' => http.Response(
              jsonEncode({
                'id': 'lib-1',
                'name': 'Movies',
                'mediaType': 0,
                'rootPath': '/media/movies',
                'watchEnabled': true,
                'createdAtUtc': '2026-11-15T10:00:00Z',
                'lastScanCompletedAtUtc': '2026-11-15T11:00:00Z',
              }),
              201,
            ),
          '/api/v1/admin/libraries/lib-1/scan' => http.Response(
              jsonEncode({
                'libraryRootId': 'lib-1',
                'filesDiscovered': 3,
                'sourcesUpserted': 2,
                'sourcesMarkedMissing': 1,
                'completedAtUtc': '2026-11-15T11:05:00Z',
              }),
              200,
            ),
          '/api/v1/admin/invites' when req.method == 'POST' => http.Response(
              jsonEncode({
                'id': 'inv-1',
                'code': 'HRM-AAAA-BBBB',
                'maxUses': 2,
                'usedCount': 0,
                'expiresAtUtc': '2026-11-16T10:00:00Z',
                'isRevoked': false,
              }),
              201,
            ),
          '/api/v1/admin/users/u-1/reset-code' => http.Response(
              jsonEncode({'resetCode': 'ABCD1234', 'expiresAtUtc': '2026-11-15T12:00:00Z'}),
              200,
            ),
          '/api/v1/admin/media/mov-1/identify' => http.Response(
              jsonEncode({
                'id': 'mov-1',
                'tmdbId': 693134,
                'title': 'Dune: Part Two',
                'year': 2024,
                'isMetadataLocked': true,
              }),
              200,
            ),
          _ => http.Response('[]', 200),
        };
      });

      final service = AdminService(
        baseUri: Uri.parse('http://localhost:5258'),
        accessToken: 'jwt',
        httpClient: client,
      );

      final createdLib = await service.createLibrary(name: 'Movies', mediaType: 0, rootPath: '/media/movies');
      expect(createdLib.lastScanCompletedAtUtc, isNotNull);
      expect((await service.scanLibrary('lib-1')).filesDiscovered, 3);
      expect((await service.createInvite()).code, 'HRM-AAAA-BBBB');
      expect((await service.issueResetCode('u-1')).resetCode, 'ABCD1234');
      expect(
        (await service.identifyMedia(mediaId: 'mov-1', tmdbId: 693134, title: 'Dune: Part Two')).isMetadataLocked,
        isTrue,
      );

      fail = true;
      await expectLater(() => service.listLibraries(), throwsA(isA<AdminApiException>()));
      await expectLater(() => service.createLibrary(name: 'a', mediaType: 0, rootPath: '/a'), throwsA(isA<AdminApiException>()));
      await expectLater(() => service.scanLibrary('a'), throwsA(isA<AdminApiException>()));
      await expectLater(() => service.listInvites(), throwsA(isA<AdminApiException>()));
      await expectLater(() => service.createInvite(), throwsA(isA<AdminApiException>()));
      await expectLater(() => service.listUsers(), throwsA(isA<AdminApiException>()));
      await expectLater(() => service.issueResetCode('u'), throwsA(isA<AdminApiException>()));
      await expectLater(
        () => service.identifyMedia(mediaId: 'm', tmdbId: 1, title: 't'),
        throwsA(isA<AdminApiException>()),
      );
      expect(const AdminApiException('err', statusCode: 400).toString(), contains('400'));
    });
  });
}
