import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../models/user.dart';
import '../models/post.dart';
import '../models/highlight.dart';
import '../models/audio_track.dart';
import 'realtime_provider.dart';

// Re-export the canonical AudioTrack so legacy callers that imported it
// from this file (explore/publication_viewer/media_prepare/profile) keep
// compiling without churn. The local class duplicate was deleted 2026-05-09
// — only one AudioTrack lives in the app now: `core/models/audio_track.dart`.
export '../models/audio_track.dart' show AudioTrack;

class UserProfileState {
  final User? user;
  final List<Post> posts;
  final List<Post> savedPosts;
  final List<Highlight> highlights;
  final bool isLoading;
  final String? error;
  /// true = приватный профиль, viewer не подписан → бэк отдал 403 на /posts.
  /// Header показывается, но posts-grid заменяется на «Закрытый профиль».
  final bool isLocked;
  /// Состояние загрузки «Сохранённого» — чтобы отличать «идёт загрузка» и
  /// «ошибка» от честного «пусто» (раньше сбой сети маскировался пустым
  /// списком «Пока ничего не сохранено»).
  final bool savedPostsLoading;
  final bool savedPostsError;

  const UserProfileState({
    this.user,
    this.posts = const [],
    this.savedPosts = const [],
    this.highlights = const [],
    this.isLoading = false,
    this.error,
    this.isLocked = false,
    this.savedPostsLoading = false,
    this.savedPostsError = false,
  });

  UserProfileState copyWith({
    User? user,
    List<Post>? posts,
    List<Post>? savedPosts,
    List<Highlight>? highlights,
    bool? isLoading,
    String? error,
    bool clearError = false,
    bool? isLocked,
    bool? savedPostsLoading,
    bool? savedPostsError,
  }) {
    return UserProfileState(
      user: user ?? this.user,
      posts: posts ?? this.posts,
      savedPosts: savedPosts ?? this.savedPosts,
      highlights: highlights ?? this.highlights,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      isLocked: isLocked ?? this.isLocked,
      savedPostsLoading: savedPostsLoading ?? this.savedPostsLoading,
      savedPostsError: savedPostsError ?? this.savedPostsError,
    );
  }
}

class UserProfileNotifier extends StateNotifier<UserProfileState> {
  final String username;
  final ApiClient _api;
  final Ref _ref;
  ProviderSubscription<AsyncValue<RealtimeEvent>>? _wsSub;

  UserProfileNotifier(this.username, this._api, this._ref)
      : super(const UserProfileState()) {
    loadProfile();
    _listenPresence();
  }

  /// Live-update isOnline / lastSeenAt при connect/disconnect peer'а через WS.
  /// Бэк broadcast'ит user.presence всем онлайн-юзерам; здесь фильтруем по
  /// state.user.id и мутируем поля.
  void _listenPresence() {
    _wsSub = _ref.listen<AsyncValue<RealtimeEvent>>(
      realtimeEventsProvider,
      (prev, next) {
        next.whenData((evt) {
          if (evt.type != 'user.presence' || evt.payload is! Map) return;
          final p = (evt.payload as Map).cast<String, dynamic>();
          final userId = p['user_id']?.toString() ?? '';
          final currentUser = state.user;
          if (currentUser == null || userId.isEmpty) return;
          if (currentUser.id != userId) return; // не наш юзер — игнор
          final isOnline = (p['is_online'] ?? false) as bool;
          final lastSeen = p['last_seen_at'] != null
              ? DateTime.tryParse(p['last_seen_at'].toString())
              : null;
          state = state.copyWith(
            user: currentUser.copyWith(
              isOnline: isOnline,
              lastSeenAt: lastSeen,
            ),
          );
        });
      },
    );
  }

