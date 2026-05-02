import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../models/story.dart';

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

  StoryNotifier(this._api) : super(const StoryState()) {
    loadStories();
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
}

final storyProvider = StateNotifierProvider<StoryNotifier, StoryState>((ref) {
  final api = ref.watch(apiClientProvider);
  return StoryNotifier(api);
});
