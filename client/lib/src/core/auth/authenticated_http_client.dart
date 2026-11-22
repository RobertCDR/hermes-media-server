import 'dart:async';
import 'package:http/http.dart' as http;

/// HTTP client wrapper that injects the active Bearer token and retries once
/// after a single-flight refresh whenever an authenticated API call returns 401.
class AuthenticatedHttpClient extends http.BaseClient {
  AuthenticatedHttpClient({
    required this.inner,
    required this.getAccessToken,
    required this.refreshAccessToken,
    this.onSessionExpired,
  });

  final http.Client inner;
  final String? Function() getAccessToken;
  final Future<String?> Function() refreshAccessToken;
  final FutureOr<void> Function()? onSessionExpired;

  static bool _shouldAttemptAuthRefresh(Uri url) {
    final path = url.path.toLowerCase();
    return path != '/api/v1/auth/login' &&
        path != '/api/v1/auth/refresh' &&
        path != '/api/v1/auth/register' &&
        path != '/api/v1/auth/reset-password' &&
        path != '/api/v1/setup' &&
        path != '/api/v1/system/info' &&
        path != '/health/live';
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final isAuthEligible = _shouldAttemptAuthRefresh(request.url);
    final tokenBefore = getAccessToken();

    // Clone body upfront only if request is replayable on 401
    final List<int>? cachedBodyBytes =
        isAuthEligible && request is http.Request ? request.bodyBytes : null;

    if (isAuthEligible && tokenBefore != null && tokenBefore.isNotEmpty) {
      // Keep services wired with the initial session token synchronized after refresh.
      request.headers['Authorization'] = 'Bearer $tokenBefore';
    }

    final initialResponse = await inner.send(request);
    if (initialResponse.statusCode != 401 || !isAuthEligible) {
      return initialResponse;
    }

    // Drain initial unauthorized stream so the underlying socket can be reused cleanly.
    await initialResponse.stream.drain<void>();

    String? refreshedToken;
    var transientRefreshFailure = false;
    try {
      refreshedToken = await refreshAccessToken();
    } catch (_) {
      refreshedToken = null;
      transientRefreshFailure = true;
    }

    if (refreshedToken == null || refreshedToken.isEmpty) {
      if (!transientRefreshFailure) {
        await onSessionExpired?.call();
      }
      return http.StreamedResponse(
        const Stream<List<int>>.empty(),
        transientRefreshFailure ? 503 : 401,
        request: request,
        reasonPhrase:
            transientRefreshFailure ? 'Service Unavailable' : 'Unauthorized',
      );
    }

    final retry = _cloneRequest(
      request,
      accessToken: refreshedToken,
      bodyBytes: cachedBodyBytes,
    );
    if (retry == null) {
      return http.StreamedResponse(
        const Stream<List<int>>.empty(),
        401,
        request: request,
        reasonPhrase: 'Unauthorized',
      );
    }

    return inner.send(retry);
  }

  http.BaseRequest? _cloneRequest(
    http.BaseRequest original, {
    required String accessToken,
    List<int>? bodyBytes,
  }) {
    if (original is! http.Request) {
      return null;
    }
    final cloned = http.Request(original.method, original.url)
      ..followRedirects = original.followRedirects
      ..maxRedirects = original.maxRedirects
      ..persistentConnection = original.persistentConnection;
    cloned.headers.addAll(original.headers);
    cloned.headers['Authorization'] = 'Bearer $accessToken';
    if (bodyBytes != null && bodyBytes.isNotEmpty) {
      cloned.bodyBytes = bodyBytes;
    }
    return cloned;
  }

  @override
  void close() {
    // Inner HTTP client lifecycle is owned by HermesApp.
  }
}
