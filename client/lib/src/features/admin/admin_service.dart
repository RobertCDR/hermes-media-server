import 'dart:convert';
import 'package:http/http.dart' as http;
import 'admin_models.dart';

class AdminApiException implements Exception {
  const AdminApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'AdminApiException($statusCode): $message';
}

class AdminService {
  AdminService({
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

  Future<List<LibraryRootModel>> listLibraries() async {
    final response = await httpClient.get(baseUri.resolve('/api/v1/admin/libraries'), headers: _headers);
    if (response.statusCode != 200) {
      throw AdminApiException('Failed to load libraries', statusCode: response.statusCode);
    }

    final decoded = jsonDecode(response.body) as List<dynamic>;
    return decoded.map((e) => LibraryRootModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<LibraryRootModel> createLibrary({
    required String name,
    required int mediaType,
    required String rootPath,
    bool watchEnabled = true,
  }) async {
    final response = await httpClient.post(
      baseUri.resolve('/api/v1/admin/libraries'),
      headers: _headers,
      body: jsonEncode({
        'name': name,
        'mediaType': mediaType,
        'rootPath': rootPath,
        'watchEnabled': watchEnabled,
      }),
    );
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw AdminApiException('Failed to create library', statusCode: response.statusCode);
    }

    return LibraryRootModel.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<LibraryScanSummaryModel> scanLibrary(String libraryId) async {
    final response = await httpClient.post(
      baseUri.resolve('/api/v1/admin/libraries/$libraryId/scan'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw AdminApiException('Library scan failed', statusCode: response.statusCode);
    }

    return LibraryScanSummaryModel.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> queueLibraryScan(String libraryId) async {
    final response = await httpClient.post(
      baseUri.resolve('/api/v1/admin/libraries/$libraryId/scan/queue'),
      headers: _headers,
    );
    if (response.statusCode != 202 && response.statusCode != 200) {
      throw AdminApiException('Queue scan failed', statusCode: response.statusCode);
    }
  }

  Future<List<ActiveStreamSessionModel>> listActiveSessions() async {
    final response = await httpClient.get(
      baseUri.resolve('/api/v1/admin/sessions'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw AdminApiException('Failed to load sessions', statusCode: response.statusCode);
    }
    final decoded = jsonDecode(response.body) as List<dynamic>;
    return decoded
        .map((e) => ActiveStreamSessionModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> stopSession(String sessionId) async {
    final response = await httpClient.delete(
      baseUri.resolve('/api/v1/admin/sessions/${Uri.encodeComponent(sessionId)}'),
      headers: _headers,
    );
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw AdminApiException('Failed to stop session', statusCode: response.statusCode);
    }
  }

  Future<List<UnmatchedMediaModel>> listUnmatchedMedia() async {
    final response = await httpClient.get(
      baseUri.resolve('/api/v1/admin/media/unmatched'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw AdminApiException('Failed to load unmatched media', statusCode: response.statusCode);
    }
    final decoded = jsonDecode(response.body) as List<dynamic>;
    return decoded
        .map((e) => UnmatchedMediaModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<TmdbCandidateModel>> searchTmdb({
    required String query,
    required int mediaType,
  }) async {
    final uri = baseUri.resolve('/api/v1/admin/media/tmdb-search').replace(
      queryParameters: {
        'query': query,
        'mediaType': '$mediaType',
      },
    );
    final response = await httpClient.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw AdminApiException('TMDb search failed', statusCode: response.statusCode);
    }
    final decoded = jsonDecode(response.body) as List<dynamic>;
    return decoded
        .map((e) => TmdbCandidateModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Uri? buildArtworkUri(String? artworkHash, {String variant = 'thumb_400'}) {
    if (artworkHash == null || artworkHash.isEmpty) {
      return null;
    }
    return baseUri.resolve('/api/v1/artwork/$artworkHash/$variant.webp');
  }

  Future<List<InviteModel>> listInvites() async {
    final response = await httpClient.get(baseUri.resolve('/api/v1/admin/invites'), headers: _headers);
    if (response.statusCode != 200) {
      throw AdminApiException('Failed to load invites', statusCode: response.statusCode);
    }

    final decoded = jsonDecode(response.body) as List<dynamic>;
    return decoded.map((e) => InviteModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<InviteModel> createInvite({int maxUses = 1, int expiresInHours = 24}) async {
    final response = await httpClient.post(
      baseUri.resolve('/api/v1/admin/invites'),
      headers: _headers,
      body: jsonEncode({
        'maxUses': maxUses,
        'expiresInHours': expiresInHours,
      }),
    );
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw AdminApiException('Failed to create invite', statusCode: response.statusCode);
    }

    return InviteModel.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<InviteModel> revokeInvite(String inviteId) async {
    final response = await httpClient.post(
      baseUri.resolve('/api/v1/admin/invites/$inviteId/revoke'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw AdminApiException('Failed to revoke invite', statusCode: response.statusCode);
    }
    return InviteModel.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<UserSummaryModel>> listUsers() async {
    final response = await httpClient.get(baseUri.resolve('/api/v1/admin/users'), headers: _headers);
    if (response.statusCode != 200) {
      throw AdminApiException('Failed to load users', statusCode: response.statusCode);
    }

    final decoded = jsonDecode(response.body) as List<dynamic>;
    return decoded.map((e) => UserSummaryModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<ResetCodeModel> issueResetCode(String userId) async {
    final response = await httpClient.post(
      baseUri.resolve('/api/v1/admin/users/$userId/reset-code'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw AdminApiException('Failed to issue reset code', statusCode: response.statusCode);
    }

    return ResetCodeModel.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> deactivateUser(String userId) async {
    final response = await httpClient.delete(
      baseUri.resolve('/api/v1/admin/users/$userId'),
      headers: _headers,
    );
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw AdminApiException('Failed to remove user', statusCode: response.statusCode);
    }
  }

  Future<IdentifyMediaResult> identifyMedia({
    required String mediaId,
    required int tmdbId,
    required String title,
    int? year,
    String? overview,
  }) async {
    final response = await httpClient.post(
      baseUri.resolve('/api/v1/admin/media/$mediaId/identify'),
      headers: _headers,
      body: jsonEncode({
        'tmdbId': tmdbId,
        'title': title,
        'year': year,
        'overview': overview,
      }),
    );
    if (response.statusCode != 200) {
      throw AdminApiException('Failed to identify media', statusCode: response.statusCode);
    }

    return IdentifyMediaResult.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }
}
