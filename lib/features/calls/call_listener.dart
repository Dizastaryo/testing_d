import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import '../../core/providers/realtime_provider.dart';
import 'call_screen.dart';
import 'call_service.dart';
import 'group_call_screen.dart';
import 'group_call_service.dart';

/// Обёртка над всем app-деревом. Wire'ит CallService в realtime-stream,
/// open'ает CallScreen modal'ом когда появляется активная сессия, и (C-6)
/// рендерит floating mini-call overlay когда CallService.minimized == true.
///
/// Должен сидеть выше навигатора (в `MaterialApp.builder`).
class CallListener extends ConsumerStatefulWidget {
  final Widget child;
  const CallListener({super.key, required this.child});

  @override
  ConsumerState<CallListener> createState() => _CallListenerState();
}

class _CallListenerState extends ConsumerState<CallListener> {
  bool _open = false;
  bool _groupOpen = false;

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
    CallService.instance.session.addListener(_onSession);
    CallService.instance.minimized.addListener(_onMinimized);
    GroupCallService.instance.session.addListener(_onGroupSession);
  }

  @override
  void dispose() {
    CallService.instance.session.removeListener(_onSession);
    CallService.instance.minimized.removeListener(_onMinimized);
    GroupCallService.instance.session.removeListener(_onGroupSession);
    super.dispose();
  }

  void _onGroupSession() {
    final s = GroupCallService.instance.session.value;
    if (s != null && !_groupOpen) {
      _groupOpen = true;
      Navigator.of(context, rootNavigator: true).push(
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
  }

  void _onSession() {
    final s = CallService.instance.session.value;
    if (s != null && !_open) {
      _pushCallScreen();
    }
  }

  /// C-6: когда минимизация снимается (юзер тапнул mini) → push CallScreen
  /// обратно. Когда minimized=true, ничего не делаем — CallScreen уже poppedwise
  /// PopScope onPopInvoked, ниже на стеке другие routes.
  void _onMinimized() {
    final isMin = CallService.instance.minimized.value;
    if (!isMin && CallService.instance.session.value != null && !_open) {
      _pushCallScreen();
    }
  }

  void _pushCallScreen() {
    _open = true;
    Navigator.of(context, rootNavigator: true).push(
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

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<RealtimeEvent>>(
      realtimeEventsProvider,
      (_, next) {
        next.whenData((evt) {
          if (!evt.type.startsWith('call.')) return;
          // Group call events идут в GroupCallService; offer/answer/ice —
          // в оба сервиса (фильтр внутри каждого: GroupCallService обрабатывает
          // только когда session != null, иначе fallback в CallService).
          final isGroupEvent = evt.type.startsWith('call.group.');
          if (isGroupEvent) {
            GroupCallService.instance.onRealtimeEvent(evt);
          } else {
            // Peer signaling (offer/answer/ice/invite/accept/decline/end).
            // Если group-session активна — пробуем сначала туда. CallService
            // и GroupCallService совместимы — каждый обработает свои peer ID'шники.
            if (GroupCallService.instance.session.value != null) {
              GroupCallService.instance.onRealtimeEvent(evt);
            } else {
              CallService.instance.onRealtimeEvent(evt);
            }
          }
        });
      },
    );
    // C-6: рендерим mini-call overlay поверх child'а когда minimized=true и
    // есть активная сессия. ValueListenable rebuild только когда меняется.
    return Stack(
      children: [
        widget.child,
        ValueListenableBuilder<CallSession?>(
          valueListenable: CallService.instance.session,
          builder: (_, sess, __) {
            if (sess == null) return const SizedBox.shrink();
            return ValueListenableBuilder<bool>(
              valueListenable: CallService.instance.minimized,
              builder: (_, isMin, __) {
                if (!isMin) return const SizedBox.shrink();
                return _MiniCallOverlay(session: sess);
              },
            );
          },
        ),
      ],
    );
  }
}

/// Floating PiP overlay (C-6). Drag-friendly было бы плюсом, для MVP
/// фиксированная позиция bottom-right. Tap → restore full-screen,
/// hangup-кнопка для быстрого завершения без раскрытия.
class _MiniCallOverlay extends StatelessWidget {
  final CallSession session;
  const _MiniCallOverlay({required this.session});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isVoice = session.kind == CallKind.voice;
    return Positioned(
      right: 12,
      bottom: media.padding.bottom + 80, // выше bottom-nav
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
                // Background: peer avatar full-bleed.
                if (session.peerAvatarUrl.isNotEmpty)
                  Positioned.fill(
                    child: ColorFiltered(
                      colorFilter: ColorFilter.mode(
                        Colors.black.withValues(alpha: 0.25),
                        BlendMode.darken,
                      ),
                      child: CachedNetworkImage(
                        imageUrl: session.peerAvatarUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            const SizedBox.shrink(),
                      ),
                    ),
                  ),
                // Username + kind icon (top).
                Positioned(
                  top: 6,
                  left: 8,
                  right: 8,
                  child: Row(
                    children: [
                      Icon(
                        isVoice
                            ? PhosphorIconsFill.phone
                            : PhosphorIconsFill.videoCamera,
                        size: 12,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '@${session.peerUsername}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            shadows: [
                              Shadow(
                                color: Colors.black54,
                                blurRadius: 2,
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                // Hangup button (bottom-right).
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
