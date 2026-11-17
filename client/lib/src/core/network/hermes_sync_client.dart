import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../features/music/music_models.dart';
import '../../features/music/music_playback_coordinator.dart';
import '../../features/music/music_service.dart';

const String _signalRRecordSeparator = '\u001E';

typedef WebSocketChannelFactory = WebSocketChannel Function(Uri uri);

class HermesSyncException implements Exception {
  const HermesSyncException(this.message, {this.isHubError = false});

  final String message;
  final bool isHubError;

  @override
  String toString() => 'HermesSyncException: $message';
}

enum HermesSyncConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

class WatchProgressUpdatedEvent {
  const WatchProgressUpdatedEvent({
    this.movieId,
    this.episodeId,
    required this.positionMs,
    required this.durationMs,
    required this.isWatched,
    required this.updatedAtUtc,
  });

  final String? movieId;
  final String? episodeId;
  final int positionMs;
  final int durationMs;
  final bool isWatched;
  final DateTime updatedAtUtc;

  factory WatchProgressUpdatedEvent.fromJson(Map<String, dynamic> json) {
    final rawUpdated = json['updatedAtUtc'] as String?;
    return WatchProgressUpdatedEvent(
      movieId: json['movieId'] as String?,
      episodeId: json['episodeId'] as String?,
      positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      isWatched: json['isWatched'] as bool? ?? false,
      updatedAtUtc: rawUpdated != null
          ? (DateTime.tryParse(rawUpdated)?.toUtc() ?? DateTime.now().toUtc())
          : DateTime.now().toUtc(),
    );
  }
}

class HermesSyncClient {
  HermesSyncClient({
    required this.baseUri,
    required this.httpClient,
    required this.getAccessToken,
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    WebSocketChannelFactory? channelFactory,
    this.pingInterval = const Duration(seconds: 15),
    this.handshakeTimeout = const Duration(seconds: 5),
    this.reconnectDelays = const [
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
      Duration(seconds: 15),
    ],
  }) : _channelFactory = channelFactory ?? WebSocketChannel.connect;

  final Uri baseUri;
  final http.Client httpClient;
  final String Function() getAccessToken;
  final String deviceId;
  final String deviceName;
  final String platform;
  final WebSocketChannelFactory _channelFactory;
  final Duration pingInterval;
  final Duration handshakeTimeout;
  final List<Duration> reconnectDelays;

  final ValueNotifier<HermesSyncConnectionState> _connectionState =
      ValueNotifier<HermesSyncConnectionState>(
    HermesSyncConnectionState.disconnected,
  );
  final StreamController<PlaybackSessionState> _sessionController =
      StreamController<PlaybackSessionState>.broadcast();
  final StreamController<List<OnlineDeviceModel>> _devicesController =
      StreamController<List<OnlineDeviceModel>>.broadcast();
  final StreamController<WatchProgressUpdatedEvent> _watchProgressController =
      StreamController<WatchProgressUpdatedEvent>.broadcast();

  final Map<String, _PendingInvocation> _pendingInvocations = {};

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _streamSub;
  Completer<void>? _handshakeCompleter;
  Timer? _handshakeTimer;
  Timer? _pingTimer;
  Timer? _reconnectTimer;

  bool _started = false;
  bool _disposed = false;
  int _connectEpoch = 0;
  Object? _activeConnectionToken;
  int _reconnectAttempt = 0;
  int _nextInvocationId = 0;
  String _rxBuffer = '';

  PlaybackSessionState? _currentSession;
  List<OnlineDeviceModel> _currentDevices = const [];

  ValueListenable<HermesSyncConnectionState> get connectionState =>
      _connectionState;

  bool get isConnected =>
      _connectionState.value == HermesSyncConnectionState.connected &&
      _channel != null;

  PlaybackSessionState? get currentSession => _currentSession;

  List<OnlineDeviceModel> get currentDevices => _currentDevices;

  Stream<PlaybackSessionState> get sessionStream => _sessionController.stream;

  Stream<List<OnlineDeviceModel>> get devicesStream =>
      _devicesController.stream;

  Stream<WatchProgressUpdatedEvent> get watchProgressStream =>
      _watchProgressController.stream;

  void start() {
    if (_disposed || _started) {
      return;
    }
    _started = true;
    _reconnectAttempt = 0;
    unawaited(_connect());
  }

  Future<void> stop() async {
    _started = false;
    _connectEpoch++;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _closeActiveConnection(
      nextState: HermesSyncConnectionState.disconnected,
    );
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await stop();
    _connectionState.dispose();
    await Future.wait([
      _sessionController.close(),
      _devicesController.close(),
      _watchProgressController.close(),
    ]);
  }

