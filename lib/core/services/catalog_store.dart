import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/catalog_entry.dart';
import 'offline_storage_service.dart';

// ─── CatalogStore (абстракция) ───────────────────────────────────────────────

/// Абстракция хранилища каталога оффлайн-библиотеки.
///
/// Отвечает только за CRUD каталожных записей, SQL-запросы и агрегаты.
/// Не знает о файловой системе, сети и бизнес-логике.
abstract class CatalogStore {
  // ── Lifecycle ──
  Future<void> open();
  Future<void> close();

  // ── CRUD ──
  Future<void> upsert(CatalogEntry entry);
  Future<void> deleteById(String fileId);
  Future<CatalogEntry?> findById(String fileId);
  Future<bool> exists(String fileId);

  // ── Queries ──
  Future<List<CatalogEntry>> query({
    String? searchText,
    OfflineKind? kind,
    String? tag,
    String? collectionId,
    CatalogSortField sortBy = CatalogSortField.savedAt,
    bool descending = true,
    int limit = 30,
    int offset = 0,
  });

  Future<int> count({OfflineKind? kind, String? tag, String? collectionId});

  // ── Aggregates ──
  Future<int> totalSizeBytes();
  Future<Map<OfflineKind, int>> countByKind();

  // ── Tags ──
  Future<void> addTag(String fileId, String tag);
  Future<void> removeTag(String fileId, String tag);
  Future<List<String>> allTags();

  // ── Collections ──
  Future<void> addToCollection(String fileId, String collectionId);
  Future<void> removeFromCollection(String fileId, String collectionId);

  // ── Reading progress ──
  Future<void> updateProgress(
      String fileId, double percent, String? position);
  Future<void> updateLastOpened(String fileId, DateTime when);

  // ── Bulk ──
  Future<List<String>> allFileIds();
  Future<void> deleteMany(List<String> fileIds);
}

// ─── SqliteCatalogStore ──────────────────────────────────────────────────────

/// Реализация [CatalogStore] на SQLite (sqflite).
///
/// БД: `offline_catalog.db` в applicationDocumentsDirectory.
/// Таблицы: offline_catalog, catalog_tags, catalog_collections, catalog_fts.
class SqliteCatalogStore implements CatalogStore {
  Database? _db;

  Database get _database {
    final db = _db;
    if (db == null) throw StateError('CatalogStore not opened');
    return db;
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  Future<void> open() async {
    if (_db != null) return;
    final appDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(appDir.path, 'offline_catalog.db');
    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: _onCreate,
      onOpen: (db) async {
        // D3: SQLite performance optimizations
        await db.execute('PRAGMA journal_mode=WAL');
        await db.execute('PRAGMA synchronous=NORMAL');
        await db.execute('PRAGMA cache_size=-8000'); // 8 MB cache
      },
    );
  }

  @override
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  // ── Schema ─────────────────────────────────────────────────────────────────

