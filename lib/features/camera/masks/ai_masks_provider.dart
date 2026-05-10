import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import 'ai_mask_models.dart';

/// Список AI-масок текущего юзера + кнопки create / delete.
/// State: `AsyncValue<List<AIMask>>` (loading/data/error через стандартный
/// Riverpod-pattern).
class AIMasksNotifier extends AsyncNotifier<List<AIMask>> {
  @override
  Future<List<AIMask>> build() async {
    return _load();
  }

  Future<List<AIMask>> _load() async {
    final api = ref.read(apiClientProvider);
    final r = await api.get('/ai/masks');
    final data = r.data is Map && (r.data as Map).containsKey('data')
        ? r.data['data']
        : r.data;
    if (data is! List) return const [];
    return data
        .map((e) => AIMask.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Создание новой маски через `POST /ai/mask`. Может занять до 60s
  /// (DALL-E generation + download). Возвращает свежесозданную маску,
  /// которая prepend'ится в state.
  ///
  /// Бросает [AIMaskException] с человекочитаемым сообщением на rate-limit
  /// (429), no-api-key (503), и т.д.
  Future<AIMask> generate(String prompt) async {
    final api = ref.read(apiClientProvider);
    try {
      final r = await api.post(
        '/ai/mask',
        data: {'prompt': prompt},
        options: Options(receiveTimeout: const Duration(seconds: 120)),
      );
      final data = r.data is Map && (r.data as Map).containsKey('data')
          ? r.data['data']
          : r.data;
      if (data is! Map<String, dynamic>) {
        throw const AIMaskException('Сервер вернул некорректный ответ');
      }
      final mask = AIMask.fromJson(data);
      // Prepend в state — новая маска идёт первой.
      state = state.whenData((list) => [mask, ...list]);
      return mask;
    } on DioException catch (e) {
      final code = e.response?.statusCode ?? 0;
      final msg = _extractError(e.response?.data) ??
          'не удалось сгенерировать маску';
      if (code == 429) throw AIMaskException('Лимит сегодня исчерпан: $msg');
      if (code == 503) throw AIMaskException('AI временно недоступен');
      throw AIMaskException(msg);
    }
  }

  Future<void> delete(String id) async {
    final api = ref.read(apiClientProvider);
    await api.delete('/ai/masks/$id');
    state = state.whenData((list) => list.where((m) => m.id != id).toList());
  }

  String? _extractError(dynamic data) {
    if (data is Map && data['error'] is String) {
      return data['error'] as String;
    }
    return null;
  }
}

final aiMasksProvider =
    AsyncNotifierProvider<AIMasksNotifier, List<AIMask>>(AIMasksNotifier.new);

class AIMaskException implements Exception {
  final String message;
  const AIMaskException(this.message);
  @override
  String toString() => message;
}
