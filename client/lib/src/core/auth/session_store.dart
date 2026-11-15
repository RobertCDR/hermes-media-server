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
}

abstract interface class SessionStore {
  Future<HermesSession?> load();
  Future<void> save(HermesSession session);
  Future<void> clear();
}

class InMemorySessionStore implements SessionStore {
  HermesSession? _current;

  @override
  Future<HermesSession?> load() async => _current;

  @override
  Future<void> save(HermesSession session) async {
    _current = session;
  }

  @override
  Future<void> clear() async {
    _current = null;
  }
}
