import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/providers/realtime_provider.dart';
import 'call_service.dart' show CallKind, CallSender;

/// Состояние group-call'а (C-7).
enum GroupCallStatus {
  idle,
  outgoingInviting, // мы запустили звонок, ждём чтобы кто-то joined
  incomingRinging,  // нас пригласили
  active,           // мы joined (хотя бы один peer connected)
}

/// Один peer в group-call'е. Per-peer renderer + connection state.
class GroupCallPeer {
  final String userId;
  final RTCVideoRenderer renderer = RTCVideoRenderer();
  RTCPeerConnection? pc;
  MediaStream? remoteStream;
  GroupCallPeer(this.userId);
}

class GroupCallSession {
  final String chatId;
  final String chatTitle;
  final CallKind kind;
  final bool isOutgoing;
  final GroupCallStatus status;
  /// userId инициатора звонка (для display «X звонит вам»).
  final String inviterId;
  final String inviterUsername;

  const GroupCallSession({
    required this.chatId,
    required this.chatTitle,
    required this.kind,
    required this.isOutgoing,
    required this.status,
    required this.inviterId,
    required this.inviterUsername,
  });

  GroupCallSession copyWith({GroupCallStatus? status}) => GroupCallSession(
        chatId: chatId,
        chatTitle: chatTitle,
        kind: kind,
        isOutgoing: isOutgoing,
        status: status ?? this.status,
        inviterId: inviterId,
        inviterUsername: inviterUsername,
      );
}

/// Singleton — WebRTC mesh для group-чатов. Каждый участник держит N-1
/// peer-connections (по одному на каждого remote-участника).
///
/// Сервер ничего не знает про active-call participants — frontend сам
/// поддерживает Map'у peer'ов и шлёт offer/answer/ice через WS signaling.
///
/// Capacity: mesh масштабируется как O(N²) connections, разумно до ~4-5
/// человек на текущем железе. SFU (LiveKit) — отдельная инфра-задача.
class GroupCallService {
  GroupCallService._();
  static final GroupCallService instance = GroupCallService._();

  final ValueNotifier<GroupCallSession?> session = ValueNotifier(null);
  /// `Map<userId, GroupCallPeer>` для всех known remote peers (включая тех
  /// кто ещё не connected).
  final ValueNotifier<Map<String, GroupCallPeer>> peers = ValueNotifier({});
  final ValueNotifier<MediaStream?> localStream = ValueNotifier(null);
  final ValueNotifier<bool> isMuted = ValueNotifier(false);
  final ValueNotifier<bool> isCameraOff = ValueNotifier(false);

  CallSender? _sender;
  final AudioPlayer _ringPlayer = AudioPlayer();
  Timer? _ringTimer;

  void setSender(CallSender s) {
    _sender = s;
  }

  void onRealtimeEvent(RealtimeEvent evt) => _onRealtimeEvent(evt);

  // ── Начало звонка ──

  /// Caller инициирует. Шлёт `call.group.invite` всем участникам chat'а
  /// (backend fan-out'ит). По мере того как peers присылают `call.group.join`,
  /// мы создаём peer-connection и отправляем offer.
  Future<void> startGroupCall({
    required String chatId,
    required String chatTitle,
    required String myId,
    required String myUsername,
    CallKind kind = CallKind.video,
  }) async {
    if (session.value != null) return;
    session.value = GroupCallSession(
      chatId: chatId,
      chatTitle: chatTitle,
      kind: kind,
      isOutgoing: true,
      status: GroupCallStatus.outgoingInviting,
      inviterId: myId,
      inviterUsername: myUsername,
    );
    await _initLocalStream();
    _startRingback();
    _send('call.group.invite', {
      'chat_id': chatId,
      'kind': kind == CallKind.voice ? 'voice' : 'video',
    });
  }

  // ── Приём приглашения ──

  Future<void> acceptGroupCall() async {
    final s = session.value;
    if (s == null || s.status != GroupCallStatus.incomingRinging) return;
    _stopRing();
    session.value = s.copyWith(status: GroupCallStatus.active);
    await _initLocalStream();
    // Сообщаем другим что мы joined → они создадут к нам peer-connection.
    _send('call.group.join', {'chat_id': s.chatId});
  }

  Future<void> declineGroupCall() async {
    final s = session.value;
    if (s == null) return;
    _stopRing();
    _send('call.group.leave', {'chat_id': s.chatId});
    await _cleanup();
  }

  // ── Hangup ──

