import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/models/room.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/room_provider.dart';
import '../../core/providers/realtime_provider.dart';
import '../../core/services/call_bg_service.dart';
import '../../core/services/voice_room_service.dart';
import 'call_screen.dart';
import 'call_service.dart';
import 'group_call_screen.dart';
import 'group_call_service.dart';
import '../live/live_viewer_screen.dart';

/// Обёртка над всем app-деревом. Wire'ит CallService в realtime-stream,
/// open'ает CallScreen modal'ом когда появляется активная сессия, и (C-6)
/// рендерит floating mini-call overlay когда CallService.minimized == true.
///
/// Должен сидеть выше навигатора (в `MaterialApp.builder`).
class CallListener extends ConsumerStatefulWidget {
  final Widget child;
  /// Ключ GoRouter'овского корневого Navigator'а. Нужен потому что
  /// CallListener живёт в MaterialApp.builder — его context находится
  /// ВЫШЕ навигатора и Navigator.of(context) не может найти его как предка.
  final GlobalKey<NavigatorState> navigatorKey;
  const CallListener({super.key, required this.child, required this.navigatorKey});

  @override
  ConsumerState<CallListener> createState() => _CallListenerState();
}

class _CallListenerState extends ConsumerState<CallListener> {
  bool _open = false;
  bool _groupOpen = false;
  bool _panelOpen = false;

  static const _pipCh = MethodChannel('seeu/pip');

  @override
  void initState() {
    super.initState();
    CallService.instance.setSender(
      (type, payload) =>
          ref.read(realtimeSenderProvider).send(type, payload),
    );
    GroupCallService.instance.setSender(
      (type, payload) =>
          ref.read(realtimeSenderProvider).send(type, payload),
    );
    // Live streams use LiveKit for media — no WS sender/signaling needed here.
    CallService.instance.session.addListener(_onSession);
    CallService.instance.minimized.addListener(_onMinimized);
    CallService.instance.lastError.addListener(_onCallError);
    GroupCallService.instance.session.addListener(_onGroupSession);
    GroupCallService.instance.minimized.addListener(_onGroupMinimized);
    GroupCallService.instance.lastError.addListener(_onGroupCallError);
    VoiceRoomService.instance.minimized.addListener(_onVoiceRoomMinimized);
    _pipCh.setMethodCallHandler(_onPipMessage);
  }

  @override
  void dispose() {
    CallService.instance.session.removeListener(_onSession);
    CallService.instance.minimized.removeListener(_onMinimized);
    CallService.instance.lastError.removeListener(_onCallError);
    GroupCallService.instance.session.removeListener(_onGroupSession);
    GroupCallService.instance.minimized.removeListener(_onGroupMinimized);
    GroupCallService.instance.lastError.removeListener(_onGroupCallError);
    VoiceRoomService.instance.minimized.removeListener(_onVoiceRoomMinimized);
    super.dispose();
  }

  /// Сообщения от нативного PiP-канала.
  Future<dynamic> _onPipMessage(MethodCall call) async {
    switch (call.method) {
      case 'pipModeChanged':
        // Android: Activity вошла/вышла из PiP-режима.
        CallBgService.instance.pipMode.value = call.arguments as bool? ?? false;
      case 'pipReturn':
        // iOS: пользователь нажал «Развернуть» в нативном PiP.
        unawaited(CallBgService.instance.exitPip());
        if (GroupCallService.instance.session.value != null) {
          GroupCallService.instance.minimized.value = false;
        } else if (CallService.instance.session.value != null) {
          CallService.instance.minimized.value = false;
        } else if (VoiceRoomService.instance.activeRoomId.value != null) {
          // Голосовой канал: minimized=false → _onVoiceRoomMinimized → navigate to room.
          VoiceRoomService.instance.minimized.value = false;
        }
    }
  }

  void _onCallError() {
    final err = CallService.instance.lastError.value;
    if (err == null || err.isEmpty) return;
    CallService.instance.lastError.value = null;
    if (!mounted) return;
    showSeeUSnackBar(context, err, tone: SeeUTone.danger);
  }

  void _onGroupCallError() {
    final err = GroupCallService.instance.lastError.value;
    if (err == null || err.isEmpty) return;
    GroupCallService.instance.lastError.value = null;
    if (!mounted) return;
    showSeeUSnackBar(context, err, tone: SeeUTone.danger);
  }

