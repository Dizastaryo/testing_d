import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/config/app_config.dart';
import '../../core/providers/realtime_provider.dart';
import '../../core/services/call_bg_service.dart';
import '../../core/services/logger.dart';
import 'call_service.dart' show CallKind, CallSender, CallService, CallStatus;

/// Состояние group-call'а (C-7).
enum GroupCallStatus {
  idle,
  outgoingInviting, // мы запустили звонок, ждём чтобы кто-то joined
  incomingRinging,  // нас пригласили
  active,           // мы joined (хотя бы один peer connected)
}

// ── Member status tracking ──────────────────────────────────────────────────

/// Статус участника во время ожидания ответа на звонок.
enum GroupCallMemberStatus { ringing, joined, declined }

/// Данные одного участника чата, которому был разослан инвайт.
class GroupCallMember {
  final String userId;
  final String username;
  final String fullName;
  final String avatarUrl;
  final GroupCallMemberStatus status;

  const GroupCallMember({
    required this.userId,
    required this.username,
    this.fullName = '',
    this.avatarUrl = '',
    this.status = GroupCallMemberStatus.ringing,
  });

  GroupCallMember copyWith({GroupCallMemberStatus? status}) => GroupCallMember(
        userId: userId,
        username: username,
        fullName: fullName,
        avatarUrl: avatarUrl,
        status: status ?? this.status,
      );
}

// ────────────────────────────────────────────────────────────────────────────

/// Один peer в group-call'е. Per-peer renderer + connection state.
class GroupCallPeer {
  final String userId;
  String username;
  final RTCVideoRenderer renderer = RTCVideoRenderer();
  RTCPeerConnection? pc;
  MediaStream? remoteStream;
  final List<RTCIceCandidate> pendingIce = [];
  GroupCallPeer(this.userId, {this.username = ''});
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
  /// Момент перехода в active — для таймера длительности звонка (#M-3).
  final DateTime? connectedAt;

  const GroupCallSession({
    required this.chatId,
    required this.chatTitle,
    required this.kind,
    required this.isOutgoing,
    required this.status,
    required this.inviterId,
    required this.inviterUsername,
    this.connectedAt,
  });

