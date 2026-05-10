import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/providers/realtime_provider.dart';

/// Сигнатура «отправить WS-сообщение». Injection-point вместо direct-привязки
/// к Riverpod-типам (Ref vs WidgetRef).
typedef CallSender = void Function(String type, Map<String, dynamic> payload);

/// Состояние текущего call'а.
enum CallStatus {
  idle,             // нет активного звонка
  outgoingRinging,  // мы позвонили, ждём accept
  incomingRinging,  // нам позвонили, ждём решения юзера
  connecting,       // accept'нули, ICE-trickle идёт
  connected,        // оба stream'а connected
  ended,            // hangup
}

class CallSession {
  final String peerId;
  final String peerUsername;
  final String peerAvatarUrl;
  final bool isOutgoing;
  final CallStatus status;

  const CallSession({
    required this.peerId,
    required this.peerUsername,
    required this.peerAvatarUrl,
    required this.isOutgoing,
    required this.status,
  });

  CallSession copyWith({CallStatus? status}) => CallSession(
        peerId: peerId,
        peerUsername: peerUsername,
        peerAvatarUrl: peerAvatarUrl,
        isOutgoing: isOutgoing,
        status: status ?? this.status,
      );
}

/// Singleton — один peer-connection переживает навигацию между screens.
/// Использует существующий realtime-канал (тот же WS что у chat'а и
/// нотификаций), а НЕ открывает свой второй коннект:
///   - incoming `call.*` events приходят через `realtimeEventsProvider`
///   - outgoing — через `realtimeSenderProvider.send(...)`
class CallService {
  CallService._();
  static final CallService instance = CallService._();

  // ── State ──
  final ValueNotifier<CallSession?> session = ValueNotifier(null);
  final ValueNotifier<MediaStream?> localStream = ValueNotifier(null);
  final ValueNotifier<MediaStream?> remoteStream = ValueNotifier(null);
  final ValueNotifier<bool> isMuted = ValueNotifier(false);
  final ValueNotifier<bool> isCameraOff = ValueNotifier(false);

  RTCPeerConnection? _pc;
  final List<RTCIceCandidate> _pendingIce = [];

  CallSender? _sender;

  /// Injected upstream-sender. CallListener вызывает раз на init.
  void setSender(CallSender s) {
    _sender = s;
  }

  /// Caller (CallListener) ловит incoming realtime-events и форвардит сюда.
  void onRealtimeEvent(RealtimeEvent evt) => _onRealtimeEvent(evt);

  // ── Outgoing call ──

  Future<void> startCall({
    required String peerId,
    required String peerUsername,
    required String peerAvatarUrl,
  }) async {
    if (session.value != null && session.value!.status != CallStatus.ended) {
      return; // уже активен
    }
    session.value = CallSession(
      peerId: peerId,
      peerUsername: peerUsername,
      peerAvatarUrl: peerAvatarUrl,
      isOutgoing: true,
      status: CallStatus.outgoingRinging,
    );
    await _initLocalStream();
    _send('call.invite', {'to_user_id': peerId, 'kind': 'video'});
  }

  // ── Incoming call ──

  Future<void> acceptIncoming() async {
    final s = session.value;
    if (s == null || s.status != CallStatus.incomingRinging) return;
    session.value = s.copyWith(status: CallStatus.connecting);
    await _initLocalStream();
    await _ensurePeerConnection();
    _send('call.accept', {'to_user_id': s.peerId});
    // Caller на свой call.accept event создаст offer и отправит call.offer.
  }

  Future<void> declineIncoming() async {
    final s = session.value;
    if (s == null || s.status != CallStatus.incomingRinging) return;
    _send('call.decline', {'to_user_id': s.peerId});
    await _cleanup();
  }

  // ── End ──

  Future<void> hangup() async {
    final s = session.value;
    if (s == null) return;
    _send('call.end', {'to_user_id': s.peerId});
    await _cleanup();
  }

  // ── Mute / Camera toggle ──

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

  Future<void> switchCamera() async {
    final tracks = localStream.value?.getVideoTracks() ?? const [];
    if (tracks.isEmpty) return;
    try {
      await Helper.switchCamera(tracks.first);
    } catch (_) {}
  }

  // ── Internals ──

  void _onRealtimeEvent(RealtimeEvent evt) {
    final type = evt.type;
    if (!type.startsWith('call.')) return;
    final payload = evt.payload;
    if (payload is! Map) return;
    final p = Map<String, dynamic>.from(payload);
    final from = p['from_user_id']?.toString() ?? '';
    switch (type) {
      case 'call.invite':
        _handleIncomingInvite(from, p);
        break;
      case 'call.accept':
        _handleAccept(p);
        break;
      case 'call.decline':
        _handleDecline(p);
        break;
      case 'call.offer':
        _handleOffer(p);
        break;
      case 'call.answer':
        _handleAnswer(p);
        break;
      case 'call.ice':
        _handleIce(p);
        break;
      case 'call.end':
        _handleRemoteEnd(p);
        break;
    }
  }