  Future<T> invoke<T>(
    String target,
    List<Object?> arguments, {
    Duration timeout = const Duration(seconds: 10),
  }) {
    final channel = _channel;
    if (_disposed ||
        channel == null ||
        _connectionState.value != HermesSyncConnectionState.connected) {
      return Future<T>.error(
        const HermesSyncException('SignalR hub is not connected.'),
      );
    }

    final invocationId = (++_nextInvocationId).toString();
    final completer = Completer<Object?>();
    final timer = Timer(timeout, () {
      final pending = _pendingInvocations.remove(invocationId);
      if (pending != null && !pending.completer.isCompleted) {
        pending.completer.completeError(
          HermesSyncException('SignalR invocation "$target" timed out.'),
        );
      }
    });

    _pendingInvocations[invocationId] = _PendingInvocation(completer, timer);

    try {
      final frame = jsonEncode({
        'type': 1,
        'invocationId': invocationId,
        'target': target,
        'arguments': arguments,
      });
      channel.sink.add('$frame$_signalRRecordSeparator');
    } catch (error) {
      _pendingInvocations.remove(invocationId);
      timer.cancel();
      if (!completer.isCompleted) {
        completer.completeError(
          HermesSyncException('Failed to send "$target": $error'),
        );
      }
    }

    return completer.future.then((value) => value as T);
  }

  Future<void> reportProgress(int positionMs) async {
    final channel = _channel;
    if (_disposed ||
        channel == null ||
        _connectionState.value != HermesSyncConnectionState.connected) {
      return;
    }
    try {
      final frame = jsonEncode({
        'type': 1,
        'target': 'ReportProgress',
        'arguments': [
          {'positionMs': positionMs},
        ],
      });
      channel.sink.add('$frame$_signalRRecordSeparator');
    } catch (_) {
      // Non-critical heartbeat; reconnect loop recovers transport state.
    }
  }

