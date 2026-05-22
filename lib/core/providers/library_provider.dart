import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../models/file_item.dart';

final libraryApiClientProvider = Provider<Dio>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final dio = Dio(BaseOptions(
    baseUrl: ApiEndpoints.libraryBaseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
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

final fileCategoriesProvider = FutureProvider<List<FileCategory>>((ref) async {
  final dio = ref.watch(libraryApiClientProvider);
  final resp = await dio.get(ApiEndpoints.filesCategories);
  final data = resp.data['data'] as List? ?? [];
  return data.map((e) => FileCategory.fromJson(e)).toList();
});

/// LIB-6: trending — top-N files за 7 дней по hot-score (likes*2+downloads).
final trendingFilesProvider = FutureProvider<List<FileItem>>((ref) async {
  final dio = ref.watch(libraryApiClientProvider);
  final resp = await dio.get('/files/trending', queryParameters: {'limit': '10'});
  final data = resp.data['data'] as List? ?? [];
  return data.map((e) => FileItem.fromJson(e as Map<String, dynamic>)).toList();
});

final filesProvider = FutureProvider.family<List<FileItem>, String?>((ref, categoryId) async {
  final dio = ref.watch(libraryApiClientProvider);
  final params = <String, dynamic>{'limit': '20', 'page': '1'};
  if (categoryId != null && categoryId.isNotEmpty) {
    params['category_id'] = categoryId;
  }
  final resp = await dio.get(ApiEndpoints.files, queryParameters: params);
  final data = resp.data['data'] as List? ?? [];
  return data.map((e) => FileItem.fromJson(e)).toList();
});

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
}

final libraryActionsProvider = Provider<LibraryActions>((ref) {
  return LibraryActions(ref.watch(libraryApiClientProvider));
});

/// Files uploaded by a specific user (profile tab).
final userFilesProvider = FutureProvider.family<List<FileItem>, String>((ref, userId) async {
  final dio = ref.watch(libraryApiClientProvider);
  final resp = await dio.get(ApiEndpoints.userFiles(userId));
  final data = resp.data['data'] as List? ?? [];
  return data.map((e) => FileItem.fromJson(e as Map<String, dynamic>)).toList();
});
