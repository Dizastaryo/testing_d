import 'dart:async';
import 'package:dio/dio.dart';
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

  /// Returns a friendly Russian error string on failure, null on success.
  /// Most callers ignore the result and rely on optimistic UI rollback.
  Future<String?> toggleFollow() async {
    final user = state.user;
    if (user == null) return null;

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
        final resp = await _api.post(ApiEndpoints.followUser(username));
        final raw = resp.data;
        final status = raw is Map
            ? (raw['data'] is Map
                ? (raw['data'] as Map)['status']?.toString()
                : null)
            : null;
        if (status == 'requested') {
          // Private account: we sent a request, no follow row yet. Revert
          // the optimistic +1 + isFollowing flip so the UI tells the truth.
          state = state.copyWith(user: user);
          return 'Запрос отправлен. Ждите подтверждения.';
        }
      }
      return null;
    } on DioException catch (e) {
      state = state.copyWith(user: user);
      if (e.response?.statusCode == 403) {
        return 'Нельзя подписаться: пользователь вас заблокировал или вы его';
      }
      return apiErrorMessage(e);
    } catch (_) {
      state = state.copyWith(user: user);
      return 'Что-то пошло не так';
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

// Audio track model
class AudioTrack {
  final String id;
  final String title;
  final String artist;
  final String coverUrl;
  final String audioUrl;
  final int durationSeconds;
  final int usesCount;
  final String genre;

  const AudioTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.coverUrl,
    required this.audioUrl,
    this.durationSeconds = 0,
    this.usesCount = 0,
    this.genre = '',
  });

  factory AudioTrack.fromJson(Map<String, dynamic> json) {
    final baseUrl = ApiEndpoints.baseUrl.replaceAll('/api/v1', '');
    String toAbs(String url) =>
        url.startsWith('/') ? baseUrl + url : url;
    return AudioTrack(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      artist: json['artist']?.toString() ?? '',
      coverUrl: toAbs(json['cover_url']?.toString() ?? ''),
      audioUrl: toAbs(json['audio_url']?.toString() ?? ''),
      durationSeconds: (json['duration_seconds'] ?? 0) as int,
      usesCount: (json['uses_count'] ?? 0) as int,
      genre: json['genre']?.toString() ?? '',
    );
  }
}

// Trending tag model
class TrendingTag {
  final String tag;
  final int postsCount;

  const TrendingTag({required this.tag, required this.postsCount});

  factory TrendingTag.fromJson(Map<String, dynamic> json) {
    return TrendingTag(
      tag: json['tag']?.toString() ?? '',
      postsCount: (json['posts_count'] ?? 0) as int,
    );
  }
}

// Audio tracks provider
final audioTracksProvider = FutureProvider<List<AudioTrack>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final resp = await api.get(ApiEndpoints.audioTracks);
  final data = resp.data;
  final listData = data is Map && data.containsKey('data') ? data['data'] : data;
  if (listData is List) {
    return listData.map((j) => AudioTrack.fromJson(j as Map<String, dynamic>)).toList();
  }
  return [];
});

// Trending tags provider
final trendingTagsProvider = FutureProvider<List<TrendingTag>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final resp = await api.get(ApiEndpoints.trendingTags);
  final data = resp.data;
  final listData = data is Map && data.containsKey('data') ? data['data'] : data;
  if (listData is List) {
    return listData.map((j) => TrendingTag.fromJson(j as Map<String, dynamic>)).toList();
  }
  return [];
});

// Explore grid posts provider with pagination.
class ExploreState {
  final List<Post> posts;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;
  final int page;

  const ExploreState({
    this.posts = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
    this.page = 1,
  });

  ExploreState copyWith({
    List<Post>? posts,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    int? page,
  }) {
    return ExploreState(
      posts: posts ?? this.posts,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: error,
      page: page ?? this.page,
    );
  }
}

class ExploreNotifier extends StateNotifier<ExploreState> {
  static const _limit = 20;
  final ApiClient _api;
  ExploreNotifier(this._api) : super(const ExploreState()) {
    refresh();
  }

  Future<void> refresh() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final r = await _api.get(ApiEndpoints.explore,
          queryParameters: {'page': '1', 'limit': '$_limit'});
      final data = r.data is Map && r.data.containsKey('data')
          ? r.data['data']
          : r.data;
      final list = data is List
          ? data.map((j) => Post.fromJson(j as Map<String, dynamic>)).toList()
          : <Post>[];
      final hasNext = _hasNext(r.data, list.length);
      state = ExploreState(posts: list, isLoading: false, hasMore: hasNext, page: 2);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore || state.isLoading) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final r = await _api.get(ApiEndpoints.explore,
          queryParameters: {'page': '${state.page}', 'limit': '$_limit'});
      final data = r.data is Map && r.data.containsKey('data')
          ? r.data['data']
          : r.data;
      final list = data is List
          ? data.map((j) => Post.fromJson(j as Map<String, dynamic>)).toList()
          : <Post>[];
      final hasNext = _hasNext(r.data, list.length);
      state = state.copyWith(
        posts: [...state.posts, ...list],
        isLoadingMore: false,
        hasMore: hasNext,
        page: state.page + 1,
      );
    } catch (_) {
      state = state.copyWith(isLoadingMore: false);
    }
  }

  bool _hasNext(dynamic body, int returnedCount) {
    // Prefer server-reported has_next_page; fall back to "got full page".
    if (body is Map) {
      final meta = body['meta'];
      if (meta is Map && meta.containsKey('has_next_page')) {
        return meta['has_next_page'] == true;
      }
    }
    return returnedCount >= _limit;
  }
}

final exploreProvider =
    StateNotifierProvider<ExploreNotifier, ExploreState>((ref) {
  final api = ref.watch(apiClientProvider);
  return ExploreNotifier(api);
});
