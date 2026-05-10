import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../models/story.dart';
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
  }) {
    return StoryState(
      storyGroups: storyGroups ?? this.storyGroups,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class StoryNotifier extends StateNotifier<StoryState> {
  final ApiClient _api;
  final Ref _ref;
  ProviderSubscription<AsyncValue<RealtimeEvent>>? _wsSub;

  StoryNotifier(this._api, this._ref) : super(const StoryState()) {
    loadStories();
    _listenRealtime();
  }

  /// Subscribes to WS events that affect a story's lightweight aggregate
  /// state (current: views_count). Author sees realtime view-counter
  /// without polling/refresh. Reactions follow a separate path via
  /// `post.reaction`-like push that's not yet wired to story (see DONE
  /// 2026-05-09 — story reactions persist but rely on UI tap → optimistic
  /// update; remote viewers' reactions are not pushed).
  void _listenRealtime() {
    _wsSub = _ref.listen<AsyncValue<RealtimeEvent>>(
      realtimeEventsProvider,
      (prev, next) {
        next.whenData((evt) {
          if (evt.type != 'story.view.added' || evt.payload is! Map) return;
          final p = (evt.payload as Map).cast<String, dynamic>();
          final id = p['story_id']?.toString() ?? '';
          final n = p['views_count'];
          if (id.isEmpty || n is! num) return;
          applyViewsCountUpdate(id, n.toInt());
        });
      },
    );
  }

  @override
  void dispose() {
    _wsSub?.close();
    super.dispose();
  }

  /// Server pushed an updated view-count for one of our stories. Replace
  /// the field in-place — viewer-state (isSeen, my_reaction) is per-viewer
  /// and stays untouched.
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
    state = state.copyWith(isLoading: true, error: null);
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

  Future<void> markSeen(String storyId) async {
    final updatedGroups = state.storyGroups.map((group) {
      final updatedStories = group.stories.map((story) {
        if (story.id == storyId) return story.copyWith(isSeen: true);
        return story;
      }).toList();
      return StoryGroup(
        author: group.author,
        stories: updatedStories,
        allSeen: updatedStories.every((s) => s.isSeen),
      );
    }).toList();

    state = state.copyWith(storyGroups: updatedGroups);

    try {
      await _api.post(ApiEndpoints.viewStory(storyId));
    } catch (_) {}
  }

  /// Optimistic emoji-reaction toggle on a story. Same emoji = unreact
  /// (DELETE), different emoji = upsert (POST). Mirrors post-reactions.
  Future<void> toggleReaction(String storyId, String emoji) async {
    Story? original;
    final newGroups = state.storyGroups.map((g) {
      final stories = g.stories.map((s) {
        if (s.id != storyId) return s;
        original = s;
        final isSame = s.myReaction == emoji;
        final newCounts = Map<String, int>.from(s.reactions);
        if (s.myReaction.isNotEmpty) {
          newCounts[s.myReaction] = (newCounts[s.myReaction] ?? 1) - 1;
          if ((newCounts[s.myReaction] ?? 0) <= 0) {
            newCounts.remove(s.myReaction);
          }
        }
        final newMine = isSame ? '' : emoji;
        if (newMine.isNotEmpty) {
          newCounts[newMine] = (newCounts[newMine] ?? 0) + 1;
        }
        return s.copyWith(reactions: newCounts, myReaction: newMine);
      }).toList();
      return StoryGroup(
        author: g.author,
        stories: stories,
        allSeen: g.allSeen,
      );
    }).toList();

    if (original == null) return;
    state = state.copyWith(storyGroups: newGroups);

    final isSame = original!.myReaction == emoji;
    try {
      if (isSame) {
        await _api.delete(ApiEndpoints.reactStory(storyId));
      } else {
        await _api.post(
          ApiEndpoints.reactStory(storyId),
          data: {'emoji': emoji},
        );
      }
    } catch (_) {
      // Rollback on failure — preserve previous state.
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
