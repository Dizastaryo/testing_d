import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../models/user.dart';
import '../models/post.dart';
import '../models/highlight.dart';

class UserProfileState {
  final User? user;
  final List<Post> posts;
  final List<Post> savedPosts;
  final List<Post> taggedPosts;
  final List<Highlight> highlights;
  final bool isLoading;
  final String? error;

  const UserProfileState({
    this.user,
    this.posts = const [],
    this.savedPosts = const [],
    this.taggedPosts = const [],
    this.highlights = const [],
    this.isLoading = false,
    this.error,
  });

  UserProfileState copyWith({
    User? user,
    List<Post>? posts,
    List<Post>? savedPosts,
    List<Post>? taggedPosts,
    List<Highlight>? highlights,
    bool? isLoading,
    String? error,
  }) {
    return UserProfileState(
      user: user ?? this.user,
      posts: posts ?? this.posts,
      savedPosts: savedPosts ?? this.savedPosts,
      taggedPosts: taggedPosts ?? this.taggedPosts,
      highlights: highlights ?? this.highlights,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class UserProfileNotifier extends StateNotifier<UserProfileState> {
  final String username;
  final ApiClient _api;

  UserProfileNotifier(this.username, this._api) : super(const UserProfileState()) {
    loadProfile();
  }

  List<dynamic> _extractList(dynamic data) {
    if (data is Map && data.containsKey('data')) {
      final d = data['data'];
      if (d is List) return d;
      return [];
    }
    if (data is List) return data;
    return [];
  }

  Map<String, dynamic> _extractMap(dynamic data) {
    if (data is Map && data.containsKey('data')) {
      return data['data'] as Map<String, dynamic>;
    }
    if (data is Map<String, dynamic>) return data;
    return {};
  }

  Future<void> loadProfile() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final userFuture = _api.get(ApiEndpoints.userProfile(username));
      final postsFuture = _api.get(ApiEndpoints.userPosts(username));

      final results = await Future.wait([userFuture, postsFuture]);

      final userResp = results[0];
      final postsResp = results[1];

      final user = User.fromJson(_extractMap(userResp.data));
      final posts = _extractList(postsResp.data)
          .map((j) => Post.fromJson(j as Map<String, dynamic>))
          .toList();

      List<Highlight> highlights = [];
      try {
        final hlResp = await _api.get(ApiEndpoints.userHighlights(username));
        highlights = _extractList(hlResp.data)
            .map((j) => Highlight.fromJson(j as Map<String, dynamic>))
            .toList();
      } catch (_) {}

      state = UserProfileState(
        user: user,
        posts: posts,
        highlights: highlights,
      );
    } catch (e) {
      state = UserProfileState(error: e.toString());
    }
  }

  Future<void> loadSavedPosts() async {
    try {
      final resp = await _api.get(ApiEndpoints.userSavedPosts(username));
      final posts = _extractList(resp.data)
          .map((j) => Post.fromJson(j as Map<String, dynamic>))
          .toList();
      state = state.copyWith(savedPosts: posts);
    } catch (_) {
      state = state.copyWith(savedPosts: []);
    }
  }

  Future<void> loadTaggedPosts() async {
    state = state.copyWith(taggedPosts: []);
  }

  Future<void> toggleFollow() async {
    final user = state.user;
    if (user == null) return;

    final wasFollowing = user.isFollowing;
    state = state.copyWith(
      user: user.copyWith(
        isFollowing: !wasFollowing,
        followersCount: wasFollowing
            ? user.followersCount - 1
            : user.followersCount + 1,
      ),
    );

    try {
      if (wasFollowing) {
        await _api.delete(ApiEndpoints.followUser(username));
      } else {
        await _api.post(ApiEndpoints.followUser(username));
      }
    } catch (_) {
      state = state.copyWith(user: user);
    }
  }
}

final userProfileProvider = StateNotifierProvider.family<
    UserProfileNotifier, UserProfileState, String>((ref, username) {
  final api = ref.watch(apiClientProvider);
  return UserProfileNotifier(username, api);
});

// Search provider
class SearchState {
  final List<User> users;
  final List<Post> posts;
  final bool isLoading;
  final String query;

  const SearchState({
    this.users = const [],
    this.posts = const [],
    this.isLoading = false,
    this.query = '',
  });
}

class SearchNotifier extends StateNotifier<SearchState> {
  final ApiClient _api;
  Timer? _debounceTimer;

  SearchNotifier(this._api) : super(const SearchState());

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  String _searchType = 'all';

  void setSearchType(String type) {
    _searchType = type;
    if (state.query.isNotEmpty) {
      _doSearch(state.query);
    }
  }

  Future<void> search(String query) async {
    _debounceTimer?.cancel();
    if (query.trim().isEmpty) {
      state = const SearchState();
      return;
    }
    final completer = Completer<void>();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      _doSearch(query).then((_) => completer.complete());
    });
    return completer.future;
  }

  Future<void> _doSearch(String query) async {
    if (query.trim().isEmpty) {
      state = const SearchState();
      return;
    }
    state = SearchState(query: query, isLoading: true);
    try {
      final params = <String, dynamic>{'q': query};
      if (_searchType != 'all') {
        params['type'] = _searchType;
      }
      final resp = await _api.get(ApiEndpoints.search, queryParameters: params);
      final data = resp.data;
      final resultData = data is Map && data.containsKey('data') ? data['data'] : data;

      List<User> users = [];
      List<Post> posts = [];

      if (resultData is Map) {
        if (resultData['users'] is List) {
          users = (resultData['users'] as List)
              .map((j) => User.fromJson(j as Map<String, dynamic>))
              .toList();
        }
        if (resultData['posts'] is List) {
          posts = (resultData['posts'] as List)
              .map((j) => Post.fromJson(j as Map<String, dynamic>))
              .toList();
        }
      }

      state = SearchState(users: users, posts: posts, query: query);
    } catch (_) {
      state = SearchState(query: query);
    }
  }

  void clear() => state = const SearchState();
}

final searchProvider = StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  final api = ref.watch(apiClientProvider);
  return SearchNotifier(api);
});

// Explore grid posts provider
final explorePostsProvider = FutureProvider<List<Post>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final resp = await api.get(ApiEndpoints.explore);
  final data = resp.data;
  final listData = data is Map && data.containsKey('data') ? data['data'] : data;
  if (listData is List) {
    return listData.map((j) => Post.fromJson(j as Map<String, dynamic>)).toList();
  }
  return [];
});
