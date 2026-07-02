import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Нормализация телефонного номера и SHA-256 хэш для приватного матчинга
/// контактов (Фаза 2).
///
/// ВАЖНО: эта логика — точная копия backend `pkg/phone/phone.go`. Любое
/// изменение правил нормализации ОБЯЗАНО синхронно повторяться на бэкенде,
/// иначе хэши перестанут совпадать и матчинг сломается.
class PhoneUtil {
  PhoneUtil._();

  /// Приводит сырой номер к каноничному E.164: '+' и только цифры.
  /// KZ/RU-эвристика: 11 цифр с ведущей 8 → +7…; 10 цифр → префикс +7;
  /// уже имеющийся '+' сохраняется. Пустой/мусорный ввод → ''.
  static String normalize(String raw) {
    final trimmed = raw.trim();
    final hasPlus = trimmed.startsWith('+');

    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';

    var d = digits;
    if (!hasPlus) {
      if (d.length == 11 && d[0] == '8') {
        d = '7${d.substring(1)}';
      } else if (d.length == 10) {
        d = '7$d';
      }
    }
    return '+$d';
  }

  /// Hex SHA-256 от УЖЕ нормализованного номера. Пустой ввод → ''.
  static String hash(String normalized) {
    if (normalized.isEmpty) return '';
    return sha256.convert(utf8.encode(normalized)).toString();
  }

  /// Шорткат: normalize → hash. Пустой результат нормализации даёт ''.
  static String normalizeAndHash(String raw) => hash(normalize(raw));
}
