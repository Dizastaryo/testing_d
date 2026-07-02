import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../models/video.dart';

/// Dio client for the video service (8002). Still used by the Shorts viewer
/// (opened from Explore) — the long-video "Видеотека" section was removed, but
/// vertical Shorts continue to stream from the same backend.
final videoApiClientProvider = Provider<Dio>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final dio = Dio(BaseOptions(
    baseUrl: ApiEndpoints.videoBaseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    headers: {'Accept': 'application/json'},
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

/// A single video by id. Used by the vertical Shorts viewer opened from Explore,
/// which needs the playback URL (the Explore card only carries the video id).
final singleVideoProvider =
    FutureProvider.autoDispose.family<Video, String>((ref, id) async {
  final dio = ref.watch(videoApiClientProvider);
  final resp = await dio.get('/videos/$id');
  final data = resp.data is Map && (resp.data as Map).containsKey('data')
      ? resp.data['data']
      : resp.data;
  return Video.fromJson((data as Map).cast<String, dynamic>());
});