  @override
  void dispose() {
    _wsSub?.close();
    super.dispose();
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
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      // User-эндпоинт обязательный — без него вообще профиль не рендерится.
      final userResp = await _api.get(ApiEndpoints.userProfile(username));
      final user = User.fromJson(_extractMap(userResp.data));

      // Posts: если приватный профиль и viewer не подписан — backend
      // отдаёт 403, тогда показываем locked-placeholder, остальной UI live.
      List<Post> posts = const [];
      bool isLocked = false;
      try {
        final postsResp = await _api.get(ApiEndpoints.userPosts(username));
        posts = _extractList(postsResp.data)
            .map((j) => Post.fromJson(j as Map<String, dynamic>))
            .toList();
      } on DioException catch (e) {
        if (e.response?.statusCode == 403) {
          isLocked = true;
        } else {
          rethrow;
        }
      }

      List<Highlight> highlights = const [];
      try {
        final hlResp = await _api.get(ApiEndpoints.userHighlights(username));
        highlights = _extractList(hlResp.data)
            .map((j) => Highlight.fromJson(j as Map<String, dynamic>))
            .toList();
      } catch (_) {}

      if (!mounted) return;
      state = UserProfileState(
        user: user,
        posts: posts,
        highlights: highlights,
        isLocked: isLocked,
      );
    } catch (e) {
      if (mounted) state = UserProfileState(error: e.toString());
    }
  }

  Future<void> loadSavedPosts() async {
    if (mounted) {
      state = state.copyWith(savedPostsLoading: true, savedPostsError: false);
    }
    try {
      final resp = await _api.get(ApiEndpoints.userSavedPosts(username));
      final posts = _extractList(resp.data)
          .map((j) => Post.fromJson(j as Map<String, dynamic>))
          .toList();
      if (mounted) {
        state = state.copyWith(
            savedPosts: posts, savedPostsLoading: false, savedPostsError: false);
      }
    } catch (_) {
      // Ошибку показываем как ошибку, а не как «пусто».
      if (mounted) {
        state = state.copyWith(savedPostsLoading: false, savedPostsError: true);
      }
    }
  }

  /// Returns a friendly Russian error string on failure, null on success.
  /// Most callers ignore the result and rely on optimistic UI rollback.
  Future<String?> toggleFollow() async {
    final user = state.user;
    if (user == null) return null;

    final wasFollowing = user.isFollowing;
    final wasPending = user.hasPendingFollowRequest;

    // Три состояния → три варианта оптимистичного апдейта:
    // 1. Подписан → жмём «Отписаться» → DELETE → followersCount-1.
    // 2. Запрос отправлен → жмём «Отменить» → DELETE → флаг pending=false.
    // 3. Не подписан/не отправлено → жмём «Подписаться» → POST. Оптимистично
    //    флипаем в isFollowing=true + followersCount+1, после ответа если
    //    приватный → revert на pending=true (без счётчика).
    if (wasFollowing) {
      state = state.copyWith(
        user: user.copyWith(
          isFollowing: false,
          followersCount: user.followersCount - 1,
        ),
      );
    } else if (wasPending) {
      state = state.copyWith(
        user: user.copyWith(hasPendingFollowRequest: false),
      );
    } else {
      state = state.copyWith(
        user: user.copyWith(
          isFollowing: true,
          followersCount: user.followersCount + 1,
        ),
      );
    }

    try {
      if (wasFollowing || wasPending) {
        // DELETE — backend сам разруливает: если pending → отменяет запрос,
        // если follow → unfollow + декремент counter'а на бэке.
        await _api.delete(ApiEndpoints.followUser(username));
      } else {
        final resp = await _api.post(ApiEndpoints.followUser(username));
        final raw = resp.data;
        final status = raw is Map
            ? (raw['data'] is Map
                ? (raw['data'] as Map)['status']?.toString()
                : null)
            : null;
        if (status == 'requested' && mounted) {
          // Приватный → запрос отправлен. Откатываем optimistic isFollowing
          // и счётчик, ставим pending=true — поверх ТЕКУЩЕГО state.user,
          // чтобы не потерять presence-обновление, пришедшее за время await.
          final cur = state.user ?? user;
          state = state.copyWith(
            user: cur.copyWith(
              isFollowing: false,
              followersCount: user.followersCount,
              hasPendingFollowRequest: true,
            ),
          );
        }
      }
      return null;
    } on DioException catch (e) {
      // Откат по follow-полям поверх актуального state.user (а не замена на
      // устаревший снапшот `user`) — иначе теряется presence-обновление,
      // прилетевшее по WS во время запроса.
      if (mounted) {
        final cur = state.user ?? user;
        state = state.copyWith(
          user: cur.copyWith(
            isFollowing: wasFollowing,
            hasPendingFollowRequest: wasPending,
            followersCount: user.followersCount,
          ),
        );
      }
      if (e.response?.statusCode == 403) {
        return 'Нельзя подписаться: пользователь вас заблокировал или вы его';
      }
      return apiErrorMessage(e);
    } catch (_) {
      if (mounted) {
        final cur = state.user ?? user;
        state = state.copyWith(
          user: cur.copyWith(
            isFollowing: wasFollowing,
            hasPendingFollowRequest: wasPending,
            followersCount: user.followersCount,
          ),
        );
      }
      return 'Что-то пошло не так';
    }
  }
}

