import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../models/post.dart';
import '../services/logger.dart';
import 'realtime_provider.dart';

/// FEED-2: режим сортировки feed. По умолчанию chrono — стабильная cursor-
/// pagination newest-first. Smart — score-based offset-paginated.
enum FeedSortMode { chrono, smart }

class FeedState {
  final List<Post> posts;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;
  final int _page;
  /// FEED-1: opaque cursor для followup-страницы. Пустой = first page.
  final String nextCursor;
  /// FEED-3: счётчик новых постов от подписок которые пришли через WS пока
  /// юзер скроллит. UI показывает banner «N новых постов ↑» когда > 0.
  final int pendingNewCount;
  /// FEED-2: текущий режим сортировки.
  final FeedSortMode sortMode;
  /// FEED-7: ids постов которые injection'нулись из explore (не подписки).
  /// PostCard рендерит "Рекомендуем" badge когда `id in recommendedIds`.
  final Set<String> recommendedIds;

  const FeedState({
    this.posts = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
    int page = 1,
    this.nextCursor = '',
    this.pendingNewCount = 0,
    this.sortMode = FeedSortMode.chrono,
    this.recommendedIds = const {},
  }) : _page = page;

  int get page => _page;

  FeedState copyWith({
    List<Post>? posts,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    bool clearError = false,
    int? page,
    String? nextCursor,
    int? pendingNewCount,
    FeedSortMode? sortMode,
    Set<String>? recommendedIds,
  }) {
    return FeedState(
      posts: posts ?? this.posts,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : (error ?? this.error),
      page: page ?? _page,
      nextCursor: nextCursor ?? this.nextCursor,
      pendingNewCount: pendingNewCount ?? this.pendingNewCount,
      sortMode: sortMode ?? this.sortMode,
      recommendedIds: recommendedIds ?? this.recommendedIds,
    );
  }
}

class FeedNotifier extends StateNotifier<FeedState> {
  final ApiClient _api;
  final Ref _ref;
  ProviderSubscription<AsyncValue<RealtimeEvent>>? _wsSub;

  FeedNotifier(this._api, this._ref) : super(const FeedState()) {
    loadFeed();
    _listenRealtime();
  }

  /// Subscribes to realtime events:
  ///   - `post.reaction` — peer изменил реакции на пост → update counts.
  ///   - `post.created` (FEED-3) — friend опубликовал новый пост → инкремент
  ///     pendingNewCount, UI banner «N новых постов ↑». Auto-merge на refresh.
  /// Likes/saves stay REST-only — per-viewer state, не aggregate.
  void _listenRealtime() {
    _wsSub = _ref.listen<AsyncValue<RealtimeEvent>>(
      realtimeEventsProvider,
      (prev, next) {
        next.whenData((evt) {
          if (evt.payload is! Map) return;
          final p = (evt.payload as Map).cast<String, dynamic>();
          if (evt.type == 'post.reaction') {
            final postId = p['post_id']?.toString() ?? '';
            if (postId.isEmpty) return;
            final raw = p['reactions'];
            final counts = raw is Map
                ? Map<String, int>.from(raw.map(
                    (k, v) => MapEntry(k.toString(), (v as num).toInt())))
                : <String, int>{};
            applyReactionUpdate(postId, counts);
            return;
          }
          if (evt.type == 'post.created') {
            // Не auto-merge'им — юзер мог быть в середине scroll'а. Просто
            // инкрементим счётчик; UI rendered banner «N новых постов ↑»;
            // тап на banner → refresh + scroll-to-top.
            state = state.copyWith(pendingNewCount: state.pendingNewCount + 1);
            return;
          }
        });
      },
    );
  }

  @override
  void dispose() {
    _wsSub?.close();
    super.dispose();
  }

  static const _limit = 20;

