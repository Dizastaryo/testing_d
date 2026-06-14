import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// ─── OfflineKind ─────────────────────────────────────────────────────────────

enum OfflineKind {
  pdf,
  epub,
  text;

  String get _subdir {
    switch (this) {
      case OfflineKind.pdf:
        return 'offline_pdf';
      case OfflineKind.epub:
        return 'offline_epub';
      case OfflineKind.text:
        return 'offline_text';
    }
  }

  String _filename(String fileId) {
    switch (this) {
      case OfflineKind.pdf:
        return '$fileId.pdf';
      case OfflineKind.epub:
        return '$fileId.epub';
      case OfflineKind.text:
        return '$fileId.txt';
    }
  }

  /// Извлекает fileId из имени файла.
  /// Возвращает null если формат не совпадает или файл неполный (.downloading).
  String? _parseFileId(String filename) {
    if (filename.endsWith('.downloading')) return null;
    switch (this) {
      case OfflineKind.pdf:
        if (filename.endsWith('.pdf')) return filename.substring(0, filename.length - 4);
      case OfflineKind.epub:
        if (filename.endsWith('.epub')) return filename.substring(0, filename.length - 5);
      case OfflineKind.text:
        if (filename.endsWith('.txt')) return filename.substring(0, filename.length - 4);
    }
    return null;
  }
}

// ─── OfflineEntry ─────────────────────────────────────────────────────────────

class OfflineEntry {
  final String fileId;
  final OfflineKind kind;
  final String path;
  final int sizeBytes;
  final DateTime savedAt;

  const OfflineEntry({
    required this.fileId,
    required this.kind,
    required this.path,
    required this.sizeBytes,
    required this.savedAt,
  });
}

// ─── OfflineStorageService ───────────────────────────────────────────────────

/// Единое хранилище для оффлайн-файлов библиотеки.
///
/// Структура директорий (все под applicationDocumentsDirectory):
///   offline_pdf/{fileId}.pdf    — PDF и конвертированные документы
///   offline_epub/{fileId}.epub  — EPUB (постоянное, а не tmpDir)
///   offline_text/{fileId}.txt   — декодированный текст TXT/MD
///
/// Загрузка атомарна: сначала пишется в {file}.downloading, затем переименовывается.
/// Источник истины — файловая система. Без SQLite/Hive/SharedPreferences.
/// Синглтон через offlineStorageProvider; инициализация выполняется один раз.
class OfflineStorageService {
  late final Future<void> _initFuture;
  late String _appDocPath;

  OfflineStorageService() {
    _initFuture = _init();
  }

  // ── Инициализация ──────────────────────────────────────────────────────────

  Future<void> _init() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    _appDocPath = appDocDir.path;

    // Создаём поддиректории если не существуют
    for (final kind in OfflineKind.values) {
      final dir = Directory(p.join(_appDocPath, kind._subdir));
      if (!await dir.exists()) await dir.create(recursive: true);
    }

