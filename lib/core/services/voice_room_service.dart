import 'dart:async';

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

  void join(String roomId, String roomName) {
    activeRoomId.value = roomId;
    activeRoomName.value = roomName;
    minimized.value = false; // только что вошли — экран открыт
    unawaited(CallBgService.instance.configureForCall());
    unawaited(CallBgService.instance.startForeground(
      title: 'Голосовой канал',
      body: roomName,
    ));
  }

  void leave() {
    activeRoomId.value = null;
    activeRoomName.value = '';
    minimized.value = false; // сброс
    unawaited(CallBgService.instance.stopForeground());
  }
}
