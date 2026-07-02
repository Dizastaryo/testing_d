import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../models/explore_item.dart';

/// State for the backend-owned mixed Explore feed.
class ExploreFeedState {
  final List<ExploreItem> items;
  final String filter; // all | shorts | videos | popular | posts
  final String query;
  final String mode; // personalization_mode: anonymous | cold_start | personalized_light
  final int offset; // next offset to request
  final bool hasMore;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;

  const ExploreFeedState({
    this.items = const [],
    this.filter = 'all',
    this.query = '',
    this.mode = '',
    this.offset = 0,
    this.hasMore = true,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
  });

  ExploreFeedState copyWith({
    List<ExploreItem>? items,
    String? filter,
    String? query,
    String? mode,
    int? offset,
    bool? hasMore,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
    bool clearError = false,
  }) {
    return ExploreFeedState(
      items: items ?? this.items,
      filter: filter ?? this.filter,
      query: query ?? this.query,
      mode: mode ?? this.mode,
      offset: offset ?? this.offset,
      hasMore: hasMore ?? this.hasMore,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

List<dynamic> _dataList(dynamic body) {
  if (body is Map && body['data'] is List) return body['data'] as List;
  if (body is List) return body;
  return const [];
}

Map<String, dynamic>? _meta(dynamic body) {
  if (body is Map && body['meta'] is Map) {
    return (body['meta'] as Map).cast<String, dynamic>();
  }
  return null;
}

/// Owns the single unified Explore feed. Chips call [setFilter]; the search bar
/// calls [search]; the grid calls [loadMore]/[refresh]. All sourced from the
/// backend `/explore` endpoint — no client-side composition of the mix.
class ExploreFeedNotifier extends StateNotifier<ExploreFeedState> {
  static const _limit = 30;
  final ApiClient _api;

  ExploreFeedNotifier(this._api) : super(const ExploreFeedState()) {
    refresh();
  }

  Future<void> setFilter(String filter) async {
    if (filter == state.filter) return;
    state = state.copyWith(filter: filter);
    await refresh();
  }

  Future<void> search(String query) async {
    if (query == state.query) return;
    state = state.copyWith(query: query);
    await refresh();
  }

  List<ExploreItem> _parse(List<dynamic> data) => data
      .whereType<Map>()
      .map((j) => ExploreItem.fromJson(j.cast<String, dynamic>()))
      .where((it) => it.isOpenable) // skip items missing their id — no crash
      // Long videos (the Видеотека section) were removed from the app — drop
      // them from Explore so nothing links to the deleted watch page. Shorts
      // (vertical) and posts stay.
      .where((it) => it.type != ExploreItemType.video)
      .toList();

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final r = await _api.get(ApiEndpoints.explore, queryParameters: {
        'filter': state.filter,
        if (state.query.isNotEmpty) 'q': state.query,
        'limit': '$_limit',
        'offset': '0',
      });
      final items = _parse(_dataList(r.data));
      final meta = _meta(r.data);
      state = ExploreFeedState(
        items: items,
        filter: state.filter,
        query: state.query,
        mode: meta?['personalization_mode']?.toString() ?? '',
        offset: (meta?['next_offset'] as num?)?.toInt() ?? items.length,
        hasMore: (meta?['has_more'] as bool?) ?? (items.length >= _limit),
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore || state.isLoading) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final r = await _api.get(ApiEndpoints.explore, queryParameters: {
        'filter': state.filter,
        if (state.query.isNotEmpty) 'q': state.query,
        'limit': '$_limit',
        'offset': '${state.offset}',
      });
      final more = _parse(_dataList(r.data));
      final meta = _meta(r.data);
      state = state.copyWith(
        items: [...state.items, ...more],
        isLoadingMore: false,
        hasMore: (meta?['has_more'] as bool?) ?? (more.length >= _limit),
        offset: (meta?['next_offset'] as num?)?.toInt() ??
            (state.offset + more.length),
      );
    } catch (_) {
      state = state.copyWith(isLoadingMore: false);
    }
  }

  /// Removes an item from the current grid (used by the "Не интересно" / "Скрыть"
  /// long-press menu so it disappears immediately, without a refresh).
  void removeItem(ExploreItem target) {
    state = state.copyWith(
      items: state.items
          .where((it) => !(it.type == target.type &&
              it.postId == target.postId &&
              it.videoId == target.videoId))
          .toList(),
    );
  }
}

final exploreFeedProvider =
    StateNotifierProvider<ExploreFeedNotifier, ExploreFeedState>((ref) {
  return ExploreFeedNotifier(ref.watch(apiClientProvider));
});
