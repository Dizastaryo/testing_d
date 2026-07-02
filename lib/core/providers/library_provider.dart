import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../config/server_config.dart';
import '../models/file_item.dart';

final libraryApiClientProvider = Provider<Dio>((ref) {
  ref.watch(serverIpProvider); // rebuild when IP changes → new baseUrl
  final apiClient = ref.watch(apiClientProvider);
  final dio = Dio(BaseOptions(
    baseUrl: ApiEndpoints.libraryBaseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 6), // LibreOffice холодный старт ~60-90с
    headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
  ));
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) async {
      final token = await apiClient.getAccessToken();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    },
  ));
  return dio;
});

// ─── Categories ────────────────────────────────────────────────────────────
final fileCategoriesProvider = FutureProvider<List<FileCategory>>((ref) async {
  final dio = ref.watch(libraryApiClientProvider);
  final resp = await dio.get(ApiEndpoints.filesCategories);
  final data = resp.data['data'] as List? ?? [];
  return data.map((e) => FileCategory.fromJson(e)).toList();
});

// ─── Trending ──────────────────────────────────────────────────────────────
final trendingFilesProvider = FutureProvider<List<FileItem>>((ref) async {
  final dio = ref.watch(libraryApiClientProvider);
  final resp = await dio.get(ApiEndpoints.filesTrending, queryParameters: {'limit': 10});
  final data = resp.data['data'] as List? ?? [];
  return data.map((e) => FileItem.fromJson(e as Map<String, dynamic>)).toList();
});

// ─── Recently Viewed ────────────────────────────────────────────────────────
final recentlyViewedProvider = FutureProvider<List<FileItem>>((ref) async {
  final dio = ref.watch(libraryApiClientProvider);
  try {
    final resp = await dio.get(ApiEndpoints.myRecentlyViewed, queryParameters: {'limit': 20});
    final data = resp.data['data'] as List? ?? [];
    return data.map((e) => FileItem.fromJson(e as Map<String, dynamic>)).toList();
  } catch (_) {
    return [];
  }
});

// ─── Recommendations ────────────────────────────────────────────────────────
final recommendationsProvider = FutureProvider<List<FileItem>>((ref) async {
  final dio = ref.watch(libraryApiClientProvider);
  try {
    final resp = await dio.get(ApiEndpoints.myRecommendations, queryParameters: {'limit': 10});
    final data = resp.data['data'] as List? ?? [];
    return data.map((e) => FileItem.fromJson(e as Map<String, dynamic>)).toList();
  } catch (_) {
    return [];
  }
});

// ─── Search Suggestions ─────────────────────────────────────────────────────
final searchSuggestionsProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, q) async {
  if (q.length < 2) return [];
  final dio = ref.watch(libraryApiClientProvider);
  // Provider-level debounce: each keystroke recreates this autoDispose family
  // instance for the new query and disposes the previous one. Cancelling the
  // in-flight request on dispose means only the last keystroke actually fires.
  final cancelToken = CancelToken();
  ref.onDispose(() => cancelToken.cancel());
  await Future.delayed(const Duration(milliseconds: 300));
  if (cancelToken.isCancelled) return [];
  try {
    final resp = await dio.get(ApiEndpoints.filesSuggestions,
        queryParameters: {'q': q}, cancelToken: cancelToken);
    final data = resp.data['data'] as List? ?? [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  } catch (_) {
    return [];
  }
});

// ─── Popular Authors ────────────────────────────────────────────────────────
final popularAuthorsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.watch(libraryApiClientProvider);
  try {
    final resp = await dio.get(ApiEndpoints.filesPopularAuthors, queryParameters: {'limit': 10});
    final data = resp.data['data'] as List? ?? [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  } catch (_) {
    return [];
  }
});

// ─── Library list (cursor-based, with search + sort + category) ────────────
class LibraryListParams {
  final String categoryId;
  final String q;
  final String sort; // date | likes | downloads | title
  final String format; // pdf | epub | docx | txt и т.д.
  final String language; // ru | en | kk и т.д.

  const LibraryListParams({
    this.categoryId = '',
    this.q = '',
    this.sort = 'date',
    this.format = '',
    this.language = '',
  });

  @override
  bool operator ==(Object other) =>
      other is LibraryListParams &&
      other.categoryId == categoryId &&
      other.q == q &&
      other.sort == sort &&
      other.format == format &&
      other.language == language;

  @override
  int get hashCode => Object.hash(categoryId, q, sort, format, language);
}

class LibraryListState {
  final List<FileItem> items;
  final bool isLoading;
  final bool isLoadingMore;
  final String cursor;
  final bool hasMore;
  final String? error;
  // Set when a *pagination* (loadMore) request fails. While true we stop
  // auto-paging on scroll so the screen doesn't spin into a tight error loop.
  // Cleared on an explicit retry.
  final bool pagingError;

