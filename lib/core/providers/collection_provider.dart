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

  Future<Collection?> create(String name, String description) async {
    try {
      final resp = await _dio.post(ApiEndpoints.collections,
          data: {'name': name, 'description': description});
      final c = Collection.fromJson(resp.data['data'] as Map<String, dynamic>);
      state = state.whenData((list) => [c, ...list]);
      return c;
    } catch (_) {
      return null;
    }
  }

  Future<bool> update(String id, String name, String description) async {
    try {
      await _dio.put(ApiEndpoints.collectionById(id),
          data: {'name': name, 'description': description});
      state = state.whenData((list) => list.map((c) {
            if (c.id == id) {
              return Collection(
                id: c.id,
                userId: c.userId,
                name: name,
                description: description,
                coverFileId: c.coverFileId,
                filesCount: c.filesCount,
                files: c.files,
                createdAt: c.createdAt,
                updatedAt: DateTime.now(),
              );
            }
            return c;
          }).toList());
      return true;
    } catch (_) {
      return false;
    }
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
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> removeFile(String collectionId, String fileId) async {
    try {
      await _dio.delete(ApiEndpoints.collectionFile(collectionId, fileId));
      return true;
    } catch (_) {
      return false;
    }
  }
}

final collectionsProvider = StateNotifierProvider.autoDispose<
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
