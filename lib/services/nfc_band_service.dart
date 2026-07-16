import 'dart:async';

import 'package:nfc_manager/nfc_manager.dart';

/// Чтение NFC-тега браслета SeeU (Фазы 4/5). Тег отдаёт NDEF URI
/// `https://seeu.app/nfc/<public_id_hex>`. Сервис извлекает public_id_hex —
/// дальше он резолвится в профиль (Фаза 4) или шлётся как касание для пары (Фаза 5).
class NfcBandService {
  static const _uriMarker = '/nfc/';

  /// Доступен ли NFC на устройстве.
  static Future<bool> isAvailable() => NfcManager.instance.isAvailable();

  /// Запускает сессию чтения. Возвращает public_id_hex (lowercase) или null,
  /// если тег не наш / не прочитан / NFC недоступен. Сессия закрывается сама.
  static Future<String?> readBandHash() async {
    if (!await isAvailable()) return null;

    final completer = Completer<String?>();
    await NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        // try/finally: раньше исключение в _extractHash (парсинг NDEF)
        // не давало вызвать stopSession и completer.complete — сессия
        // висела открытой, а caller'ский await зависал навсегда (кнопка
        // «Сканировать» в вечной загрузке).
        String? hash;
        try {
          hash = _extractHash(tag);
        } catch (_) {
          hash = null;
        } finally {
          try {
            await NfcManager.instance.stopSession();
          } catch (_) {}
          if (!completer.isCompleted) completer.complete(hash);
        }
      },
      // Without this, a cancelled/timed-out session (e.g. user dismisses the
      // iOS NFC sheet) never calls onDiscovered, so the completer — and the
      // caller's await — would hang forever instead of surfacing a failure.
      onError: (_) async {
        if (!completer.isCompleted) completer.complete(null);
      },
    );
    return completer.future;
  }

  /// Останавливает активную сессию (например, при закрытии экрана).
  static Future<void> stop() async {
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {}
  }

  static String? _extractHash(NfcTag tag) {
    final ndef = Ndef.from(tag);
    final msg = ndef?.cachedMessage;
    if (msg == null) return null;

    for (final record in msg.records) {
      final uri = _decodeUri(record);
      if (uri == null) continue;
      final idx = uri.indexOf(_uriMarker);
      if (idx < 0) continue;
      final hash = uri.substring(idx + _uriMarker.length).trim().toLowerCase();
      if (hash.isNotEmpty) return hash;
    }
    return null;
  }

  /// Декодирует URI из NDEF-record (well-known 'U' с префиксом-кодом).
  static String? _decodeUri(NdefRecord record) {
    if (record.typeNameFormat != NdefTypeNameFormat.nfcWellknown) return null;
    if (record.type.length != 1 || record.type[0] != 0x55) return null; // 'U'
    final payload = record.payload;
    if (payload.isEmpty) return null;

    final prefix = _uriPrefix(payload[0]);
    final body = String.fromCharCodes(payload.sublist(1));
    return '$prefix$body';
  }

  // Сокращения URI-префиксов NDEF (нам нужен 0x04 = "https://").
  static String _uriPrefix(int code) {
    switch (code) {
      case 0x01:
        return 'http://www.';
      case 0x02:
        return 'https://www.';
      case 0x03:
        return 'http://';
      case 0x04:
        return 'https://';
      default:
        return '';
    }
  }
}
