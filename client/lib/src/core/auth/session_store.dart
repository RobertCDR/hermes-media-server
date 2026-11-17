import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class HermesSession {
  const HermesSession({
    required this.serverPrimaryUrl,
    this.serverLanFallbackUrl,
    required this.serverId,
    required this.deviceId,
    required this.deviceName,
    required this.userId,
    required this.username,
    required this.role,
    required this.accessToken,
    required this.refreshToken,
  });

  final String serverPrimaryUrl;
  final String? serverLanFallbackUrl;
  final String serverId;
  final String deviceId;
  final String deviceName;
  final String userId;
  final String username;
  final String role;
  final String accessToken;
  final String refreshToken;

  bool get isAdmin => role.toLowerCase() == 'admin';

  HermesSession copyWith({
    String? serverPrimaryUrl,
    String? serverLanFallbackUrl,
    String? serverId,
    String? accessToken,
    String? refreshToken,
    String? role,
  }) {
    return HermesSession(
      serverPrimaryUrl: serverPrimaryUrl ?? this.serverPrimaryUrl,
      serverLanFallbackUrl: serverLanFallbackUrl ?? this.serverLanFallbackUrl,
      serverId: serverId ?? this.serverId,
      deviceId: deviceId,
      deviceName: deviceName,
      userId: userId,
      username: username,
      role: role ?? this.role,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'serverPrimaryUrl': serverPrimaryUrl,
      if (serverLanFallbackUrl != null && serverLanFallbackUrl!.isNotEmpty)
        'serverLanFallbackUrl': serverLanFallbackUrl,
      'serverId': serverId,
      'deviceId': deviceId,
      'deviceName': deviceName,
      'userId': userId,
      'username': username,
      'role': role,
      'accessToken': accessToken,
      'refreshToken': refreshToken,
    };
  }

  static HermesSession? fromJson(Map<String, dynamic> json) {
    final primaryUrl = json['serverPrimaryUrl'] as String?;
    final serverId = json['serverId'] as String?;
    final deviceId = json['deviceId'] as String?;
    final userId = json['userId'] as String?;
    final username = json['username'] as String?;
    final accessToken = json['accessToken'] as String?;
    final refreshToken = json['refreshToken'] as String?;

    if ([primaryUrl, serverId, deviceId, userId, username, accessToken, refreshToken]
        .any((v) => v == null || v.trim().isEmpty)) {
      return null;
    }

    return HermesSession(
      serverPrimaryUrl: primaryUrl!,
      serverLanFallbackUrl: json['serverLanFallbackUrl'] as String?,
      serverId: serverId!,
      deviceId: deviceId!,
      deviceName: json['deviceName'] as String? ?? 'Hermes Client',
      userId: userId!,
      username: username!,
      role: json['role'] as String? ?? 'Member',
      accessToken: accessToken!,
      refreshToken: refreshToken!,
    );
  }
}

class SavedServerEndpoints {
  const SavedServerEndpoints({
    required this.primaryUrl,
    this.lanFallbackUrl,
  });

  final String primaryUrl;
  final String? lanFallbackUrl;
}

abstract interface class SessionStore {
  Future<HermesSession?> load();
  Future<void> save(HermesSession session);
  Future<void> clear();
}

abstract interface class EndpointHistoryStore {
  Future<SavedServerEndpoints?> loadLastEndpoints();
  Future<void> saveLastEndpoints(SavedServerEndpoints endpoints);
}

class InMemorySessionStore implements SessionStore, EndpointHistoryStore {
  HermesSession? _current;
  SavedServerEndpoints? _lastEndpoints;

  @override
  Future<HermesSession?> load() async => _current;

  @override
  Future<void> save(HermesSession session) async {
    _current = session;
    _lastEndpoints = SavedServerEndpoints(
      primaryUrl: session.serverPrimaryUrl,
      lanFallbackUrl: session.serverLanFallbackUrl,
    );
  }

  @override
  Future<void> clear() async {
    _current = null;
  }

  @override
  Future<SavedServerEndpoints?> loadLastEndpoints() async => _lastEndpoints;

  @override
  Future<void> saveLastEndpoints(SavedServerEndpoints endpoints) async {
    _lastEndpoints = endpoints;
  }
}

/// Persists the user's active session and last server endpoints via SharedPreferences.
class SharedPrefsSessionStore implements SessionStore, EndpointHistoryStore {
  static const _sessionKey = 'hermes.session.v1';
  static const _primaryUrlKey = 'hermes.last_primary_url.v1';
  static const _lanUrlKey = 'hermes.last_lan_url.v1';

  Future<SharedPreferences?> _prefsOrNull() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<HermesSession?> load() async {
    final prefs = await _prefsOrNull();
    final raw = prefs?.getString(_sessionKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return HermesSession.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(HermesSession session) async {
    final prefs = await _prefsOrNull();
    if (prefs == null) return;
    await prefs.setString(_sessionKey, jsonEncode(session.toJson()));
    await saveLastEndpoints(
      SavedServerEndpoints(
        primaryUrl: session.serverPrimaryUrl,
        lanFallbackUrl: session.serverLanFallbackUrl,
      ),
    );
  }

  @override
  Future<void> clear() async {
    final prefs = await _prefsOrNull();
    await prefs?.remove(_sessionKey);
  }

  @override
  Future<SavedServerEndpoints?> loadLastEndpoints() async {
    final prefs = await _prefsOrNull();
    final primary = prefs?.getString(_primaryUrlKey);
    if (primary == null || primary.trim().isEmpty) {
      return null;
    }
    final lan = prefs?.getString(_lanUrlKey);
    return SavedServerEndpoints(
      primaryUrl: primary,
      lanFallbackUrl: (lan == null || lan.trim().isEmpty) ? null : lan,
    );
  }

  @override
  Future<void> saveLastEndpoints(SavedServerEndpoints endpoints) async {
    final prefs = await _prefsOrNull();
    if (prefs == null) return;
    await prefs.setString(_primaryUrlKey, endpoints.primaryUrl);
    final lan = endpoints.lanFallbackUrl?.trim() ?? '';
    if (lan.isEmpty) {
      await prefs.remove(_lanUrlKey);
    } else {
      await prefs.setString(_lanUrlKey, lan);
    }
  }
}
