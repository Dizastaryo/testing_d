import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/config/app_config.dart';
import '../../core/providers/realtime_provider.dart';
import '../../core/services/logger.dart';

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
    appLog('[CallService] startRing status=$status');
    if (status == CallStatus.incomingRinging) {
      HapticFeedback.heavyImpact();
      _ringTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
        HapticFeedback.heavyImpact();
      });
      _playRingAsset('assets/sounds/ringtone.wav', loud: true);
    } else if (status == CallStatus.outgoingRinging) {
      HapticFeedback.lightImpact();
      _ringTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        HapticFeedback.lightImpact();
      });
      _playRingAsset('assets/sounds/ringback.wav', loud: false);
    }
  }

  /// BUG-2 (c): настраиваем AudioSession ПЕРЕД проигрыванием ringtone.
  /// Без этого iOS режет звук во время silent-mode (mute-switch на боку),
  /// Android иногда routes ring через earpiece вместо speaker. Категория
  /// `playback + speech` гарантирует громкое воспроизведение через main
  /// speaker даже при подключённых наушниках.
  bool _audioSessionConfigured = false;
  Future<void> _ensureAudioSession() async {
    if (_audioSessionConfigured) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.duckOthers,
        avAudioSessionMode: AVAudioSessionMode.voicePrompt,
        avAudioSessionRouteSharingPolicy:
            AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions:
            AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          flags: AndroidAudioFlags.audibilityEnforced,
          usage: AndroidAudioUsage.notificationRingtone,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransient,
        androidWillPauseWhenDucked: true,
      ));
      await session.setActive(true);
      _audioSessionConfigured = true;
      appLog('[CallService] audio session configured for ringtone');
    } catch (e, st) {
      appLog.error('[CallService] audio session configure failed', e, st);
    }
  }

  /// Loop play asset через _ringPlayer. BUG-2 (b): раньше silent catch
  /// проглатывал любые ошибки — broken asset = тишина без объяснений.
  /// Теперь логируем и пробрасываем в `_lastRingError` для display'а.
  Future<void> _playRingAsset(String assetPath, {required bool loud}) async {
    await _ensureAudioSession();
    try {
      await _ringPlayer.stop();
      await _ringPlayer.setAsset(assetPath);
      await _ringPlayer.setLoopMode(LoopMode.one);
      await _ringPlayer.setVolume(loud ? 1.0 : 0.7);
      await _ringPlayer.play();
      appLog('[CallService] ring playing $assetPath (loud=$loud)');
    } catch (e, st) {
      appLog.error('[CallService] ring asset play failed: $assetPath', e, st);
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
    } catch (e) {
      appLog.warn('[CallService] endtone play failed', e);
    }
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
    } catch (e) {
      appLog.warn('[CallService] switchCamera failed', e);
    }
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
    } catch (e, st) {
      appLog.error('[CallService] getUserMedia failed', e, st);
      await _cleanup();
    }
  }

  Future<void> _ensurePeerConnection() async {
    if (_pc != null) return;
    final pc = await createPeerConnection({
      'iceServers': AppConfig.iceServers,
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
    // BUG-9: race condition fix. Между проверкой `_pc == null` и `_pc!`
    // вызовом другая async-операция (например hangup) могла обнулить _pc.
    // Capture в local var один раз — все последующие .createOffer/.setLocal
    // идут на тот же instance даже если поле уже обнулили.
    final pc = _pc;
    if (pc == null) return;
    // C-5: при reconnect передаём iceRestart=true → WebRTC сгенерирует
    // новые ICE candidates, минуя кэш старой failed-сессии.
    final RTCSessionDescription offer;
    try {
      offer = await pc.createOffer(
        iceRestart ? {'iceRestart': true} : {},
      );
      await pc.setLocalDescription(offer);
    } catch (e, st) {
      appLog.error('[CallService] createOffer/setLocalDescription failed', e, st);
      return;
    }
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
    appLog('[CallService] incoming invite from=$from payload-keys=${p.keys.toList()}');
    if (from.isEmpty) {
      appLog.warn('[CallService] incoming invite ignored: empty from_user_id');
      return;
    }
    if (session.value != null && session.value!.status != CallStatus.ended) {
      appLog('[CallService] busy — declining incoming from $from');
      _send('call.decline', {'to_user_id': from});
      return;
    }
    // BUG-2 (a): backend теперь обогащает payload через relayCallEvent.
    // Раньше эти поля могли быть пустые → blank UI на CallScreen.
    final username = p['from_username']?.toString() ?? '';
    final avatar = p['from_avatar']?.toString() ?? '';
    // C-2: caller's kind ('video'/'voice') приходит в payload.
    final kindStr = p['kind']?.toString();
    final kind = kindStr == 'voice' ? CallKind.voice : CallKind.video;
    appLog('[CallService] establishing incoming session: peer=@$username kind=$kind');
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
    // BUG-9: тот же race-fix что и в _createAndSendOffer. _pc мог быть
    // обнулён в _cleanup между await'ами — capture в local var.
    final pc = _pc;
    if (pc == null) {
      appLog.warn('[CallService] _handleOffer: _pc null after ensure');
      return;
    }
    final sdp = p['sdp']?.toString() ?? '';
    final type = p['type']?.toString() ?? 'offer';
    try {
      await pc.setRemoteDescription(RTCSessionDescription(sdp, type));
      for (final cand in _pendingIce) {
        await pc.addCandidate(cand);
      }
      _pendingIce.clear();
      final answer = await pc.createAnswer({});
      await pc.setLocalDescription(answer);
      final s = session.value;
      if (s == null) return;
      _send('call.answer', {
        'to_user_id': s.peerId,
        'sdp': answer.sdp,
        'type': answer.type,
      });
    } catch (e, st) {
      appLog.error('[CallService] _handleOffer failed', e, st);
    }
  }

  Future<void> _handleAnswer(Map<String, dynamic> p) async {
    // BUG-9: local-var capture для NPE safety.
    final pc = _pc;
    if (pc == null) return;
    final sdp = p['sdp']?.toString() ?? '';
    final type = p['type']?.toString() ?? 'answer';
    try {
      await pc.setRemoteDescription(RTCSessionDescription(sdp, type));
      for (final cand in _pendingIce) {
        await pc.addCandidate(cand);
      }
      _pendingIce.clear();
    } catch (e, st) {
      appLog.error('[CallService] _handleAnswer failed', e, st);
    }
  }

  Future<void> _handleIce(Map<String, dynamic> p) async {
    final cand = RTCIceCandidate(
      p['candidate']?.toString() ?? '',
      p['sdp_mid']?.toString(),
      (p['sdp_m_line_index'] as num?)?.toInt(),
    );
    // BUG-9: local-var capture. _pc мог быть обнулён между check и addCandidate.
    final pc = _pc;
    if (pc == null) {
      _pendingIce.add(cand);
      return;
    }
    try {
      if ((await pc.getRemoteDescription()) == null) {
        _pendingIce.add(cand);
        return;
      }
      await pc.addCandidate(cand);
    } catch (e) {
      appLog.warn('[CallService] _handleIce addCandidate failed', e);
    }
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
    } catch (e) {
      appLog.warn('[CallService] pc.close failed', e);
    }
    _pc = null;
    final ls = localStream.value;
    if (ls != null) {
      for (final t in ls.getTracks()) {
        try {
          await t.stop();
        } catch (e) {
          appLog.warn('[CallService] track.stop failed', e);
        }
      }
      try {
        await ls.dispose();
      } catch (e) {
        appLog.warn('[CallService] localStream.dispose failed', e);
      }
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
