import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../models/post.dart';

/// Лента «Волн» для вкладки «Волны» в Интересном (§04 D). Тянет только волны
/// (`/posts/explore?media_type=wave`) — текст-первые посты, которые в сетке
/// «Все» скрыты (пустая плитка), а тут показываются полноценной лентой.
final wavesFeedProvider = FutureProvider.autoDispose<List<Post>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final r = await api.get(ApiEndpoints.postsExplore, queryParameters: {
    'media_type': 'wave',
    'page': '1',
    'limit': '30',
  });
  final body = r.data;
  final data =
      (body is Map && body.containsKey('data')) ? body['data'] : body;
  if (data is List) {
    return data
        .whereType<Map>()
        .map((j) => Post.fromJson(j.cast<String, dynamic>()))
        .toList();
  }
  return <Post>[];
});