  Future<void> _onCreate(Database db, int version) async {
    // ── Основная таблица каталога ──
    await db.execute('''
      CREATE TABLE offline_catalog (
        file_id          TEXT    PRIMARY KEY,
        kind             TEXT    NOT NULL,
        local_path       TEXT    NOT NULL,
        size_bytes       INTEGER NOT NULL DEFAULT 0,
        saved_at         TEXT    NOT NULL,
        last_opened_at   TEXT,
        title            TEXT    NOT NULL DEFAULT '',
        author           TEXT,
        original_format  TEXT,
        cover_url        TEXT,
        cover_local_path TEXT,
        reading_percent  REAL    NOT NULL DEFAULT 0.0,
        reading_position TEXT
      )
    ''');

    // ── Теги ──
    await db.execute('''
      CREATE TABLE catalog_tags (
        file_id  TEXT NOT NULL REFERENCES offline_catalog(file_id) ON DELETE CASCADE,
        tag      TEXT NOT NULL,
        PRIMARY KEY (file_id, tag)
      )
    ''');

    // ── Коллекции ──
    await db.execute('''
      CREATE TABLE catalog_collections (
        file_id       TEXT NOT NULL REFERENCES offline_catalog(file_id) ON DELETE CASCADE,
        collection_id TEXT NOT NULL,
        PRIMARY KEY (file_id, collection_id)
      )
    ''');

    // ── FTS5 для полнотекстового поиска по title + author ──
    await db.execute('''
      CREATE VIRTUAL TABLE catalog_fts USING fts5(
        title,
        author,
        content='offline_catalog',
        content_rowid='rowid',
        tokenize='unicode61 remove_diacritics 2'
      )
    ''');

    // ── Триггеры синхронизации FTS ──
    await db.execute('''
      CREATE TRIGGER catalog_fts_insert AFTER INSERT ON offline_catalog BEGIN
        INSERT INTO catalog_fts(rowid, title, author)
        VALUES (NEW.rowid, NEW.title, NEW.author);
      END
    ''');

    await db.execute('''
      CREATE TRIGGER catalog_fts_delete AFTER DELETE ON offline_catalog BEGIN
        INSERT INTO catalog_fts(catalog_fts, rowid, title, author)
        VALUES ('delete', OLD.rowid, OLD.title, OLD.author);
      END
    ''');

    await db.execute('''
      CREATE TRIGGER catalog_fts_update AFTER UPDATE OF title, author
      ON offline_catalog BEGIN
        INSERT INTO catalog_fts(catalog_fts, rowid, title, author)
        VALUES ('delete', OLD.rowid, OLD.title, OLD.author);
        INSERT INTO catalog_fts(rowid, title, author)
        VALUES (NEW.rowid, NEW.title, NEW.author);
      END
    ''');

    // ── Индексы ──
    await db.execute(
        'CREATE INDEX idx_catalog_saved_at ON offline_catalog(saved_at DESC)');
    await db.execute('''
      CREATE INDEX idx_catalog_last_opened ON offline_catalog(last_opened_at DESC)
        WHERE last_opened_at IS NOT NULL
    ''');
    await db.execute(
        'CREATE INDEX idx_catalog_kind ON offline_catalog(kind)');
    await db.execute(
        'CREATE INDEX idx_catalog_title ON offline_catalog(title COLLATE NOCASE)');
    await db.execute(
        'CREATE INDEX idx_catalog_size ON offline_catalog(size_bytes DESC)');
    await db.execute(
        'CREATE INDEX idx_tags_tag ON catalog_tags(tag)');
    await db.execute(
        'CREATE INDEX idx_collections_cid ON catalog_collections(collection_id)');
  }

  // ── CRUD ───────────────────────────────────────────────────────────────────

