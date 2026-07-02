import 'dart:convert';

class ReadingProgress {
  final String fileId;
  final Map<String, dynamic> position;
  final DateTime lastReadAt;

  ReadingProgress({
    required this.fileId,
    required this.position,
    required this.lastReadAt,
  });

  factory ReadingProgress.fromJson(Map<String, dynamic> json) {
    final pos = json['position'];
    Map<String, dynamic> posMap = {};
    if (pos is Map) posMap = Map<String, dynamic>.from(pos);
    if (pos is String) {
      try { posMap = Map<String, dynamic>.from(jsonDecode(pos) as Map); } catch (_) {}
    }
    return ReadingProgress(
      fileId: json['file_id'] ?? '',
      position: posMap,
      lastReadAt: DateTime.tryParse(json['last_read_at'] ?? '') ?? DateTime.now(),
    );
  }

  /// Процент прочтения (0.0–1.0) для PDF (page/total) или offset/total.
  double get percentage {
    if (position.containsKey('page') && position.containsKey('total')) {
      final page = (position['page'] as num?)?.toInt() ?? 0;
      final total = (position['total'] as num?)?.toInt() ?? 1;
      return total > 0 ? page / total : 0;
    }
    if (position.containsKey('offset') && position.containsKey('total')) {
      final offset = (position['offset'] as num?)?.toDouble() ?? 0;
      final total = (position['total'] as num?)?.toDouble() ?? 1;
      return total > 0 ? (offset / total).clamp(0.0, 1.0) : 0;
    }
    if (position.containsKey('pct')) {
      return ((position['pct'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0);
    }
    return 0;
  }

  String get displayProgress {
    if (position.containsKey('page') && position.containsKey('total')) {
      return 'Стр. ${(position['page'] as num?)?.toInt() ?? 0} / ${(position['total'] as num?)?.toInt() ?? 0}';
    }
    return '${(percentage * 100).toInt()}%';
  }
}

class FileBookmark {
  final String id;
  final String fileId;
  final Map<String, dynamic> position;
  final String note;
  final DateTime createdAt;

  FileBookmark({
    required this.id,
    required this.fileId,
    required this.position,
    required this.note,
    required this.createdAt,
  });

  factory FileBookmark.fromJson(Map<String, dynamic> json) {
    final pos = json['position'];
    Map<String, dynamic> posMap = {};
    if (pos is Map) posMap = Map<String, dynamic>.from(pos);
    return FileBookmark(
      id: json['id'] ?? '',
      fileId: json['file_id'] ?? '',
      position: posMap,
      note: json['note'] ?? '',
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
    );
  }
}

class ReadingGoal {
  final int year;
  final int goalBooks;
  final int doneBooks;

  ReadingGoal({required this.year, required this.goalBooks, required this.doneBooks});

  double get progress => goalBooks == 0 ? 0 : (doneBooks / goalBooks).clamp(0.0, 1.0);
  bool get achieved => doneBooks >= goalBooks;

  factory ReadingGoal.fromJson(Map<String, dynamic> json) => ReadingGoal(
        year: json['year'] ?? DateTime.now().year,
        goalBooks: json['goal_books'] ?? 0,
        doneBooks: json['done_books'] ?? 0,
      );
}

class ReadingStatus {
  final String fileId;
  final String status;
  final DateTime updatedAt;

  ReadingStatus({
    required this.fileId,
    required this.status,
    required this.updatedAt,
  });

  factory ReadingStatus.fromJson(Map<String, dynamic> json) => ReadingStatus(
        fileId: json['file_id'] ?? '',
        status: json['status'] ?? '',
        updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
      );
}
