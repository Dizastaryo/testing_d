import '../services/offline_storage_service.dart';

// ─── CatalogSortField ────────────────────────────────────────────────────────

enum CatalogSortField {
  savedAt,
  lastOpenedAt,
  title,
  sizeBytes,
  readingPercent,
}

// ─── CatalogEntry ────────────────────────────────────────────────────────────

/// Запись в оффлайн-каталоге библиотеки.
///
/// Хранится в SQLite (таблица offline_catalog).
/// Содержит метаданные книги + путь к blob-файлу на диске.
class CatalogEntry {
  final String fileId;
  final OfflineKind kind;
  final String localPath;
  final int sizeBytes;
  final DateTime savedAt;
  final DateTime? lastOpenedAt;

  // ── Метаданные ──
  final String title;
  final String? author;
  final String? originalFormat;
  final String? coverUrl;
  final String? coverLocalPath;

  // ── Reading ──
  final double readingPercent;
  final String? readingPosition;

  const CatalogEntry({
    required this.fileId,
    required this.kind,
    required this.localPath,
    required this.sizeBytes,
    required this.savedAt,
    this.lastOpenedAt,
    required this.title,
    this.author,
    this.originalFormat,
    this.coverUrl,
    this.coverLocalPath,
    this.readingPercent = 0.0,
    this.readingPosition,
  });

  CatalogEntry copyWith({
    DateTime? lastOpenedAt,
    double? readingPercent,
    String? readingPosition,
    String? coverLocalPath,
  }) =>
      CatalogEntry(
        fileId: fileId,
        kind: kind,
        localPath: localPath,
        sizeBytes: sizeBytes,
        savedAt: savedAt,
        lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
        title: title,
        author: author,
        originalFormat: originalFormat,
        coverUrl: coverUrl,
        coverLocalPath: coverLocalPath ?? this.coverLocalPath,
        readingPercent: readingPercent ?? this.readingPercent,
        readingPosition: readingPosition ?? this.readingPosition,
      );

  /// Конвертация из строки SQLite в [OfflineKind].
  static OfflineKind _parseKind(String s) => switch (s) {
        'pdf' => OfflineKind.pdf,
        'epub' => OfflineKind.epub,
        _ => OfflineKind.text,
      };

  /// Создаёт [CatalogEntry] из строки SQLite.
  factory CatalogEntry.fromRow(Map<String, Object?> row) => CatalogEntry(
        fileId: row['file_id'] as String,
        kind: _parseKind(row['kind'] as String),
        localPath: row['local_path'] as String,
        sizeBytes: row['size_bytes'] as int? ?? 0,
        savedAt: DateTime.parse(row['saved_at'] as String),
        lastOpenedAt: row['last_opened_at'] != null
            ? DateTime.parse(row['last_opened_at'] as String)
            : null,
        title: row['title'] as String? ?? '',
        author: row['author'] as String?,
        originalFormat: row['original_format'] as String?,
        coverUrl: row['cover_url'] as String?,
        coverLocalPath: row['cover_local_path'] as String?,
        readingPercent: (row['reading_percent'] as num?)?.toDouble() ?? 0.0,
        readingPosition: row['reading_position'] as String?,
      );

  /// Конвертация в Map для SQLite INSERT/UPDATE.
  Map<String, Object?> toRow() => {
        'file_id': fileId,
        'kind': kind.name,
        'local_path': localPath,
        'size_bytes': sizeBytes,
        'saved_at': savedAt.toIso8601String(),
        'last_opened_at': lastOpenedAt?.toIso8601String(),
        'title': title,
        'author': author,
        'original_format': originalFormat,
        'cover_url': coverUrl,
        'cover_local_path': coverLocalPath,
        'reading_percent': readingPercent,
        'reading_position': readingPosition,
      };
}

// ─── DownloadRequest ─────────────────────────────────────────────────────────

/// Запрос на скачивание книги в оффлайн.
///
/// Передаётся в [OfflineCatalogRepository.enqueueDownload].
/// Содержит всю информацию для скачивания blob + создания CatalogEntry.
class DownloadRequest {
  final String fileId;
  final OfflineKind kind;
  final String url;

  // ── Метаданные (для записи в каталог) ──
  final String title;
  final String? author;
  final String? originalFormat;
  final String? coverUrl;

  /// Приоритет загрузки. 0 = наивысший (текущая книга), 10 = batch download.
  final int priority;

  const DownloadRequest({
    required this.fileId,
    required this.kind,
    required this.url,
    required this.title,
    this.author,
    this.originalFormat,
    this.coverUrl,
    this.priority = 5,
  });

  DownloadRequest copyWith({int? priority}) => DownloadRequest(
        fileId: fileId,
        kind: kind,
        url: url,
        title: title,
        author: author,
        originalFormat: originalFormat,
        coverUrl: coverUrl,
        priority: priority ?? this.priority,
      );
}

// ─── DownloadTaskStatus ──────────────────────────────────────────────────────

enum DownloadTaskStatus {
  queued,
  downloading,
  paused,
  completed,
  failed,
}

// ─── ReconcileResult ─────────────────────────────────────────────────────────

/// Результат reconciliation каталога и файловой системы.
class ReconcileResult {
  /// Записей в каталоге, для которых файл удалён ОС — удалены из каталога.
  final int orphanedEntries;

  /// Файлов на диске, которых не было в каталоге — добавлены.
  final int unindexedFiles;

  /// Время выполнения reconciliation.
  final Duration elapsed;

  const ReconcileResult({
    required this.orphanedEntries,
    required this.unindexedFiles,
    required this.elapsed,
  });
}
