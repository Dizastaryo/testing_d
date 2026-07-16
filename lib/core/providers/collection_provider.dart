import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_endpoints.dart';
import '../models/collection.dart';
import 'library_provider.dart';

// ─── Collections list ───────────────────────────────────────────────────────

class CollectionsNotifier extends StateNotifier<AsyncValue<List<Collection>>> {
  final dynamic _dio;

  CollectionsNotifier(this._dio) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    try {
      final resp = await _dio.get(ApiEndpoints.collections);
      final items = resp.data?['data'] as List? ?? [];
      state = AsyncValue.data(
          items.map((e) => Collection.fromJson(e as Map<String, dynamic>)).toList());
    } catch (e, s) {
      state = AsyncValue.error(e, s);
    }
  }

  Future<Collection?> create(String name, String description,
      {bool isPublic = false}) async {
    try {
      final resp = await _dio.post(ApiEndpoints.collections, data: {
        'name': name,
        'description': description,
        'is_public': isPublic,
      });
      final c = Collection.fromJson(resp.data['data'] as Map<String, dynamic>);
      state = state.whenData((list) => [c, ...list]);
      return c;
    } catch (_) {
      return null;
    }
  }

  /// PUT перезаписывает коллекцию целиком, поэтому шлём и публичность —
  /// иначе правка названия молча закрыла бы расшаренную подборку.
  Future<bool> update(String id, String name, String description,
      {bool? isPublic}) async {
    try {
      final current = state.valueOrNull?.firstWhere(
        (c) => c.id == id,
        orElse: () => throw StateError('not found'),
      );
      final pub = isPublic ?? current?.isPublic ?? false;

      await _dio.put(ApiEndpoints.collectionById(id), data: {
        'name': name,
        'description': description,
        'is_public': pub,
      });
      state = state.whenData((list) => list
          .map((c) => c.id == id
              ? c.copyWith(
                  name: name,
                  description: description,
                  isPublic: pub,
                  updatedAt: DateTime.now(),
                )
              : c)
          .toList());
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Открыть/закрыть подборку по ссылке — то, что делает её «плейлистом,
  /// которым можно делиться».
  Future<bool> setPublic(String id, bool isPublic) async {
    final c = state.valueOrNull?.where((x) => x.id == id).firstOrNull;
    if (c == null) return false;
    return update(id, c.name, c.description, isPublic: isPublic);
  }

  Future<bool> delete(String id) async {
    try {
      await _dio.delete(ApiEndpoints.collectionById(id));
      state = state.whenData((list) => list.where((c) => c.id != id).toList());
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> addFile(String collectionId, String fileId) async {
    try {
      await _dio.post(ApiEndpoints.collectionFiles(collectionId),
          data: {'file_id': fileId});
      // Бэк идемпотентен (повторное добавление — no-op), поэтому слепой «+1»
      // завышал filesCount при добавлении уже лежащего файла. Берём правду с
      // сервера: load() без loading-состояния, мерцания нет.
      await load();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> removeFile(String collectionId, String fileId) async {
    try {
      await _dio.delete(ApiEndpoints.collectionFile(collectionId, fileId));
      state = state.whenData((list) => list
          .map((c) => c.id == collectionId
              ? c.copyWith(
                  filesCount: (c.filesCount - 1).clamp(0, 999999),
                  files: c.files.where((f) => f.id != fileId).toList(),
                  updatedAt: DateTime.now(),
                )
              : c)
          .toList());
      return true;
    } catch (_) {
      return false;
    }
  }
}

final collectionsProvider = StateNotifierProvider<
    CollectionsNotifier, AsyncValue<List<Collection>>>(
  (ref) => CollectionsNotifier(ref.watch(libraryApiClientProvider)),
);

// ─── Collection detail (with files) ─────────────────────────────────────────

final collectionDetailProvider =
    FutureProvider.autoDispose.family<Collection, String>((ref, id) async {
  final dio = ref.watch(libraryApiClientProvider);
  final resp = await dio.get(ApiEndpoints.collectionById(id));
  final data = resp.data?['data'] as Map<String, dynamic>?;
  if (data == null) throw Exception('Коллекция не найдена');
  return Collection.fromJson(data);
});
