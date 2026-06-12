import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_endpoints.dart';

// ─── Models ──────────────────────────────────────────────────────────────────

class ScannerLikerItem {
  final String userId;
  final String username;
  final String fullName;
  final String avatarUrl;
  final bool isVerified;
  final DateTime likedAt;

  const ScannerLikerItem({
    required this.userId,
    required this.username,
    required this.fullName,
    required this.avatarUrl,
    required this.isVerified,
    required this.likedAt,
  });

  factory ScannerLikerItem.fromJson(Map<String, dynamic> j) => ScannerLikerItem(
        userId: j['user_id']?.toString() ?? '',
        username: j['username']?.toString() ?? '',
        fullName: j['full_name']?.toString() ?? '',
        avatarUrl: j['avatar_url']?.toString() ?? '',
        isVerified: (j['is_verified'] as bool?) ?? false,
        likedAt: j['liked_at'] != null
            ? DateTime.tryParse(j['liked_at'].toString()) ?? DateTime.now()
            : DateTime.now(),
      );
}

class ScannerSentItem {
  final String scanAlias;
  final String scanAvatarUrl;
  final String deviceHash;

  const ScannerSentItem({
    required this.scanAlias,
    required this.scanAvatarUrl,
    required this.deviceHash,
  });

  factory ScannerSentItem.fromJson(Map<String, dynamic> j) => ScannerSentItem(
        scanAlias: j['scan_alias']?.toString() ?? '',
        scanAvatarUrl: j['scan_avatar_url']?.toString() ?? '',
        deviceHash: j['device_hash']?.toString() ?? '',
      );
}

// ─── Received likes state ────────────────────────────────────────────────────

class ReceivedLikesState {
  final List<ScannerLikerItem> items;
  final int total;
  final bool isLoading;
  final String? error;

  const ReceivedLikesState({
    this.items = const [],
    this.total = 0,
    this.isLoading = false,
    this.error,
  });

  ReceivedLikesState copyWith({
    List<ScannerLikerItem>? items,
    int? total,
    bool? isLoading,
    String? error,
  }) =>
      ReceivedLikesState(
        items: items ?? this.items,
        total: total ?? this.total,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

class ReceivedLikesNotifier extends StateNotifier<ReceivedLikesState> {
  final ApiClient _api;

  ReceivedLikesNotifier(this._api) : super(const ReceivedLikesState()) {
    load();
  }

  Future<void> load({int limit = 20, int offset = 0}) async {
    state = state.copyWith(isLoading: true);
    try {
      final res = await _api.get(
        ApiEndpoints.scannerReceivedLikes,
        queryParameters: {'limit': limit, 'offset': offset},
      );
      final data = res.data['data'] as Map<String, dynamic>? ?? {};
      final list = (data['items'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ScannerLikerItem.fromJson)
          .toList();
      final total = (data['total'] as num?)?.toInt() ?? list.length;
      state = state.copyWith(items: list, total: total, isLoading: false);
    } on DioException catch (e) {
      state = state.copyWith(
          isLoading: false,
          error: e.response?.data?['error']?.toString() ?? e.message);
    }
  }
}

final receivedLikesProvider =
    StateNotifierProvider<ReceivedLikesNotifier, ReceivedLikesState>((ref) {
  return ReceivedLikesNotifier(ref.watch(apiClientProvider));
});

// ─── Sent likes state ────────────────────────────────────────────────────────

class SentLikesState {
  final List<ScannerSentItem> items;
  final bool isLoading;
  final String? error;

  const SentLikesState({
    this.items = const [],
    this.isLoading = false,
    this.error,
  });

  SentLikesState copyWith({
    List<ScannerSentItem>? items,
    bool? isLoading,
    String? error,
  }) =>
      SentLikesState(
        items: items ?? this.items,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

class SentLikesNotifier extends StateNotifier<SentLikesState> {
  final ApiClient _api;

  SentLikesNotifier(this._api) : super(const SentLikesState()) {
    load();
  }

  Future<void> load({int limit = 20, int offset = 0}) async {
    state = state.copyWith(isLoading: true);
    try {
      final res = await _api.get(
        ApiEndpoints.scannerSentLikes,
        queryParameters: {'limit': limit, 'offset': offset},
      );
      final data = res.data['data'] as Map<String, dynamic>? ?? {};
      final list = (data['items'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ScannerSentItem.fromJson)
          .toList();
      state = state.copyWith(items: list, isLoading: false);
    } on DioException catch (e) {
      state = state.copyWith(
          isLoading: false,
          error: e.response?.data?['error']?.toString() ?? e.message);
    }
  }
}

final sentLikesProvider =
    StateNotifierProvider<SentLikesNotifier, SentLikesState>((ref) {
  return SentLikesNotifier(ref.watch(apiClientProvider));
});

// ─── Like action helpers ─────────────────────────────────────────────────────

/// Ставит лайк по deviceHash. Возвращает true если успешно.
Future<bool> postScannerLike(ApiClient api, String deviceHash) async {
  try {
    await api.post(ApiEndpoints.scannerLike, data: {'device_hash': deviceHash});
    return true;
  } on DioException {
    return false;
  }
}

/// Убирает лайк по deviceHash. Возвращает true если успешно.
Future<bool> removeScannerLike(ApiClient api, String deviceHash) async {
  try {
    await api.delete(ApiEndpoints.scannerUnlike(deviceHash));
    return true;
  } on DioException {
    return false;
  }
}

// ─── Unseen likes count (for bottom nav badge) ───────────────────────────────

/// Провайдер кол-ва непросмотренных лайков.
/// Используется для badge на иконке профиля в нижнем меню.
final unseenLikesProvider = FutureProvider.autoDispose<int>((ref) async {
  try {
    final api = ref.read(apiClientProvider);
    final res = await api.get(ApiEndpoints.scannerUnseenCount);
    final data = res.data is Map ? (res.data['data'] ?? res.data) : res.data;
    return (data is Map ? (data['count'] as num?)?.toInt() : null) ?? 0;
  } catch (_) {
    return 0;
  }
});

/// Отмечает все лайки просмотренными. Возвращает true если успешно.
Future<void> markLikesSeen(ApiClient api) async {
  try {
    await api.post(ApiEndpoints.scannerMarkSeen);
  } catch (_) {}
}