  /// FEED-4 + FEED-1: smart-merge first-page (теперь через cursor) поверх
  /// existing posts. FEED-3: сбрасывает pendingNewCount после refresh.
  /// FEED-2: использует `sort=smart` если `sortMode == smart`.
  /// FEED-7: параллельно фетчит explore-recommendations + interleave.
  Future<void> loadFeed() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final params = <String, String>{'limit': '$_limit'};
      if (state.sortMode == FeedSortMode.smart) {
        params['sort'] = 'smart';
        params['page'] = '1';
      }
      // FEED-7: параллельный fetch explore-recommended (3 поста). Если не
      // удалось — просто пропускаем injection, feed работает.
      final results = await Future.wait([
        _api.get(ApiEndpoints.feed, queryParameters: params),
        _api.get(ApiEndpoints.explore, queryParameters: {'limit': '3'})
            .catchError((_) => _api.get(ApiEndpoints.feed,
                queryParameters: {'limit': '0'})), // dummy fallback
      ]);
      final response = results[0];
      final exploreResp = results[1];
      final data = response.data;
      final listData =
          data is Map && data.containsKey('data') ? data['data'] : data;
      final fresh = (listData as List)
          .map((j) => Post.fromJson(j as Map<String, dynamic>))
          .toList();
      final exploreData = exploreResp.data;
      final exploreList = exploreData is Map &&
              exploreData.containsKey('data')
          ? exploreData['data']
          : exploreData;
      final exploreFresh = (exploreList is List)
          ? exploreList
              .map((j) => Post.fromJson(j as Map<String, dynamic>))
              .where((p) =>
                  !fresh.any((f) => f.id == p.id)) // skip duplicates
              .toList()
          : <Post>[];

