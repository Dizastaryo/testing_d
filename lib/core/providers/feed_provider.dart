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
  ///   - `post.created` (FEED-3) — friend опубликовал новый пост → инкремент
  ///     pendingNewCount, UI banner «N новых постов ↑». Auto-merge на refresh.
  /// Likes/saves stay REST-only — per-viewer state, не aggregate.
  void _listenRealtime() {
    _wsSub = _ref.listen<AsyncValue<RealtimeEvent>>(
      realtimeEventsProvider,
      (prev, next) {
        next.whenData((evt) {
          if (evt.payload is! Map) return;
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
      final response = await _api.get(ApiEndpoints.feed, queryParameters: params);
      final data = response.data;
      final listData =
          data is Map && data.containsKey('data') ? data['data'] : data;
      final fresh = (listData is List ? listData : <dynamic>[])
          .map((j) => Post.fromJson(j as Map<String, dynamic>))
          .toList();

      // FEED-7: рекомендации для инъекции. Раньше здесь дергался /explore,
      // чья форма — ExploreItem (id элемента ≠ post_id, медиа в image_url),
      // и парсился как Post: в ленту вставлялись «посты» без картинки с
      // неверным id (лайк/комменты били мимо). Берём /posts/explore — он
      // отдаёт полноценные Post. И это отдельный best-effort запрос: его
      // сбой не должен ронять уже успешно загруженную ленту (раньше падение
      // fallback-а внутри Future.wait уводило весь loadFeed в error-стейт).
      var exploreFresh = <Post>[];
      try {
        final exploreResp = await _api.get(ApiEndpoints.postsExplore,
            queryParameters: {'page': '1', 'limit': '3'});
        final exploreData = exploreResp.data;
        final exploreList = exploreData is Map &&
                exploreData.containsKey('data')
            ? exploreData['data']
            : exploreData;
        if (exploreList is List) {
          exploreFresh = exploreList
              .map((j) => Post.fromJson(j as Map<String, dynamic>))
              .where((p) =>
                  !fresh.any((f) => f.id == p.id)) // skip duplicates
              .toList();
        }
      } catch (_) {
        // Рекомендации недоступны — лента живёт без инъекции.
      }

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
  /// - Existing посты с тем же id что в fresh → берём fresh-версию целиком:
  ///   сервер гидрирует is_liked/is_saved для авторизованного viewer'а, так
  ///   что fresh — источник правды и для per-viewer полей.
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

  /// Заменить пост в ленте обновлённой версией (лайк/сохранение и т.п.).
  /// Мутации теперь живут в PostCard (карточка работает и вне ленты) — она
  /// зовёт этот метод, чтобы кэш ленты не разъехался с тем, что видел
  /// пользователь. No-op, если поста в ленте нет.
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

  /// Сдвинуть счётчик комментариев поста (после add/delete комментария),
  /// чтобы бейдж «N комментариев» на карточке не отставал до полного рефетча.
  void adjustCommentsCount(String postId, int delta) {
    final idx = state.posts.indexWhere((p) => p.id == postId);
    if (idx < 0) return;
    final p = state.posts[idx];
    applyPostUpdate(p.copyWith(
      commentsCount: (p.commentsCount + delta).clamp(0, 1 << 31),
    ));
  }

  void removePost(String postId) {
    state = state.copyWith(
      posts: state.posts.where((p) => p.id != postId).toList(),
    );
  }

  /// Блокировка автора: скрыть ВСЕ его посты из ленты, не только тот, из
  /// которого открыли меню (блок действует на весь контент пользователя).
  void removeAuthor(String username) {
    state = state.copyWith(
      posts:
          state.posts.where((p) => p.author.username != username).toList(),
    );
  }

}

final feedProvider = StateNotifierProvider<FeedNotifier, FeedState>((ref) {
  final api = ref.watch(apiClientProvider);
  return FeedNotifier(api, ref);
});