  Future<void> _connect() async {
    if (_disposed || !_started) {
      return;
    }

    final epoch = ++_connectEpoch;
    _setConnectionState(
      _reconnectAttempt == 0
          ? HermesSyncConnectionState.connecting
          : HermesSyncConnectionState.reconnecting,
    );

    try {
      final initialToken = getAccessToken();
      final negotiateUri = baseUri.resolve('/hubs/sync/negotiate').replace(
        queryParameters: {
          'negotiateVersion': '1',
          'deviceId': deviceId,
          'deviceName': deviceName,
          'platform': platform,
        },
      );

      final response = await httpClient.post(
        negotiateUri,
        headers: {
          'Accept': 'application/json',
          if (initialToken.isNotEmpty) 'Authorization': 'Bearer $initialToken',
        },
      );

      if (_disposed || !_started || epoch != _connectEpoch) {
        return;
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HermesSyncException(
          'SignalR negotiate failed with HTTP ${response.statusCode}.',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const HermesSyncException(
          'SignalR negotiate returned an invalid JSON payload.',
        );
      }

      final redirectUrl = decoded['url'] as String?;
      final redirectToken = decoded['accessToken'] as String?;
      final connectionToken = (decoded['connectionToken'] as String?) ??
          (decoded['connectionId'] as String?);

      // Re-read token in case AuthenticatedHttpClient rotated it during negotiate.
      final freshToken = (redirectToken != null && redirectToken.isNotEmpty)
          ? redirectToken
          : getAccessToken();

      final targetBaseUri = (redirectUrl != null && redirectUrl.isNotEmpty)
          ? Uri.parse(redirectUrl)
          : baseUri.resolve('/hubs/sync');

      final wsScheme = switch (targetBaseUri.scheme) {
        'https' || 'wss' => 'wss',
        _ => 'ws',
      };

      final mergedQuery = <String, String>{
        ...targetBaseUri.queryParameters,
        if (connectionToken != null && connectionToken.isNotEmpty)
          'id': connectionToken,
        if (freshToken.isNotEmpty) 'access_token': freshToken,
        'deviceId': deviceId,
        'deviceName': deviceName,
        'platform': platform,
      };

      final wsUri = targetBaseUri.replace(
        scheme: wsScheme,
        queryParameters: mergedQuery,
      );

      final channel = _channelFactory(wsUri);
      final connectionTokenObj = Object();
      _activeConnectionToken = connectionTokenObj;
      _channel = channel;
      _rxBuffer = '';

      final handshakeCompleter = Completer<void>();
      _handshakeCompleter = handshakeCompleter;
      _handshakeTimer?.cancel();
      _handshakeTimer = Timer(handshakeTimeout, () {
        if (!handshakeCompleter.isCompleted) {
          handshakeCompleter.completeError(
            const HermesSyncException('SignalR JSON handshake timed out.'),
          );
        }
      });

      _streamSub = channel.stream.listen(
        (rawMessage) {
          if (_disposed ||
              epoch != _connectEpoch ||
              !identical(_activeConnectionToken, connectionTokenObj)) {
            return;
          }
          _onSocketData(rawMessage);
        },
        onError: (Object error, StackTrace _) {
          if (!handshakeCompleter.isCompleted) {
            handshakeCompleter.completeError(error);
          }
          if (epoch == _connectEpoch &&
              identical(_activeConnectionToken, connectionTokenObj)) {
            unawaited(_handleSocketDisconnected(connectionTokenObj));
          }
        },
        onDone: () {
          if (!handshakeCompleter.isCompleted) {
            handshakeCompleter.completeError(
              const HermesSyncException(
                'WebSocket closed before SignalR handshake completed.',
              ),
            );
          }
          if (epoch == _connectEpoch &&
              identical(_activeConnectionToken, connectionTokenObj)) {
            unawaited(_handleSocketDisconnected(connectionTokenObj));
          }
        },
      );

      await channel.ready;
      if (_disposed ||
          !_started ||
          epoch != _connectEpoch ||
          !identical(_activeConnectionToken, connectionTokenObj)) {
        await _closeActiveConnection(
          nextState: HermesSyncConnectionState.disconnected,
        );
        return;
      }

      channel.sink.add(
        '{"protocol":"json","version":1}$_signalRRecordSeparator',
      );
      await handshakeCompleter.future;

      if (_disposed ||
          !_started ||
          epoch != _connectEpoch ||
          !identical(_activeConnectionToken, connectionTokenObj)) {
        await _closeActiveConnection(
          nextState: HermesSyncConnectionState.disconnected,
        );
        return;
      }

      _reconnectAttempt = 0;
      _setConnectionState(HermesSyncConnectionState.connected);
      _startKeepAliveTimer(connectionTokenObj);
    } catch (_) {
      if (_disposed || !_started || epoch != _connectEpoch) {
        return;
      }
      await _handleSocketDisconnected(_activeConnectionToken);
    }
  }

  void _startKeepAliveTimer(Object connectionTokenObj) {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(pingInterval, (_) {
      final channel = _channel;
      if (_disposed ||
          !_started ||
          channel == null ||
          !identical(_activeConnectionToken, connectionTokenObj) ||
          _connectionState.value != HermesSyncConnectionState.connected) {
        return;
      }
      try {
        channel.sink.add('{"type":6}$_signalRRecordSeparator');
      } catch (_) {
        unawaited(_handleSocketDisconnected(connectionTokenObj));
      }
    });
  }

  void _onSocketData(dynamic rawMessage) {
    final text = switch (rawMessage) {
      final String s => s,
      final List<int> bytes => utf8.decode(bytes),
      _ => rawMessage.toString(),
    };
    _rxBuffer = '$_rxBuffer$text';

    while (true) {
      final sepIdx = _rxBuffer.indexOf(_signalRRecordSeparator);
      if (sepIdx < 0) {
        break;
      }
      final rawFrame = _rxBuffer.substring(0, sepIdx).trim();
      _rxBuffer = _rxBuffer.substring(sepIdx + 1);
      if (rawFrame.isEmpty) {
        continue;
      }

      dynamic decoded;
      try {
        decoded = jsonDecode(rawFrame);
      } catch (_) {
        continue;
      }
      if (decoded is! Map<String, dynamic>) {
        continue;
      }

      final handshake = _handshakeCompleter;
      if (handshake != null && !handshake.isCompleted) {
        _handshakeTimer?.cancel();
        _handshakeTimer = null;
        final handshakeError = decoded['error'] as String?;
        if (handshakeError != null && handshakeError.isNotEmpty) {
          handshake.completeError(HermesSyncException(handshakeError));
        } else {
          handshake.complete();
        }
        continue;
      }

      _handleSignalRFrame(decoded);
    }
  }

  void _handleSignalRFrame(Map<String, dynamic> frame) {
    final type = (frame['type'] as num?)?.toInt();
    switch (type) {
      case 1:
        _handleServerInvocation(frame);
      case 3:
        _handleCompletion(frame);
      case 6:
        // Keep-alive ping from server; no response payload required.
        break;
      case 7:
        final allowReconnect = frame['allowReconnect'] as bool? ?? true;
        if (!allowReconnect) {
          _started = false;
        }
        unawaited(_handleSocketDisconnected(_activeConnectionToken));
    }
  }

  void _handleServerInvocation(Map<String, dynamic> frame) {
    final target = frame['target'] as String?;
    final args = frame['arguments'] as List<dynamic>? ?? const [];
    if (target == null || args.isEmpty) {
      return;
    }

    switch (target) {
      case 'SessionStateUpdated':
        final payload = args.first;
        if (payload is Map<String, dynamic>) {
          final state = PlaybackSessionState.fromJson(payload);
          _currentSession = state;
          if (!_disposed && !_sessionController.isClosed) {
            _sessionController.add(state);
          }
        }
      case 'DevicesUpdated':
        final payload = args.first;
        if (payload is List<dynamic>) {
          final devices = payload
              .whereType<Map<String, dynamic>>()
              .map(OnlineDeviceModel.fromJson)
              .toList(growable: false);
          _currentDevices = devices;
          if (!_disposed && !_devicesController.isClosed) {
            _devicesController.add(devices);
          }
        }
      case 'WatchProgressUpdated':
        final payload = args.first;
        if (payload is Map<String, dynamic>) {
          final evt = WatchProgressUpdatedEvent.fromJson(payload);
          if (!_disposed && !_watchProgressController.isClosed) {
            _watchProgressController.add(evt);
          }
        }
    }
  }

  void _handleCompletion(Map<String, dynamic> frame) {
    final invocationId = frame['invocationId'] as String?;
    if (invocationId == null) {
      return;
    }
    final pending = _pendingInvocations.remove(invocationId);
    if (pending == null) {
      return;
    }
    pending.timer.cancel();
    if (pending.completer.isCompleted) {
      return;
    }
    final error = frame['error'] as String?;
    if (error != null && error.isNotEmpty) {
      pending.completer.completeError(
        HermesSyncException(error, isHubError: true),
      );
      return;
    }
    pending.completer.complete(frame['result']);
  }

  Future<void> _handleSocketDisconnected(Object? connectionTokenObj) async {
    if (connectionTokenObj != null &&
        !identical(_activeConnectionToken, connectionTokenObj)) {
      return;
    }
    _activeConnectionToken = null;
    await _closeActiveConnection(
      nextState: _started && !_disposed
          ? HermesSyncConnectionState.reconnecting
          : HermesSyncConnectionState.disconnected,
    );
    if (_disposed || !_started) {
      return;
    }

    _reconnectTimer?.cancel();
    final idx = _reconnectAttempt < reconnectDelays.length
        ? _reconnectAttempt
        : reconnectDelays.length - 1;
    final delay = reconnectDelays.isEmpty
        ? const Duration(seconds: 5)
        : reconnectDelays[idx];
    _reconnectAttempt++;

    final epoch = _connectEpoch;
    _reconnectTimer = Timer(delay, () {
      if (!_disposed && _started && epoch == _connectEpoch) {
        unawaited(_connect());
      }
    });
  }

  Future<void> _closeActiveConnection({
    required HermesSyncConnectionState nextState,
  }) async {
    _activeConnectionToken = null;
    _pingTimer?.cancel();
    _pingTimer = null;
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    _handshakeCompleter = null;

    final pendingEntries = _pendingInvocations.values.toList(growable: false);
    _pendingInvocations.clear();
    for (final entry in pendingEntries) {
      entry.timer.cancel();
      if (!entry.completer.isCompleted) {
        entry.completer.completeError(
          const HermesSyncException('SignalR connection closed.'),
        );
      }
    }

    final sub = _streamSub;
    _streamSub = null;
    final channel = _channel;
    _channel = null;

    if (sub != null) {
      try {
        await sub.cancel();
      } catch (_) {}
    }
    if (channel != null) {
      try {
        await channel.sink.close();
      } catch (_) {}
    }

    _setConnectionState(nextState);
  }

  void _setConnectionState(HermesSyncConnectionState next) {
    if (!_disposed && _connectionState.value != next) {
      _connectionState.value = next;
    }
  }
}

class _PendingInvocation {
  const _PendingInvocation(this.completer, this.timer);

