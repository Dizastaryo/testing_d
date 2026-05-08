import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_endpoints.dart';

class InviteSummary {
  final String inviterId;
  final String inviterUsername;
  final String inviterFullName;
  final String inviterAvatarUrl;
  final String code;
  final bool used;

  InviteSummary({
    required this.inviterId,
    required this.inviterUsername,
    required this.inviterFullName,
    required this.inviterAvatarUrl,
    required this.code,
    required this.used,
  });

  factory InviteSummary.fromJson(Map<String, dynamic> j) {
    final inv = (j['inviter'] as Map?)?.cast<String, dynamic>() ?? const {};
    return InviteSummary(
      inviterId: inv['id'] as String? ?? '',
      inviterUsername: inv['username'] as String? ?? '',
      inviterFullName: inv['full_name'] as String? ?? '',
      inviterAvatarUrl: inv['avatar_url'] as String? ?? '',
      code: j['code'] as String? ?? '',
      used: j['used'] as bool? ?? false,
    );
  }
}

/// Public lookup. Returns null if code is empty / not found.
final inviteLookupProvider =
    FutureProvider.autoDispose.family<InviteSummary?, String>((ref, code) async {
  if (code.isEmpty) return null;
  try {
    final api = ref.read(apiClientProvider);
    final r = await api.get(ApiEndpoints.inviteByCode(code));
    final data = r.data is Map && r.data.containsKey('data') ? r.data['data'] : r.data;
    return InviteSummary.fromJson(data as Map<String, dynamic>);
  } on DioException {
    return null;
  }
});

class InvitesNotifier extends StateNotifier<AsyncValue<List<dynamic>>> {
  final ApiClient _api;
  InvitesNotifier(this._api) : super(const AsyncValue.loading()) {
    refresh();
  }

  Future<String?> createCode() async {
    try {
      final r = await _api.post(ApiEndpoints.invites);
      final data = r.data is Map && r.data.containsKey('data') ? r.data['data'] : r.data;
      await refresh();
      return data['code'] as String?;
    } on DioException catch (_) {
      return null;
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    try {
      final r = await _api.get(ApiEndpoints.myInvites);
      final data = r.data is Map && r.data.containsKey('data') ? r.data['data'] : r.data;
      final items = (data as Map)['items'] as List? ?? [];
      state = AsyncValue.data(items);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final invitesProvider =
    StateNotifierProvider<InvitesNotifier, AsyncValue<List<dynamic>>>((ref) {
  return InvitesNotifier(ref.read(apiClientProvider));
});
