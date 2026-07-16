import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_endpoints.dart';
import '../models/reading.dart';
import 'library_provider.dart';

// ─── Reading Progress ──────────────────────────────────────────────────────

final readingProgressProvider =
    FutureProvider.autoDispose.family<ReadingProgress?, String>((ref, fileId) async {
  final dio = ref.watch(libraryApiClientProvider);
  try {
    final resp = await dio.get(ApiEndpoints.fileProgress(fileId));
    if (resp.statusCode == 204 || resp.data == null) return null;
    final data = resp.data?['data'];
    if (data == null) return null;
    return ReadingProgress.fromJson(data as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
});

// ─── Bookmarks ─────────────────────────────────────────────────────────────

class BookmarksNotifier extends StateNotifier<AsyncValue<List<FileBookmark>>> {
  final String fileId;
  final dynamic _dio;

  BookmarksNotifier(this.fileId, this._dio)
      : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final resp = await _dio.get(ApiEndpoints.fileBookmarks(fileId));
      final items = resp.data?['data']?['items'] as List? ?? [];
      if (!mounted) return;
      state = AsyncValue.data(
          items.map((e) => FileBookmark.fromJson(e as Map<String, dynamic>)).toList());
    } catch (e, s) {
      if (mounted) state = AsyncValue.error(e, s);
    }
  }

  /// Adds bookmark. Returns error message or null on success.
  Future<String?> addBookmark(Map<String, dynamic> position, String note) async {
    try {
      await _dio.post(ApiEndpoints.fileBookmarks(fileId), data: {
        'position': position,
        'note': note,
      });
      await _load();
      return null;
    } catch (e) {
      return 'Не удалось сохранить закладку';
    }
  }

  /// Deletes bookmark. Returns error message or null on success.
  Future<String?> deleteBookmark(String bookmarkId) async {
    try {
      await _dio.delete(ApiEndpoints.bookmarkById(bookmarkId));
      if (mounted) {
        state = state.whenData(
            (list) => list.where((b) => b.id != bookmarkId).toList());
      }
      return null;
    } catch (e) {
      return 'Не удалось удалить закладку';
    }
  }
}

final bookmarksProvider =
    StateNotifierProvider.autoDispose.family<BookmarksNotifier,
        AsyncValue<List<FileBookmark>>, String>(
  (ref, fileId) {
    final dio = ref.watch(libraryApiClientProvider);
    return BookmarksNotifier(fileId, dio);
  },
);

// ─── Все мои закладки (Полка → Закладки) ───────────────────────────────────

/// Закладка вместе с книгой, к которой она относится — чтобы список закладок
/// показывал название и автора, а не голый идентификатор файла.
class BookmarkEntry {
  final FileBookmark bookmark;
  final String fileTitle;
  final String authorName;
  final String coverUrl;

  const BookmarkEntry({
    required this.bookmark,
    required this.fileTitle,
    required this.authorName,
    required this.coverUrl,
  });

  factory BookmarkEntry.fromJson(Map<String, dynamic> j) {
    final title = (j['file_title'] as String?) ?? '';
    final filename = (j['filename'] as String?) ?? '';
    return BookmarkEntry(
      bookmark: FileBookmark.fromJson(j),
      fileTitle: title.isNotEmpty ? title : filename,
      authorName: (j['author_name'] as String?) ?? '',
      coverUrl: (j['cover_url'] as String?) ?? '',
    );
  }

  /// «Стр. 214» / «12%» — куда именно ведёт закладка.
  String get positionLabel {
    final pos = bookmark.position;
    final page = (pos['page'] as num?)?.toInt();
    if (page != null && page > 0) return 'Стр. $page';
    final pct = (pos['pct'] as num?)?.toDouble();
    if (pct != null) return '${(pct * 100).round()}%';
    // Легаси-формат текстовых закладок (пиксельный offset/total) → доля.
    final offset = (pos['offset'] as num?)?.toDouble();
    final total = (pos['total'] as num?)?.toDouble();
    if (offset != null && total != null && total > 0) {
      return '${(offset / total * 100).clamp(0, 100).round()}%';
    }
    return '';
  }
}

final allBookmarksProvider = FutureProvider<List<BookmarkEntry>>((ref) async {
  final dio = ref.watch(libraryApiClientProvider);
  final resp = await dio.get(ApiEndpoints.myBookmarks);
  final items = resp.data?['data']?['items'] as List? ?? [];
  return items
      .whereType<Map>()
      .map((e) => BookmarkEntry.fromJson(Map<String, dynamic>.from(e)))
      .toList();
});

