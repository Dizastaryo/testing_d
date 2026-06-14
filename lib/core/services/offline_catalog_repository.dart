import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/catalog_entry.dart';
import 'catalog_store.dart';
import 'offline_storage_service.dart';

// ─── DownloadProgress ────────────────────────────────────────────────────────

class DownloadProgress {
  final String fileId;
  final DownloadTaskStatus status;
  final double progress; // 0.0–1.0
  final String? error;

  const DownloadProgress({
    required this.fileId,
    required this.status,
    this.progress = 0,
    this.error,
  });
}

// ─── _DownloadTask (internal) ────────────────────────────────────────────────

class _DownloadTask {
  DownloadRequest request;
  DownloadTaskStatus status = DownloadTaskStatus.queued;
  double progress = 0;
  int retryCount = 0;
  DateTime enqueuedAt;
  CancelToken? cancelToken;
  String? error;

  _DownloadTask({required this.request}) : enqueuedAt = DateTime.now();
}

// ─── DownloadQueueManager ────────────────────────────────────────────────────

/// Очередь загрузок с приоритетами, pause/resume/cancel, retry.
///
/// maxConcurrentDownloads = 3 параллельных загрузки.
/// Приоритет 0 = наивысший (текущая книга), 10 = batch.
/// Retry: exponential backoff [2s, 8s, 30s], maxRetries=3.
class DownloadQueueManager {
  final OfflineStorageService _storage;
  final int maxConcurrentDownloads;
  static const _maxRetries = 3;
  static const _retryDelays = [
    Duration(seconds: 2),
    Duration(seconds: 8),
    Duration(seconds: 30),
  ];

  final List<_DownloadTask> _queue = [];
  final Map<String, _DownloadTask> _active = {};
  final _controller = StreamController<List<DownloadProgress>>.broadcast();
  final Map<String, StreamController<DownloadProgress>> _fileControllers = {};

  DownloadQueueManager({
    required OfflineStorageService storage,
    this.maxConcurrentDownloads = 3,
  }) : _storage = storage;

  void Function(String fileId, String localPath, DownloadRequest request)?
      onCompleted;

  // ── Public API ──

  void enqueue(DownloadRequest request) {
    if (_active.containsKey(request.fileId)) return;
    if (_queue.any((t) => t.request.fileId == request.fileId)) return;
    _queue.add(_DownloadTask(request: request));
    _sortQueue();
    _notifyAll();
    _processNext();
  }

  void cancel(String fileId) {
    final active = _active.remove(fileId);
    if (active != null) {
      active.cancelToken?.cancel('User cancelled');
      active.status = DownloadTaskStatus.failed;
      active.error = 'Отменено';
      _notifyFile(fileId, active);
    }
    _queue.removeWhere((t) => t.request.fileId == fileId);
    _fileControllers.remove(fileId)?.close();
    _notifyAll();
    _processNext();
  }

  void pause(String fileId) {
    final active = _active.remove(fileId);
    if (active != null) {
      active.cancelToken?.cancel('Paused');
      active.status = DownloadTaskStatus.paused;
      _queue.add(active);
      _notifyFile(fileId, active);
      _notifyAll();
      _processNext();
    } else {
      final idx = _queue.indexWhere((t) => t.request.fileId == fileId);
      if (idx >= 0) _queue[idx].status = DownloadTaskStatus.paused;
      _notifyAll();
    }
  }

  void resume(String fileId) {
    final idx = _queue.indexWhere((t) => t.request.fileId == fileId);
    if (idx >= 0 && _queue[idx].status == DownloadTaskStatus.paused) {
      _queue[idx].status = DownloadTaskStatus.queued;
      _sortQueue();
      _notifyAll();
      _processNext();
    }
  }

  void pauseAll() {
    for (final id in _active.keys.toList()) {
      pause(id);
    }
    for (final t in _queue) {
      if (t.status == DownloadTaskStatus.queued) {
        t.status = DownloadTaskStatus.paused;
      }
    }
    _notifyAll();
  }

