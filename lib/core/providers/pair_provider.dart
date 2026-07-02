import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../models/pair.dart';

/// Регистрирует NFC-касание чужого браслета. [targetDeviceHash] — public_id_hex,
/// прочитанный с тега. Возвращает статус сервера: 'tap_recorded' | 'prompt_created'
/// | 'ignored' (нет доступа). При 'prompt_created' оба получат промпт «Стать парой?».
Future<String> recordNfcTap(WidgetRef ref, String targetDeviceHash) async {
  final api = ref.read(apiClientProvider);
  final res = await api.post(ApiEndpoints.pairsTap,
      data: {'target_device_hash': targetDeviceHash});
  final data = res.data is Map ? (res.data['data'] ?? res.data) : res.data;
  return (data['status'] as String?) ?? 'tap_recorded';
}

/// Отвечает на промпт пары (accept=false → тихо отклонить).
Future<void> respondPairPrompt(WidgetRef ref, String promptId, bool accept) async {
  final api = ref.read(apiClientProvider);
  await api.post(ApiEndpoints.pairsRespond(promptId), data: {'accept': accept});
}

/// Входящие промпты пары.
class PairPromptsNotifier extends StateNotifier<AsyncValue<List<PairPrompt>>> {
  final ApiClient _api;

  PairPromptsNotifier(this._api) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final res = await _api.get(ApiEndpoints.pairsPrompts);
      final data = res.data is Map ? (res.data['data'] ?? res.data) : res.data;
      final items = (data['items'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(PairPrompt.fromJson)
          .toList();
      state = AsyncValue.data(items);
    } on DioException catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> respond(String promptId, bool accept) async {
    await _api.post(ApiEndpoints.pairsRespond(promptId), data: {'accept': accept});
    await load();
  }
}

final pairPromptsProvider = StateNotifierProvider<PairPromptsNotifier,
    AsyncValue<List<PairPrompt>>>(
  (ref) => PairPromptsNotifier(ref.read(apiClientProvider)),
);

/// Есть ли у пользователя [userId] пара (🔥🔥) — для профиля.
final pairCheckProvider = FutureProvider.family<bool, String>((ref, userId) async {
  final api = ref.read(apiClientProvider);
  try {
    final res = await api.get(ApiEndpoints.pairsCheck(userId));
    final data = res.data is Map ? (res.data['data'] ?? res.data) : res.data;
    return (data['is_paired'] as bool?) ?? false;
  } catch (_) {
    return false;
  }
});
