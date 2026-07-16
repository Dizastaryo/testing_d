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

  // Толерантный парсинг (?.toString() + tryParse): одна битая/null строка из
  // /me/blocks раньше роняла весь список в AsyncValue.error.
  factory BlockedUser.fromJson(Map<String, dynamic> j) => BlockedUser(
        userId: j['user_id']?.toString() ?? '',
        username: j['username']?.toString() ?? '',
        fullName: j['full_name']?.toString() ?? '',
        avatarUrl: j['avatar_url']?.toString() ?? '',
        blockedAt:
            DateTime.tryParse(j['blocked_at']?.toString() ?? '') ??
                DateTime.now(),
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

/// Набор username'ов, чьи комментарии я ограничил — чтобы меню профиля
/// показывало «Ограничить»/«Снять ограничение» (раньше было только
/// «Ограничить» без обратного действия из UI, хотя ручка DELETE есть).
class RestrictionsNotifier extends StateNotifier<AsyncValue<Set<String>>> {
  final ApiClient _api;

  RestrictionsNotifier(this._api) : super(const AsyncValue.loading()) {
    refresh();
  }

  Future<void> refresh() async {
    try {
      final resp = await _api.get(ApiEndpoints.myRestrictions);
      final data = resp.data is Map && resp.data.containsKey('data')
          ? resp.data['data']
          : resp.data;
      final items = (data is Map ? data['items'] as List? : null) ?? [];
      state = AsyncValue.data(items
          .whereType<Map>()
          .map((e) => e['username']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toSet());
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  bool isRestricted(String username) =>
      state.value?.contains(username) ?? false;

  /// Тоггл ограничения. Возвращает friendly-ошибку или null.
  Future<String?> toggle(String username, bool restrict) async {
    try {
      if (restrict) {
        await _api.post(ApiEndpoints.restrictUser(username));
      } else {
        await _api.delete(ApiEndpoints.restrictUser(username));
      }
      final cur = Set<String>.from(state.value ?? const <String>{});
      if (restrict) {
        cur.add(username);
      } else {
        cur.remove(username);
      }
      state = AsyncValue.data(cur);
      return null;
    } on DioException catch (e) {
      return apiErrorMessage(e);
    }
  }
}

final restrictionsProvider =
    StateNotifierProvider<RestrictionsNotifier, AsyncValue<Set<String>>>((ref) {
  return RestrictionsNotifier(ref.watch(apiClientProvider));
});
