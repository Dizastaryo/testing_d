import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/catalog_entry.dart';
import '../services/offline_catalog_repository.dart';
import '../services/offline_storage_service.dart';
import 'offline_catalog_provider.dart';

// ─── State ──────────────────────────────────────────────────────────────────

class OfflineLibraryState {
  final List<CatalogEntry> items;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final int offset;
  final int totalCount;
  final OfflineKind? kindFilter;
  final CatalogSortField sortBy;
  final String? search;

  /// Ошибка загрузки офлайн-каталога (SQLite/FTS5 может не открыться). Раньше
  /// исключение просто пробрасывалось, isLoading оставался true, и экран висел
  /// в вечном спиннере без ретрая.
  final String? error;

  const OfflineLibraryState({
    this.items = const [],
    this.isLoading = true,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.offset = 0,
    this.totalCount = 0,
    this.kindFilter,
    this.sortBy = CatalogSortField.savedAt,
    this.search,
    this.error,
  });

  OfflineLibraryState copyWith({
    List<CatalogEntry>? items,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    int? offset,
    int? totalCount,
    OfflineKind? kindFilter,
    bool clearKindFilter = false,
    CatalogSortField? sortBy,
    String? search,
    bool clearSearch = false,
    String? error,
    bool clearError = false,
  }) =>
      OfflineLibraryState(
        items: items ?? this.items,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        hasMore: hasMore ?? this.hasMore,
        offset: offset ?? this.offset,
        totalCount: totalCount ?? this.totalCount,
        kindFilter: clearKindFilter ? null : (kindFilter ?? this.kindFilter),
        sortBy: sortBy ?? this.sortBy,
        search: clearSearch ? null : (search ?? this.search),
        error: clearError ? null : (error ?? this.error),
      );
}

// ─── Notifier ───────────────────────────────────────────────────────────────

class OfflineLibraryNotifier extends StateNotifier<OfflineLibraryState> {
  final OfflineCatalogRepository _repo;
  static const _pageSize = 30;

  OfflineLibraryNotifier(this._repo) : super(const OfflineLibraryState()) {
    loadInitial();
  }

  Future<void> loadInitial() async {
    state = state.copyWith(
        isLoading: true, offset: 0, items: [], clearError: true);
    try {
      final items = await _repo.list(
        search: state.search,
        kind: state.kindFilter,
        sortBy: state.sortBy,
        limit: _pageSize,
        offset: 0,
      );
      final total = await _repo.count(kind: state.kindFilter);
      if (!mounted) return;
      state = state.copyWith(
        items: items,
        isLoading: false,
        offset: items.length,
        totalCount: total,
        hasMore: items.length >= _pageSize,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final items = await _repo.list(
        search: state.search,
        kind: state.kindFilter,
        sortBy: state.sortBy,
        limit: _pageSize,
        offset: state.offset,
      );
      if (!mounted) return;
      state = state.copyWith(
        items: [...state.items, ...items],
        isLoadingMore: false,
        offset: state.offset + items.length,
        hasMore: items.length >= _pageSize,
      );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(isLoadingMore: false);
    }
  }

  void setKindFilter(OfflineKind? kind) {
    if (kind == state.kindFilter) return;
    state = state.copyWith(
      kindFilter: kind,
      clearKindFilter: kind == null,
    );
    loadInitial();
  }

  void setSortBy(CatalogSortField sort) {
    if (sort == state.sortBy) return;
    state = state.copyWith(sortBy: sort);
    loadInitial();
  }

  void setSearch(String? query) {
    final q = (query == null || query.isEmpty) ? null : query;
    state = state.copyWith(search: q, clearSearch: q == null);
    loadInitial();
  }

  Future<void> deleteItem(String fileId) async {
    await _repo.delete(fileId);
    final items = state.items.where((e) => e.fileId != fileId).toList();
    state = state.copyWith(
      items: items,
      // offset должен идти в ногу с items.length (loadMore читает с offset).
      // Без этого каждое удаление сдвигает БД, и следующий loadMore пропускает
      // по одной книге. totalCount не уводим в минус.
      offset: items.length,
      totalCount: (state.totalCount - 1).clamp(0, 1 << 30),
    );
  }

  Future<void> deleteItems(List<String> fileIds) async {
    await _repo.deleteMany(fileIds);
    final items =
        state.items.where((e) => !fileIds.contains(e.fileId)).toList();
    state = state.copyWith(
      items: items,
      offset: items.length,
      totalCount: (state.totalCount - fileIds.length).clamp(0, 1 << 30),
    );
  }

  Future<void> refresh() async {
    await _repo.reconcile();
    await loadInitial();
  }
}

// ─── Providers ──────────────────────────────────────────────────────────────

final offlineLibraryProvider =
    StateNotifierProvider.autoDispose<OfflineLibraryNotifier, OfflineLibraryState>(
  (ref) => OfflineLibraryNotifier(ref.read(offlineCatalogProvider)),
);

final offlineTotalSizeProvider = FutureProvider.autoDispose<int>((ref) {
  return ref.read(offlineCatalogProvider).totalSizeBytes();
});
