import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_endpoints.dart';

class GifModel {
  final String id;
  final String category;
  final String previewUrl;
  final String fullUrl;

  const GifModel({
    required this.id,
    required this.category,
    required this.previewUrl,
    required this.fullUrl,
  });

  factory GifModel.fromJson(Map<String, dynamic> j) {
    return GifModel(
      id: j['id']?.toString() ?? '',
      category: j['category']?.toString() ?? '',
      previewUrl: j['preview_url']?.toString() ?? '',
      fullUrl: j['full_url']?.toString() ?? '',
    );
  }
}

/// Fixed category list, fetched once from the backend so the client never
/// hardcodes its own copy (see domain.GifCategories on the backend — single
/// source of truth).
final gifCategoryProvider = FutureProvider<List<String>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final resp = await api.get(ApiEndpoints.gifCategories);
  final categories = resp.data['data']['categories'] as List? ?? [];
  return categories.map((e) => e.toString()).toList();
});

/// Русские подписи категорий GIF.
///
/// Сами id остаются английскими намеренно: они приходят с бэкенда
/// (domain.GifCategories — единый источник) и уходят обратно в API фильтром,
/// поэтому переводим ТОЛЬКО отображение, не трогая протокол.
const Map<String, String> _kGifCategoryLabels = {
  'happy': 'Радость',
  'sad': 'Грусть',
  'angry': 'Злость',
  'love': 'Любовь',
  'laughing': 'Смех',
  'crying': 'Слёзы',
  'surprised': 'Удивление',
  'confused': 'Растерянность',
  'excited': 'Восторг',
  'bored': 'Скука',
  'tired': 'Усталость',
  'thumbsup': 'Одобряю',
  'thumbsdown': 'Против',
  'celebration': 'Праздник',
  'facepalm': 'Фейспалм',
  'shocked': 'Шок',
  'wink': 'Подмигиваю',
  'nervous': 'Волнение',
};

/// Подпись категории для UI. Незнакомый id (бэкенд завёл новую категорию, а
/// словарь ещё не пополнили) показываем как есть с заглавной буквы — это
/// честнее пустой пилюли и сразу видно, что нужно добавить перевод.
String gifCategoryLabel(String id) {
  final ru = _kGifCategoryLabels[id];
  if (ru != null) return ru;
  if (id.isEmpty) return id;
  return id[0].toUpperCase() + id.substring(1);
}

class GifListNotifier extends StateNotifier<AsyncValue<List<GifModel>>> {
  final ApiClient _api;
  final String category;

  GifListNotifier(this._api, this.category)
      : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final resp = await _api.get(
        ApiEndpoints.gifs,
        queryParameters: {'category': category, 'limit': 30},
      );
      final list = (resp.data['data'] as List? ?? [])
          .map((e) => GifModel.fromJson(e as Map<String, dynamic>))
          .toList();
      state = AsyncValue.data(list);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }
}

/// One GIF grid per category — kept alive per-category so switching tabs
/// back and forth doesn't re-fetch.
final gifListProvider = StateNotifierProvider.family<GifListNotifier,
    AsyncValue<List<GifModel>>, String>(
  (ref, category) => GifListNotifier(ref.watch(apiClientProvider), category),
);
