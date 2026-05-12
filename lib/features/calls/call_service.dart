import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:just_audio/just_audio.dart';

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
  reconnecting,     // C-5: упала связь, пробуем ICE-restart
  ended,            // hangup
}

/// Тип звонка — video или voice (C-2 audio-only). Кладётся в WS payload и
/// влияет на getUserMedia options (video false для voice) + UI rendering
/// (без remote-renderer'а на стороне callee для voice).
enum CallKind { video, voice }

class CallSession {
  final String peerId;
  final String peerUsername;
  final String peerAvatarUrl;
  final bool isOutgoing;
  final CallStatus status;
  final CallKind kind;
  /// Момент когда статус перешёл в `connected` — для отображения таймера
  /// MM:SS в UI (C-4). null пока not-connected.
  final DateTime? connectedAt;

  const CallSession({
    required this.peerId,
    required this.peerUsername,
    required this.peerAvatarUrl,
    required this.isOutgoing,
    required this.status,
    this.kind = CallKind.video,
    this.connectedAt,
  });

  CallSession copyWith({
    CallStatus? status,
    CallKind? kind,
    DateTime? connectedAt,
  }) =>
      CallSession(
        peerId: peerId,
        peerUsername: peerUsername,
        peerAvatarUrl: peerAvatarUrl,
        isOutgoing: isOutgoing,
        status: status ?? this.status,
        kind: kind ?? this.kind,
        connectedAt: connectedAt ?? this.connectedAt,
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
  /// C-6: PiP флаг. true = CallScreen свёрнут, CallListener рендерит
  /// floating mini-bubble поверх всего app'а. Tap на mini → set false +
  /// re-open full-screen. Сбрасывается на каждый новый звонок.
  final ValueNotifier<bool> minimized = ValueNotifier(false);

  RTCPeerConnection? _pc;
  final List<RTCIceCandidate> _pendingIce = [];

  // C-3 / C-3.1: ring-loop. Haptic + sine-wave WAV asset (programmatically
  // synthesized via assets/sounds/generate_tones.py — CC0 by construction).
  // На incoming/outgoing звучат разные тона + параллельно вибрация.
  // Ring player отдельный от music-плеера — не мешает background-audio.
  Timer? _ringTimer;
  final AudioPlayer _ringPlayer = AudioPlayer();

  // C-5: timer для ICE-restart fallback'а — даём 10 сек на восстановление.
  Timer? _reconnectTimer;

  CallSender? _sender;

  /// Injected upstream-sender. CallListener вызывает раз на init.
  void setSender(CallSender s) {
    _sender = s;
  }

  /// C-3 / C-3.1: запускает ring-loop с haptic + sine-wave audio asset.
  /// Incoming — telephone ringtone (800Hz dual-tone) + heavy vibration.
  /// Outgoing — Russian ringback (425Hz, 1с+3с silence) + light vibration.
  /// Идемпотент: cancel'ит previous timer перед стартом нового.
  void _startRing(CallStatus status) {
    _ringTimer?.cancel();
    if (status == CallStatus.incomingRinging) {
      HapticFeedback.heavyImpact();
      _ringTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
        HapticFeedback.heavyImpact();
      });
      _playRingAsset('assets/sounds/ringtone.wav');
    } else if (status == CallStatus.outgoingRinging) {
      HapticFeedback.lightImpact();
      _ringTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        HapticFeedback.lightImpact();
      });
      _playRingAsset('assets/sounds/ringback.wav');
    }
  }

  /// Loop play asset через _ringPlayer. Errors silent — если asset не
  /// загрузился (broken build), haptic всё равно сработает.
  Future<void> _playRingAsset(String assetPath) async {
    try {
      await _ringPlayer.stop();
      await _ringPlayer.setAsset(assetPath);
      await _ringPlayer.setLoopMode(LoopMode.one);
      await _ringPlayer.setVolume(0.7);
      await _ringPlayer.play();
    } catch (_) {
      // Silent fallback на haptic-only.
    }
  }

  void _stopRing() {
    _ringTimer?.cancel();
    _ringTimer = null;
    unawaited(_ringPlayer.stop());
  }

  /// One-shot endtone (descending chirp) при hangup. Играется до cleanup'а
  /// audio session, поэтому ставим короткий 500ms.
  Future<void> _playEndTone() async {
    try {
      await _ringPlayer.stop();
      await _ringPlayer.setAsset('assets/sounds/endtone.wav');
      await _ringPlayer.setLoopMode(LoopMode.off);
      await _ringPlayer.setVolume(0.6);
      await _ringPlayer.play();
    } catch (_) {}
  }

  /// Caller (CallListener) ловит incoming realtime-events и форвардит сюда.
  void onRealtimeEvent(RealtimeEvent evt) => _onRealtimeEvent(evt);

  // ── Outgoing call ──

  Future<void> startCall({
    required String peerId,
    required String peerUsername,
    required String peerAvatarUrl,
    CallKind kind = CallKind.video,
  }) async {
    if (session.value != null && session.value!.status != CallStatus.ended) {
      return; // уже активен
    }
    minimized.value = false; // C-6: новый звонок всегда полноэкранный.
    session.value = CallSession(
      peerId: peerId,
      peerUsername: peerUsername,
      peerAvatarUrl: peerAvatarUrl,
      isOutgoing: true,
      status: CallStatus.outgoingRinging,
      kind: kind,
    );
    _startRing(CallStatus.outgoingRinging);
    await _initLocalStream();
    _send('call.invite', {
      'to_user_id': peerId,
      'kind': kind == CallKind.voice ? 'voice' : 'video',
    });
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
    final s = session.value;
    final isVoice = s != null && s.kind == CallKind.voice;
    try {
      // C-2: voice-call → отключаем video в getUserMedia (экономит трафик
      // + camera permission не нужен на callee если он принимает voice).
      final media = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': isVoice
            ? false
            : {
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
        // C-3: ring выключается при transition в connected.
        // C-5: success-reconnect — отменяем reconnect timer + статус
        // обратно в connected (был reconnecting).
        _stopRing();
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        final s = session.value;
        if (s != null) {
          // C-4: фиксируем connect моmenт (только если ещё не fix'или —
          // на reconnect сохраняем оригинальный connectedAt).
          session.value = s.copyWith(
            status: CallStatus.connected,
            connectedAt: s.connectedAt ?? DateTime.now(),
          );
        }
      } else if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        // C-5: temporary disconnect — пробуем восстановить через ICE-restart.
        // Cleanup'имся только если reconnect не помог за 10 сек.
        _tryReconnect();
      } else if (state ==
              RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
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

  Future<void> _createAndSendOffer({bool iceRestart = false}) async {
    if (_pc == null) return;
    // C-5: при reconnect передаём iceRestart=true → WebRTC сгенерирует
    // новые ICE candidates, минуя кэш старой failed-сессии.
    final offer = await _pc!.createOffer(
      iceRestart ? {'iceRestart': true} : {},
    );
    await _pc!.setLocalDescription(offer);
    final s = session.value;
    if (s == null) return;
    _send('call.offer', {
      'to_user_id': s.peerId,
      'sdp': offer.sdp,
      'type': offer.type,
    });
  }

  /// C-5: попытка ICE-restart. Только caller инициирует (callee получит
  /// новый offer через WS и автоматически setRemoteDescription/answer).
  /// Если за 10 сек не connected → cleanup.
  void _tryReconnect() {
    final s = session.value;
    if (s == null || s.status == CallStatus.reconnecting) return;
    if (_pc == null) {
      unawaited(_cleanup());
      return;
    }
    session.value = s.copyWith(status: CallStatus.reconnecting);

    // Только caller тригерит ICE-restart. Callee пассивно ждёт новый offer.
    if (s.isOutgoing) {
      unawaited(_createAndSendOffer(iceRestart: true));
    }

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 10), () {
      // Если за 10 сек state не вернулся в connected — сдаёмся.
      final cur = session.value;
      if (cur != null && cur.status == CallStatus.reconnecting) {
        unawaited(_cleanup());
      }
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
    // C-2: caller's kind ('video'/'voice') приходит в payload.
    final kindStr = p['kind']?.toString();
    final kind = kindStr == 'voice' ? CallKind.voice : CallKind.video;
    minimized.value = false;
    session.value = CallSession(
      peerId: from,
      peerUsername: username,
      peerAvatarUrl: avatar,
      isOutgoing: false,
      status: CallStatus.incomingRinging,
      kind: kind,
    );
    _startRing(CallStatus.incomingRinging);
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
    // C-3 / C-5: останавливаем ring + reconnect timer'ы при любом cleanup'е.
    _stopRing();
    // C-3.1: end-tone chirp если звонок был active (не на silent decline).
    final s = session.value;
    if (s != null && s.status != CallStatus.idle) {
      unawaited(_playEndTone());
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
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
    final endingSession = session.value;
    if (endingSession != null) {
      session.value = endingSession.copyWith(status: CallStatus.ended);
      Future.delayed(const Duration(seconds: 1), () {
        session.value = null;
        minimized.value = false; // C-6: сбрасываем PiP на каждый cleanup.
      });
    } else {
      minimized.value = false;
    }
  }

  void _send(String type, Map<String, dynamic> payload) {
    _sender?.call(type, payload);
  }
}