  void _showLiveBanner(Map<String, dynamic> payload) {
    if (!mounted) return;
    final streamId = payload['stream_id']?.toString() ?? '';
    final username = payload['username']?.toString() ?? '';
    final avatarUrl = payload['avatar_url']?.toString() ?? '';
    final title = payload['title']?.toString() ?? '';
    if (streamId.isEmpty) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        duration: const Duration(seconds: 5),
        content: GestureDetector(
          onTap: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            final nav = widget.navigatorKey.currentState;
            nav?.push(MaterialPageRoute(
              builder: (_) => LiveViewerScreen(streamId: streamId),
            ));
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: SeeUColors.accent.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: SeeUColors.accent, width: 1.5),
                    color: Colors.grey.shade800,
                  ),
                  child: ClipOval(
                    child: avatarUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: avatarUrl, fit: BoxFit.cover)
                        : const Icon(Icons.person, color: Colors.white54, size: 18),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '@$username начал(а) эфир',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                      if (title.isNotEmpty)
                        Text(title,
                            style: const TextStyle(
                                color: Colors.white60, fontSize: 12),
                            overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: SeeUColors.live,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('LIVE',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onGroupSession() {
    final s = GroupCallService.instance.session.value;
    if (s == null || _groupOpen) return;
    final nav = widget.navigatorKey.currentState;
    if (nav == null) return;
    _groupOpen = true;
    nav.push(
      PageRouteBuilder(
        opaque: true,
        fullscreenDialog: true,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, __, ___) => const GroupCallScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    ).then((_) {
      _groupOpen = false;
    });
  }

  void _onSession() {
    final s = CallService.instance.session.value;
    if (s != null && !_open) {
      _pushCallScreen();
    }
  }

  /// C-6: когда минимизация снимается (юзер тапнул mini) → push CallScreen обратно.
  void _onMinimized() {
    final isMin = CallService.instance.minimized.value;
    if (!isMin && CallService.instance.session.value != null && !_open) {
      _pushCallScreen();
    }
  }

  /// Аналог _onMinimized для группового звонка.
  void _onGroupMinimized() {
    final isMin = GroupCallService.instance.minimized.value;
    if (!isMin && GroupCallService.instance.session.value != null && !_groupOpen) {
      _pushGroupCallScreen();
    }
  }

  /// Пользователь тапнул по mini-overlay голосового канала → показываем Voice Panel.
  void _onVoiceRoomMinimized() {
    final isMin = VoiceRoomService.instance.minimized.value;
    final roomId = VoiceRoomService.instance.activeRoomId.value;
    // Не открывать панель если: overlay свёрнут (isMin=true),
    // нет активной комнаты, панель уже открыта, или RoomScreen уже открыт.
    if (isMin || roomId == null || _panelOpen) return;
    if (VoiceRoomService.instance.currentOpenRoomId != null) return;
    _showVoicePanel(roomId);
  }

  void _showVoicePanel(String roomId) {
    final nav = widget.navigatorKey.currentState;
    final ctx = widget.navigatorKey.currentContext;
    if (nav == null || ctx == null) return;
    _panelOpen = true;
    nav.push(
      PageRouteBuilder(
        opaque: true,
        fullscreenDialog: true,
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, __, ___) => _VoiceRoomFullPanel(
          roomId: roomId,
          roomName: VoiceRoomService.instance.activeRoomName.value,
          onViewChat: () => ctx.push('/room/$roomId'),
        ),
        transitionsBuilder: (_, anim, __, child) => SlideTransition(
          position: Tween(begin: const Offset(0, 1), end: Offset.zero)
              .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    ).then((_) {
      _panelOpen = false;
    });
  }

  void _pushCallScreen() {
    final nav = widget.navigatorKey.currentState;
    if (nav == null) return;
    _open = true;
    nav.push(
      PageRouteBuilder(
        opaque: true,
        fullscreenDialog: true,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, __, ___) => const CallScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    ).then((_) {
      _open = false;
    });
  }

  void _pushGroupCallScreen() {
    final nav = widget.navigatorKey.currentState;
    if (nav == null) return;
    _groupOpen = true;
    nav.push(
      PageRouteBuilder(
        opaque: true,
        fullscreenDialog: true,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, __, ___) => const GroupCallScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    ).then((_) {
      _groupOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<RealtimeEvent>>(
      realtimeEventsProvider,
      (_, next) {
        next.whenData((evt) {
          // Live stream events (media goes through LiveKit; here we only show
          // the "someone you follow went live" banner — list updates live in
          // live_streams_provider).
          if (evt.type.startsWith('live_stream.')) {
            if (evt.type == 'live_stream.started') {
              final payload = evt.payload is Map
                  ? Map<String, dynamic>.from(evt.payload as Map)
                  : <String, dynamic>{};
              _showLiveBanner(payload);
            }
            return;
          }
          if (!evt.type.startsWith('call.')) return;
          final isGroupEvent = evt.type.startsWith('call.group.');
          if (isGroupEvent) {
            GroupCallService.instance.onRealtimeEvent(evt);
          } else {
            if (GroupCallService.instance.session.value != null) {
              // #32: входящий 1-1 звонок во время активного group call → авто-отклонить.
              if (evt.type == 'call.invite') {
                final payload = evt.payload;
                if (payload is Map) {
                  final from = payload['from_user_id']?.toString() ?? '';
                  if (from.isNotEmpty) {
                    ref.read(realtimeSenderProvider).send(
                      'call.decline',
                      {'to_user_id': from},
                    );
                  }
                }
              } else {
                GroupCallService.instance.onRealtimeEvent(evt);
              }
            } else {
              CallService.instance.onRealtimeEvent(evt);
            }
          }
        });
      },
    );

    return Stack(
      children: [
        widget.child,

        // ── 1-на-1 звонок mini overlay ─────────────────────────────────────
        // iOS: нативный AVPictureInPicture — Flutter overlay не нужен.
        // Android: Flutter overlay (Activity PiP не поддерживает произвольный UI).
        if (!Platform.isIOS)
          ValueListenableBuilder<CallSession?>(
            valueListenable: CallService.instance.session,
            builder: (_, sess, __) {
              if (sess == null) return const SizedBox.shrink();
              return ValueListenableBuilder<bool>(
                valueListenable: CallService.instance.minimized,
                builder: (_, isMin, __) {
                  if (!isMin) return const SizedBox.shrink();
                  return const _MiniCallOverlay();
                },
              );
            },
          ),

        // ── Групповой звонок mini overlay ──────────────────────────────────
        if (!Platform.isIOS)
          ValueListenableBuilder<GroupCallSession?>(
            valueListenable: GroupCallService.instance.session,
            builder: (_, groupSess, __) {
              if (groupSess == null) return const SizedBox.shrink();
              return ValueListenableBuilder<bool>(
                valueListenable: GroupCallService.instance.minimized,
                builder: (_, isMin, __) {
                  if (!isMin) return const SizedBox.shrink();
                  return const _MiniGroupCallOverlay();
                },
              );
            },
          ),

        // ── Голосовой канал комнаты mini overlay ───────────────────────────
        // iOS: нативный AVPictureInPicture — Flutter overlay не нужен.
        if (!Platform.isIOS)
        ValueListenableBuilder<String?>(
          valueListenable: VoiceRoomService.instance.activeRoomId,
          builder: (_, roomId, __) {
            if (roomId == null) return const SizedBox.shrink();
            return ValueListenableBuilder<bool>(
              valueListenable: VoiceRoomService.instance.minimized,
              builder: (_, isMin, __) {
                if (!isMin) return const SizedBox.shrink();
                return ValueListenableBuilder<String>(
                  valueListenable: VoiceRoomService.instance.activeRoomName,
                  builder: (_, roomName, __) {
                    return _MiniVoiceRoomOverlay(
                      roomId: roomId,
                      roomName: roomName,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        VoiceRoomService.instance.minimized.value = false;
                      },
                      onLeave: () async {
                        VoiceRoomService.instance.leave();
                        try {
                          await ref
                              .read(apiClientProvider)
                              .delete(ApiEndpoints.roomVoice(roomId));
                        } catch (_) {}
                      },
                    );
                  },
                );
              },
            );
          },
        ),
      ],
    );
  }
}

// ─── 1-на-1 Mini Call Overlay ─────────────────────────────────────────────────

/// Floating PiP для 1-на-1 звонка (C-6). StatefulWidget с таймером
/// длительности и динамическим статусом.
class _MiniCallOverlay extends StatefulWidget {
  const _MiniCallOverlay();

  @override
  State<_MiniCallOverlay> createState() => _MiniCallOverlayState();
}

class _MiniCallOverlayState extends State<_MiniCallOverlay> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    CallService.instance.session.addListener(_onSession);
    _syncTicker();
  }

  void _onSession() {
    _syncTicker();
    if (mounted) setState(() {});
  }

  void _syncTicker() {
    final s = CallService.instance.session.value;
    if (s != null && s.status == CallStatus.connected) {
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    CallService.instance.session.removeListener(_onSession);
    super.dispose();
  }

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  String _miniStatus(CallSession s) {
    switch (s.status) {
      case CallStatus.outgoingRinging:
        if (s.peerResponseSeen == false) return 'Не отвечает…';
        return 'Соединение…';
      case CallStatus.incomingRinging:
        return 'Входящий…';
      case CallStatus.connecting:
        return 'Соединение…';
      case CallStatus.connected:
        final at = s.connectedAt;
        if (at != null) return _fmtDuration(DateTime.now().difference(at));
        return 'В разговоре';
      case CallStatus.reconnecting:
        return 'Восст. связи…';
      case CallStatus.ended:
      case CallStatus.idle:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final sess = CallService.instance.session.value;
    if (sess == null) return const SizedBox.shrink();
    final media = MediaQuery.of(context);
    final isVoice = sess.kind == CallKind.voice;
    final isConnected = sess.status == CallStatus.connected;

    return Positioned(
      right: 12,
      bottom: media.padding.bottom + 80,
      child: Material(
        elevation: 12,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            CallService.instance.minimized.value = false;
          },
          child: Container(
            width: 120,
            height: 160,
            decoration: const BoxDecoration(
              gradient: SeeUGradients.heroOrange,
            ),
            child: Stack(
              children: [
                // Фон — аватар пира.
                if (sess.peerAvatarUrl.isNotEmpty)
                  Positioned.fill(
                    child: ColorFiltered(
                      colorFilter: ColorFilter.mode(
                        Colors.black.withValues(alpha: 0.28),
                        BlendMode.darken,
                      ),
                      child: CachedNetworkImage(
                        imageUrl: sess.peerAvatarUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),

                // Тип звонка + имя (сверху).
                Positioned(
                  top: 8,
                  left: 8,
                  right: 8,
                  child: Row(
                    children: [
                      Icon(
                        isVoice
                            ? PhosphorIconsFill.phone
                            : PhosphorIconsFill.videoCamera,
                        size: 11,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '@${sess.peerUsername}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            shadows: [
                              Shadow(color: Colors.black54, blurRadius: 2),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                // Статус / таймер (по центру снизу над кнопкой).
                Positioned(
                  bottom: 60,
                  left: 6,
                  right: 6,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isConnected)
                        Container(
                          width: 5,
                          height: 5,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: const BoxDecoration(
                            color: Colors.greenAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      Text(
                        _miniStatus(sess),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          shadows: const [
                            Shadow(color: Colors.black54, blurRadius: 2),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Кнопка завершить (снизу справа).
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      CallService.instance.hangup();
                    },
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: SeeUColors.error,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: SeeUColors.error.withValues(alpha: 0.5),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        PhosphorIconsFill.phoneSlash,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Групповой звонок Mini Overlay ───────────────────────────────────────────

class _MiniGroupCallOverlay extends StatefulWidget {
  const _MiniGroupCallOverlay();

  @override
  State<_MiniGroupCallOverlay> createState() => _MiniGroupCallOverlayState();
}

class _MiniGroupCallOverlayState extends State<_MiniGroupCallOverlay> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    GroupCallService.instance.session.addListener(_onSession);
    GroupCallService.instance.peers.addListener(_onSession);
    _syncTicker();
  }

  void _onSession() {
    _syncTicker();
    if (mounted) setState(() {});
  }

  void _syncTicker() {
    final s = GroupCallService.instance.session.value;
    if (s != null &&
        s.status == GroupCallStatus.active &&
        s.connectedAt != null) {
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    GroupCallService.instance.session.removeListener(_onSession);
    GroupCallService.instance.peers.removeListener(_onSession);
    super.dispose();
  }

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final sess = GroupCallService.instance.session.value;
    if (sess == null) return const SizedBox.shrink();
    final media = MediaQuery.of(context);
    final isVoice = sess.kind == CallKind.voice;
    final peers = GroupCallService.instance.peers.value;

    String subtitle;
    if (sess.status == GroupCallStatus.outgoingInviting) {
      subtitle = 'Вызываем участников…';
    } else if (sess.connectedAt != null) {
      final dur = DateTime.now().difference(sess.connectedAt!);
      final count = peers.length + 1;
      subtitle = '${_fmtDuration(dur)} · $count участн.';
    } else {
      subtitle = isVoice ? 'Голосовой' : 'Видеозвонок';
    }

    return Positioned(
      right: 12,
      bottom: media.padding.bottom + 80,
      child: Material(
        elevation: 12,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            GroupCallService.instance.minimized.value = false;
          },
          child: Container(
            width: 190,
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C2E),
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // Иконка
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: SeeUColors.accent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isVoice
                        ? PhosphorIconsFill.phone
                        : PhosphorIconsFill.videoCamera,
                    color: SeeUColors.accent,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 8),
                // Название + статус
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        sess.chatTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Завершить
                GestureDetector(
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    GroupCallService.instance.hangup();
                  },
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: SeeUColors.error,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      PhosphorIconsFill.phoneSlash,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Голосовой канал комнаты Mini Overlay ────────────────────────────────────

class _MiniVoiceRoomOverlay extends StatelessWidget {
  final String roomId;
  final String roomName;
  final VoidCallback onTap;
  final Future<void> Function() onLeave;

  const _MiniVoiceRoomOverlay({
    required this.roomId,
    required this.roomName,
    required this.onTap,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Positioned(
      left: 12,
      bottom: media.padding.bottom + 80,
      child: GestureDetector(
        onTap: onTap,
        child: Material(
          elevation: 12,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: SeeUColors.accent.withValues(alpha: 0.18),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Иконка микрофона
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: SeeUColors.accent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  PhosphorIconsBold.microphone,
                  color: SeeUColors.accent,
                  size: 14,
                ),
              ),
              const SizedBox(width: 8),
              // Название комнаты
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      roomName,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A1A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Голосовой канал',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.black.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Кнопка покинуть
              GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  onLeave();
                },
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: SeeUColors.error,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    PhosphorIconsBold.phoneSlash,
                    color: Colors.white,
                    size: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

// ─── Голосовой канал — полноэкранная панель (Discord-стиль) ──────────────────

class _VoiceRoomFullPanel extends ConsumerStatefulWidget {
  final String roomId;
  final String roomName;
  final VoidCallback onViewChat;

  const _VoiceRoomFullPanel({
    required this.roomId,
    required this.roomName,
    required this.onViewChat,
  });

  @override
  ConsumerState<_VoiceRoomFullPanel> createState() => _VoiceRoomFullPanelState();
}

class _VoiceRoomFullPanelState extends ConsumerState<_VoiceRoomFullPanel> {
  Timer? _tick;
  bool _suppressMinimize = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    // Показываем mini-overlay если всё ещё в голосовом канале,
    // кроме случаев когда уходим к Room Chat или покидаем канал.
    if (!_suppressMinimize &&
        VoiceRoomService.instance.activeRoomId.value == widget.roomId) {
      VoiceRoomService.instance.minimized.value = true;
    }
    super.dispose();
  }

  Future<void> _toggleMute(Room room) async {
    HapticFeedback.selectionClick();
    final myId = ref.read(authProvider).user?.id ?? '';
    final newMuted = !room.isMuted;
    ref.read(roomDetailProvider(widget.roomId).notifier).setMyMute(myId, newMuted);
    try {
      await ref.read(apiClientProvider).patch(ApiEndpoints.muteRoom(room.id));
    } catch (_) {
      // Откат оптимистичного обновления
      ref.read(roomDetailProvider(widget.roomId).notifier).setMyMute(myId, room.isMuted);
    }
  }

  Future<void> _leaveVoice() async {
    HapticFeedback.mediumImpact();
    final myId = ref.read(authProvider).user?.id ?? '';
    await ref.read(roomDetailProvider(widget.roomId).notifier).leaveVoice(myId);
    VoiceRoomService.instance.leave();
    _suppressMinimize = true;
    if (mounted) Navigator.of(context).pop();
  }

  void _viewChat() {
    _suppressMinimize = true;
    Navigator.of(context).pop();
    // microtask чтобы pop завершился до push
    Future.microtask(widget.onViewChat);
  }

  String _fmtDuration() {
    final joined = VoiceRoomService.instance.joinedAt.value;
    if (joined == null) return '0:00';
    final d = DateTime.now().difference(joined);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final roomState = ref.watch(roomDetailProvider(widget.roomId));
    final room = roomState.room;
    final myId = ref.read(authProvider).user?.id ?? '';
    final voiceParticipants = room?.voiceParticipants ?? [];
    final isMuted = room?.isMuted ?? false;
    final inVoice = room?.isInVoice ?? false;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      body: SafeArea(
        child: Column(
          children: [
            // ── Шапка ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                children: [
                  // Свернуть → mini overlay
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        PhosphorIconsBold.caretDown,
                        color: Colors.white54,
                        size: 18,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Column(
                    children: [
                      Text(
                        widget.roomName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Голосовой · ${_fmtDuration()}',
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Перейти в чат комнаты
                  GestureDetector(
                    onTap: _viewChat,
                    child: Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        PhosphorIconsBold.chatCircle,
                        color: Colors.white54,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Участники голосового канала ───────────────────────────
            Expanded(
              child: voiceParticipants.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 72, height: 72,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              PhosphorIconsBold.microphone,
                              color: Colors.white24,
                              size: 32,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Никого нет в эфире',
                            style: TextStyle(color: Colors.white38, fontSize: 15),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Войди в голосовой канал первым',
                            style: TextStyle(color: Colors.white24, fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
                      child: Wrap(
                        spacing: 20,
                        runSpacing: 28,
                        alignment: WrapAlignment.center,
                        children: voiceParticipants.map((p) {
                          final isMe = p.userId == myId;
                          return _VoiceParticipantTile(
                            participant: p,
                            isMe: isMe,
                          );
                        }).toList(),
                      ),
                    ),
            ),

            // ── Панель управления ─────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(32, 22, 32, 30),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (inVoice) ...[
                    _VoiceControlButton(
                      icon: isMuted
                          ? PhosphorIconsBold.microphoneSlash
                          : PhosphorIconsBold.microphone,
                      label: isMuted ? 'Включить' : 'Выключить',
                      bgColor: isMuted
                          ? const Color(0xFF2E2E45)
                          : SeeUColors.success.withValues(alpha: 0.15),
                      iconColor: isMuted ? Colors.white38 : SeeUColors.success,
                      onTap: room != null ? () => _toggleMute(room) : null,
                    ),
                    const SizedBox(width: 24),
                  ],
                  _VoiceControlButton(
                    icon: PhosphorIconsBold.phoneSlash,
                    label: 'Покинуть',
                    bgColor: SeeUColors.error.withValues(alpha: 0.18),
                    iconColor: SeeUColors.error,
                    onTap: inVoice ? _leaveVoice : null,
                    size: 64,
                    iconSize: 24,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceParticipantTile extends StatelessWidget {
  final RoomParticipant participant;
  final bool isMe;

  const _VoiceParticipantTile({required this.participant, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final hasPic =
        participant.avatarUrl != null && participant.avatarUrl!.isNotEmpty;

    return SizedBox(
      width: 72,
      child: Column(
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              Container(
                width: 60, height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: isMe
                      ? Border.all(color: SeeUColors.accent, width: 2.5)
                      : Border.all(
                          color: Colors.white.withValues(alpha: 0.08)),
                  color: const Color(0xFF2A2A40),
                ),
                clipBehavior: Clip.antiAlias,
                child: hasPic
                    ? CachedNetworkImage(
                        imageUrl: participant.avatarUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            _buildInitials(participant.fullName),
                      )
                    : _buildInitials(participant.fullName),
              ),
              if (participant.isMuted)
                Container(
                  width: 20, height: 20,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F0F1A),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  child: const Icon(
                    PhosphorIconsBold.microphoneSlash,
                    size: 10,
                    color: Colors.white38,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            participant.fullName.split(' ').first,
            style: TextStyle(
              color: isMe ? SeeUColors.accent : Colors.white60,
              fontSize: 11,
              fontWeight: isMe ? FontWeight.w700 : FontWeight.w400,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildInitials(String name) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Center(
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _VoiceControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color bgColor;
  final Color iconColor;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;

  const _VoiceControlButton({
    required this.icon,
    required this.label,
    required this.bgColor,
    required this.iconColor,
    this.onTap,
    this.size = 56,
    this.iconSize = 20,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: size, height: size,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: iconSize),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