  GroupCallSession copyWith({GroupCallStatus? status, DateTime? connectedAt}) =>
      GroupCallSession(
        chatId: chatId,
        chatTitle: chatTitle,
        kind: kind,
        isOutgoing: isOutgoing,
        status: status ?? this.status,
        inviterId: inviterId,
        inviterUsername: inviterUsername,
        connectedAt: connectedAt ?? this.connectedAt,
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
  final ValueNotifier<bool> isSpeakerOn = ValueNotifier(false);
  /// #5: последняя ошибка — показывается снэкбаром через CallListener.
  final ValueNotifier<String?> lastError = ValueNotifier(null);
  /// Список участников чата, которым отправлен инвайт, с их статусами.
  final ValueNotifier<List<GroupCallMember>> invitedMembers = ValueNotifier([]);
  /// PiP флаг — аналог CallService.minimized. true = GroupCallScreen свёрнут,
  /// CallListener рендерит floating mini overlay. Tap → set false → re-open.
  final ValueNotifier<bool> minimized = ValueNotifier(false);

  CallSender? _sender;
  final AudioPlayer _ringPlayer = AudioPlayer();
  Timer? _ringTimer;
  // #10: таймаут исходящего группового звонка — 60 сек без join → hangup.
  Timer? _inviteTimer;
  // #13: защита от concurrent _ensurePeer() для одного userId.
  final Map<String, Completer<GroupCallPeer>> _peerCreating = {};

  void setSender(CallSender s) {
    _sender = s;
  }

  /// Передаёт список участников чата (без себя) при старте звонка.
  void setInvitedMembers(List<GroupCallMember> members) {
    invitedMembers.value = List<GroupCallMember>.of(members);
  }

  void _updateMemberStatus(String userId, GroupCallMemberStatus status,
      {String username = ''}) {
    final list = List<GroupCallMember>.of(invitedMembers.value);
    final idx = list.indexWhere((m) => m.userId == userId);
    if (idx < 0) {
      // Незнакомый участник присоединился — добавляем
      if (status == GroupCallMemberStatus.joined) {
        list.add(GroupCallMember(userId: userId, username: username, status: status));
        invitedMembers.value = list;
      }
      return;
    }
    list[idx] = list[idx].copyWith(status: status);
    invitedMembers.value = list;
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
    minimized.value = false;
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
    // #H-10: cleanup мог запуститься пока ждали getUserMedia — не отправляем
    // invite и не запускаем foreground service в мёртвую сессию.
    if (session.value == null) return;
    unawaited(CallBgService.instance.startForeground(
      title: 'Групповой звонок',
      body: chatTitle,
    ));
    _startRingback();
    // #10: 60 секунд без единого join → автоматический hangup.
    _inviteTimer?.cancel();
    _inviteTimer = Timer(const Duration(seconds: 60), () {
      if (session.value?.status == GroupCallStatus.outgoingInviting) {
        hangup();
      }
    });
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
    // #M-3: фиксируем момент перехода в active — без connectedAt таймер/лейбл
    // длительности у принявшего звонок никогда не запускается.
    session.value = s.copyWith(
      status: GroupCallStatus.active,
      connectedAt: DateTime.now(),
    );
    unawaited(CallBgService.instance.configureForCall());
    await _initLocalStream();
    // #H-1: после await getUserMedia сессия могла быть очищена (отказ в
    // разрешениях → _cleanup). Без проверки отправляется call.group.join
    // в мёртвую сессию → все участники создают PC в никуда.
    if (session.value == null) return;
    _send('call.group.join', {'chat_id': s.chatId});
  }

  Future<void> declineGroupCall() async {
    final s = session.value;
    if (s == null) return;
    _stopRing();
    // #H-4: атомарно обнуляем сессию — повторный тап не пройдёт guard.
    session.value = null;
    _send('call.group.leave', {'chat_id': s.chatId});
    await _cleanup();
  }

  // ── Hangup ──

  Future<void> hangup() async {
    final s = session.value;
    if (s == null) return;
    _stopRing();
    // #H-4: атомарно обнуляем — двойной тап не отправит второй leave.
    session.value = null;
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

  Future<void> switchCamera() async {
    final tracks = localStream.value?.getVideoTracks() ?? const [];
    if (tracks.isEmpty) return;
    try {
      await Helper.switchCamera(tracks.first);
    } catch (e) {
      appLog.warn('[GroupCallService] switchCamera failed', e);
    }
  }

  Future<void> toggleSpeaker() async {
    final next = !isSpeakerOn.value;
    try {
      await Helper.setSpeakerphoneOn(next);
      isSpeakerOn.value = next;
    } catch (e) {
      appLog.warn('[GroupCallService] toggleSpeaker failed', e);
    }
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
      // Уже в групповом звонке — silently игнорируем.
      return;
    }
    // #H-11: если активен 1-на-1 звонок (CallService), тоже игнорируем.
    // Без этого создаётся параллельная group-сессия, и call_listener начинает
    // маршрутизировать call.offer/answer/ice в GroupCallService вместо
    // CallService → 1-на-1 звонок ломается (ICE/SDP идут не туда).
    final oneOnOneSession = CallService.instance.session.value;
    if (oneOnOneSession != null &&
        oneOnOneSession.status != CallStatus.ended &&
        oneOnOneSession.status != CallStatus.idle) {
      return;
    }
    final chatId = p['chat_id']?.toString() ?? '';
    final from = p['from_user_id']?.toString() ?? '';
    final kindStr = p['kind']?.toString();
    final kind = kindStr == 'voice' ? CallKind.voice : CallKind.video;
    if (chatId.isEmpty || from.isEmpty) return;
    final chatTitle = p['chat_title']?.toString() ?? 'Групповой звонок';
    final inviterUsername = p['from_username']?.toString() ?? '';
    session.value = GroupCallSession(
      chatId: chatId,
      chatTitle: chatTitle,
      kind: kind,
      isOutgoing: false,
      status: GroupCallStatus.incomingRinging,
      inviterId: from,
      inviterUsername: inviterUsername,
    );
    unawaited(CallBgService.instance.startForeground(
      title: 'Входящий групповой звонок',
      body: inviterUsername.isNotEmpty ? inviterUsername : chatTitle,
    ));
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
      // #10: кто-то вошёл — отменяем invite-timeout.
      _inviteTimer?.cancel();
      _inviteTimer = null;
      // #M-3: фиксируем момент первого join для таймера длительности.
      session.value = s.copyWith(
        status: GroupCallStatus.active,
        connectedAt: DateTime.now(),
      );
    }
    // Получаем (или создаём) peer + connection + отправляем offer.
    final fromUsername = p['from_username']?.toString() ?? '';
    _updateMemberStatus(from, GroupCallMemberStatus.joined, username: fromUsername);
    final GroupCallPeer peer;
    try {
      peer = await _ensurePeer(from, username: fromUsername);
    } on StateError {
      return; // #H-3: сессия завершилась пока создавался PC
    } catch (e, st) {
      appLog.error('[GroupCallService] _handleMemberJoined: ensurePeer failed', e, st);
      return;
    }
    if (session.value == null) return; // #H-3: проверяем после await
    await _createAndSendOffer(peer);
  }