  void resumeAll() {
    for (final t in _queue) {
      if (t.status == DownloadTaskStatus.paused) {
        t.status = DownloadTaskStatus.queued;
      }
    }
    _sortQueue();
    _notifyAll();
    _processNext();
  }

  void boostPriority(String fileId) {
    final idx = _queue.indexWhere((t) => t.request.fileId == fileId);
    if (idx >= 0) {
      final task = _queue.removeAt(idx);
      task.request = task.request.copyWith(priority: 0);
      task.status = DownloadTaskStatus.queued;
      _queue.insert(0, task);
      _notifyAll();
      _processNext();
    }
  }

  Stream<DownloadProgress> watch(String fileId) {
    _fileControllers[fileId] ??= StreamController<DownloadProgress>.broadcast();
    return _fileControllers[fileId]!.stream;
  }

  Stream<List<DownloadProgress>> watchAll() => _controller.stream;

  List<DownloadProgress> snapshot() {
    final all = <DownloadProgress>[];
    for (final t in _active.values) {
      all.add(_toProgress(t));
    }
    for (final t in _queue) {
      all.add(_toProgress(t));
    }
    return all;
  }

  bool isInQueue(String fileId) =>
      _active.containsKey(fileId) ||
      _queue.any((t) => t.request.fileId == fileId);

  // ── Internal ──

  void _sortQueue() {
    _queue.sort((a, b) {
      final pr = a.request.priority.compareTo(b.request.priority);
      if (pr != 0) return pr;
      return a.enqueuedAt.compareTo(b.enqueuedAt);
    });
  }

  void _processNext() {
    while (_active.length < maxConcurrentDownloads) {
      final idx =
          _queue.indexWhere((t) => t.status == DownloadTaskStatus.queued);
      if (idx < 0) break;
      final task = _queue.removeAt(idx);
      _startDownload(task);
    }
  }

  Future<void> _startDownload(_DownloadTask task) async {
    final fileId = task.request.fileId;
    task.status = DownloadTaskStatus.downloading;
    task.cancelToken = CancelToken();
    _active[fileId] = task;
    _notifyFile(fileId, task);
    _notifyAll();

    try {
      await _storage.download(
        fileId,
        task.request.kind,
        task.request.url,
        onProgress: (received, total) {
          if (total > 0) {
            task.progress = received / total;
            _notifyFile(fileId, task);
            _notifyAll();
          }
        },
      );

      task.status = DownloadTaskStatus.completed;
      task.progress = 1.0;
      _active.remove(fileId);
      _notifyFile(fileId, task);
      _fileControllers.remove(fileId)?.close();
      _notifyAll();

      final path = await _storage.localPath(fileId, task.request.kind);
      if (path != null) {
        onCompleted?.call(fileId, path, task.request);
      }
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        _active.remove(fileId);
      } else {
        _handleError(task, e.toString());
      }
    } catch (e) {
      _handleError(task, e.toString());
    }
    _processNext();
  }

  void _handleError(_DownloadTask task, String error) {
    final fileId = task.request.fileId;
    _active.remove(fileId);

    if (task.retryCount < _maxRetries) {
      task.retryCount++;
      task.status = DownloadTaskStatus.queued;
      task.error = null;
      _queue.add(task);
      _sortQueue();
      _notifyAll();

      final delay = _retryDelays[
          (task.retryCount - 1).clamp(0, _retryDelays.length - 1)];
      Future.delayed(delay, () {
        if (_queue.contains(task) && task.status == DownloadTaskStatus.queued) {
          _processNext();
        }
      });
    } else {
      task.status = DownloadTaskStatus.failed;
      task.error = error;
      _notifyFile(fileId, task);
      _notifyAll();
    }
  }

  DownloadProgress _toProgress(_DownloadTask t) => DownloadProgress(
        fileId: t.request.fileId,
        status: t.status,
        progress: t.progress,
        error: t.error,
      );

  void _notifyFile(String fileId, _DownloadTask t) {
    _fileControllers[fileId]?.add(_toProgress(t));
  }

  void _notifyAll() {
    if (!_controller.isClosed) {
      _controller.add(snapshot());
    }
  }

  void dispose() {
    _controller.close();
    for (final c in _fileControllers.values) {
      c.close();
    }
    for (final t in _active.values) {
      t.cancelToken?.cancel('Disposed');
    }
    _active.clear();
    _queue.clear();
  }
}

