import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'call_bg_service.dart';

/// Singleton — отслеживает активный голосовой канал комнаты.
/// Заполняется в RoomScreen._joinVoice / _leaveVoice / _leaveRoom / _closeRoom.
/// Читается в CallListener для отображения floating overlay.
class VoiceRoomService {
  VoiceRoomService._();
  static final VoiceRoomService instance = VoiceRoomService._();

  /// ID комнаты, в чьём голосовом канале сейчас находимся. null = не в голосовом.
  final ValueNotifier<String?> activeRoomId = ValueNotifier(null);

  /// Название комнаты — для display в overlay.
  final ValueNotifier<String> activeRoomName = ValueNotifier('');

  /// true = RoomScreen закрыт, mini-overlay виден.
  /// false = RoomScreen открыт, mini-overlay скрыт.
  /// Аналогично CallService.minimized / GroupCallService.minimized.
  final ValueNotifier<bool> minimized = ValueNotifier(false);

  /// Момент входа в голосовой канал — для корректного таймера в нативном PiP.
  final ValueNotifier<DateTime?> joinedAt = ValueNotifier(null);

  void join(String roomId, String roomName) {
    activeRoomId.value = roomId;
    activeRoomName.value = roomName;
    minimized.value = false; // только что вошли — экран открыт
    joinedAt.value = DateTime.now();
    unawaited(CallBgService.instance.configureForCall());
    unawaited(CallBgService.instance.startForeground(
      title: 'Голосовой канал',
      body: roomName,
    ));
    // Сообщаем Android: голосовой канал активен → onUserLeaveHint → auto PiP.
    unawaited(CallBgService.instance.setCallActive(true));
    // iOS: подготовить нативный PiP — зарегистрировать lifecycle-наблюдатели.
    if (Platform.isIOS) {
      unawaited(CallBgService.instance.prepareCallPip(
        username: roomName,
        kind: 'voice',
      ));
    }
  }

  void leave() {
    // iOS: очистить PiP до сброса состояния — снять наблюдатели.
    if (Platform.isIOS) {
      unawaited(CallBgService.instance.clearCallPip());
    }
    activeRoomId.value = null;
    activeRoomName.value = '';
    minimized.value = false; // сброс
    joinedAt.value = null;
    unawaited(CallBgService.instance.stopForeground());
    unawaited(CallBgService.instance.setCallActive(false));
  }
}