  final Completer<Object?> completer;
  final Timer timer;
}

class SignalRConnectTransport implements ConnectTransport {
  SignalRConnectTransport({
    required this.syncClient,
    required this.musicService,
    required this.localDeviceId,
    this.localDeviceName = 'This Device',
  });

  final HermesSyncClient syncClient;
  final MusicService musicService;
  final String localDeviceId;
  final String localDeviceName;

  int _offlineVersion = 0;

  @override
  Future<PlaybackSessionState> startPlayback(
    List<String> queueSongIds,
    int startIndex,
  ) async {
    if (syncClient.isConnected) {
      try {
        final raw = await syncClient.invoke<Object?>(
          'StartPlayback',
          [
            {'queueSongIds': queueSongIds, 'startIndex': startIndex},
          ],
        );
        return _parseSession(raw);
      } on HermesSyncException catch (error) {
        if (error.isHubError) rethrow;
      }
    }

    final prev = syncClient.currentSession;
    _offlineVersion = _nextOfflineVersion(prev);
    return PlaybackSessionState(
      sessionId: prev?.sessionId ?? 'local',
      version: _offlineVersion,
      activeRendererDeviceId: localDeviceId,
      activeRendererDeviceName: localDeviceName,
      state: PlaybackState.playing,
      repeatMode: prev?.repeatMode ?? HermesRepeatMode.off,
      shuffle: prev?.shuffle ?? false,
      volume: prev?.volume ?? 1.0,
      currentIndex: startIndex,
      currentSongId: queueSongIds.isEmpty
          ? null
          : queueSongIds[startIndex.clamp(0, queueSongIds.length - 1)],
      positionMs: 0,
      queueSongIds: List<String>.from(queueSongIds),
    );
  }

