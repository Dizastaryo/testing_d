import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/catalog_store.dart';
import '../services/offline_catalog_repository.dart';
import '../services/offline_storage_service.dart';

/// Синглтон [OfflineCatalogRepository] на всё приложение.
///
/// Координирует SQLite каталог и blob-хранилище.
/// Инициализация: вызывается один раз при старте через ref.read(...).init().
final offlineCatalogProvider = Provider<OfflineCatalogRepository>((ref) {
  final storage = ref.read(offlineStorageProvider);
  final store = SqliteCatalogStore();
  final repo = OfflineCatalogRepository(store: store, storage: storage);
  ref.onDispose(() => repo.dispose());
  return repo;
});

/// Синхронный O(1) провайдер: скачан ли файл для офлайн.
///
/// Заменяет [isFileDownloadedProvider] из offline_storage_service.dart.
/// Работает из in-memory Set без I/O.
final isOfflineProvider = Provider.family<bool, String>((ref, fileId) {
  final repo = ref.read(offlineCatalogProvider);
  return repo.isDownloaded(fileId);
});
