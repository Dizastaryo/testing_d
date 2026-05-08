import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_endpoints.dart';

class BlockedUser {
  final String userId;
  final String username;
  final String fullName;
  final String avatarUrl;
  final DateTime blockedAt;

  BlockedUser({
    required this.userId,
    required this.username,
    required this.fullName,
    required this.avatarUrl,
    required this.blockedAt,
  });

  factory BlockedUser.fromJson(Map<String, dynamic> j) => BlockedUser(
        userId: j['user_id'] as String,
        username: j['username'] as String,
        fullName: (j['full_name'] as String?) ?? '',
        avatarUrl: (j['avatar_url'] as String?) ?? '',
        blockedAt: DateTime.parse(j['blocked_at'] as String),
      );
}

class BlocksNotifier extends StateNotifier<AsyncValue<List<BlockedUser>>> {
  final ApiClient _api;

  BlocksNotifier(this._api) : super(const AsyncValue.loading()) {
    refresh();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    try {
      final resp = await _api.get(ApiEndpoints.myBlocks);
      final data = resp.data is Map && resp.data.containsKey('data')
          ? resp.data['data']
          : resp.data;
      final items = (data as Map)['items'] as List? ?? [];
      state = AsyncValue.data(
          items.map((e) => BlockedUser.fromJson(e as Map<String, dynamic>)).toList());
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Returns a friendly Russian error string or null on success.
  Future<String?> block(String username) async {
    try {
      await _api.post(ApiEndpoints.blockUser(username));
      await refresh();
      return null;
    } on DioException catch (e) {
      return apiErrorMessage(e);
    }
  }

  Future<String?> unblock(String username) async {
    try {
      await _api.delete(ApiEndpoints.blockUser(username));
      // Optimistic local removal then refresh.
      final current = state.value;
      if (current != null) {
        state = AsyncValue.data(
            current.where((u) => u.username != username).toList());
      }
      return null;
    } on DioException catch (e) {
      return apiErrorMessage(e);
    }
  }
}

final blocksProvider =
    StateNotifierProvider<BlocksNotifier, AsyncValue<List<BlockedUser>>>((ref) {
  return BlocksNotifier(ref.watch(apiClientProvider));
});