  Future<void> hangup() async {
    final s = session.value;
    if (s == null) return;
    _send('call.group.leave', {'chat_id': s.chatId});
    await _cleanup();
  }

  // ── Mute / Camera ──

  void toggleMute() {
    final tracks = localStream.value?.getAudioTracks() ?? const [];
    if (tracks.isEmpty) return;
    final next = !isMuted.value;
    for (final t in tracks) {
      t.enabled = !next;
    }
    isMuted.value = next;
  }

  void toggleCamera() {
    final tracks = localStream.value?.getVideoTracks() ?? const [];
    if (tracks.isEmpty) return;
    final next = !isCameraOff.value;
    for (final t in tracks) {
      t.enabled = !next;
    }
    isCameraOff.value = next;
  }

  // ── Internals ──

  void _onRealtimeEvent(RealtimeEvent evt) {
    final type = evt.type;
    final payload = evt.payload;
    if (payload is! Map) return;
    final p = Map<String, dynamic>.from(payload);

    switch (type) {
      case 'call.group.invite':
        _handleIncomingInvite(p);
        break;
      case 'call.group.member.joined':
        _handleMemberJoined(p);
        break;
      case 'call.group.member.left':
        _handleMemberLeft(p);
        break;
      // Per-peer signaling — те же события что у 1-1, но мы их интерпретируем
      // ТОЛЬКО когда session active (иначе CallService один-на-один обработает).
      case 'call.offer':
      case 'call.answer':
      case 'call.ice':
        if (session.value != null) {
          _handlePeerSignaling(type, p);
        }
        break;
    }
  }

  Future<void> _handleIncomingInvite(Map<String, dynamic> p) async {
    if (session.value != null) {
      // Уже в каком-то call'е — silently игнорируем (peer всё равно увидит
      // что мы не joined'ились).
      return;
    }
    final chatId = p['chat_id']?.toString() ?? '';
    final from = p['from_user_id']?.toString() ?? '';
    final kindStr = p['kind']?.toString();
    final kind = kindStr == 'voice' ? CallKind.voice : CallKind.video;
    if (chatId.isEmpty || from.isEmpty) return;
    session.value = GroupCallSession(
      chatId: chatId,
      chatTitle: p['chat_title']?.toString() ?? 'Групповой звонок',
      kind: kind,
      isOutgoing: false,
      status: GroupCallStatus.incomingRinging,
      inviterId: from,
      inviterUsername: p['from_username']?.toString() ?? '',
    );
    _startRingtone();
  }

  /// Новый peer joined в наш активный call → мы создаём ему peer-connection
  /// и отправляем offer. Caller side инициирует — convention'ом тот кто уже
  /// был в session offer'ит joiner'у.
  Future<void> _handleMemberJoined(Map<String, dynamic> p) async {
    final s = session.value;
    if (s == null ||
        (s.status != GroupCallStatus.active &&
            s.status != GroupCallStatus.outgoingInviting)) {
      return;
    }
    final from = p['from_user_id']?.toString() ?? '';
    if (from.isEmpty) return;
    // Если это первый join после нашего invite — переходим в active.
    if (s.status == GroupCallStatus.outgoingInviting) {
      _stopRing();
      session.value = s.copyWith(status: GroupCallStatus.active);
    }
    // Получаем (или создаём) peer + connection + отправляем offer.
    final peer = await _ensurePeer(from);
    await _createAndSendOffer(peer);
  }

  Future<void> _handleMemberLeft(Map<String, dynamic> p) async {
    final from = p['from_user_id']?.toString() ?? '';
    if (from.isEmpty) return;
    await _removePeer(from);
    // Если ушёл последний peer — закрываем call.
    if (peers.value.isEmpty && session.value != null) {
      await _cleanup();
    }
  }

  /// Per-peer signaling: offer/answer/ice. Берём from_user_id чтобы понять
  /// какому peer'у адресовано.
  Future<void> _handlePeerSignaling(
      String type, Map<String, dynamic> p) async {
    final from = p['from_user_id']?.toString() ?? '';
    if (from.isEmpty) return;
    final peer = await _ensurePeer(from);
    final pc = peer.pc;
    if (pc == null) return;
    if (type == 'call.offer') {
      final sdp = p['sdp']?.toString() ?? '';
      final t = p['type']?.toString() ?? 'offer';
      await pc.setRemoteDescription(RTCSessionDescription(sdp, t));
      final answer = await pc.createAnswer({});
      await pc.setLocalDescription(answer);
      _send('call.answer', {
        'to_user_id': from,
        'sdp': answer.sdp,
        'type': answer.type,
      });
    } else if (type == 'call.answer') {
      final sdp = p['sdp']?.toString() ?? '';
      final t = p['type']?.toString() ?? 'answer';
      await pc.setRemoteDescription(RTCSessionDescription(sdp, t));
    } else if (type == 'call.ice') {
      final cand = RTCIceCandidate(
        p['candidate']?.toString() ?? '',
        p['sdp_mid']?.toString(),
        (p['sdp_m_line_index'] as num?)?.toInt(),
      );
      try {
        await pc.addCandidate(cand);
      } catch (_) {}
    }
  }

