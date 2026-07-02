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
      state = AsyncValue.data(
          items.map((e) => FileBookmark.fromJson(e as Map<String, dynamic>)).toList());
    } catch (e, s) {
      state = AsyncValue.error(e, s);
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
      state = state.whenData(
          (list) => list.where((b) => b.id != bookmarkId).toList());
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

// ─── Reading Status ────────────────────────────────────────────────────────

class ReadingStatusNotifier extends StateNotifier<String?> {
  final String fileId;
  final dynamic _dio;
  bool _loading = false;

  ReadingStatusNotifier(this.fileId, this._dio) : super(null) {
    _load();
  }

  Future<void> _load() async {
    try {
      final resp = await _dio.get(ApiEndpoints.fileReadingStatus(fileId));
      if (resp.statusCode == 204) {
        state = null;
        return;
      }
      state = resp.data?['data']?['status'] as String?;
    } catch (_) {
      state = null;
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
      state = prev;
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

class ReadingGoalNotifier extends StateNotifier<ReadingGoal?> {
  final dynamic _dio;
  ReadingGoalNotifier(this._dio) : super(null);

  Future<void> setGoal(int goalBooks) async {
    final year = DateTime.now().year;
    final resp = await _dio.put(ApiEndpoints.myReadingGoal,
        data: {'goal_books': goalBooks},
        queryParameters: {'year': year});
    final data = resp.data?['data'];
    if (data != null) {
      state = ReadingGoal.fromJson(data as Map<String, dynamic>);
    }
  }

  Future<void> deleteGoal() async {
    final year = DateTime.now().year;
    await _dio.delete(ApiEndpoints.myReadingGoal, queryParameters: {'year': year});
    state = null;
  }
}

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
  bool _loaded = false;

  FileNoteNotifier(this._dio, this._fileId) : super('') {
    _load();
  }

  Future<void> _load() async {
    try {
      final resp = await _dio.get(ApiEndpoints.fileNotes(_fileId));
      final content = resp.data?['data']?['content'] as String? ?? '';
      if (mounted) state = content;
      _loaded = true;
    } catch (_) {}
  }

  Future<void> save(String content) async {
    state = content;
    try {
      await _dio.put(ApiEndpoints.fileNotes(_fileId),
          data: {'content': content});
    } catch (_) {}
  }

  Future<void> delete() async {
    state = '';
    try {
      await _dio.delete(ApiEndpoints.fileNotes(_fileId));
    } catch (_) {}
  }

  bool get isLoaded => _loaded;
}
