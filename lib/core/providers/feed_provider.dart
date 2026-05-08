import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../models/post.dart';

class FeedState {
  final List<Post> posts;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;
  final int _page;

  const FeedState({
    this.posts = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
    int page = 1,
  }) : _page = page;

  int get page => _page;

  FeedState copyWith({
    List<Post>? posts,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    int? page,
  }) {
    return FeedState(
      posts: posts ?? this.posts,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: error,
      page: page ?? _page,
    );
  }
}

class FeedNotifier extends StateNotifier<FeedState> {
  final ApiClient _api;

  FeedNotifier(this._api) : super(const FeedState()) {
    loadFeed();
  }

  static const _limit = 20;

  Future<void> loadFeed() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _api.get(ApiEndpoints.feed,
          queryParameters: {'page': '1', 'limit': '$_limit'});
      final data = response.data;
      final listData =
          data is Map && data.containsKey('data') ? data['data'] : data;
      final posts = (listData as List)
          .map((j) => Post.fromJson(j as Map<String, dynamic>))
          .toList();
      state = FeedState(
        posts: posts,
        isLoading: false,
        hasMore: _hasNext(data, posts.length),
        page: 2,
      );
    } catch (e) {
      // Preserve existing posts on error
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore || state.isLoading) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final response = await _api.get(ApiEndpoints.feed,
          queryParameters: {'page': '${state.page}', 'limit': '$_limit'});
      final data = response.data;
      final listData =
          data is Map && data.containsKey('data') ? data['data'] : data;
      final newPosts = (listData as List)
          .map((j) => Post.fromJson(j as Map<String, dynamic>))
          .toList();
      state = state.copyWith(
        posts: [...state.posts, ...newPosts],
        isLoadingMore: false,
        hasMore: _hasNext(data, newPosts.length),
        page: state.page + 1,
      );
    } catch (_) {
      state = state.copyWith(isLoadingMore: false);
    }
  }

  bool _hasNext(dynamic body, int returnedCount) {
    if (body is Map) {
      final meta = body['meta'];
      if (meta is Map && meta.containsKey('has_next_page')) {
        return meta['has_next_page'] == true;
      }
    }
    return returnedCount >= _limit;
  }

  Future<void> refresh() => loadFeed();

  Future<void> toggleLike(String postId) async {
    // H13: Capture newLiked before optimistic update
    final original = state.posts.firstWhere((p) => p.id == postId);
    final newLiked = !original.isLiked;

    final posts = state.posts.map((p) {
      if (p.id != postId) return p;
      return p.copyWith(
        isLiked: newLiked,
        likesCount: newLiked ? p.likesCount + 1 : p.likesCount - 1,
      );
    }).toList();
    state = state.copyWith(posts: posts);

    try {
      if (newLiked) {
        await _api.post(ApiEndpoints.likePost(postId));
      } else {
        await _api.delete(ApiEndpoints.likePost(postId));
      }
    } catch (_) {}
  }

  Future<void> toggleSave(String postId) async {
    final posts = state.posts.map((p) {
      if (p.id != postId) return p;
      return p.copyWith(isSaved: !p.isSaved);
    }).toList();
    state = state.copyWith(posts: posts);

    final post = state.posts.firstWhere((p) => p.id == postId);
    try {
      if (post.isSaved) {
        await _api.post(ApiEndpoints.savePost(postId));
      } else {
        await _api.delete(ApiEndpoints.savePost(postId));
      }
    } catch (_) {}
  }

  void removePost(String postId) {
    state = state.copyWith(
      posts: state.posts.where((p) => p.id != postId).toList(),
    );
  }
}

final feedProvider = StateNotifierProvider<FeedNotifier, FeedState>((ref) {
  final api = ref.watch(apiClientProvider);
  return FeedNotifier(api);
});
