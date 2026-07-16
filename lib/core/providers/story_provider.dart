import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../models/story.dart';
import '../services/logger.dart';
import 'realtime_provider.dart';

class StoryState {
  final List<StoryGroup> storyGroups;
  final bool isLoading;
  final String? error;

  const StoryState({
    this.storyGroups = const [],
    this.isLoading = false,
    this.error,
  });

  StoryState copyWith({
    List<StoryGroup>? storyGroups,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    // Как в FeedState: без явного clearError любое copyWith(storyGroups: …)
    // молча стирало error — фоновые апдейты (например, live-счётчик
    // просмотров) гасили сообщение об ошибке загрузки.
    return StoryState(
      storyGroups: storyGroups ?? this.storyGroups,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class StoryNotifier extends StateNotifier<StoryState> {
  final ApiClient _api;
  final Ref _ref;
  ProviderSubscription<AsyncValue<RealtimeEvent>>? _wsSub;
  // FEED-6: debounce для story.created event'ов — burst (несколько друзей
  // постят одновременно) → один reload вместо N.
  Timer? _createdDebounce;

  StoryNotifier(this._api, this._ref) : super(const StoryState()) {
    loadStories();
    _listenRealtime();
  }

  /// Realtime обработчики:
  ///   - `story.view.added` — author видит view-counter без refresh.
  ///   - `story.created` (FEED-6) — friend опубликовал story → reload
  ///     storyFeed (debounced 500ms на случай burst'а).
  void _listenRealtime() {
    _wsSub = _ref.listen<AsyncValue<RealtimeEvent>>(
      realtimeEventsProvider,
      (prev, next) {
        next.whenData((evt) {
          if (evt.payload is! Map) return;
          final p = (evt.payload as Map).cast<String, dynamic>();
          if (evt.type == 'story.view.added') {
            final id = p['story_id']?.toString() ?? '';
            final n = p['views_count'];
            if (id.isEmpty || n is! num) return;
            applyViewsCountUpdate(id, n.toInt());
            return;
          }
          if (evt.type == 'story.created') {
            // Debounced reload — одна story = один refetch, burst = тоже один.
            _createdDebounce?.cancel();
            _createdDebounce = Timer(
              const Duration(milliseconds: 500),
              () {
                if (!mounted) return;
                loadStories();
              },
            );
            return;
          }
        });
      },
    );
  }

  @override
  void dispose() {
    _createdDebounce?.cancel();
    _wsSub?.close();
    super.dispose();
  }

  /// Server pushed an updated view-count for one of our stories. Replace
  /// the field in-place — viewer-state (isSeen) is per-viewer and stays
  /// untouched.
  void applyViewsCountUpdate(String storyId, int viewsCount) {
    final groups = state.storyGroups.map((g) {
      final stories = g.stories.map((s) {
        if (s.id != storyId) return s;
        return s.copyWith(viewsCount: viewsCount);
      }).toList();
      return StoryGroup(
        author: g.author,
        stories: stories,
        allSeen: g.allSeen,
      );
    }).toList();
    state = state.copyWith(storyGroups: groups);
  }

  Future<void> loadStories() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final resp = await _api.get(ApiEndpoints.storyFeed);
      final data = resp.data;
      final listData = data is Map && data.containsKey('data') ? data['data'] : data;
      final groups = (listData as List)
          .map((j) => StoryGroup.fromJson(j as Map<String, dynamic>))
          .toList();
      state = StoryState(storyGroups: groups);
    } catch (e) {
      // M54: Preserve existing storyGroups on error
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Optimistically marks [storyId] as seen. On network failure, rolls back
  /// to the pre-mutation state — mirrors the rollback pattern in
  /// [toggleLike] below (save original before mutating, restore in catch).
  Future<void> markSeen(String storyId) async {
    Story? original;
    final updatedGroups = state.storyGroups.map((group) {
      final updatedStories = group.stories.map((story) {
        if (story.id != storyId) return story;
        original = story;
        return story.copyWith(isSeen: true);
      }).toList();
      return StoryGroup(
        author: group.author,
        stories: updatedStories,
        allSeen: updatedStories.every((s) => s.isSeen),
      );
    }).toList();

    if (original == null) return;
    state = state.copyWith(storyGroups: updatedGroups);

    try {
      await _api.post(ApiEndpoints.viewStory(storyId));
    } catch (_) {
      // Rollback on failure — preserve previous state (author under-counts
      // the view instead of the viewer wrongly believing it registered).
      final rolled = state.storyGroups.map((g) {
        final stories =
            g.stories.map((s) => s.id == storyId ? original! : s).toList();
        return StoryGroup(
          author: g.author,
          stories: stories,
          allSeen: stories.every((s) => s.isSeen),
        );
      }).toList();
      state = state.copyWith(storyGroups: rolled);
    }
  }

  /// Optimistic like/unlike toggle on a story — optimistic-then-reconcile
  /// pattern (mirrors FeedNotifier.toggleLike for posts).
  /// The server hydrates `is_liked` on every story fetch now, so this just
  /// keeps the in-memory state in sync with what the backend already
  /// persists — no more purely-local `_likedStoryIds` set that reset every
  /// time the viewer was reopened.
  Future<void> toggleLike(String storyId) async {
    Story? original;
    final newGroups = state.storyGroups.map((g) {
      final stories = g.stories.map((s) {
        if (s.id != storyId) return s;
        original = s;
        final newLiked = !s.isLiked;
        return s.copyWith(
          isLiked: newLiked,
          likesCount: newLiked
              ? s.likesCount + 1
              : (s.likesCount > 0 ? s.likesCount - 1 : 0),
        );
      }).toList();
      return StoryGroup(
        author: g.author,
        stories: stories,
        allSeen: g.allSeen,
      );
    }).toList();

    if (original == null) return;
    state = state.copyWith(storyGroups: newGroups);

    final newLiked = !original!.isLiked;
    try {
      if (newLiked) {
        await _api.post(ApiEndpoints.likeStory(storyId));
      } else {
        await _api.delete(ApiEndpoints.likeStory(storyId));
      }
    } catch (e, st) {
      // Server rejected the like/unlike (e.g. duplicate like → 409) — log it
      // instead of silently swallowing, and roll back the optimistic update
      // so the UI doesn't keep a state the backend never recorded.
      appLog.error('[StoryNotifier] toggleLike error', e, st);
      final rolled = state.storyGroups.map((g) {
        final stories = g.stories
            .map((s) => s.id == storyId ? original! : s)
            .toList();
        return StoryGroup(
          author: g.author,
          stories: stories,
          allSeen: g.allSeen,
        );
      }).toList();
      state = state.copyWith(storyGroups: rolled);
    }
  }
}

final storyProvider = StateNotifierProvider<StoryNotifier, StoryState>((ref) {
  final api = ref.watch(apiClientProvider);
  return StoryNotifier(api, ref);
});