  @override
  Future<void> upsert(CatalogEntry entry) async {
    await _database.insert(
      'offline_catalog',
      entry.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> deleteById(String fileId) async {
    await _database.delete(
      'offline_catalog',
      where: 'file_id = ?',
      whereArgs: [fileId],
    );
  }

  @override
  Future<CatalogEntry?> findById(String fileId) async {
    final rows = await _database.query(
      'offline_catalog',
      where: 'file_id = ?',
      whereArgs: [fileId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CatalogEntry.fromRow(rows.first);
  }

  @override
  Future<bool> exists(String fileId) async {
    final rows = await _database.rawQuery(
      'SELECT 1 FROM offline_catalog WHERE file_id = ? LIMIT 1',
      [fileId],
    );
    return rows.isNotEmpty;
  }

  // ── Queries ────────────────────────────────────────────────────────────────

  @override
  Future<List<CatalogEntry>> query({
    String? searchText,
    OfflineKind? kind,
    String? tag,
    String? collectionId,
    CatalogSortField sortBy = CatalogSortField.savedAt,
    bool descending = true,
    int limit = 30,
    int offset = 0,
  }) async {
    final where = <String>[];
    final args = <Object>[];
    var from = 'offline_catalog AS c';

    // FTS search
    if (searchText != null && searchText.isNotEmpty) {
      from = 'offline_catalog AS c '
          'JOIN catalog_fts AS f ON c.rowid = f.rowid';
      where.add('f.catalog_fts MATCH ?');
      args.add('$searchText*');
    }

    // Kind filter
    if (kind != null) {
      where.add('c.kind = ?');
      args.add(kind.name);
    }

    // Tag filter
    if (tag != null) {
      from += ' JOIN catalog_tags AS t ON c.file_id = t.file_id';
      where.add('t.tag = ?');
      args.add(tag);
    }

    // Collection filter
    if (collectionId != null) {
      from += ' JOIN catalog_collections AS cc ON c.file_id = cc.file_id';
      where.add('cc.collection_id = ?');
      args.add(collectionId);
    }

    final whereClause =
        where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';

    // Sort
    final dir = descending ? 'DESC' : 'ASC';
    final orderBy = switch (sortBy) {
      CatalogSortField.savedAt => 'c.saved_at $dir',
      CatalogSortField.lastOpenedAt => 'c.last_opened_at $dir',
      CatalogSortField.title => 'c.title COLLATE NOCASE $dir',
      CatalogSortField.sizeBytes => 'c.size_bytes $dir',
      CatalogSortField.readingPercent => 'c.reading_percent $dir',
    };

    final sql = 'SELECT c.* FROM $from $whereClause '
        'ORDER BY $orderBy LIMIT ? OFFSET ?';
    args.addAll([limit, offset]);

    final rows = await _database.rawQuery(sql, args);
    return rows.map(CatalogEntry.fromRow).toList();
  }

  @override
  Future<int> count({
    OfflineKind? kind,
    String? tag,
    String? collectionId,
  }) async {
    final where = <String>[];
    final args = <Object>[];
    var from = 'offline_catalog AS c';

    if (kind != null) {
      where.add('c.kind = ?');
      args.add(kind.name);
    }
    if (tag != null) {
      from += ' JOIN catalog_tags AS t ON c.file_id = t.file_id';
      where.add('t.tag = ?');
      args.add(tag);
    }
    if (collectionId != null) {
      from += ' JOIN catalog_collections AS cc ON c.file_id = cc.file_id';
      where.add('cc.collection_id = ?');
      args.add(collectionId);
    }

    final whereClause =
        where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';

    final rows = await _database.rawQuery(
      'SELECT COUNT(*) AS cnt FROM $from $whereClause',
      args,
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  // ── Aggregates ─────────────────────────────────────────────────────────────

  @override
  Future<int> totalSizeBytes() async {
    final rows = await _database.rawQuery(
      'SELECT COALESCE(SUM(size_bytes), 0) AS total FROM offline_catalog',
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  @override
  Future<Map<OfflineKind, int>> countByKind() async {
    final rows = await _database.rawQuery(
      'SELECT kind, COUNT(*) AS cnt FROM offline_catalog GROUP BY kind',
    );
    final result = <OfflineKind, int>{};
    for (final row in rows) {
      final kindStr = row['kind'] as String;
      final kind = switch (kindStr) {
        'pdf' => OfflineKind.pdf,
        'epub' => OfflineKind.epub,
        _ => OfflineKind.text,
      };
      result[kind] = row['cnt'] as int? ?? 0;
    }
    return result;
  }

  // ── Tags ───────────────────────────────────────────────────────────────────

  @override
  Future<void> addTag(String fileId, String tag) async {
    await _database.insert(
      'catalog_tags',
      {'file_id': fileId, 'tag': tag},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<void> removeTag(String fileId, String tag) async {
    await _database.delete(
      'catalog_tags',
      where: 'file_id = ? AND tag = ?',
      whereArgs: [fileId, tag],
    );
  }

  @override
  Future<List<String>> allTags() async {
    final rows = await _database.rawQuery(
      'SELECT DISTINCT tag FROM catalog_tags ORDER BY tag',
    );
    return rows.map((r) => r['tag'] as String).toList();
  }

  // ── Collections ────────────────────────────────────────────────────────────

  @override
  Future<void> addToCollection(String fileId, String collectionId) async {
    await _database.insert(
      'catalog_collections',
      {'file_id': fileId, 'collection_id': collectionId},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<void> removeFromCollection(String fileId, String collectionId) async {
    await _database.delete(
      'catalog_collections',
      where: 'file_id = ? AND collection_id = ?',
      whereArgs: [fileId, collectionId],
    );
  }

  // ── Reading progress ───────────────────────────────────────────────────────

  @override
  Future<void> updateProgress(
      String fileId, double percent, String? position) async {
    await _database.update(
      'offline_catalog',
      {
        'reading_percent': percent,
        'reading_position': position,
      },
      where: 'file_id = ?',
      whereArgs: [fileId],
    );
  }

  @override
  Future<void> updateLastOpened(String fileId, DateTime when) async {
    await _database.update(
      'offline_catalog',
      {'last_opened_at': when.toIso8601String()},
      where: 'file_id = ?',
      whereArgs: [fileId],
    );
  }

  // ── Bulk ───────────────────────────────────────────────────────────────────

  @override
  Future<List<String>> allFileIds() async {
    final rows = await _database.rawQuery(
      'SELECT file_id FROM offline_catalog',
    );
    return rows.map((r) => r['file_id'] as String).toList();
  }

  @override
  Future<void> deleteMany(List<String> fileIds) async {
    if (fileIds.isEmpty) return;
    final batch = _database.batch();
    for (final id in fileIds) {
      batch.delete('offline_catalog', where: 'file_id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }
}
