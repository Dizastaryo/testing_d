import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../models/post.dart';
import '../services/logger.dart';

/// Content type filter for PublicationViewer infinite feed.
enum ContentType { all, video, photo }

class ContentFeedState {
  final List<Post> posts;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final int page;

  const ContentFeedState({
    this.posts = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.page = 1,
  });

  ContentFeedState copyWith({
    List<Post>? posts,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    int? page,
  }) => ContentFeedState(
    posts: posts ?? this.posts,
    isLoading: isLoading ?? this.isLoading,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    hasMore: hasMore ?? this.hasMore,
    page: page ?? this.page,
  );
}

class ContentFeedNotifier extends StateNotifier<ContentFeedState> {
  static const _limit = 10;
  final ApiClient _api;
  final ContentType contentType;

  ContentFeedNotifier(this._api, this.contentType) : super(const ContentFeedState()) {
    refresh();
  }

  String? get _mediaTypeParam {
    switch (contentType) {
      case ContentType.video: return 'video';
      case ContentType.photo: return 'image';
      case ContentType.all: return null;
    }
  }

  Future<void> refresh() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true);
    try {
      final params = <String, dynamic>{'page': '1', 'limit': '$_limit'};
      if (_mediaTypeParam != null) params['media_type'] = _mediaTypeParam;
      final r = await _api.get(ApiEndpoints.postsExplore, queryParameters: params);
      final data = r.data is Map && r.data.containsKey('data') ? r.data['data'] : r.data;
      final list = data is List
          ? data.map((j) => Post.fromJson(j as Map<String, dynamic>)).toList()
          : <Post>[];
      state = ContentFeedState(posts: list, hasMore: list.length >= _limit, page: 2);
    } catch (e, st) {
      appLog.error('[ContentFeedNotifier] load error', e, st);
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore || state.isLoading) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final params = <String, dynamic>{'page': '${state.page}', 'limit': '$_limit'};
      if (_mediaTypeParam != null) params['media_type'] = _mediaTypeParam;
      final r = await _api.get(ApiEndpoints.postsExplore, queryParameters: params);
      final data = r.data is Map && r.data.containsKey('data') ? r.data['data'] : r.data;
      final list = data is List
          ? data.map((j) => Post.fromJson(j as Map<String, dynamic>)).toList()
          : <Post>[];
      final existing = state.posts.map((p) => p.id).toSet();
      final fresh = list.where((p) => !existing.contains(p.id)).toList();
      state = state.copyWith(
        posts: [...state.posts, ...fresh],
        isLoadingMore: false,
        hasMore: list.length >= _limit,
        page: state.page + 1,
      );
    } catch (e, st) {
      appLog.error('[ContentFeedNotifier] loadMore error', e, st);
      state = state.copyWith(isLoadingMore: false);
    }
  }

  /// Гарантирует, что пост с [postId] есть в ленте: плитка грида
  /// «Интересного» приходит из другой выборки (/explore) и может
  /// отсутствовать здесь — раньше вьюер молча открывал первый пост этой
  /// ленты вместо тапнутого. Дотягиваем пост по id и вставляем первым.
  Future<void> ensurePost(String postId) async {
    if (state.posts.any((p) => p.id == postId)) return;
    try {
      final r = await _api.get(ApiEndpoints.postById(postId));
      final data = r.data is Map && (r.data as Map).containsKey('data')
          ? r.data['data']
          : r.data;
      final post = Post.fromJson(data as Map<String, dynamic>);
      if (!mounted || state.posts.any((p) => p.id == postId)) return;
      state = state.copyWith(posts: [post, ...state.posts]);
    } catch (_) {
      // Пост удалён/недоступен — вьюер останется на первой странице.
    }
  }

  Future<void> toggleLike(String postId) async {
    final idx = state.posts.indexWhere((p) => p.id == postId);
    if (idx < 0) return;
    final original = state.posts[idx];
    final newLiked = !original.isLiked;
    final updated = original.copyWith(
      isLiked: newLiked,
      likesCount: newLiked ? original.likesCount + 1
          : (original.likesCount > 0 ? original.likesCount - 1 : 0),
    );
    _replacePost(idx, updated);
    try {
      if (newLiked) {
        await _api.post(ApiEndpoints.likePost(postId));
      } else {
        await _api.delete(ApiEndpoints.likePost(postId));
      }
    } catch (_) {
      _replacePost(idx, original);
    }
  }

  Future<void> toggleSave(String postId) async {
    final idx = state.posts.indexWhere((p) => p.id == postId);
    if (idx < 0) return;
    final original = state.posts[idx];
    final updated = original.copyWith(isSaved: !original.isSaved);
    _replacePost(idx, updated);
    try {
      if (updated.isSaved) {
        await _api.post(ApiEndpoints.savePost(postId));
      } else {
        await _api.delete(ApiEndpoints.savePost(postId));
      }
    } catch (_) {
      _replacePost(idx, original);
    }
  }

  void _replacePost(int idx, Post post) {
    state = state.copyWith(posts: [
      ...state.posts.sublist(0, idx), post, ...state.posts.sublist(idx + 1),
    ]);
  }
}

/// Family provider keyed by ContentType.
final contentFeedProvider = StateNotifierProvider.family<
    ContentFeedNotifier, ContentFeedState, ContentType>((ref, type) {
  return ContentFeedNotifier(ref.watch(apiClientProvider), type);
});