  const LibraryListState({
    this.items = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.cursor = '',
    this.hasMore = true,
    this.error,
    this.pagingError = false,
  });

  LibraryListState copyWith({
    List<FileItem>? items,
    bool? isLoading,
    bool? isLoadingMore,
    String? cursor,
    bool? hasMore,
    String? error,
    bool? pagingError,
  }) =>
      LibraryListState(
        items: items ?? this.items,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        cursor: cursor ?? this.cursor,
        hasMore: hasMore ?? this.hasMore,
        error: error,
        pagingError: pagingError ?? this.pagingError,
      );
}

class LibraryListNotifier extends StateNotifier<LibraryListState> {
  final Dio _dio;
  LibraryListParams _params;

  LibraryListNotifier(this._dio, this._params) : super(const LibraryListState());

  void updateParams(LibraryListParams params) {
    if (_params == params) return;
    _params = params;
    load(reset: true);
  }

  Future<void> load({bool reset = false}) async {
    if (reset) {
      state = const LibraryListState(isLoading: true);
    } else {
      // Stop auto-paging once a page request has failed; an explicit
      // retryLoadMore() clears the flag before calling load() again.
      if (!state.hasMore || state.isLoadingMore || state.pagingError) return;
      state = state.copyWith(isLoadingMore: true);
    }

    try {
      final params = <String, dynamic>{'limit': 20};
      if (_params.categoryId.isNotEmpty) params['category_id'] = _params.categoryId;
      if (_params.q.isNotEmpty) params['q'] = _params.q;
      if (_params.sort.isNotEmpty && _params.sort != 'date') params['sort'] = _params.sort;
      if (_params.format.isNotEmpty) params['format'] = _params.format;
      if (_params.language.isNotEmpty) params['language'] = _params.language;
      if (!reset && state.cursor.isNotEmpty) params['cursor'] = state.cursor;

      final resp = await _dio.get(ApiEndpoints.files, queryParameters: params);
      final data = resp.data['data'] as List? ?? [];
      final nextCursor = resp.data['meta']?['next_cursor'] as String? ?? '';
      final fetched = data.map((e) => FileItem.fromJson(e as Map<String, dynamic>)).toList();

      state = LibraryListState(
        items: reset ? fetched : [...state.items, ...fetched],
        cursor: nextCursor,
        hasMore: nextCursor.isNotEmpty,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        isLoadingMore: false,
        // Mark pagination failures so _onScroll stops re-firing near bottom.
        pagingError: !reset,
        error: e.toString(),
      );
    }
  }

  /// Explicit retry after a pagination failure: clears the flag and re-fetches
  /// the next page.
  Future<void> retryLoadMore() async {
    if (state.isLoadingMore) return;
    state = state.copyWith(pagingError: false);
    await load();
  }
}

// autoDispose: every category/sort/format/language combo builds its own
// notifier holding the full loaded list. The browse + category screens
// recreate these params frequently, so keeping them alive leaks live
// notifiers + lists. autoDispose frees them once nothing watches the combo.
final libraryListProvider = StateNotifierProvider.autoDispose
    .family<LibraryListNotifier, LibraryListState, LibraryListParams>(
  (ref, params) {
    final dio = ref.watch(libraryApiClientProvider);
    final notifier = LibraryListNotifier(dio, params);
    notifier.load(reset: true);
    return notifier;
  },
);

// ─── My uploaded files ─────────────────────────────────────────────────────
final userFilesProvider = FutureProvider.family<List<FileItem>, String>((ref, userId) async {
  final dio = ref.watch(libraryApiClientProvider);
  final resp = await dio.get(ApiEndpoints.userFiles(userId));
  final data = resp.data['data'] as List? ?? [];
  return data.map((e) => FileItem.fromJson(e as Map<String, dynamic>)).toList();
});

// ─── Similar files (same category, excluding current) ─────────────────────
final similarFilesProvider =
    FutureProvider.autoDispose.family<List<FileItem>, ({String fileId, String categoryId})>(
        (ref, arg) async {
  if (arg.categoryId.isEmpty) return [];
  final dio = ref.watch(libraryApiClientProvider);
  final resp = await dio.get(ApiEndpoints.files, queryParameters: {
    'category_id': arg.categoryId,
    'exclude_id': arg.fileId,
    'limit': 8,
    'sort': 'likes',
  });
  final data = resp.data['data'] as List? ?? [];
  return data.map((e) => FileItem.fromJson(e as Map<String, dynamic>)).toList();
});

