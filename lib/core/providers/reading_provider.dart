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

  Future<void> addBookmark(Map<String, dynamic> position, String note) async {
    try {
      await _dio.post(ApiEndpoints.fileBookmarks(fileId), data: {
        'position': position,
        'note': note,
      });
      await _load();
    } catch (_) {}
  }

  Future<void> deleteBookmark(String bookmarkId) async {
    try {
      await _dio.delete(ApiEndpoints.bookmarkById(bookmarkId));
      state = state.whenData(
          (list) => list.where((b) => b.id != bookmarkId).toList());
    } catch (_) {}
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
      if (newStatus == null || newStatus == state) {
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
