import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

// ─── Library list (cursor-based, with search + sort + category) ────────────
class LibraryListParams {
  final String categoryId;
  final String q;
  final String sort; // date | likes | downloads | title

  const LibraryListParams({
    this.categoryId = '',
    this.q = '',
    this.sort = 'date',
  });

  @override
  bool operator ==(Object other) =>
      other is LibraryListParams &&
      other.categoryId == categoryId &&
      other.q == q &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(categoryId, q, sort);
}

class LibraryListState {
  final List<FileItem> items;
  final bool isLoading;
  final bool isLoadingMore;
  final String cursor;
  final bool hasMore;
  final String? error;

  const LibraryListState({
    this.items = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.cursor = '',
    this.hasMore = true,
    this.error,
  });

  LibraryListState copyWith({
    List<FileItem>? items,
    bool? isLoading,
    bool? isLoadingMore,
    String? cursor,
    bool? hasMore,
    String? error,
  }) =>
      LibraryListState(
        items: items ?? this.items,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        cursor: cursor ?? this.cursor,
        hasMore: hasMore ?? this.hasMore,
        error: error,
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
      if (!state.hasMore || state.isLoadingMore) return;
      state = state.copyWith(isLoadingMore: true);
    }

    try {
      final params = <String, dynamic>{'limit': 20};
      if (_params.categoryId.isNotEmpty) params['category_id'] = _params.categoryId;
      if (_params.q.isNotEmpty) params['q'] = _params.q;
      if (_params.sort.isNotEmpty && _params.sort != 'date') params['sort'] = _params.sort;
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
        error: e.toString(),
      );
    }
  }
}

final libraryListProvider =
    StateNotifierProvider.family<LibraryListNotifier, LibraryListState, LibraryListParams>(
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

// ─── Reading list ──────────────────────────────────────────────────────────
final readingListProvider =
    FutureProvider.family<List<FileItem>, String>((ref, status) async {
  final dio = ref.watch(libraryApiClientProvider);
  final resp = await dio.get(ApiEndpoints.myReadingList, queryParameters: {'status': status});
  final data = resp.data['data'] as List? ?? [];
  return data.map((e) => FileItem.fromJson(e as Map<String, dynamic>)).toList();
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
}

final libraryActionsProvider = Provider<LibraryActions>((ref) {
  return LibraryActions(ref.watch(libraryApiClientProvider));
});