// ─── Files by author ───────────────────────────────────────────────────────
final authorFilesProvider =
    FutureProvider.autoDispose.family<List<FileItem>, String>((ref, author) async {
  if (author.isEmpty) return [];
  final dio = ref.watch(libraryApiClientProvider);
  final resp = await dio.get(ApiEndpoints.files, queryParameters: {
    'author': author,
    'limit': 20,
    'sort': 'date',
  });
  final data = resp.data['data'] as List? ?? [];
  return data.map((e) => FileItem.fromJson(e as Map<String, dynamic>)).toList();
});

final socialPicksProvider = FutureProvider<List<FileItem>>((ref) async {
  final dio = ref.watch(libraryApiClientProvider);
  try {
    final resp = await dio.get(ApiEndpoints.filesSocialPicks, queryParameters: {'limit': 10});
    final raw = resp.data;
    final data = (raw is Map && raw.containsKey('data'))
        ? raw['data'] as List? ?? []
        : raw as List? ?? [];
    return data.map((e) => FileItem.fromJson(e as Map<String, dynamic>)).toList();
  } catch (_) {
    return [];
  }
});

final fileRelatedProvider =
    FutureProvider.autoDispose.family<List<FileItem>, String>((ref, fileId) async {
  if (fileId.isEmpty) return [];
  final dio = ref.watch(libraryApiClientProvider);
  try {
    final resp = await dio.get(ApiEndpoints.fileRelated(fileId), queryParameters: {'limit': 8});
    final raw = resp.data;
    final data = (raw is Map && raw.containsKey('data'))
        ? raw['data'] as List? ?? []
        : raw as List? ?? [];
    return data.map((e) => FileItem.fromJson(e as Map<String, dynamic>)).toList();
  } catch (_) {
    return [];
  }
});

// ─── Reading stats ────────────────────────────────────────────────────────
final readingStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final dio = ref.watch(libraryApiClientProvider);
  final resp = await dio.get(ApiEndpoints.myReadingStats);
  return resp.data['data'] as Map<String, dynamic>? ?? {};
});

// ─── Reading list ──────────────────────────────────────────────────────────
final readingListProvider =
    FutureProvider.family<List<FileItem>, String>((ref, status) async {
  final dio = ref.watch(libraryApiClientProvider);
  final resp = await dio.get(ApiEndpoints.myReadingList, queryParameters: {'status': status});
  final data = resp.data['data'] as List? ?? [];
  return data.map((e) => FileItem.fromJson(e as Map<String, dynamic>)).toList();
});

// ─── Recently read ────────────────────────────────────────────────────────
final recentlyReadProvider = FutureProvider<List<FileItem>>((ref) async {
  final dio = ref.watch(libraryApiClientProvider);
  try {
    final resp = await dio.get(ApiEndpoints.myRecentlyRead, queryParameters: {'limit': 10});
    final data = resp.data['data'] as List? ?? [];
    return data.map((e) => FileItem.fromJson(e as Map<String, dynamic>)).toList();
  } catch (_) {
    return [];
  }
});

// ─── Library actions ───────────────────────────────────────────────────────
class LibraryActions {
  final Dio _dio;
  LibraryActions(this._dio);