// autoDispose: without it this family kept one notifier per visited username
// alive for the whole app lifetime, each holding a realtimeEvents presence
// subscription. The notifier's dispose() cancels its _wsSub, so autoDispose
// reclaims both the notifier and the subscription once no widget watches it.
final userProfileProvider = StateNotifierProvider.autoDispose.family<
    UserProfileNotifier, UserProfileState, String>((ref, username) {
  final api = ref.watch(apiClientProvider);
  return UserProfileNotifier(username, api, ref);
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

  /// Дебаунс-поиск. Намеренно void: раньше метод возвращал Future от
  /// Completer'а, который никогда не завершался, если таймер отменялся
  /// повторным вводом — любой `await search(...)` завис бы навсегда.
  void search(String query) {
    _debounceTimer?.cancel();
    if (query.trim().isEmpty) {
      state = const SearchState();
      return;
    }
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      _doSearch(query);
    });
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

// Trending tag model
class TrendingTag {
  final String tag;
  final int postsCount;

  const TrendingTag({required this.tag, required this.postsCount});

  factory TrendingTag.fromJson(Map<String, dynamic> json) {
    return TrendingTag(
      tag: json['tag']?.toString() ?? '',
      // BUG-20 паттерн: агрегаты могут прийти double'ом — прямой `as int`
      // ронял парсинг трендов CastError'ом.
      postsCount: (json['posts_count'] as num?)?.toInt() ?? 0,
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
    bool clearError = false,
    int? page,
  }) {
    return ExploreState(
      posts: posts ?? this.posts,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : (error ?? this.error),
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
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final r = await _api.get(ApiEndpoints.postsExplore,
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
      final r = await _api.get(ApiEndpoints.postsExplore,
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

  /// Optimistic like toggle. Mirrors FeedNotifier behaviour so the same
  /// post seen in PublicationViewer reflects the updated state instantly.
  Future<void> toggleLike(String postId) async {
    final idx = state.posts.indexWhere((p) => p.id == postId);
    if (idx < 0) return;
    final original = state.posts[idx];
    final newLiked = !original.isLiked;
    final updated = original.copyWith(
      isLiked: newLiked,
      likesCount: newLiked
          ? original.likesCount + 1
          : (original.likesCount > 0 ? original.likesCount - 1 : 0),
    );
    state = state.copyWith(
      posts: [
        ...state.posts.sublist(0, idx),
        updated,
        ...state.posts.sublist(idx + 1),
      ],
    );
    try {
      if (newLiked) {
        await _api.post(ApiEndpoints.likePost(postId));
      } else {
        await _api.delete(ApiEndpoints.likePost(postId));
      }
    } catch (_) {
      // Roll back on failure.
      final i = state.posts.indexWhere((p) => p.id == postId);
      if (i >= 0) {
        state = state.copyWith(
          posts: [
            ...state.posts.sublist(0, i),
            original,
            ...state.posts.sublist(i + 1),
          ],
        );
      }
    }
  }

  Future<void> toggleSave(String postId) async {
    final idx = state.posts.indexWhere((p) => p.id == postId);
    if (idx < 0) return;
    final original = state.posts[idx];
    final updated = original.copyWith(isSaved: !original.isSaved);
    state = state.copyWith(
      posts: [
        ...state.posts.sublist(0, idx),
        updated,
        ...state.posts.sublist(idx + 1),
      ],
    );
    try {
      if (updated.isSaved) {
        await _api.post(ApiEndpoints.savePost(postId));
      } else {
        await _api.delete(ApiEndpoints.savePost(postId));
      }
    } catch (_) {
      final i = state.posts.indexWhere((p) => p.id == postId);
      if (i >= 0) {
        state = state.copyWith(
          posts: [
            ...state.posts.sublist(0, i),
            original,
            ...state.posts.sublist(i + 1),
          ],
        );
      }
    }
  }

  /// Гарантирует, что пост с [postId] есть в ленте (см.
  /// ContentFeedNotifier.ensurePost — тот же сценарий для вьюера).
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

  /// Заменить пост обновлённой версией (мутация пришла из PostCard или
  /// другого экрана). No-op, если поста здесь нет.
  void applyPostUpdate(Post updated) {
    final idx = state.posts.indexWhere((p) => p.id == updated.id);
    if (idx < 0) return;
    state = state.copyWith(
      posts: [
        ...state.posts.sublist(0, idx),
        updated,
        ...state.posts.sublist(idx + 1),
      ],
    );
  }

  /// Сдвиг счётчика комментариев после add/delete комментария.
  void adjustCommentsCount(String postId, int delta) {
    final idx = state.posts.indexWhere((p) => p.id == postId);
    if (idx < 0) return;
    final p = state.posts[idx];
    applyPostUpdate(p.copyWith(
      commentsCount: (p.commentsCount + delta).clamp(0, 1 << 31),
    ));
  }

}

final exploreProvider =
    StateNotifierProvider<ExploreNotifier, ExploreState>((ref) {
  final api = ref.watch(apiClientProvider);
  return ExploreNotifier(api);
});
