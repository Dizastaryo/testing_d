import 'dart:ui' show Color;

/// Compact number format for likes, followers, views etc.
/// 1234 → "1.2К", 1500000 → "1.5М"
String formatCount(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}М';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}К';
  return '$n';
}

/// Color for file extension badge in library screens.
Color colorForFileType(String ext) {
  switch (ext) {
    case 'pdf':
      return const Color(0xFFFF5A3C); // SeeUColors.accent
    case 'zip':
    case 'rar':
      return const Color(0xFFC04CFD);
    case 'txt':
    case 'md':
      return const Color(0xFF2FA84F);
    case 'mp3':
    case 'wav':
      return const Color(0xFF4A90E2);
    default:
      return const Color(0xFFFFC107);
  }
}

/// Duration → "m:ss" (e.g. "3:07").
String formatDuration(Duration d) {
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// User-friendly error message from a raw exception/error.
/// Replaces technical stack traces and exception types with readable Russian text.
String friendlyError(Object error) {
  final s = error.toString();
  if (s.contains('SocketException') || s.contains('Connection refused')) {
    return 'Нет подключения к серверу';
  }
  if (s.contains('TimeoutException') || s.contains('timed out')) {
    return 'Превышено время ожидания';
  }
  if (s.contains('403')) return 'Нет доступа';
  if (s.contains('404')) return 'Не найдено';
  if (s.contains('500') || s.contains('502') || s.contains('503')) {
    return 'Ошибка сервера. Попробуйте позже';
  }
  if (s.contains('FormatException')) return 'Ошибка формата данных';
  return 'Что-то пошло не так. Попробуйте ещё раз';
}
