import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class HermesServerInfo {
  const HermesServerInfo({
    required this.serverId,
    required this.serverName,
    required this.version,
    required this.setupCompleted,
  });

  final String serverId;
  final String serverName;
  final String version;
  final bool setupCompleted;

  factory HermesServerInfo.fromJson(Map<String, dynamic> json) {
    return HermesServerInfo(
      serverId: json['serverId'] as String? ?? '',
      serverName: json['serverName'] as String? ?? 'Hermes Media Server',
      version: json['version'] as String? ?? '1.0.0',
      setupCompleted: json['setupCompleted'] as bool? ?? false,
    );
  }
}

class ResolvedEndpoint {
  const ResolvedEndpoint({
    required this.baseUri,
    required this.usedFallback,
    required this.info,
  });

  final Uri baseUri;
  final bool usedFallback;
  final HermesServerInfo info;
}

class HermesConnectionException implements Exception {
  const HermesConnectionException(this.message);

  final String message;

  @override
  String toString() => 'HermesConnectionException: $message';
}

class EndpointResolver {
  EndpointResolver({
    required this.httpClient,
    this.probeTimeout = const Duration(milliseconds: 1500),
  });

  final http.Client httpClient;
  final Duration probeTimeout;

  Future<ResolvedEndpoint> resolve({
    required String primaryUrl,
    String? lanFallbackUrl,
    String? expectedServerId,
  }) async {
    final normalizedPrimary = _normalizeUri(primaryUrl);
    final primaryResult = await _probeEndpoint(
      normalizedPrimary,
      expectedServerId: expectedServerId,
    );
    if (primaryResult != null) {
      return ResolvedEndpoint(
        baseUri: normalizedPrimary,
        usedFallback: false,
        info: primaryResult,
      );
    }

    if (lanFallbackUrl != null && lanFallbackUrl.trim().isNotEmpty) {
      final normalizedFallback = _normalizeUri(lanFallbackUrl);
      final fallbackResult = await _probeEndpoint(
        normalizedFallback,
        expectedServerId: expectedServerId,
      );
      if (fallbackResult != null) {
        return ResolvedEndpoint(
          baseUri: normalizedFallback,
          usedFallback: true,
          info: fallbackResult,
        );
      }
    }

    throw const HermesConnectionException(
      'Unable to reach a matching Hermes Media Server on primary or LAN fallback URL.',
    );
  }

  Future<HermesServerInfo?> _probeEndpoint(
    Uri baseUri, {
    String? expectedServerId,
  }) async {
    try {
      final infoUri = baseUri.resolve('/api/v1/system/info');
      final response = await httpClient.get(infoUri).timeout(probeTimeout);
      if (response.statusCode != 200) {
        return null;
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final info = HermesServerInfo.fromJson(payload);
      if (info.serverId.isEmpty) {
        return null;
      }

      if (expectedServerId != null &&
          expectedServerId.isNotEmpty &&
          info.serverId != expectedServerId) {
        return null;
      }

      return info;
    } catch (_) {
      return null;
    }
  }

  static Uri _normalizeUri(String rawUrl) {
    final trimmed = rawUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      throw HermesConnectionException('Invalid server URL: $rawUrl');
    }
    return parsed;
  }
}
