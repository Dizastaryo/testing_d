import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../config/server_config.dart';
import '../models/video.dart';

final videoApiClientProvider = Provider<Dio>((ref) {
  ref.watch(serverIpProvider); // rebuild when IP changes → new baseUrl
  final apiClient = ref.watch(apiClientProvider);
  final dio = Dio(BaseOptions(
    baseUrl: ApiEndpoints.videoBaseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
    headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
  ));
  // Share auth token from main client
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

// === Videos ===

final videoCategoriesProvider = FutureProvider<List<VideoCategory>>((ref) async {
  final dio = ref.watch(videoApiClientProvider);
  final resp = await dio.get(ApiEndpoints.videosCategories);
  final data = resp.data['data'] as List? ?? [];
  return data.map((e) => VideoCategory.fromJson(e)).toList();
});

final videosFeaturedProvider = FutureProvider<Video?>((ref) async {
  final dio = ref.watch(videoApiClientProvider);
  final resp = await dio.get(ApiEndpoints.videosFeatured);
  final data = resp.data['data'];
  if (data == null) return null;
  return Video.fromJson(data);
});

final videosProvider = FutureProvider.family<List<Video>, String?>((ref, categoryId) async {
  final dio = ref.watch(videoApiClientProvider);
  final params = <String, dynamic>{'limit': '20', 'page': '1'};
  if (categoryId != null && categoryId.isNotEmpty) {
    params['category_id'] = categoryId;
  }
  final resp = await dio.get(ApiEndpoints.videos, queryParameters: params);
  final data = resp.data['data'] as List? ?? [];
  return data.map((e) => Video.fromJson(e)).toList();
});

/// Videos uploaded by a specific user (profile tab).
final userVideosProvider = FutureProvider.family<List<Video>, String>((ref, userId) async {
  final dio = ref.watch(videoApiClientProvider);
  final resp = await dio.get(ApiEndpoints.userVideos(userId));
  final data = resp.data['data'] as List? ?? [];
  return data.map((e) => Video.fromJson(e)).toList();
});

// Reels providers removed — every publication is now a unified post served
// by the api service. Use exploreProvider / feedProvider instead.
