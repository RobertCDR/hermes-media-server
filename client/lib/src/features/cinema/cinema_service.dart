import 'dart:convert';
import 'package:http/http.dart' as http;
import 'cinema_models.dart';

class CinemaApiException implements Exception {
  const CinemaApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'CinemaApiException($statusCode): $message';
}

class CinemaService {
  CinemaService({
    required this.baseUri,
    required this.accessToken,
    required this.httpClient,
  });

  final Uri baseUri;
  final String accessToken;
  final http.Client httpClient;

  Map<String, String> get _authHeaders => {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      };

  Future<List<MovieSummary>> listMovies() async {
    final response = await httpClient.get(
      baseUri.resolve('/api/v1/cinema/movies'),
      headers: _authHeaders,
    );
    if (response.statusCode != 200) {
      throw CinemaApiException('Failed to load movies', statusCode: response.statusCode);
    }

    final decoded = jsonDecode(response.body) as List<dynamic>;
    return decoded
        .map((e) => MovieSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<TvSeriesSummary>> listSeries() async {
    final response = await httpClient.get(
      baseUri.resolve('/api/v1/cinema/series'),
      headers: _authHeaders,
    );
    if (response.statusCode != 200) {
      throw CinemaApiException('Failed to load series', statusCode: response.statusCode);
    }

    final decoded = jsonDecode(response.body) as List<dynamic>;
    return decoded
        .map((e) => TvSeriesSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<String> issueStreamTicket(String mediaSourceId) async {
    final response = await httpClient.post(
      baseUri.resolve('/api/v1/auth/stream-tickets'),
      headers: _authHeaders,
      body: jsonEncode({'mediaSourceId': mediaSourceId}),
    );
    if (response.statusCode != 200) {
      throw CinemaApiException('Failed to issue stream ticket', statusCode: response.statusCode);
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return decoded['ticket'] as String;
  }

  Uri buildVideoStreamUri({
    required String mediaSourceId,
    required String ticket,
    required VideoQualityPreset quality,
    int audioStreamIndex = 1,
    int startSeconds = 0,
  }) {
    if (quality == VideoQualityPreset.directPlay) {
      return baseUri.resolve('/api/v1/streams/$mediaSourceId/direct').replace(
        queryParameters: {'ticket': ticket},
      );
    }

    final params = <String, String>{
      'quality': quality.apiValue,
      'ticket': ticket,
      'audioStreamIndex': audioStreamIndex.toString(),
      if (startSeconds > 0) 'startSeconds': startSeconds.toString(),
    };
    return baseUri
        .resolve('/api/v1/streams/$mediaSourceId/video/master.m3u8')
        .replace(queryParameters: params);
  }

  Uri buildSubtitleVttUri({
    required String mediaSourceId,
    required int streamIndex,
    required String ticket,
  }) {
    return baseUri
        .resolve('/api/v1/streams/$mediaSourceId/subtitles/$streamIndex.vtt')
        .replace(queryParameters: {'ticket': ticket});
  }

  Uri? buildArtworkUri(String? artworkHash, {String variant = 'poster_800'}) {
    if (artworkHash == null || artworkHash.isEmpty) {
      return null;
    }
    return baseUri.resolve('/api/v1/artwork/$artworkHash/$variant.webp');
  }

  Future<WatchProgressModel> updateWatchProgress({
    String? movieId,
    String? episodeId,
    required int positionMs,
    required int durationMs,
    bool? markWatched,
  }) async {
    final response = await httpClient.put(
      baseUri.resolve('/api/v1/cinema/progress'),
      headers: _authHeaders,
      body: jsonEncode({
        'movieId': movieId,
        'episodeId': episodeId,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'markWatched': ?markWatched,
      }),
    );

    if (response.statusCode != 200) {
      throw CinemaApiException('Failed to update watch progress', statusCode: response.statusCode);
    }

    return WatchProgressModel.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<bool> setWatchlist({
    String? movieId,
    String? tvSeriesId,
    required bool inWatchlist,
  }) async {
    final response = await httpClient.put(
      baseUri.resolve('/api/v1/cinema/watchlist'),
      headers: _authHeaders,
      body: jsonEncode({
        'movieId': movieId,
        'tvSeriesId': tvSeriesId,
        'inWatchlist': inWatchlist,
      }),
    );

    if (response.statusCode != 200) {
      throw CinemaApiException(
        'Failed to update watchlist',
        statusCode: response.statusCode,
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return decoded['inWatchlist'] as bool? ?? inWatchlist;
  }

  Future<void> setSeriesWatched({
    required String seriesId,
    required bool watched,
  }) async {
    final response = await httpClient.put(
      baseUri.resolve('/api/v1/cinema/series/$seriesId/watched'),
      headers: _authHeaders,
      body: jsonEncode({'watched': watched}),
    );

    if (response.statusCode != 200) {
      throw CinemaApiException(
        'Failed to update series watched status',
        statusCode: response.statusCode,
      );
    }
  }

  Future<List<CustomListModel>> listCustomLists() async {
    final response = await httpClient.get(
      baseUri.resolve('/api/v1/cinema/lists'),
      headers: _authHeaders,
    );
    if (response.statusCode != 200) {
      throw CinemaApiException('Failed to load custom lists', statusCode: response.statusCode);
    }
    final decoded = jsonDecode(response.body) as List<dynamic>;
    return decoded
        .map((e) => CustomListModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<CustomListModel> createCustomList({
    required String name,
    String? description,
  }) async {
    final response = await httpClient.post(
      baseUri.resolve('/api/v1/cinema/lists'),
      headers: _authHeaders,
      body: jsonEncode({
        'name': name,
        'description': ?description,
      }),
    );
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw CinemaApiException('Failed to create custom list', statusCode: response.statusCode);
    }
    return CustomListModel.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<CustomListModel> updateCustomList({
    required String listId,
    required String name,
    String? description,
  }) async {
    final response = await httpClient.put(
      baseUri.resolve('/api/v1/cinema/lists/$listId'),
      headers: _authHeaders,
      body: jsonEncode({
        'name': name,
        'description': ?description,
      }),
    );
    if (response.statusCode != 200) {
      throw CinemaApiException('Failed to update custom list', statusCode: response.statusCode);
    }
    return CustomListModel.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> deleteCustomList(String listId) async {
    final response = await httpClient.delete(
      baseUri.resolve('/api/v1/cinema/lists/$listId'),
      headers: _authHeaders,
    );
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw CinemaApiException('Failed to delete custom list', statusCode: response.statusCode);
    }
  }

  Future<CustomListModel> addItemToCustomList({
    required String listId,
    String? movieId,
    String? tvSeriesId,
  }) async {
    final response = await httpClient.post(
      baseUri.resolve('/api/v1/cinema/lists/$listId/items'),
      headers: _authHeaders,
      body: jsonEncode({
        'movieId': movieId,
        'tvSeriesId': tvSeriesId,
      }),
    );
    if (response.statusCode != 200) {
      throw CinemaApiException('Failed to add item to list', statusCode: response.statusCode);
    }
    return CustomListModel.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<CustomListModel> removeItemFromCustomList({
    required String listId,
    String? itemId,
    String? movieId,
    String? tvSeriesId,
  }) async {
    final Uri uri;
    if (itemId != null) {
      uri = baseUri.resolve('/api/v1/cinema/lists/$listId/items/$itemId');
    } else {
      uri = baseUri.resolve('/api/v1/cinema/lists/$listId/items').replace(
        queryParameters: {
          'movieId': ?movieId,
          'seriesId': ?tvSeriesId,
        },
      );
    }
    final response = await httpClient.delete(uri, headers: _authHeaders);
    if (response.statusCode != 200) {
      throw CinemaApiException('Failed to remove item from list', statusCode: response.statusCode);
    }
    return CustomListModel.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }
}
