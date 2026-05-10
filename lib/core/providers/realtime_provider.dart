import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../api/api_client.dart';
import '../config/app_config.dart';
import 'auth_provider.dart';

/// One incoming server message: `{type, payload}` from `internal/ws/hub.go`.
class RealtimeEvent {
  final String type;
  final dynamic payload;
  const RealtimeEvent(this.type, this.payload);
}

/// Stream of every event the backend pushes to this user. Subscribe from
/// any provider/widget to react to realtime traffic. Stays empty when
/// the user is logged out; connection auto-restarts on login.
final realtimeEventsProvider = StreamProvider<RealtimeEvent>((ref) {
  final auth = ref.watch(authProvider);
  if (!auth.isAuthenticated) {
    return const Stream<RealtimeEvent>.empty();
  }
  final controller = ref.read(_realtimeConnectionProvider);
  return controller.events;
});

/// Holds the underlying connection. Separate provider so callers can both
/// listen (events) and send (upstream) without recreating the socket.
final _realtimeConnectionProvider = Provider<_RealtimeConnection>((ref) {
  final controller = _RealtimeConnection(ref);
  ref.onDispose(controller.dispose);
  return controller;
});

/// Public API for pushing client-originated events upstream to the server
/// (typing indicators, future "now playing" announcements, etc.).
final realtimeSenderProvider = Provider<RealtimeSender>((ref) {
  // Watching auth here means a logout disposes the sender; next login spins up
  // a fresh connection lazily on first send/listen.
  ref.watch(authProvider);
  return RealtimeSender(ref);
});

class RealtimeSender {
  final Ref _ref;
  RealtimeSender(this._ref);

  /// Best-effort send. If the socket isn't open yet (still reconnecting),
  /// the frame is dropped — caller should treat upstream events as advisory.
  void send(String type, Map<String, dynamic> payload) {
    final auth = _ref.read(authProvider);
    if (!auth.isAuthenticated) return;
    final conn = _ref.read(_realtimeConnectionProvider);
    conn.send(type, payload);
  }
}

/// Long-lived WebSocket holder. Owns reconnect logic with exponential backoff.
/// Errors and onDone trigger reconnect; events are forwarded into a broadcast
/// stream so multiple listeners can subscribe.
class _RealtimeConnection {
  final Ref _ref;
  final _events = StreamController<RealtimeEvent>.broadcast();
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnect;
  Duration _backoff = const Duration(seconds: 1);
  bool _disposed = false;
  /// Wall-clock time the last `_connect` attempt opened a channel. Used to
  /// detect "WS handshake closes immediately" — a signature of token expiry.
  DateTime? _connectStartedAt;
  /// Set true while we've already triggered a refresh in the current
  /// reconnect cycle, so we don't ping `/auth/refresh` repeatedly when the
  /// refresh-token itself is also dead.
  bool _refreshAttempted = false;

  _RealtimeConnection(this._ref) {
    _connect();
  }

  Stream<RealtimeEvent> get events => _events.stream;

  Future<void> _connect() async {
    if (_disposed) return;
    try {
      final storage = _ref.read(secureStorageProvider);
      final token = await storage.read(key: 'access_token');
      if (token == null || token.isEmpty) {
        // No token — user just logged out mid-reconnect. Stop.
        return;
      }

      final base = AppConfig.apiBaseUrl;
      // ws[s]://host/api/v1/ws?token=<jwt>. Token via query param because
      // browser WebSocket can't send custom headers in the handshake.
      final wsUrl = base
          .replaceFirst('http://', 'ws://')
          .replaceFirst('https://', 'wss://');
      final uri = Uri.parse('$wsUrl/ws?token=$token');

      debugPrint('[realtime] connecting to $uri');
      _channel = WebSocketChannel.connect(uri);
      _connectStartedAt = DateTime.now();

      _sub = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );

      // Reset backoff once we got a connection. Real "connected" signal would
      // be a server-sent hello, but for now successful subscribe = good.
      _backoff = const Duration(seconds: 1);
    } catch (e) {
      debugPrint('[realtime] connect error: $e');
      _scheduleReconnect();
    }
  }

  /// Heuristic: if the connection died within 3 seconds of opening AND we
  /// haven't already attempted a refresh in this cycle, the access token is
  /// most likely expired (server's `middleware.Auth` rejected the upgrade).
  /// A long-lived connection that dies from network blip would last longer.
  bool _looksLikeAuthFailure() {
    final start = _connectStartedAt;
    if (start == null) return false;
    final lifespan = DateTime.now().difference(start);
    return lifespan < const Duration(seconds: 3) && !_refreshAttempted;
  }

  void _onMessage(dynamic raw) {
    try {
      // Hub batches messages with '\n' between each — split if needed.
      final text = raw is String ? raw : utf8.decode(raw as List<int>);
      for (final chunk in text.split('\n')) {
        if (chunk.trim().isEmpty) continue;
        final body = jsonDecode(chunk);
        if (body is! Map) continue;
        final type = body['type']?.toString() ?? '';
        final payload = body['payload'];
        if (type.isEmpty) continue;
        _events.add(RealtimeEvent(type, payload));
      }
    } catch (e) {
      debugPrint('[realtime] parse error: $e raw=$raw');
    }
  }

  void _onError(Object error) {
    debugPrint('[realtime] socket error: $error');
    _scheduleReconnect();
  }

  void _onDone() {
    final code = _channel?.closeCode;
    final reason = _channel?.closeReason;
    debugPrint('[realtime] socket closed code=$code reason=$reason');
    _scheduleReconnect();
  }

  /// Triggers an immediate refresh-token flow before the next reconnect when
  /// we suspect the access token is the reason the WS keeps dying. Marks
  /// `_refreshAttempted` so we don't loop refresh attempts within one cycle.
  Future<void> _refreshAndReconnect() async {
    if (_disposed) return;
    _refreshAttempted = true;
    debugPrint('[realtime] suspect token expiry — refreshing');
    final ok = await _ref.read(apiClientProvider).refreshTokens();
    if (_disposed) return;
    if (ok) {
      // Reset backoff on successful refresh — next attempt should succeed.
      _backoff = const Duration(seconds: 1);
      _connect();
    } else {
      // Refresh-token also dead: stop trying. Next user action will trigger
      // a 401 on REST → auth_provider drops to login screen.
      debugPrint('[realtime] refresh failed — giving up reconnect cycle');
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnect?.cancel();
    if (_looksLikeAuthFailure()) {
      _refreshAndReconnect();
      return;
    }
    final delay = _backoff;
    debugPrint('[realtime] reconnecting in ${delay.inSeconds}s');
    _reconnect = Timer(delay, () {
      // A new attempt opens a window for refresh-on-quick-disconnect again,
      // but only if backoff has grown past first try (i.e. multiple immediate
      // disconnects in a row could each individually justify a refresh).
      if (_backoff > const Duration(seconds: 4)) {
        _refreshAttempted = false;
      }
      _connect();
    });
    // Exponential backoff capped at 30s.
    _backoff = Duration(seconds: (_backoff.inSeconds * 2).clamp(1, 30));
  }

  /// Sends `{type, payload}` to the server. Drops silently if the socket
  /// is mid-reconnect — clients should treat realtime as advisory.
  void send(String type, Map<String, dynamic> payload) {
    final ch = _channel;
    if (ch == null || _disposed) return;
    try {
      ch.sink.add(jsonEncode({'type': type, 'payload': payload}));
    } catch (e) {
      debugPrint('[realtime] send error: $e');
    }
  }

  void dispose() {
    _disposed = true;
    _reconnect?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _events.close();
  }
}
