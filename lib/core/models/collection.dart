import 'file_item.dart';

/// Коллекция — плейлист в мире книг: подборка, которой можно поделиться.
///
/// Не путать с полкой: полка — это СОСТОЯНИЕ книги («Хочу», «Читаю»,
/// «Прочитано»), одно на книгу и всегда личное. Коллекция — это подборка:
/// книга может лежать в скольких угодно коллекциях независимо от статуса,
/// а коллекцию целиком можно открыть другому человеку.
class Collection {
  final String id;
  final String userId;
  final String name;
  final String description;
  final String? coverFileId;
  final int filesCount;
  final List<String> coverUrls;
  final List<FileItem> files;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Открыта по ссылке: любой, кому дали ссылку, увидит подборку (только чтение).
  final bool isPublic;

  /// Я ли владелец. У гостя нет правки, удаления и добавления книг.
  final bool isOwner;

  final String ownerUsername;
  final String ownerName;
  final String ownerAvatar;

  const Collection({
    required this.id,
    required this.userId,
    required this.name,
    required this.description,
    this.coverFileId,
    required this.filesCount,
    this.coverUrls = const [],
    this.files = const [],
    required this.createdAt,
    required this.updatedAt,
    this.isPublic = false,
    this.isOwner = true,
    this.ownerUsername = '',
    this.ownerName = '',
    this.ownerAvatar = '',
  });

  factory Collection.fromJson(Map<String, dynamic> json) {
    final filesRaw = json['files'] as List? ?? [];
    final coverRaw = json['cover_urls'] as List? ?? [];
    return Collection(
      id: json['id'] ?? '',
      userId: json['user_id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      coverFileId: json['cover_file_id'] as String?,
      filesCount: (json['files_count'] as num?)?.toInt() ?? filesRaw.length,
      coverUrls: coverRaw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList(),
      files: filesRaw
          .map((e) => FileItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt:
          DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
      isPublic: (json['is_public'] as bool?) ?? false,
      isOwner: (json['is_owner'] as bool?) ?? true,
      ownerUsername: (json['owner_username'] as String?) ?? '',
      ownerName: (json['owner_name'] as String?) ?? '',
      ownerAvatar: (json['owner_avatar'] as String?) ?? '',
    );
  }

  Collection copyWith({
    String? name,
    String? description,
    String? coverFileId,
    int? filesCount,
    List<String>? coverUrls,
    List<FileItem>? files,
    DateTime? updatedAt,
    bool? isPublic,
  }) =>
      Collection(
        id: id,
        userId: userId,
        name: name ?? this.name,
        description: description ?? this.description,
        coverFileId: coverFileId ?? this.coverFileId,
        filesCount: filesCount ?? this.filesCount,
        coverUrls: coverUrls ?? this.coverUrls,
        files: files ?? this.files,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        isPublic: isPublic ?? this.isPublic,
        isOwner: isOwner,
        ownerUsername: ownerUsername,
        ownerName: ownerName,
        ownerAvatar: ownerAvatar,
      );

  FileItem? get coverFile =>
      files.isNotEmpty ? files.first : null;
}
