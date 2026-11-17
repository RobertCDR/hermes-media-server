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
    final roots = decoded
        .map((e) => LibraryRootModel.fromJson(e as Map<String, dynamic>))
        .toList();
    return _enrichMissingLibraryCounts(roots);
  }

  Future<List<LibraryRootModel>> _enrichMissingLibraryCounts(
    List<LibraryRootModel> roots,
  ) async {
    final missingTypes = roots
        .where((r) => !r.hasReportedCount && r.lastScanCompletedAtUtc != null)
        .map((r) => r.mediaType)
        .toSet();
    if (missingTypes.isEmpty) {
      return roots;
    }

    final countsByType = <int, int>{};
    for (final mediaType in missingTypes) {
      // Only attribute catalog totals cleanly when there is a single root of that media type.
      if (roots.where((r) => r.mediaType == mediaType).length != 1) {
        continue;
      }
      final path = switch (mediaType) {
        0 => '/api/v1/cinema/movies',
        1 => '/api/v1/cinema/series',
        _ => '/api/v1/music/songs',
      };
      try {
        final resp = await httpClient.get(baseUri.resolve(path), headers: _headers);
        if (resp.statusCode == 200) {
          final items = jsonDecode(resp.body);
          if (items is List) {
            countsByType[mediaType] = items.length;
          }
        }
      } catch (_) {
        // Leave hasReportedCount false so UI stays accurate ("Scanned") rather than showing 0.
      }
    }

    if (countsByType.isEmpty) {
      return roots;
    }
    return roots.map((r) {
      final fallback = countsByType[r.mediaType];
      if (!r.hasReportedCount && fallback != null) {
        return r.copyWith(itemCount: fallback, hasReportedCount: true);
      }
      return r;
    }).toList();
  }

  Future<LibraryRootModel> createLibrary({
    required String name,
    required int mediaType,
    required String rootPath,
    bool watchEnabled = true,
    bool fetchMetadata = true,
  }) async {
    final response = await httpClient.post(
      baseUri.resolve('/api/v1/admin/libraries'),
      headers: _headers,
      body: jsonEncode({
        'name': name,
        'mediaType': mediaType,
        'rootPath': rootPath,
        'watchEnabled': watchEnabled,
        'fetchMetadata': fetchMetadata,
      }),
    );
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw AdminApiException('Failed to create library', statusCode: response.statusCode);
    }

    return LibraryRootModel.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<LibraryRootModel> updateLibrary({
    required String id,
    required String name,
    required String rootPath,
    bool watchEnabled = true,
    bool fetchMetadata = true,
  }) async {
    final response = await httpClient.put(
      baseUri.resolve('/api/v1/admin/libraries/$id'),
      headers: _headers,
      body: jsonEncode({
        'name': name,
        'rootPath': rootPath,
        'watchEnabled': watchEnabled,
        'fetchMetadata': fetchMetadata,
      }),
    );
    if (response.statusCode != 200) {
      throw AdminApiException('Failed to update library', statusCode: response.statusCode);
    }

    return LibraryRootModel.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> deleteLibrary(String libraryId) async {
    final response = await httpClient.delete(
      baseUri.resolve('/api/v1/admin/libraries/$libraryId'),
      headers: _headers,
    );
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw AdminApiException('Failed to delete library', statusCode: response.statusCode);
    }
  }

  Future<ServerSettingsModel> getServerSettings() async {
    final response = await httpClient.get(
      baseUri.resolve('/api/v1/admin/settings'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw AdminApiException('Failed to load server settings', statusCode: response.statusCode);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const AdminApiException('Unexpected server settings payload');
    }
    return ServerSettingsModel.fromJson(decoded);
  }

  Future<ServerSettingsModel> updateServerSettings(UpdateServerSettingsInput input) async {
    final response = await httpClient.put(
      baseUri.resolve('/api/v1/admin/settings'),
      headers: _headers,
      body: jsonEncode(input.toJson()),
    );
    if (response.statusCode != 200) {
      throw AdminApiException('Failed to update server settings', statusCode: response.statusCode);
    }

    return ServerSettingsModel.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
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
