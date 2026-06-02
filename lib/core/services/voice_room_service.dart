import 'package:flutter/foundation.dart';

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

  void join(String roomId, String roomName) {
    activeRoomId.value = roomId;
    activeRoomName.value = roomName;
  }

  void leave() {
    activeRoomId.value = null;
    activeRoomName.value = '';
  }
}
