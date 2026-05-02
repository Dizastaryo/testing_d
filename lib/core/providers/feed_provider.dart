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

  Future<void> loadFeed() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _api.get(ApiEndpoints.feed, queryParameters: {'page': '1', 'limit': '20'});
      final data = response.data;
      final listData = data is Map && data.containsKey('data') ? data['data'] : data;
      final posts = (listData as List).map((j) => Post.fromJson(j as Map<String, dynamic>)).toList();
      state = FeedState(
        posts: posts,
        isLoading: false,
        hasMore: posts.length >= 20,
        page: 2,
      );
    } catch (e) {
      state = FeedState(
        posts: [],
        isLoading: false,
        error: e.toString(),
        hasMore: false,
      );
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final response = await _api.get(ApiEndpoints.feed, queryParameters: {'page': '${state.page}', 'limit': '20'});
      final data = response.data;
      final listData = data is Map && data.containsKey('data') ? data['data'] : data;
      final newPosts = (listData as List).map((j) => Post.fromJson(j as Map<String, dynamic>)).toList();
      state = state.copyWith(
        posts: [...state.posts, ...newPosts],
        isLoadingMore: false,
        hasMore: newPosts.length >= 20,
        page: state.page + 1,
      );
    } catch (_) {
      state = state.copyWith(isLoadingMore: false);
    }
  }

  Future<void> refresh() => loadFeed();

  Future<void> toggleLike(String postId) async {
    final posts = state.posts.map((p) {
      if (p.id != postId) return p;
      final newLiked = !p.isLiked;
      return p.copyWith(
        isLiked: newLiked,
        likesCount: newLiked ? p.likesCount + 1 : p.likesCount - 1,
      );
    }).toList();
    state = state.copyWith(posts: posts);

    final post = state.posts.firstWhere((p) => p.id == postId);
    try {
      if (post.isLiked) {
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