    await _migrateOldFiles();
    await _migrateToSharded();
  }

  // ── Миграция старых файлов ─────────────────────────────────────────────────

  /// Перемещает файлы из старой плоской структуры в новые поддиректории.
  /// Выполняется ровно один раз — маркер .offline_v1_migrated предотвращает повторы.
  /// Ошибки при переносе отдельных файлов не фатальны.
  Future<void> _migrateOldFiles() async {
    final markerFile = File(p.join(_appDocPath, '.offline_v1_migrated'));
    if (await markerFile.exists()) return;

    await for (final entity in Directory(_appDocPath).list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue; // пропускаем маркеры и скрытые файлы

      // Старые PDF: {fileId}.pdf напрямую в корне appDocDir
      if (name.endsWith('.pdf')) {
        final fileId = name.substring(0, name.length - 4);
        await _moveFile(entity, _filePath(fileId, OfflineKind.pdf));
        continue;
      }

      // Старые тексты: {fileId}_text.txt
      if (name.endsWith('_text.txt')) {
        final fileId = name.substring(0, name.length - 9); // убираем '_text.txt'
        await _moveFile(entity, _filePath(fileId, OfflineKind.text));
      }
    }

    await markerFile.writeAsString(DateTime.now().toIso8601String());
  }

  Future<void> _moveFile(File src, String destPath) async {
    try {
      final dest = File(destPath);
      if (await dest.exists()) {
        // Уже мигрировано — просто удаляем старый
        await src.delete();
        return;
      }
      // Пробуем атомарный rename (работает если на одном разделе ФС),
      // при ошибке падаем на copy + delete.
      try {
        await src.rename(destPath);
      } catch (_) {
        await src.copy(destPath);
        await src.delete();
      }
    } catch (_) {
      // Миграция некритична — пропускаем ошибочный файл
    }
  }

  // ── Миграция flat → sharded ────────────────────────────────────────────────

  /// Перемещает файлы из flat (offline_pdf/file.pdf) в sharded
  /// (offline_pdf/a1/a1b2c3d4.pdf) структуру.
  Future<void> _migrateToSharded() async {
    final markerFile = File(p.join(_appDocPath, '.offline_v2_sharded'));
    if (await markerFile.exists()) return;

    for (final kind in OfflineKind.values) {
      final dir = Directory(p.join(_appDocPath, kind._subdir));
      if (!await dir.exists()) continue;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (name.startsWith('.')) continue;
        final fileId = kind._parseFileId(name);
        if (fileId == null) continue;

        final shardedPath = _filePath(fileId, kind);
        if (entity.path == shardedPath) continue; // Already sharded

        final shardDir = Directory(p.dirname(shardedPath));
        if (!await shardDir.exists()) {
          await shardDir.create(recursive: true);
        }
        await _moveFile(entity, shardedPath);
      }
    }

    await markerFile.writeAsString(DateTime.now().toIso8601String());
  }

  // ── Пути ──────────────────────────────────────────────────────────────────

  /// Шардированный путь: offline_pdf/a1/a1b2c3d4.pdf
  /// Первые 2 символа UUID используются как поддиректория.
  String _shardDir(String fileId) =>
      fileId.length >= 2 ? fileId.substring(0, 2) : '00';

  String _filePath(String fileId, OfflineKind kind) =>
      p.join(_appDocPath, kind._subdir, _shardDir(fileId), kind._filename(fileId));


  // ── Публичный API ──────────────────────────────────────────────────────────

  /// Возвращает `true` если файл полностью скачан и доступен локально.
  Future<bool> isDownloaded(String fileId, OfflineKind kind) async {
    await _initFuture;
    return File(_filePath(fileId, kind)).exists();
  }

  /// Возвращает абсолютный путь к локальному файлу, или `null` если не скачан.
  Future<String?> localPath(String fileId, OfflineKind kind) async {
    await _initFuture;
    final path = _filePath(fileId, kind);
    return await File(path).exists() ? path : null;
  }

  /// Скачивает файл по [url] в оффлайн-хранилище.
  ///
  /// Гарантии:
  ///   — если файл уже скачан, повторного скачивания не происходит
  ///   — загрузка идёт в `{file}.downloading`; только после успеха переименовывается
  ///   — при ошибке временный файл удаляется
  ///
  /// [dio] — опционально; если не передан, создаётся с таймаутом 5 мин.
  /// [onProgress] — колбэк прогресса (received, total).
  Future<void> download(
    String fileId,
    OfflineKind kind,
    String url, {
    Dio? dio,
    CancelToken? cancelToken,
    void Function(int received, int total)? onProgress,
  }) async {
    await _initFuture;
    final destPath = _filePath(fileId, kind);

    // Не скачиваем повторно уже существующий файл
    if (await File(destPath).exists()) return;

    // Создаём shard-директорию если не существует
    final dir = Directory(p.dirname(destPath));
    if (!await dir.exists()) await dir.create(recursive: true);

    // Атомарная загрузка: пишем во временный файл, затем rename
    final tmpPath = '$destPath.downloading';
    final client =
        dio ?? Dio(BaseOptions(receiveTimeout: const Duration(minutes: 5)));
    try {
      await client.download(
        url,
        tmpPath,
        onReceiveProgress: onProgress,
        cancelToken: cancelToken,
      );
      await File(tmpPath).rename(destPath);
    } catch (e) {
      // Удаляем частично скачанный файл
      final tmp = File(tmpPath);
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    }
  }

  /// Копирует уже загруженный временный файл в постоянное хранилище (атомарно).
  Future<void> saveFromFile(
      String fileId, OfflineKind kind, String sourcePath) async {
    await _initFuture;
    final destPath = _filePath(fileId, kind);
    final dir = Directory(p.dirname(destPath));
    if (!await dir.exists()) await dir.create(recursive: true);
    final tmpPath = '$destPath.downloading';
    try {
      await File(sourcePath).copy(tmpPath);
      await File(tmpPath).rename(destPath);
    } catch (e) {
      final tmp = File(tmpPath);
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    }
  }

  /// Сохраняет декодированный текст (для TXT/MD ридера).
  Future<void> saveText(String fileId, String text) async {
    await _initFuture;
    final destPath = _filePath(fileId, OfflineKind.text);
    final dir = Directory(p.dirname(destPath));
    if (!await dir.exists()) await dir.create(recursive: true);
    final tmpPath = '$destPath.downloading';
    try {
      await File(tmpPath).writeAsString(text, flush: true);
      await File(tmpPath).rename(destPath);
    } catch (e) {
      final tmp = File(tmpPath);
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    }
  }

  /// Читает закэшированный текст. Возвращает `null` если кэша нет.
  Future<String?> readText(String fileId) async {
    await _initFuture;
    final file = File(_filePath(fileId, OfflineKind.text));
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  /// Удаляет локальную копию файла.
  Future<void> delete(String fileId, OfflineKind kind) async {
    await _initFuture;
    final file = File(_filePath(fileId, kind));
    if (await file.exists()) await file.delete();
    // Также чистим незавершённую загрузку, если есть
    final tmp = File('${file.path}.downloading');
    if (await tmp.exists()) await tmp.delete();
  }

  /// Возвращает все скачанные файлы, отсортированные по дате (новые первыми).
  /// Файлы с расширением .downloading (незавершённые) пропускаются.
  /// Предназначен для FutureProvider — не вызывать напрямую в build().
  Future<List<OfflineEntry>> listDownloaded() async {
    await _initFuture;
    final entries = <OfflineEntry>[];

    for (final kind in OfflineKind.values) {
      final dir = Directory(p.join(_appDocPath, kind._subdir));
      if (!await dir.exists()) continue;
      // Рекурсивный обход (поддерживает и flat и sharded структуру)
      await for (final entity in dir.list(recursive: true)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        final fileId = kind._parseFileId(name);
        if (fileId == null) continue;
        final stat = await entity.stat();
        entries.add(OfflineEntry(
          fileId: fileId,
          kind: kind,
          path: entity.path,
          sizeBytes: stat.size,
          savedAt: stat.modified,
        ));
      }
    }

    entries.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return entries;
  }

  /// Суммарный размер всех полностью скачанных файлов в байтах.
  /// Незавершённые загрузки (.downloading) не учитываются.
  Future<int> totalSizeBytes() async {
    await _initFuture;
    var total = 0;
    for (final kind in OfflineKind.values) {
      final dir = Directory(p.join(_appDocPath, kind._subdir));
      if (!await dir.exists()) continue;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is! File) continue;
        if (p.basename(entity.path).endsWith('.downloading')) continue;
        final stat = await entity.stat();
        total += stat.size;
      }
    }
    return total;
  }
}

// ─── Riverpod providers ───────────────────────────────────────────────────────

/// Синглтон OfflineStorageService на всё приложение.
/// Инициализируется один раз при создании; миграция старых файлов внутри.
final offlineStorageProvider = Provider<OfflineStorageService>((ref) {
  return OfflineStorageService();
});

/// Реактивная проверка: скачан ли конкретный файл нужного типа.
///
/// Пример использования в любом экране библиотеки:
/// ```dart
/// final downloaded = ref.watch(
///   isFileDownloadedProvider((fileId: file.id, kind: OfflineKind.pdf)),
/// );
/// ```
final isFileDownloadedProvider = FutureProvider.autoDispose
    .family<bool, ({String fileId, OfflineKind kind})>(
  (ref, arg) => ref.read(offlineStorageProvider).isDownloaded(arg.fileId, arg.kind),
);
