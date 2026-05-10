import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/realtime_provider.dart';
import 'call_screen.dart';
import 'call_service.dart';

/// Обёртка над всем app-деревом. Wire'ит CallService в realtime-stream и
/// open'ает CallScreen modal'ом когда появляется активная сессия.
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

  @override
  void initState() {
    super.initState();
    // Sender connecting упрямо тут — он не реактивен и read'нём один раз.
    CallService.instance.setSender(
      (type, payload) =>
          ref.read(realtimeSenderProvider).send(type, payload),
    );
    CallService.instance.session.addListener(_onSession);
  }

  @override
  void dispose() {
    CallService.instance.session.removeListener(_onSession);
    super.dispose();
  }

  void _onSession() {
    final s = CallService.instance.session.value;
    if (s != null && !_open) {
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
  }

  @override
  Widget build(BuildContext context) {
    // Слушаем realtime-stream через ref.listen — корректный pattern для
    // ConsumerStatefulWidget. Каждый call.* event летит в сервис.
    ref.listen<AsyncValue<RealtimeEvent>>(
      realtimeEventsProvider,
      (_, next) {
        next.whenData((evt) {
          if (evt.type.startsWith('call.')) {
            CallService.instance.onRealtimeEvent(evt);
          }
        });
      },
    );
    return widget.child;
  }
}
