import 'dart:convert';
import 'package:http/http.dart' as http;
import 'session_store.dart';

class AuthException implements Exception {
  const AuthException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'AuthException($statusCode): $message';
}

class AuthService {
  AuthService({
    required this.httpClient,
    required this.sessionStore,
  });

  final http.Client httpClient;
  final SessionStore sessionStore;
  Future<HermesSession>? _inFlightRefresh;

  Future<void> setupServer({
    required String baseUrl,
    required String adminUsername,
    required String adminPassword,
    required String serverName,
  }) async {
    final uri = Uri.parse(baseUrl).resolve('/api/v1/setup');
    final response = await httpClient.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': adminUsername,
        'password': adminPassword,
        'serverName': serverName,
      }),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw AuthException('Setup failed (${response.statusCode})', statusCode: response.statusCode);
    }
  }

  Future<void> registerWithInvite({
    required String baseUrl,
    required String username,
    required String password,
    required String inviteCode,
  }) async {
    final uri = Uri.parse(baseUrl).resolve('/api/v1/auth/register');
    final response = await httpClient.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
        'inviteCode': inviteCode,
      }),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw AuthException('Registration failed (${response.statusCode})', statusCode: response.statusCode);
    }
  }

  Future<HermesSession> login({
    required String primaryUrl,
    String? lanFallbackUrl,
    required String resolvedBaseUrl,
    required String serverId,
    required String username,
    required String password,
    required String deviceId,
    required String deviceName,
  }) async {
    final uri = Uri.parse(resolvedBaseUrl).resolve('/api/v1/auth/login');
    final response = await httpClient.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
        'deviceId': deviceId,
        'deviceName': deviceName,
      }),
    );

    if (response.statusCode != 200) {
      throw AuthException('Invalid credentials (${response.statusCode})', statusCode: response.statusCode);
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final session = HermesSession(
      serverPrimaryUrl: primaryUrl,
      serverLanFallbackUrl: lanFallbackUrl,
      serverId: serverId,
      deviceId: deviceId,
      deviceName: deviceName,
      userId: payload['userId'] as String,
      username: payload['username'] as String,
      role: payload['role'] as String,
      accessToken: payload['accessToken'] as String,
      refreshToken: payload['refreshToken'] as String,
    );

    await sessionStore.save(session);
    return session;
  }

  Future<HermesSession> refreshSession(String resolvedBaseUrl) {
    final pending = _inFlightRefresh;
    if (pending != null) {
      return pending;
    }

    final future = _performRefresh(resolvedBaseUrl);
    _inFlightRefresh = future;
    return future;
  }

  Future<HermesSession> _performRefresh(String resolvedBaseUrl) async {
    try {
      final current = await sessionStore.load();
      if (current == null) {
        throw const AuthException('No active session to refresh.');
      }

      final uri = Uri.parse(resolvedBaseUrl).resolve('/api/v1/auth/refresh');
      final response = await httpClient.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'deviceId': current.deviceId,
          'refreshToken': current.refreshToken,
        }),
      );

      if (response.statusCode != 200) {
        if (response.statusCode == 401 || response.statusCode == 403) {
          await sessionStore.clear();
        }
        throw AuthException('Session refresh failed (${response.statusCode})', statusCode: response.statusCode);
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final updated = current.copyWith(
        accessToken: payload['accessToken'] as String,
        refreshToken: payload['refreshToken'] as String,
        role: payload['role'] as String?,
      );
      await sessionStore.save(updated);
      return updated;
    } finally {
      _inFlightRefresh = null;
    }
  }

  Future<void> changePassword({
    required String baseUrl,
    required String accessToken,
    required String currentPassword,
    required String newPassword,
    http.Client? client,
  }) async {
    final uri = Uri.parse(baseUrl).resolve('/api/v1/auth/change-password');
    final activeClient = client ?? httpClient;
    final response = await activeClient.post(
      uri,
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException(
        'Password change failed (${response.statusCode})',
        statusCode: response.statusCode,
      );
    }
  }

  Future<void> signOut() async {
    await sessionStore.clear();
  }
}