  Future<void> _initLocalStream() async {
    if (localStream.value != null) return;
    try {
      final media = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {
          'facingMode': 'user',
          'width': 640,
          'height': 480,
        },
      });
      localStream.value = media;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[CallService] getUserMedia failed: $e');
      }
      await _cleanup();
    }
  }

  Future<void> _ensurePeerConnection() async {
    if (_pc != null) return;
    final pc = await createPeerConnection({
      'iceServers': [
        {
          'urls': [
            'stun:stun.l.google.com:19302',
            'stun:stun1.l.google.com:19302',
          ],
        },
      ],
      'sdpSemantics': 'unified-plan',
    });
    pc.onIceCandidate = (cand) {
      final s = session.value;
      if (s == null) return;
      _send('call.ice', {
        'to_user_id': s.peerId,
        'candidate': cand.candidate,
        'sdp_mid': cand.sdpMid,
        'sdp_m_line_index': cand.sdpMLineIndex,
      });
    };
    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        remoteStream.value = event.streams.first;
      }
    };
    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        final s = session.value;
        if (s != null) {
          session.value = s.copyWith(status: CallStatus.connected);
        }
      } else if (state ==
              RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state ==
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        unawaited(_cleanup());
      }
    };
    final local = localStream.value;
    if (local != null) {
      for (final track in local.getTracks()) {
        await pc.addTrack(track, local);
      }
    }
    _pc = pc;
  }

  Future<void> _createAndSendOffer() async {
    if (_pc == null) return;
    final offer = await _pc!.createOffer({});
    await _pc!.setLocalDescription(offer);
    final s = session.value;
    if (s == null) return;
    _send('call.offer', {
      'to_user_id': s.peerId,
      'sdp': offer.sdp,
      'type': offer.type,
    });
  }

  Future<void> _handleIncomingInvite(
      String from, Map<String, dynamic> p) async {
    if (session.value != null && session.value!.status != CallStatus.ended) {
      _send('call.decline', {'to_user_id': from});
      return;
    }
    final username = p['from_username']?.toString() ?? '';
    final avatar = p['from_avatar']?.toString() ?? '';
    session.value = CallSession(
      peerId: from,
      peerUsername: username,
      peerAvatarUrl: avatar,
      isOutgoing: false,
      status: CallStatus.incomingRinging,
    );
  }

  Future<void> _handleAccept(Map<String, dynamic> p) async {
    final s = session.value;
    if (s == null || !s.isOutgoing) return;
    session.value = s.copyWith(status: CallStatus.connecting);
    await _ensurePeerConnection();
    await _createAndSendOffer();
  }

  Future<void> _handleDecline(Map<String, dynamic> p) async {
    await _cleanup();
  }

  Future<void> _handleOffer(Map<String, dynamic> p) async {
    await _ensurePeerConnection();
    final sdp = p['sdp']?.toString() ?? '';
    final type = p['type']?.toString() ?? 'offer';
    await _pc!.setRemoteDescription(RTCSessionDescription(sdp, type));
    for (final cand in _pendingIce) {
      await _pc!.addCandidate(cand);
    }
    _pendingIce.clear();
    final answer = await _pc!.createAnswer({});
    await _pc!.setLocalDescription(answer);
    final s = session.value;
    if (s == null) return;
    _send('call.answer', {
      'to_user_id': s.peerId,
      'sdp': answer.sdp,
      'type': answer.type,
    });
  }

  Future<void> _handleAnswer(Map<String, dynamic> p) async {
    if (_pc == null) return;
    final sdp = p['sdp']?.toString() ?? '';
    final type = p['type']?.toString() ?? 'answer';
    await _pc!.setRemoteDescription(RTCSessionDescription(sdp, type));
    for (final cand in _pendingIce) {
      await _pc!.addCandidate(cand);
    }
    _pendingIce.clear();
  }

  Future<void> _handleIce(Map<String, dynamic> p) async {
    final cand = RTCIceCandidate(
      p['candidate']?.toString() ?? '',
      p['sdp_mid']?.toString(),
      (p['sdp_m_line_index'] as num?)?.toInt(),
    );
    if (_pc == null || (await _pc!.getRemoteDescription()) == null) {
      _pendingIce.add(cand);
      return;
    }
    await _pc!.addCandidate(cand);
  }

  Future<void> _handleRemoteEnd(Map<String, dynamic> p) async {
    await _cleanup();
  }

  Future<void> _cleanup() async {
    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;
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
    remoteStream.value = null;
    _pendingIce.clear();
    isMuted.value = false;
    isCameraOff.value = false;
    final s = session.value;
    if (s != null) {
      session.value = s.copyWith(status: CallStatus.ended);
      Future.delayed(const Duration(seconds: 1), () {
        session.value = null;
      });
    }
  }

  void _send(String type, Map<String, dynamic> payload) {
    _sender?.call(type, payload);
  }
}
