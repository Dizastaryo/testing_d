import 'package:flutter/foundation.dart';

/// UX-4: единственная точка для debug-логов. В debug-build пишет через
/// `debugPrint` (который Flutter автоматически throttle'ит и stripping'ует
/// в release). В release — полный no-op чтобы не оставлять следов в console
/// production-сборки.
///
/// Использование:
///   appLog('connecting WS');
///   appLog('error %s', err);   // как printf
///   appLog.error('failed: $e', err);
///
/// Заменяет print/debugPrint везде в проекте.
class _Logger {
  const _Logger();

  /// Info-уровень. Печатает только в debug. Принимает opt args через
  /// Object?... — лояльно к разному shape callers (просто string, error
  /// object, multiple values).
  void call(String message, [Object? a, Object? b, Object? c]) {
    if (!kDebugMode) return;
    final extras = <Object?>[a, b, c].where((e) => e != null).toList();
    if (extras.isEmpty) {
      debugPrint(message);
    } else {
      debugPrint('$message ${extras.join(' ')}');
    }
  }

  /// Error-уровень. В debug печатает с маркером. Hook для будущей
  /// интеграции Sentry/Rollbar — сейчас просто debug-print.
  void error(String message, [Object? err, StackTrace? stack]) {
    if (!kDebugMode) return;
    debugPrint('🔴 $message${err != null ? ': $err' : ''}');
    if (stack != null) debugPrint(stack.toString());
  }

  /// Warning-уровень — менее срочный чем error, но не info.
  void warn(String message, [Object? context]) {
    if (!kDebugMode) return;
    debugPrint('⚠️  $message${context != null ? ': $context' : ''}');
  }
}

const appLog = _Logger();
