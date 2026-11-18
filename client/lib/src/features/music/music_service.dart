import 'dart:convert';
import 'package:http/http.dart' as http;
import 'music_models.dart';

class MusicApiException implements Exception {
  const MusicApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'MusicApiException($statusCode): $message';
}

class MusicService {
  MusicService({
    required this.baseUri,
    required this.accessToken,
    required this.httpClient,
  });

  final Uri baseUri;
  final String accessToken;
  final http.Client httpClient;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      };

  Future<List<ArtistSummaryModel>> listArtists() async {
    final response = await httpClient.get(baseUri.resolve('/api/v1/music/artists'), headers: _headers);
    if (response.statusCode != 200) {
      throw MusicApiException('Failed to load artists', statusCode: response.statusCode);
    }
    final decoded = jsonDecode(response.body) as List<dynamic>;
    return decoded.map((e) => ArtistSummaryModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<AlbumSummaryModel>> listAlbums() async {
    final response = await httpClient.get(baseUri.resolve('/api/v1/music/albums'), headers: _headers);
    if (response.statusCode != 200) {
      throw MusicApiException('Failed to load albums', statusCode: response.statusCode);
    }
    final decoded = jsonDecode(response.body) as List<dynamic>;
    return decoded.map((e) => AlbumSummaryModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<AlbumDetailModel> getAlbum(String albumId) async {
    final response = await httpClient.get(baseUri.resolve('/api/v1/music/albums/$albumId'), headers: _headers);
    if (response.statusCode != 200) {
      throw MusicApiException('Failed to load album', statusCode: response.statusCode);
    }
    return AlbumDetailModel.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<ArtistDetailModel> getArtist(String artistId) async {
    final response = await httpClient.get(baseUri.resolve('/api/v1/music/artists/$artistId'), headers: _headers);
    if (response.statusCode != 200) {
      throw MusicApiException('Failed to load artist', statusCode: response.statusCode);
    }
    return ArtistDetailModel.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<SongModel>> listSongs() async {
    final response = await httpClient.get(baseUri.resolve('/api/v1/music/songs'), headers: _headers);
    if (response.statusCode != 200) {
      throw MusicApiException('Failed to load songs', statusCode: response.statusCode);
    }
    final decoded = jsonDecode(response.body) as List<dynamic>;
    return decoded.map((e) => SongModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<SongModel>> listLikedSongs() async {
    final response = await httpClient.get(baseUri.resolve('/api/v1/music/songs/liked'), headers: _headers);
    if (response.statusCode != 200) {
      throw MusicApiException('Failed to load liked songs', statusCode: response.statusCode);
    }
    final decoded = jsonDecode(response.body) as List<dynamic>;
    return decoded.map((e) => SongModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<ListeningHistoryItemModel>> listHistory({int limit = 40}) async {
    final uri = baseUri.resolve('/api/v1/music/history').replace(
      queryParameters: {'limit': '$limit'},
    );
    final response = await httpClient.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw MusicApiException('Failed to load listening history', statusCode: response.statusCode);
    }
    final decoded = jsonDecode(response.body) as List<dynamic>;
    return decoded
        .map((e) => ListeningHistoryItemModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> recordListen({
    required String songId,
    required int positionMs,
    required int durationMs,
    String? deviceId,
    String? contextLabel,
  }) async {
    final response = await httpClient.post(
      baseUri.resolve('/api/v1/music/history'),
      headers: _headers,
      body: jsonEncode({
        'songId': songId,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'deviceId': ?deviceId,
        'contextLabel': ?contextLabel,
      }),
    );
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw MusicApiException('Failed to record listen', statusCode: response.statusCode);
    }
  }

  Future<bool> toggleLikeSong(String songId) async {
    final response = await httpClient.post(baseUri.resolve('/api/v1/music/songs/$songId/like'), headers: _headers);
    if (response.statusCode != 200) {
      throw MusicApiException('Failed to toggle like', statusCode: response.statusCode);
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return decoded['isLiked'] as bool? ?? false;
  }

  Future<List<PlaylistSummaryModel>> listPlaylists() async {
    final response = await httpClient.get(baseUri.resolve('/api/v1/music/playlists'), headers: _headers);
    if (response.statusCode != 200) {
      throw MusicApiException('Failed to load playlists', statusCode: response.statusCode);
    }
    final decoded = jsonDecode(response.body) as List<dynamic>;
    return decoded.map((e) => PlaylistSummaryModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<PlaylistDetailModel> createPlaylist({required String name, String? description}) async {
    final response = await httpClient.post(
      baseUri.resolve('/api/v1/music/playlists'),
      headers: _headers,
      body: jsonEncode({'name': name, 'description': ?description}),
    );
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw MusicApiException('Failed to create playlist', statusCode: response.statusCode);
    }
    return PlaylistDetailModel.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<PlaylistDetailModel> getPlaylist(String playlistId) async {
    final response = await httpClient.get(
      baseUri.resolve('/api/v1/music/playlists/$playlistId'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw MusicApiException('Failed to load playlist', statusCode: response.statusCode);
    }
    return PlaylistDetailModel.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<PlaylistDetailModel> renamePlaylist({
    required String playlistId,
    required String name,
    String? description,
  }) async {
    final response = await httpClient.put(
      baseUri.resolve('/api/v1/music/playlists/$playlistId'),
      headers: _headers,
      body: jsonEncode({'name': name, 'description': ?description}),
    );
    if (response.statusCode != 200) {
      throw MusicApiException('Failed to rename playlist', statusCode: response.statusCode);
    }
    return PlaylistDetailModel.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> deletePlaylist(String playlistId) async {
    final response = await httpClient.delete(
      baseUri.resolve('/api/v1/music/playlists/$playlistId'),
      headers: _headers,
    );
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw MusicApiException('Failed to delete playlist', statusCode: response.statusCode);
    }
  }

  Future<PlaylistDetailModel> addTrackToPlaylist({
    required String playlistId,
    required String songId,
  }) async {
    final response = await httpClient.post(
      baseUri.resolve('/api/v1/music/playlists/$playlistId/tracks'),
      headers: _headers,
      body: jsonEncode({'songId': songId}),
    );
    if (response.statusCode != 200) {
      throw MusicApiException('Failed to add track to playlist', statusCode: response.statusCode);
    }
    return PlaylistDetailModel.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<PlaylistDetailModel> removePlaylistTrack({
    required String playlistId,
    required int position,
  }) async {
    final response = await httpClient.delete(
      baseUri.resolve('/api/v1/music/playlists/$playlistId/tracks/$position'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw MusicApiException('Failed to remove playlist track', statusCode: response.statusCode);
    }
    return PlaylistDetailModel.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<SongLyricsModel> getSongLyrics(String songId) async {
    final response = await httpClient.get(
      baseUri.resolve('/api/v1/music/songs/$songId/lyrics'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw MusicApiException('Failed to load song lyrics', statusCode: response.statusCode);
    }
    return SongLyricsModel.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<String> issueAudioTicket(String songId) async {
    final response = await httpClient.post(
      baseUri.resolve('/api/v1/auth/stream-tickets'),
      headers: _headers,
      body: jsonEncode({'mediaSourceId': songId}),
    );
    if (response.statusCode != 200) {
      throw MusicApiException('Failed to issue audio ticket', statusCode: response.statusCode);
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return decoded['ticket'] as String;
  }

  Future<List<OnlineDeviceModel>> getOnlineDevices() async {
    final response = await httpClient.get(baseUri.resolve('/api/v1/music/devices'), headers: _headers);
    if (response.statusCode != 200) {
      throw MusicApiException('Failed to query online devices', statusCode: response.statusCode);
    }
    final decoded = jsonDecode(response.body) as List<dynamic>;
    return decoded.map((e) => OnlineDeviceModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Uri buildAudioStreamUri({
    required String songId,
    required String ticket,
    required AudioQualityPreset quality,
  }) {
    return baseUri.resolve('/api/v1/streams/$songId/audio').replace(
      queryParameters: {
        'quality': quality.apiValue,
        'ticket': ticket,
      },
    );
  }

  Uri? buildArtworkUri(String? artworkHash, {String variant = 'thumb_400'}) {
    if (artworkHash == null || artworkHash.isEmpty) {
      return null;
    }
    return baseUri.resolve('/api/v1/artwork/$artworkHash/$variant.webp');
  }

  Future<UnifiedSearchResult> searchLibrary(String query) async {
    final uri = baseUri.resolve('/api/v1/search').replace(
      queryParameters: {'q': query.trim()},
    );
    final response = await httpClient.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw MusicApiException('Library search failed', statusCode: response.statusCode);
    }
    return UnifiedSearchResult.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }
}