  Future<GroupCallPeer> _ensurePeer(String userId) async {
    final existing = peers.value[userId];
    if (existing != null && existing.pc != null) return existing;
    final peer = existing ?? GroupCallPeer(userId);
    await peer.renderer.initialize();
    final pc = await createPeerConnection({
      'iceServers': [
        {'urls': ['stun:stun.l.google.com:19302']}
      ],
      'sdpSemantics': 'unified-plan',
    });
    pc.onIceCandidate = (cand) {
      _send('call.ice', {
        'to_user_id': userId,
        'candidate': cand.candidate,
        'sdp_mid': cand.sdpMid,
        'sdp_m_line_index': cand.sdpMLineIndex,
      });
    };
    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        peer.remoteStream = event.streams.first;
        peer.renderer.srcObject = event.streams.first;
        // Notify listeners (rebuild grid).
        peers.value = {...peers.value};
      }
    };
    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        unawaited(_removePeer(userId));
      }
    };
    final local = localStream.value;
    if (local != null) {
      for (final track in local.getTracks()) {
        await pc.addTrack(track, local);
      }
    }
    peer.pc = pc;
    peers.value = {...peers.value, userId: peer};
    return peer;
  }

  Future<void> _createAndSendOffer(GroupCallPeer peer) async {
    final pc = peer.pc;
    if (pc == null) return;
    final offer = await pc.createOffer({});
    await pc.setLocalDescription(offer);
    _send('call.offer', {
      'to_user_id': peer.userId,
      'sdp': offer.sdp,
      'type': offer.type,
    });
  }

  Future<void> _removePeer(String userId) async {
    final peer = peers.value[userId];
    if (peer == null) return;
    try {
      await peer.pc?.close();
    } catch (_) {}
    try {
      peer.renderer.srcObject = null;
      await peer.renderer.dispose();
    } catch (_) {}
    final next = Map<String, GroupCallPeer>.from(peers.value);
    next.remove(userId);
    peers.value = next;
  }

  Future<void> _initLocalStream() async {
    if (localStream.value != null) return;
    final s = session.value;
    final isVoice = s != null && s.kind == CallKind.voice;
    try {
      final media = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': isVoice
            ? false
            : {'facingMode': 'user', 'width': 640, 'height': 480},
      });
      localStream.value = media;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[GroupCallService] getUserMedia failed: $e');
      }
      await _cleanup();
    }
  }

  void _startRingtone() {
    HapticFeedback.heavyImpact();
    _ringTimer?.cancel();
    _ringTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      HapticFeedback.heavyImpact();
    });
    _playRingAsset('assets/sounds/ringtone.wav');
  }

  void _startRingback() {
    HapticFeedback.lightImpact();
    _ringTimer?.cancel();
    _ringTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      HapticFeedback.lightImpact();
    });
    _playRingAsset('assets/sounds/ringback.wav');
  }

  Future<void> _playRingAsset(String asset) async {
    try {
      await _ringPlayer.stop();
      await _ringPlayer.setAsset(asset);
      await _ringPlayer.setLoopMode(LoopMode.one);
      await _ringPlayer.setVolume(0.7);
      await _ringPlayer.play();
    } catch (_) {}
  }

  void _stopRing() {
    _ringTimer?.cancel();
    _ringTimer = null;
    unawaited(_ringPlayer.stop());
  }

  Future<void> _cleanup() async {
    _stopRing();
    // Close all peers.
    final ids = List<String>.from(peers.value.keys);
    for (final id in ids) {
      await _removePeer(id);
    }
    final ls = localStream.value;
    if (ls != null) {
      for (final t in ls.getTracks()) {
        try {
          await t.stop();
        } catch (_) {}
      }
      try {
        await ls.dispose();
      } catch (_) {}
    }
    localStream.value = null;
    isMuted.value = false;
    isCameraOff.value = false;
    session.value = null;
  }

  void _send(String type, Map<String, dynamic> payload) {
    _sender?.call(type, payload);
  }
}