// ─── OfflineCatalogRepository ────────────────────────────────────────────────

/// Единая точка входа для оффлайн-библиотеки.
///
/// Координирует [CatalogStore] (SQLite каталог), [OfflineStorageService]
/// (blob-файлы) и [DownloadQueueManager] (очередь загрузок).
///
/// Самоинициализация: первый async вызов ждёт init().
class OfflineCatalogRepository {
  final CatalogStore _store;
  final OfflineStorageService _storage;
  late final DownloadQueueManager _queue;

  final Set<String> _knownIds = {};
  final Map<String, Completer<String>> _activeDownloads = {};
  late final Future<void> _initFuture;

  OfflineCatalogRepository({
    required CatalogStore store,
    required OfflineStorageService storage,
  })  : _store = store,
        _storage = storage {
    _queue = DownloadQueueManager(storage: _storage);
    _queue.onCompleted = _onDownloadCompleted;
    _initFuture = _init();
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  Future<void> _init() async {
    await _store.open();
    final ids = await _store.allFileIds();
    _knownIds.addAll(ids);

    if (_knownIds.isEmpty) {
      await _migrateFromFilesystem();
    }

    Future.delayed(const Duration(seconds: 5), reconcile);
  }

  Future<void> _ensureInit() => _initFuture;

  Future<void> dispose() async {
    _queue.dispose();
    _knownIds.clear();
    _activeDownloads.clear();
    await _store.close();
  }

  // ── Синхронные ────────────────────────────────────────────────────────────

  bool isDownloaded(String fileId) => _knownIds.contains(fileId);

  Future<CatalogEntry?> getEntry(String fileId) async {
    await _ensureInit();
    return _store.findById(fileId);
  }

  // ── Queries ──────────────────────────────────────────────────────────────

  Future<List<CatalogEntry>> list({
    String? search,
    OfflineKind? kind,
    String? tag,
    String? collectionId,
    CatalogSortField sortBy = CatalogSortField.savedAt,
    bool descending = true,
    int limit = 30,
    int offset = 0,
  }) async {
    await _ensureInit();
    return _store.query(
      searchText: search,
      kind: kind,
      tag: tag,
      collectionId: collectionId,
      sortBy: sortBy,
      descending: descending,
      limit: limit,
      offset: offset,
    );
  }

  Future<int> count({OfflineKind? kind}) async {
    await _ensureInit();
    return _store.count(kind: kind);
  }

  Future<int> totalSizeBytes() async {
    await _ensureInit();
    return _store.totalSizeBytes();
  }

  Future<Map<OfflineKind, int>> countByKind() async {
    await _ensureInit();
    return _store.countByKind();
  }

  // ── Мутации ──────────────────────────────────────────────────────────────

  Future<void> delete(String fileId) async {
    await _ensureInit();
    final entry = await _store.findById(fileId);
    if (entry != null) {
      await _storage.delete(fileId, entry.kind);
      await _deleteCover(fileId);
    }
    await _store.deleteById(fileId);
    _knownIds.remove(fileId);
  }

  Future<void> deleteMany(List<String> fileIds) async {
    await _ensureInit();
    for (final id in fileIds) {
      final entry = await _store.findById(id);
      if (entry != null) {
        await _storage.delete(id, entry.kind);
        await _deleteCover(id);
      }
    }
    await _store.deleteMany(fileIds);
    _knownIds.removeAll(fileIds);
  }

  Future<void> markOpened(String fileId) async {
    await _ensureInit();
    return _store.updateLastOpened(fileId, DateTime.now());
  }

  Future<void> updateProgress(
    String fileId,
    double percent,
    Map<String, dynamic> position,
  ) async {
    await _ensureInit();
    return _store.updateProgress(fileId, percent, position.toString());
  }

  // ── Tags & Collections ─────────────────────────────────────────────────

  Future<void> addTag(String fileId, String tag) async {
    await _ensureInit();
    return _store.addTag(fileId, tag);
  }

  Future<void> removeTag(String fileId, String tag) async {
    await _ensureInit();
    return _store.removeTag(fileId, tag);
  }

  Future<void> addToCollection(String fileId, String collectionId) async {
    await _ensureInit();
    return _store.addToCollection(fileId, collectionId);
  }

  Future<void> removeFromCollection(String fileId, String collectionId) async {
    await _ensureInit();
    return _store.removeFromCollection(fileId, collectionId);
  }

  // ── Download (с дедупликацией) ───────────────────────────────────────────

  Future<String> ensureAvailable(
    String fileId,
    OfflineKind kind,
    String url, {
    required String title,
    String? author,
    String? coverUrl,
    String? originalFormat,
  }) async {
    await _ensureInit();

    // 1. Уже в каталоге — вернуть путь.
    if (_knownIds.contains(fileId)) {
      final path = await _storage.localPath(fileId, kind);
      if (path != null) {
        await markOpened(fileId);
        return path;
      }
      await _store.deleteById(fileId);
      _knownIds.remove(fileId);
    }

    // 2. В очереди — повысить приоритет, ждать.
    if (_queue.isInQueue(fileId)) {
      _queue.boostPriority(fileId);
      final completer = Completer<String>();
      late StreamSubscription<DownloadProgress> sub;
      sub = _queue.watch(fileId).listen((p) {
        if (p.status == DownloadTaskStatus.completed) {
          sub.cancel();
          _storage.localPath(fileId, kind).then((path) {
            completer.complete(path);
          });
        } else if (p.status == DownloadTaskStatus.failed) {
          sub.cancel();
          completer.completeError(Exception(p.error ?? 'Download failed'));
        }
      });
      return completer.future;
    }

    // 3. Уже качается — ждать тот же Future.
    if (_activeDownloads.containsKey(fileId)) {
      return _activeDownloads[fileId]!.future;
    }

    // 4. Начать загрузку.
    final completer = Completer<String>();
    _activeDownloads[fileId] = completer;

    try {
      await _storage.download(fileId, kind, url);
      final path = await _storage.localPath(fileId, kind);
      if (path == null) throw Exception('File not found after download');

      final file = File(path);
      final stat = await file.stat();

      final entry = CatalogEntry(
        fileId: fileId,
        kind: kind,
        localPath: path,
        sizeBytes: stat.size,
        savedAt: DateTime.now(),
        lastOpenedAt: DateTime.now(),
        title: title,
        author: author,
        originalFormat: originalFormat,
        coverUrl: coverUrl,
      );
      await _store.upsert(entry);
      _knownIds.add(fileId);

      if (coverUrl != null && coverUrl.isNotEmpty) {
        _downloadCover(fileId, coverUrl);
      }

      completer.complete(path);
      return path;
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      _activeDownloads.remove(fileId);
    }
  }

  Future<String?> localPath(String fileId, OfflineKind kind) =>
      _storage.localPath(fileId, kind);

  // ── Download Queue ──────────────────────────────────────────────────────

  void enqueueDownload(DownloadRequest request) {
    _ensureInit().then((_) {
      if (_knownIds.contains(request.fileId)) return;
      _queue.enqueue(request);
    });
  }

  void cancelDownload(String fileId) => _queue.cancel(fileId);
  void pauseDownload(String fileId) => _queue.pause(fileId);
  void resumeDownload(String fileId) => _queue.resume(fileId);
  void pauseAllDownloads() => _queue.pauseAll();
  void resumeAllDownloads() => _queue.resumeAll();

  Stream<DownloadProgress> watchDownload(String fileId) => _queue.watch(fileId);
  Stream<List<DownloadProgress>> watchQueue() => _queue.watchAll();
  List<DownloadProgress> queueSnapshot() => _queue.snapshot();

  Future<void> _onDownloadCompleted(
      String fileId, String localPath, DownloadRequest request) async {
    await _ensureInit();
    final file = File(localPath);
    final stat = await file.stat();

    final entry = CatalogEntry(
      fileId: fileId,
      kind: request.kind,
      localPath: localPath,
      sizeBytes: stat.size,
      savedAt: DateTime.now(),
      title: request.title,
      author: request.author,
      originalFormat: request.originalFormat,
      coverUrl: request.coverUrl,
    );
    await _store.upsert(entry);
    _knownIds.add(fileId);

    if (request.coverUrl != null && request.coverUrl!.isNotEmpty) {
      _downloadCover(fileId, request.coverUrl!);
    }
  }

  // ── Cover Downloads ─────────────────────────────────────────────────────

  Future<void> _downloadCover(String fileId, String coverUrl) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final coversDir = Directory(p.join(appDir.path, 'offline_covers'));
      if (!await coversDir.exists()) {
        await coversDir.create(recursive: true);
      }
      final coverPath = p.join(coversDir.path, '$fileId.jpg');

      if (await File(coverPath).exists()) return;

      final dio = Dio(BaseOptions(receiveTimeout: const Duration(seconds: 30)));
      await dio.download(coverUrl, coverPath);

      final entry = await _store.findById(fileId);
      if (entry != null) {
        await _store.upsert(entry.copyWith(coverLocalPath: coverPath));
      }
    } catch (_) {}
  }

  Future<void> _deleteCover(String fileId) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final coverPath = p.join(appDir.path, 'offline_covers', '$fileId.jpg');
      final file = File(coverPath);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  // ── Reconciliation ─────────────────────────────────────────────────────

  Future<ReconcileResult> reconcile() async {
    await _ensureInit();
    final sw = Stopwatch()..start();
    var orphaned = 0;
    var unindexed = 0;

    final catalogIds = await _store.allFileIds();
    for (final fileId in catalogIds) {
      final entry = await _store.findById(fileId);
      if (entry == null) continue;
      if (!await File(entry.localPath).exists()) {
        await _store.deleteById(fileId);
        _knownIds.remove(fileId);
        orphaned++;
      }
    }

    final onDisk = await _storage.listDownloaded();
    for (final diskEntry in onDisk) {
      if (!_knownIds.contains(diskEntry.fileId)) {
        final entry = CatalogEntry(
          fileId: diskEntry.fileId,
          kind: diskEntry.kind,
          localPath: diskEntry.path,
          sizeBytes: diskEntry.sizeBytes,
          savedAt: diskEntry.savedAt,
          title: diskEntry.fileId,
        );
        await _store.upsert(entry);
        _knownIds.add(diskEntry.fileId);
        unindexed++;
      }
    }

    sw.stop();
    return ReconcileResult(
      orphanedEntries: orphaned,
      unindexedFiles: unindexed,
      elapsed: sw.elapsed,
    );
  }

  Future<void> _migrateFromFilesystem() async {
    final entries = await _storage.listDownloaded();
    if (entries.isEmpty) return;
    for (final e in entries) {
      final entry = CatalogEntry(
        fileId: e.fileId,
        kind: e.kind,
        localPath: e.path,
        sizeBytes: e.sizeBytes,
        savedAt: e.savedAt,
        title: e.fileId,
      );
      await _store.upsert(entry);
      _knownIds.add(e.fileId);
    }
  }

  // ── Storage Quota ──────────────────────────────────────────────────────

  int? maxStorageBytes;
  final Set<String> _pinnedIds = {};

  void pinFile(String fileId) => _pinnedIds.add(fileId);
  void unpinFile(String fileId) => _pinnedIds.remove(fileId);
  bool isPinned(String fileId) => _pinnedIds.contains(fileId);

  Future<int> enforceQuota() async {
    if (maxStorageBytes == null) return 0;
    await _ensureInit();

    var total = await _store.totalSizeBytes();
    if (total <= maxStorageBytes!) return 0;

    var deleted = 0;
    final candidates = await _store.query(
      sortBy: CatalogSortField.lastOpenedAt,
      descending: false,
      limit: 1000,
      offset: 0,
    );

    for (final entry in candidates) {
      if (total <= maxStorageBytes!) break;
      if (_pinnedIds.contains(entry.fileId)) continue;
      await delete(entry.fileId);
      total -= entry.sizeBytes;
      deleted++;
    }
    return deleted;
  }
}