  Future<void> _handleMemberLeft(Map<String, dynamic> p) async {
    final from = p['from_user_id']?.toString() ?? '';
    if (from.isEmpty) return;
    // #C-2: запоминаем до удаления — был ли peer реально в звонке.
    // call.group.leave = "отклонил приглашение" ИЛИ "вышел из активного".
    // Если отклонил — он никогда не попадал в peers → wasActive=false →
    // не завершаем звонок, другие участники могут ещё присоединиться.
    final wasActive = peers.value.containsKey(from);
    await _removePeer(from);
    if (!wasActive) {
      _updateMemberStatus(from, GroupCallMemberStatus.declined);
    }
    if (wasActive && peers.value.isEmpty && session.value != null) {
      await _cleanup();
    }
  }

  /// Per-peer signaling: offer/answer/ice. Берём from_user_id чтобы понять
  /// какому peer'у адресовано.
  Future<void> _handlePeerSignaling(
      String type, Map<String, dynamic> p) async {
    final from = p['from_user_id']?.toString() ?? '';
    if (from.isEmpty) return;
    final fromUsername = p['from_username']?.toString() ?? '';
    final GroupCallPeer peer;
    try {
      peer = await _ensurePeer(from, username: fromUsername);
    } on StateError {
      return; // #H-3/#H-8: сессия завершилась пока создавался PC
    } catch (e, st) {
      appLog.error('[GroupCallService] _handlePeerSignaling: ensurePeer failed', e, st);
      return;
    }
    // #H-8: проверяем после любого await — сессия могла завершиться.
    if (session.value == null) return;
    final pc = peer.pc;
    if (pc == null) return;
    // #14: все signaling-операции в try/catch — невалидный SDP не должен
    // крашить всю WS-обработку.
    if (type == 'call.offer') {
      final sdp = p['sdp']?.toString() ?? '';
      final t = p['type']?.toString() ?? 'offer';
      try {
        await pc.setRemoteDescription(RTCSessionDescription(sdp, t));
        for (final cand in peer.pendingIce) {
          await pc.addCandidate(cand);
        }
        peer.pendingIce.clear();
        final answer = await pc.createAnswer({});
        await pc.setLocalDescription(answer);
        _send('call.answer', {
          'to_user_id': from,
          'sdp': answer.sdp,
          'type': answer.type,
        });
      } catch (e, st) {
        appLog.error('[GroupCallService] handle offer from $from failed', e, st);
      }
    } else if (type == 'call.answer') {
      final sdp = p['sdp']?.toString() ?? '';
      final t = p['type']?.toString() ?? 'answer';
      try {
        await pc.setRemoteDescription(RTCSessionDescription(sdp, t));
        for (final cand in peer.pendingIce) {
          await pc.addCandidate(cand);
        }
        peer.pendingIce.clear();
      } catch (e, st) {
        appLog.error('[GroupCallService] handle answer from $from failed', e, st);
      }
    } else if (type == 'call.ice') {
      final cand = RTCIceCandidate(
        p['candidate']?.toString() ?? '',
        p['sdp_mid']?.toString(),
        (p['sdp_m_line_index'] as num?)?.toInt(),
      );
      try {
        if ((await pc.getRemoteDescription()) == null) {
          peer.pendingIce.add(cand);
          return;
        }
        await pc.addCandidate(cand);
      } catch (e) {
        appLog.warn('[GroupCall] addCandidate failed', e);
      }
    }
  }