// ─── Reading Status ────────────────────────────────────────────────────────

class ReadingStatusNotifier extends StateNotifier<String?> {
  final String fileId;
  final dynamic _dio;
  bool _loading = false;
  Future<void>? _loadFuture;

  ReadingStatusNotifier(this.fileId, this._dio) : super(null) {
    _loadFuture = _load();
  }

  /// Пометить «читаю», но ТОЛЬКО если у файла ещё нет статуса — и только после
  /// того как исходный статус реально загрузился. Раньше ридер читал ещё не
  /// загруженный (null) провайдер и гонкой затирал «Прочитано»/«Хочу» → «Читаю».
  Future<void> autoSetReadingIfAbsent() async {
    await _loadFuture;
    if (!mounted) return;
    if (state == null) {
      await updateStatus('reading');
    }
  }

  Future<void> _load() async {
    try {
      final resp = await _dio.get(ApiEndpoints.fileReadingStatus(fileId));
      if (!mounted) return;
      if (resp.statusCode == 204) {
        state = null;
        return;
      }
      state = resp.data?['data']?['status'] as String?;
    } catch (_) {
      if (mounted) state = null;
    }
  }

  Future<void> updateStatus(String? newStatus) async {
    if (_loading) return;
    _loading = true;
    final prev = state;
    try {
      if (newStatus == null) {
        state = null;
        await _dio.delete(ApiEndpoints.fileReadingStatus(fileId));
      } else {
        state = newStatus;
        await _dio.put(ApiEndpoints.fileReadingStatus(fileId),
            data: {'status': newStatus});
      }
    } catch (_) {
      if (mounted) state = prev;
    } finally {
      _loading = false;
    }
  }
}

final readingStatusProvider =
    StateNotifierProvider.autoDispose.family<ReadingStatusNotifier, String?, String>(
  (ref, fileId) {
    final dio = ref.watch(libraryApiClientProvider);
    return ReadingStatusNotifier(fileId, dio);
  },
);

// ─── Reading Goal ────────────────────────────────────────────────────────────

final readingGoalProvider = FutureProvider<ReadingGoal?>((ref) async {
  final dio = ref.watch(libraryApiClientProvider);
  try {
    final year = DateTime.now().year;
    final resp = await dio.get(ApiEndpoints.myReadingGoal, queryParameters: {'year': year});
    final data = resp.data?['data'];
    if (data == null) return null;
    return ReadingGoal.fromJson(data as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
});

// ReadingGoalNotifier удалён: не имел провайдера и вызовов — цель ставится
// напрямую через dio.put в library_profile_screen. Чтение цели идёт через
// readingGoalProvider выше.

// ─── Reading Activity (heatmap) ───────────────────────────────────────────────

/// Returns [{date: "YYYY-MM-DD", sessions: N}] for the past N days.
final readingActivityProvider =
    FutureProvider.family<List<Map<String, dynamic>>, int>((ref, days) async {
  final dio = ref.watch(libraryApiClientProvider);
  try {
    final resp = await dio.get(ApiEndpoints.readingActivity,
        queryParameters: {'days': days});
    final data = resp.data?['data'] as List? ?? [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  } catch (_) {
    return [];
  }
});

// ─── File Notes (personal) ────────────────────────────────────────────────────

final fileNoteProvider =
    StateNotifierProvider.autoDispose.family<FileNoteNotifier, String, String>(
        (ref, fileId) {
  final dio = ref.watch(libraryApiClientProvider);
  return FileNoteNotifier(dio, fileId);
});

class FileNoteNotifier extends StateNotifier<String> {
  final dynamic _dio;
  final String _fileId;

  FileNoteNotifier(this._dio, this._fileId) : super('') {
    _load();
  }

  Future<void> _load() async {
    try {
      final resp = await _dio.get(ApiEndpoints.fileNotes(_fileId));
      final content = resp.data?['data']?['content'] as String? ?? '';
      if (mounted) state = content;
    } catch (_) {}
  }

  Future<void> save(String content) async {
    final prev = state;
    state = content;
    try {
      await _dio.put(ApiEndpoints.fileNotes(_fileId),
          data: {'content': content});
    } catch (_) {
      // Server rejected/failed the save — roll back so the UI doesn't keep
      // showing an unsaved note as if it had persisted.
      if (mounted) state = prev;
    }
  }

  Future<void> delete() async {
    final prev = state;
    state = '';
    try {
      await _dio.delete(ApiEndpoints.fileNotes(_fileId));
    } catch (_) {
      if (mounted) state = prev;
    }
  }
}
