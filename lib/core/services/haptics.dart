import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Тактильная обратная связь. Wrapper над [HapticFeedback] чтобы:
///   1. Один раз заглушить на web (там noop, но логи не засоряются).
///   2. Дать единый API для будущего `Settings → Haptics on/off`.
///   3. Документировать интенсивность ивента бренда: light для тапов,
///      medium для двойных-тапов / лайков, heavy для значимых событий.
class SeeUHaptics {
  SeeUHaptics._();

  static bool _enabled = !kIsWeb; // на вебе haptic API пуст — лишних вызовов не делаем

  /// Принудительно отключить (например по toggle'у в settings).
  static void setEnabled(bool v) {
    _enabled = v;
  }

  /// Лёгкий импульс — тап на bottom-nav, переключение table'а, выбор chip'а.
  static Future<void> tap() async {
    if (!_enabled) return;
    await HapticFeedback.lightImpact();
  }

  /// Средний — двойной-тап (like), длительный hold, нажатие primary-кнопки.
  static Future<void> press() async {
    if (!_enabled) return;
    await HapticFeedback.mediumImpact();
  }

  /// Сильный — успешная публикация, completed action, найденный nearby-юзер.
  static Future<void> success() async {
    if (!_enabled) return;
    await HapticFeedback.heavyImpact();
  }

  /// Selection-tick — для slider'ов и picker'ов, когда значение «защёлкнулось».
  static Future<void> tick() async {
    if (!_enabled) return;
    await HapticFeedback.selectionClick();
  }
}
