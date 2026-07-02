/// Single source of truth for "N units ago" timestamps shown across the
/// feed/explore/comments/notifications/stories surfaces. The previous mix
/// («2 ЧАСА НАЗАД» / «2h» / «2 часа назад» / relative «вчера») was an
/// audit-flagged inconsistency.
///
/// Returned strings are Russian, lowercase, single-word — designed to fit
/// in compact captions and timestamp pills. Layout:
///
///   < 60s   → «сейчас»
///   < 60m   → «Nм»          (e.g. «3м»)
///   < 24h   → «Nч»          (e.g. «5ч»)
///   < 7d    → «Nд»
///   < 30d   → «Nн»          (weeks)
///   else    → «DD.MM.YY»    (absolute date — anything older than ~month)
///
/// Note: chat-list previews (`chat_list_screen._formatTime`) intentionally
/// keep their "HH:MM today / yesterday / DD.MM" semantics — list-view
/// timestamps follow a different convention and aren't covered here.
String formatRelativeTime(DateTime dt) {
  final now = DateTime.now();
  final diff = now.difference(dt);

  if (diff.inSeconds < 60) return 'сейчас';
  if (diff.inMinutes < 60) return '${diff.inMinutes}м';
  if (diff.inHours < 24) return '${diff.inHours}ч';
  if (diff.inDays < 7) return '${diff.inDays}д';
  if (diff.inDays < 30) return '${diff.inDays ~/ 7}н';

  final dd = dt.day.toString().padLeft(2, '0');
  final mm = dt.month.toString().padLeft(2, '0');
  final yy = (dt.year % 100).toString().padLeft(2, '0');
  return '$dd.$mm.$yy';
}