  @override
  Future<PlaybackSessionState> sendTransport(
    PlaybackState state, {
    int? currentIndex,
    int? positionMs,
    HermesRepeatMode? repeatMode,
    bool? shuffle,
    double? volume,
  }) async {
    if (syncClient.isConnected) {
      try {
        final raw = await syncClient.invoke<Object?>(
          'SendTransportCommand',
          [
            {
              'state': state.index,
              'currentIndex': ?currentIndex,
              'positionMs': ?positionMs,
              if (repeatMode != null) 'repeatMode': repeatMode.index,
              'shuffle': ?shuffle,
              'volume': ?volume,
            },
          ],
        );
        return _parseSession(raw);
      } on HermesSyncException catch (error) {
        if (error.isHubError) rethrow;
      }
    }

    final prev = syncClient.currentSession;
    final queue = prev?.queueSongIds ?? const <String>[];
    final nextIndex = queue.isEmpty
        ? 0
        : (currentIndex ?? prev?.currentIndex ?? 0).clamp(0, queue.length - 1);
    _offlineVersion = _nextOfflineVersion(prev);
    return PlaybackSessionState(
      sessionId: prev?.sessionId ?? 'local',
      version: _offlineVersion,
      activeRendererDeviceId: prev?.activeRendererDeviceId ?? localDeviceId,
      activeRendererDeviceName:
          prev?.activeRendererDeviceName ?? localDeviceName,
      state: state,
      repeatMode: repeatMode ?? prev?.repeatMode ?? HermesRepeatMode.off,
      shuffle: shuffle ?? prev?.shuffle ?? false,
      volume: volume ?? prev?.volume ?? 1.0,
      currentIndex: nextIndex,
      currentSongId: queue.isEmpty ? prev?.currentSongId : queue[nextIndex],
      positionMs: positionMs ?? prev?.positionMs ?? 0,
      queueSongIds: queue,
    );
  }

  @override
  Future<PlaybackSessionState> transferOutput(String targetDeviceId) async {
    final raw = await syncClient.invoke<Object?>(
      'TransferOutput',
      [
        {'targetDeviceId': targetDeviceId},
      ],
    );
    return _parseSession(raw);
  }

  @override
  Future<List<OnlineDeviceModel>> getOnlineDevices() async {
    if (syncClient.isConnected) {
      try {
        final raw = await syncClient.invoke<Object?>(
          'GetOnlineDevices',
          const [],
        );
        if (raw is List<dynamic>) {
          return raw
              .whereType<Map<String, dynamic>>()
              .map(OnlineDeviceModel.fromJson)
              .toList(growable: false);
        }
      } catch (_) {
        // Fall back to REST device query below.
      }
    }
    return musicService.getOnlineDevices();
  }

  int _nextOfflineVersion(PlaybackSessionState? prev) {
    final base = prev?.version ?? 0;
    return (base > _offlineVersion ? base : _offlineVersion) + 1;
  }

  PlaybackSessionState _parseSession(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      throw const HermesSyncException(
        'SignalR hub returned an invalid PlaybackSessionDto payload.',
      );
    }
    return PlaybackSessionState.fromJson(raw);
  }
}
