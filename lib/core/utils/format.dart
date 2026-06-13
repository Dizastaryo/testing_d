import 'dart:ui' show Color;

/// Compact number format for likes, followers, views etc.
/// 1234 → "1.2К", 1500000 → "1.5М"
String formatCount(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}М';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}К';
  return '$n';
}

/// Color for file extension badge in library screens.
/// Covers all formats allowed by the library: pdf, epub, fb2, docx, pptx,
/// txt, rtf, md, odt, odp.
Color colorForFileType(String ext) {
  switch (ext) {
    case 'pdf':
      return const Color(0xFFE53935); // red
    case 'epub':
      return const Color(0xFF8E24AA); // purple
    case 'fb2':
      return const Color(0xFF00ACC1); // cyan
    case 'docx':
      return const Color(0xFF1E88E5); // blue
    case 'pptx':
      return const Color(0xFFFF7043); // deep orange
    case 'txt':
    case 'md':
      return const Color(0xFF43A047); // green
    case 'rtf':
      return const Color(0xFF039BE5); // light blue
    case 'odt':
      return const Color(0xFF00897B); // teal
    case 'odp':
      return const Color(0xFFE91E63); // pink
    default:
      return const Color(0xFF78909C); // blue-grey
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