  Future<Map<String, dynamic>> download(String fileId) async {
    final resp = await _dio.get(ApiEndpoints.fileDownload(fileId));
    return resp.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> preview(String fileId) async {
    final resp = await _dio.get(ApiEndpoints.filePreview(fileId));
    return resp.data['data'] as Map<String, dynamic>;
  }

  Future<void> deleteFile(String fileId) async {
    await _dio.delete(ApiEndpoints.fileById(fileId));
  }

  Future<void> upsertReadingStatus(String fileId, String status) async {
    await _dio.put(ApiEndpoints.fileReadingStatus(fileId), data: {'status': status});
  }

  Future<void> deleteReadingStatus(String fileId) async {
    await _dio.delete(ApiEndpoints.fileReadingStatus(fileId));
  }

  Future<void> updateFileMeta(String fileId, Map<String, dynamic> data) async {
    await _dio.patch(ApiEndpoints.fileById(fileId), data: data);
  }

  Future<String?> getReadingStatus(String fileId) async {
    try {
      final resp = await _dio.get(ApiEndpoints.fileReadingStatus(fileId));
      if (resp.statusCode == 204) return null;
      return resp.data['data']?['status'] as String?;
    } catch (_) {
      return null;
    }
  }

  // ── View / Like ─────────────────────────────────────────────────────────

  /// Fire-and-forget view tracking. Errors are swallowed by callers.
  Future<void> trackView(String fileId) async {
    await _dio.post(ApiEndpoints.fileView(fileId));
  }

  /// Toggle like. [liked] is the *current* state — we POST to like (when not
  /// yet liked) and DELETE to unlike.
  Future<void> setLike(String fileId, {required bool liked}) async {
    final url = ApiEndpoints.fileLike(fileId);
    if (liked) {
      await _dio.delete(url);
    } else {
      await _dio.post(url);
    }
  }

  /// Resolves the signed download URL (and related meta) for a file.
  Future<Map<String, dynamic>> downloadInfo(String fileId) async {
    final resp = await _dio.get(ApiEndpoints.fileDownload(fileId));
    final raw = resp.data;
    if (raw is Map && raw['data'] is Map) {
      return Map<String, dynamic>.from(raw['data'] as Map);
    }
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return {};
  }

  // ── Ratings / Reviews ───────────────────────────────────────────────────

  /// Loads the current user's review text for a file (empty if none).
  Future<String> loadRatingReview(String fileId) async {
    try {
      final resp = await _dio.get(ApiEndpoints.fileRating(fileId));
      final raw = resp.data;
      if (raw is Map && raw['data'] is Map) {
        return (raw['data'] as Map)['review_text'] as String? ?? '';
      }
      return '';
    } catch (_) {
      return '';
    }
  }

  Future<void> setRating(String fileId, int rating, String reviewText) async {
    await _dio.put(
      ApiEndpoints.fileRating(fileId),
      data: {'rating': rating, 'review_text': reviewText},
    );
  }

  // ── Reading position (single offset/page) ───────────────────────────────

  /// Loads the saved reading position. Returns null when none / on error.
  Future<Map<String, dynamic>?> loadProgress(String fileId) async {
    try {
      final resp = await _dio.get(ApiEndpoints.fileProgress(fileId));
      if (resp.statusCode == 204) return null;
      final raw = resp.data;
      final data = raw is Map ? raw['data'] : null;
      if (data is! Map) return null;
      final pos = data['position'];
      if (pos is Map) return Map<String, dynamic>.from(pos);
      if (pos is String) {
        try {
          return Map<String, dynamic>.from(jsonDecode(pos) as Map);
        } catch (_) {
          return null;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveProgress(String fileId, Map<String, dynamic> position) async {
    await _dio.put(ApiEndpoints.fileProgress(fileId), data: {'position': position});
  }

  // ── Per-page reading time (ReadingTracker) ──────────────────────────────

  /// Loads per-page seconds + the server threshold for "read" detection.
  Future<({Map<int, int> pages, int threshold})> loadPagesProgress(
      String fileId, int fallbackThreshold) async {
    final resp = await _dio.get(ApiEndpoints.filePagesProgress(fileId));
    final pages = <int, int>{};
    var threshold = fallbackThreshold;
    final raw = resp.data;
    if (raw is Map && raw['data'] is Map) {
      final data = raw['data'] as Map;
      final t = data['threshold_secs'];
      if (t is int) threshold = t;
      final pagesRaw = data['pages'];
      if (pagesRaw is Map) {
        pagesRaw.forEach((k, v) {
          final page = int.tryParse(k.toString());
          final secs = v is int ? v : int.tryParse(v.toString());
          if (page != null && secs != null) pages[page] = secs;
        });
      }
    }
    return (pages: pages, threshold: threshold);
  }

  Future<void> savePagesProgress(String fileId, Map<String, int> pages) async {
    await _dio.put(
      ApiEndpoints.filePagesProgress(fileId),
      data: {'pages': pages},
    );
  }
}

final libraryActionsProvider = Provider<LibraryActions>((ref) {
  return LibraryActions(ref.watch(libraryApiClientProvider));
});

// ─── Search History ─────────────────────────────────────────────────────────
const _searchHistoryKey = 'library_search_history';
const _maxSearchHistory = 10;

class SearchHistoryNotifier extends StateNotifier<List<String>> {
  SearchHistoryNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getStringList(_searchHistoryKey) ?? [];
  }

  Future<void> add(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final updated = [q, ...state.where((s) => s != q)];
    if (updated.length > _maxSearchHistory) updated.removeRange(_maxSearchHistory, updated.length);
    state = updated;
    final prefs = await SharedPreferences.getInstance();
    prefs.setStringList(_searchHistoryKey, updated);
  }

  Future<void> remove(String query) async {
    state = state.where((s) => s != query).toList();
    final prefs = await SharedPreferences.getInstance();
    prefs.setStringList(_searchHistoryKey, state);
  }

  Future<void> clear() async {
    state = [];
    final prefs = await SharedPreferences.getInstance();
    prefs.remove(_searchHistoryKey);
  }
}

final searchHistoryProvider =
    StateNotifierProvider<SearchHistoryNotifier, List<String>>(
  (ref) => SearchHistoryNotifier(),
);
