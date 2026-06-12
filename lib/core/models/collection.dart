import 'file_item.dart';

class Collection {
  final String id;
  final String userId;
  final String name;
  final String description;
  final String? coverFileId;
  final int filesCount;
  final List<FileItem> files;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Collection({
    required this.id,
    required this.userId,
    required this.name,
    required this.description,
    this.coverFileId,
    required this.filesCount,
    this.files = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  factory Collection.fromJson(Map<String, dynamic> json) {
    final filesRaw = json['files'] as List? ?? [];
    return Collection(
      id: json['id'] ?? '',
      userId: json['user_id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      coverFileId: json['cover_file_id'] as String?,
      filesCount: (json['files_count'] as num?)?.toInt() ?? filesRaw.length,
      files: filesRaw
          .map((e) => FileItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt:
          DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
    );
  }

  FileItem? get coverFile =>
      files.isNotEmpty ? files.first : null;
}
