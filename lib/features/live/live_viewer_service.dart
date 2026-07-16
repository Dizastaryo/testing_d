import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/models/live_stream.dart';

enum LiveViewerStatus { idle, joining, connected, ended, failed }

/// Viewer side of a live stream, backed by **LiveKit (SFU)**.
///
/// The viewer joins the room (`room == stream id`) subscribe-only and renders
/// the broadcaster's video track. Stream end is detected via LiveKit events
/// (broadcaster participant leaves / room disconnected) — no manual signaling.
class LiveViewerService {
  LiveViewerService._();
  static final instance = LiveViewerService._();

  final ValueNotifier<LiveViewerStatus> status =
      ValueNotifier(LiveViewerStatus.idle);
  final ValueNotifier<VideoTrack?> remoteVideoTrack = ValueNotifier(null);
  final ValueNotifier<int> viewerCount = ValueNotifier(0);

  Room? _room;
  EventsListener<RoomEvent>? _listener;
  String? _streamId;
  String? _broadcasterIdentity;
  Timer? _joinTimeout;
  bool _closing = false;
  // Поколение join'а: каждый вызов joinStream инкрементит счётчик. Если во
  // время await'ов стартовал новый join (или случился leave), устаревший
  // join распознаёт это по несовпадению gen и не портит состояние новее себя.
  int _joinGen = 0;

  // Watchdog: if the broadcaster's video never arrives, surface a failure
  // instead of hanging on "Подключение к эфиру…" forever.
  static const _joinTimeoutDuration = Duration(seconds: 20);

  // ── Join ───────────────────────────────────────────────────────────────

  Future<LiveStream> joinStream(ApiClient api, String streamId) async {
    if (status.value != LiveViewerStatus.idle) await leaveStream(api);
    final gen = ++_joinGen;
    _closing = false;
    _streamId = streamId;
    status.value = LiveViewerStatus.joining;

    // Единый catch на весь join: раньше падение api.post/парсинга (строки до
    // room.connect) выбрасывалось наружу, НЕ переводя status из joining →
    // экран навсегда «Подключение к эфиру…». Теперь любая ошибка на пути
    // join'а честно ставит failed (если этот join ещё актуален).
    try {
      final resp = await api.post(ApiEndpoints.streamJoin(streamId));
      if (gen != _joinGen) throw StateError('join superseded');
      final data = resp.data['data'] as Map<String, dynamic>;
      final stream = LiveStream.fromJson(data['stream'] as Map<String, dynamic>);
      viewerCount.value =
          (data['viewer_count'] as num?)?.toInt() ?? stream.viewerCount;
      _broadcasterIdentity = stream.userId; // token identity == userID
      final url = data['livekit_url'] as String? ?? '';
      final token = data['token'] as String? ?? '';
      if (url.isEmpty || token.isEmpty) {
        throw StateError('Сервер не выдал доступ к эфиру (LiveKit не настроен)');
      }

      final room = Room();
      _room = room;
      _listener = room.createListener();
      _wireEvents();

      _joinTimeout?.cancel();
      _joinTimeout = Timer(_joinTimeoutDuration, () {
        if (status.value == LiveViewerStatus.joining) {
          status.value = LiveViewerStatus.failed;
        }
      });

      await room.connect(url, token);
      // Пока коннектились, стартовал более новый join / случился leave —
      // не трогаем актуальное состояние, сворачиваем свою комнату.
      if (gen != _joinGen) {
        await room.disconnect();
        throw StateError('join superseded');
      }

      // The broadcaster may already be publishing — pick up an existing track.
      _attachExistingBroadcasterTrack();
      return stream;
    } catch (e) {
      debugPrint('[LiveViewer] join FAILED: $e');
      if (gen == _joinGen) {
        _joinTimeout?.cancel();
        if (!_closing) status.value = LiveViewerStatus.failed;
        await _disposeRoom();
      }
      rethrow;
    }
  }

  // ── LiveKit events ────────────────────────────────────────────────────────

  void _wireEvents() {
    _listener
      ?..on<TrackSubscribedEvent>((e) {
        final t = e.track;
        if (t is VideoTrack) {
          _joinTimeout?.cancel();
          remoteVideoTrack.value = t;
          status.value = LiveViewerStatus.connected;
        }
      })
      ..on<TrackUnsubscribedEvent>((e) {
        if (identical(e.track, remoteVideoTrack.value)) {
          remoteVideoTrack.value = null;
        }
      })
      ..on<ParticipantConnectedEvent>((_) => _updateViewerCount())
      ..on<ParticipantDisconnectedEvent>((e) {
        _updateViewerCount();
        if (e.participant.identity == _broadcasterIdentity) {
          _markEnded(); // broadcaster left → stream ended
        }
      })
      ..on<RoomDisconnectedEvent>((_) => _markEnded());
  }

  void _attachExistingBroadcasterTrack() {
    final remotes = _room?.remoteParticipants.values ?? const <RemoteParticipant>[];
    for (final p in remotes) {
      for (final pub in p.videoTrackPublications) {
        final t = pub.track;
        if (t is VideoTrack) {
          _joinTimeout?.cancel();
          remoteVideoTrack.value = t;
          status.value = LiveViewerStatus.connected;
          return;
        }
      }
    }
  }

  void _updateViewerCount() {
    // For a viewer, remoteParticipants = broadcaster + other viewers; adding
    // self gives the total minus the broadcaster ≈ remoteParticipants.length.
    final n = _room?.remoteParticipants.length ?? 0;
    if (n > 0) viewerCount.value = n;
  }

  void _markEnded() {
    if (_closing) return;
    if (status.value == LiveViewerStatus.connected ||
        status.value == LiveViewerStatus.joining) {
      status.value = LiveViewerStatus.ended;
    }
  }

  // ── Leave ──────────────────────────────────────────────────────────────────

  Future<void> leaveStream(ApiClient api) async {
    final sid = _streamId;
    _closing = true;
    _joinGen++; // отменяем любой join, ещё висящий на await'е
    _joinTimeout?.cancel();
    _joinTimeout = null;
    await _room?.disconnect();
    if (sid != null) {
      try {
        await api.delete(ApiEndpoints.streamJoin(sid));
      } catch (_) {}
    }
    await _disposeRoom();
    remoteVideoTrack.value = null;
    viewerCount.value = 0;
    _streamId = null;
    _broadcasterIdentity = null;
    status.value = LiveViewerStatus.idle;
  }

  Future<void> _disposeRoom() async {
    try {
      await _listener?.dispose();
    } catch (_) {}
    _listener = null;
    try {
      await _room?.dispose();
    } catch (_) {}
    _room = null;
  }
}
