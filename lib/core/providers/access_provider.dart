import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../models/access.dart';

// ── Access check (per userId) ──────────────────────────────────────────────────

final accessCheckProvider = FutureProvider.family<bool, String>((ref, userId) async {
  final api = ref.read(apiClientProvider);
  try {
    final res = await api.get(ApiEndpoints.accessCheck(userId));
    final data = res.data is Map ? (res.data['data'] ?? res.data) : res.data;
    return (data['has_access'] as bool?) ?? false;
  } catch (_) {
    return false;
  }
});

// ── Access list (all partners) ──────────────────────────────────────────────────

class AccessListNotifier extends StateNotifier<AsyncValue<List<AccessPartner>>> {
  final ApiClient _api;

  AccessListNotifier(this._api) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final res = await _api.get(ApiEndpoints.accessList);
      final data = res.data is Map ? (res.data['data'] ?? res.data) : res.data;
      final items = (data['items'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(AccessPartner.fromJson)
          .toList();
      state = AsyncValue.data(items);
    } on DioException catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> revoke(String userId) async {
    await _api.delete(ApiEndpoints.accessRevoke(userId));
    await load();
  }
}

final accessListProvider =
    StateNotifierProvider<AccessListNotifier, AsyncValue<List<AccessPartner>>>(
  (ref) => AccessListNotifier(ref.read(apiClientProvider)),
);

// ── Access request notifier ──────────────────────────────────────────────────────

class AccessNotifier extends StateNotifier<void> {
  final ApiClient _api;

  AccessNotifier(this._api) : super(null);

  /// Sends a pending access request to [userId]. Returns the server status:
  /// 'granted' (access already open) or 'requested'.
  Future<String> requestAccess(String userId) async {
    final res = await _api.post(ApiEndpoints.accessRequest(userId));
    final data = res.data is Map ? (res.data['data'] ?? res.data) : res.data;
    return (data['status'] as String?) ?? 'requested';
  }
}

final accessNotifierProvider =
    StateNotifierProvider<AccessNotifier, void>(
  (ref) => AccessNotifier(ref.read(apiClientProvider)),
);

// ── Incoming access requests (заявки, адресованные мне) ─────────────────────────

class IncomingRequestsNotifier
    extends StateNotifier<AsyncValue<List<AccessRequest>>> {
  final ApiClient _api;

  IncomingRequestsNotifier(this._api) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final res = await _api.get(ApiEndpoints.accessRequestsIncoming);
      final data = res.data is Map ? (res.data['data'] ?? res.data) : res.data;
      final items = (data['items'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(AccessRequest.fromJson)
          .toList();
      state = AsyncValue.data(items);
    } on DioException catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> accept(String requestId) async {
    await _api.post(ApiEndpoints.accessRequestAccept(requestId));
    await load();
  }

  Future<void> reject(String requestId) async {
    await _api.post(ApiEndpoints.accessRequestReject(requestId));
    await load();
  }
}

final incomingRequestsProvider = StateNotifierProvider<IncomingRequestsNotifier,
    AsyncValue<List<AccessRequest>>>(
  (ref) => IncomingRequestsNotifier(ref.read(apiClientProvider)),
);

// ── Sent access requests (мои отправленные, ещё не принятые) ────────────────────

class SentRequestsNotifier
    extends StateNotifier<AsyncValue<List<AccessRequest>>> {
  final ApiClient _api;

  SentRequestsNotifier(this._api) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final res = await _api.get(ApiEndpoints.accessRequestsSent);
      final data = res.data is Map ? (res.data['data'] ?? res.data) : res.data;
      final items = (data['items'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(AccessRequest.fromJson)
          .toList();
      state = AsyncValue.data(items);
    } on DioException catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final sentRequestsProvider = StateNotifierProvider<SentRequestsNotifier,
    AsyncValue<List<AccessRequest>>>(
  (ref) => SentRequestsNotifier(ref.read(apiClientProvider)),
);