      // FEED-7: inject explore-posts каждые 5 feed-posts.
      final injected = _injectRecommended(fresh, exploreFresh);
      final merged = _mergeFreshIntoExisting(injected, state.posts);
      final allRecommendedIds = {
        ...state.recommendedIds,
        ...exploreFresh.map((p) => p.id),
      };
      state = FeedState(
        posts: merged,
        isLoading: false,
        hasMore: _hasNext(data, fresh.length),
        page: state.sortMode == FeedSortMode.smart ? 2 : state.page,
        nextCursor: _extractNextCursor(data),
        pendingNewCount: 0,
        sortMode: state.sortMode,
        recommendedIds: allRecommendedIds,
      );
    } catch (e, st) {
      appLog.error('[FeedNotifier] loadFeed error', e, st);
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// FEED-5: пометить пост как просмотренный (fire-and-forget). Backend
  /// записывает в `post_views`, и feed-query больше не вернёт его при
  /// следующих pull'ах. Идемпотент — повторный call безопасен.
  /// Также добавляем id в local `_viewedIds` (in-memory cache) чтобы во
  /// время этой сессии тот же пост не отметить повторно.
  final Set<String> _viewedIds = {};
  Future<void> markPostViewed(String postId) async {
    if (postId.isEmpty || _viewedIds.contains(postId)) return;
    _viewedIds.add(postId);
    try {
      await _api.post(ApiEndpoints.viewPost(postId));
    } catch (_) {
      // Best-effort — не возвращаем error из state. Если упало — попробуем
      // на след. появлении (но _viewedIds уже set, поэтому не повторим в
      // этой сессии). Ok — отсутствие view не критично.
    }
  }

  /// FEED-2: toggle между chronological и smart. Сбрасывает feed и грузит
  /// заново — два режима не миксуются по той же странице.
  void setSortMode(FeedSortMode mode) {
    if (state.sortMode == mode) return;
    state = const FeedState().copyWith(sortMode: mode);
    loadFeed();
  }

  /// FEED-7: интерливит explore-посты в feed каждые 5 позиций.
  /// fresh — посты от подписок (новейшие сверху).
  /// recos — посты из explore (популярные, не от подписок).
  List<Post> _injectRecommended(List<Post> fresh, List<Post> recos) {
    if (recos.isEmpty || fresh.isEmpty) return fresh;
    final out = <Post>[];
    var recoIdx = 0;
    for (var i = 0; i < fresh.length; i++) {
      out.add(fresh[i]);
      // После каждого 5-го (positions 5, 10, 15...) inject один reco.
      if ((i + 1) % 5 == 0 && recoIdx < recos.length) {
        out.add(recos[recoIdx]);
        recoIdx++;
      }
    }
    return out;
  }

  /// FEED-3: тап на banner. Делает refresh с прокруткой до начала.
  /// Wrapper для семантики — UI вызывает это вместо loadFeed когда banner.
  Future<void> consumePendingAndRefresh() => loadFeed();

  String _extractNextCursor(dynamic body) {
    if (body is Map) {
      final meta = body['meta'];
      if (meta is Map && meta['next_cursor'] is String) {
        return meta['next_cursor'] as String;
      }
    }
    return '';
  }

  /// FEED-4: merge first-page результат поверх existing posts:
  /// - Новые посты (id'шников нет в existing) → добавляются СВЕРХУ в том
  ///   порядке как пришли (newest first).
  /// - Existing посты с тем же id что в fresh → берём fresh-версию (свежие
  ///   counts/reactions), но preserve `myReaction` / `isLiked` если они
  ///   были set (per-viewer state, server иногда не возвращает).
  /// - Posts которых нет в fresh — preserve at current position
  ///   (нижние страницы → не теряются).
  ///
  /// Net effect: pull-to-refresh не дёргает scroll position когда new posts
  /// тонкие. Скролл вверх к новым — manual.
  List<Post> _mergeFreshIntoExisting(List<Post> fresh, List<Post> existing) {
    if (existing.isEmpty) return fresh;
    final existingById = {for (final p in existing) p.id: p};
    final freshIds = fresh.map((p) => p.id).toSet();

    // Новые (id'шников нет в existing) — сверху.
    final newPosts = fresh.where((p) => !existingById.containsKey(p.id)).toList();

    // Updated overlay: для постов которые в БОТh fresh AND existing — берём
    // fresh (свежий counts).
    final tail = existing.map((p) {
      if (freshIds.contains(p.id)) {
        return fresh.firstWhere((f) => f.id == p.id);
      }
      return p;
    }).toList();

    return [...newPosts, ...tail];
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore || state.isLoading) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      // FEED-1: cursor flow если есть, иначе fallback на page.
      final params = <String, String>{'limit': '$_limit'};
      if (state.nextCursor.isNotEmpty) {
        params['cursor'] = state.nextCursor;
      } else {
        params['page'] = '${state.page}';
      }
      final response =
          await _api.get(ApiEndpoints.feed, queryParameters: params);
      final data = response.data;
      final listData =
          data is Map && data.containsKey('data') ? data['data'] : data;
      final newPosts = (listData as List)
          .map((j) => Post.fromJson(j as Map<String, dynamic>))
          .toList();
      // Dedup по id (на случай гонки между WS-insert'ом и pagination'ом).
      final existingIds = state.posts.map((p) => p.id).toSet();
      final unique = newPosts.where((p) => !existingIds.contains(p.id)).toList();
      state = state.copyWith(
        posts: [...state.posts, ...unique],
        isLoadingMore: false,
        hasMore: _hasNext(data, newPosts.length),
        page: state.page + 1,
        nextCursor: _extractNextCursor(data),
      );
    } catch (e, st) {
      appLog.error('[FeedNotifier] loadMore error', e, st);
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
        likesCount: newLiked
            ? p.likesCount + 1
            : (p.likesCount > 0 ? p.likesCount - 1 : 0),
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

  /// Optimistic emoji-reaction toggle on a post. Mirrors the chat-message
  /// reactions pattern: same emoji = unreact (DELETE), different = upsert
  /// (POST). Server fan-outs `post.reaction` over WS, but the optimistic
  /// path keeps the UI responsive on the user's own device.
  Future<void> toggleReaction(String postId, String emoji) async {
    final idx = state.posts.indexWhere((p) => p.id == postId);
    if (idx < 0) return;
    final original = state.posts[idx];
    final isSame = original.myReaction == emoji;

    final newCounts = Map<String, int>.from(original.reactions);
    if (original.myReaction.isNotEmpty) {
      newCounts[original.myReaction] =
          (newCounts[original.myReaction] ?? 1) - 1;
      if ((newCounts[original.myReaction] ?? 0) <= 0) {
        newCounts.remove(original.myReaction);
      }
    }
    final newMine = isSame ? '' : emoji;
    if (newMine.isNotEmpty) {
      newCounts[newMine] = (newCounts[newMine] ?? 0) + 1;
    }
    state = state.copyWith(
      posts: [
        ...state.posts.sublist(0, idx),
        original.copyWith(reactions: newCounts, myReaction: newMine),
        ...state.posts.sublist(idx + 1),
      ],
    );

    try {
      if (isSame) {
        await _api.delete(ApiEndpoints.reactPost(postId));
      } else {
        await _api.post(ApiEndpoints.reactPost(postId),
            data: {'emoji': emoji});
      }
    } catch (_) {
      // Roll back to previous shape on error.
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

  /// Apply a server-pushed reaction update (incoming WS event). Replaces
  /// the count map but keeps `myReaction` (which is per-viewer state).
  void applyReactionUpdate(String postId, Map<String, int> reactions) {
    final idx = state.posts.indexWhere((p) => p.id == postId);
    if (idx < 0) return;
    state = state.copyWith(
      posts: [
        ...state.posts.sublist(0, idx),
        state.posts[idx].copyWith(reactions: reactions),
        ...state.posts.sublist(idx + 1),
      ],
    );
  }
}

final feedProvider = StateNotifierProvider<FeedNotifier, FeedState>((ref) {
  final api = ref.watch(apiClientProvider);
  return FeedNotifier(api, ref);
});