  Future<GroupCallPeer> _ensurePeer(String userId, {String username = ''}) async {
    final existing = peers.value[userId];
    if (existing != null && existing.pc != null) {
      if (username.isNotEmpty && existing.username.isEmpty) {
        existing.username = username;
        peers.value = {...peers.value}; // #H-2: нотифицируем для ребилда UI
      }
      return existing;
    }
    // #13: если другой concurrent вызов уже создаёт PC для этого userId —
    // ждём его Completer вместо создания второго PC на того же peer'а.
    final inProgress = _peerCreating[userId];
    if (inProgress != null) {
      return inProgress.future;
    }
    final completer = Completer<GroupCallPeer>();
    _peerCreating[userId] = completer;
    // Свежесозданный peer: его initialized renderer надо освободить, если PC
    // не достроился (abort/исключение), иначе нативный renderer утечёт.
    final peer = existing ?? GroupCallPeer(userId, username: username);
    final isNewPeer = existing == null;
    try {
      await peer.renderer.initialize();
      final pc = await createPeerConnection({
        'iceServers': AppConfig.iceServers,
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
      // #H-3: если cleanup прошёл пока создавали PC — закрываем его и не
      // добавляем в карту. Без этой проверки мёртвый peer попадает обратно
      // в очищенную peers.value — утечка нативного PeerConnection.
      if (session.value == null) {
        try { await pc.close(); } catch (_) {}
        // peer не попал в карту — его initialized renderer надо освободить.
        if (isNewPeer) {
          try { peer.renderer.srcObject = null; await peer.renderer.dispose(); } catch (_) {}
        }
        final err = StateError('GroupCall session ended during peer creation');
        completer.completeError(err);
        throw err;
      }
      peer.pc = pc;
      peers.value = {...peers.value, userId: peer};
      completer.complete(peer);
      return peer;
    } catch (e, st) {
      appLog.error('[GroupCallService] _ensurePeer failed for $userId', e, st);
      // peer не добавлен в peers.value — initialized renderer надо освободить.
      if (isNewPeer) {
        try { peer.renderer.srcObject = null; await peer.renderer.dispose(); } catch (_) {}
      }
      completer.completeError(e, st);
      rethrow;
    } finally {
      _peerCreating.remove(userId);
    }
  }

  Future<void> _createAndSendOffer(GroupCallPeer peer) async {
    final pc = peer.pc;
    if (pc == null) return;
    try {
      final offer = await pc.createOffer({});
      await pc.setLocalDescription(offer);
      _send('call.offer', {
        'to_user_id': peer.userId,
        'sdp': offer.sdp,
        'type': offer.type,
      });
    } catch (e, st) {
      appLog.error('[GroupCallService] createOffer for ${peer.userId} failed', e, st);
    }
  }

  Future<void> _removePeer(String userId) async {
    final peer = peers.value[userId];
    if (peer == null) return;
    try {
      await peer.pc?.close();
    } catch (e) {
      appLog.warn('[GroupCall] peer.pc.close failed', e);
    }
    try {
      peer.renderer.srcObject = null;
      await peer.renderer.dispose();
    } catch (e) {
      appLog.warn('[GroupCall] peer.renderer.dispose failed', e);
    }
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
      // #H-9: пока ждали getUserMedia (диалог разрешений), cleanup мог
      // запуститься (caller сбросил, или declineGroupCall). Без этого
      // полученный стрим утекает — камера/микрофон остаются открытыми.
      if (session.value == null) {
        for (final t in media.getTracks()) {
          try { await t.stop(); } catch (_) {}
        }
        try { await media.dispose(); } catch (_) {}
        return;
      }
      localStream.value = media;
    } catch (e, st) {
      appLog.error('[GroupCallService] getUserMedia failed', e, st);
      // #5: показываем ошибку пользователю через CallListener.
      lastError.value = 'Нет доступа к камере / микрофону. Проверьте разрешения.';
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

  Future<void> _ensureAudioSession() async {
    await CallBgService.instance.configureForRingtone();
  }

  Future<void> _playRingAsset(String asset) async {
    try {
      await _ensureAudioSession();
      await _ringPlayer.stop();
      await _ringPlayer.setAsset(asset);
      await _ringPlayer.setLoopMode(LoopMode.one);
      await _ringPlayer.setVolume(0.7);
      await _ringPlayer.play();
    } catch (e, st) {
      appLog.error('[GroupCall] ring asset $asset failed', e, st);
    }
  }

  void _stopRing() {
    _ringTimer?.cancel();
    _ringTimer = null;
    unawaited(_ringPlayer.stop());
  }

  Future<void> _cleanup() async {
    _stopRing();
    unawaited(CallBgService.instance.stopForeground());
    unawaited(CallBgService.instance.clearCallPip());
    // #10: отменяем invite-timeout.
    _inviteTimer?.cancel();
    _inviteTimer = null;
    // #13: сбрасываем pending creators (сессия всё равно мертва).
    _peerCreating.clear();
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
        } catch (e) {
          appLog.warn('[GroupCall] track.stop failed', e);
        }
      }
      try {
        await ls.dispose();
      } catch (e) {
        appLog.warn('[GroupCall] localStream.dispose failed', e);
      }
    }
    localStream.value = null;
    isMuted.value = false;
    isCameraOff.value = false;
    if (isSpeakerOn.value) {
      try { await Helper.setSpeakerphoneOn(false); } catch (_) {}
    }
    isSpeakerOn.value = false;
    invitedMembers.value = [];
    // #L-2: принудительно очищаем — страховка если concurrent _ensurePeer
    // добавил peer между итерациями выше.
    peers.value = {};
    session.value = null;
    minimized.value = false;
  }

  void _send(String type, Map<String, dynamic> payload) {
    // #4: guard — без sender все сообщения пропадут молча.
    if (_sender == null) {
      appLog.warn('[GroupCallService] _send: sender not set, dropping $type');
      return;
    }
    _sender!.call(type, payload);
  }
}
