import '../api/api_endpoints.dart';
import 'user.dart';

String _absUrl(String? url) {
  if (url == null || url.isEmpty) return '';
  if (url.startsWith('/')) {
    return ApiEndpoints.libraryBaseUrl.replaceAll('/api/v1', '') + url;
  }
  return url;
}

class FileCategory {
  final String id;
  final String name;

  FileCategory({required this.id, required this.name});

  factory FileCategory.fromJson(Map<String, dynamic> json) => FileCategory(
        id: json['id'] ?? '',
        name: json['name'] ?? '',
      );
}

class FileItem {
  final String id;
  final String userId;
  final String filename;
  final String fileUrl;
  final String mimeType;
  final int fileSize;
  final String categoryId;
  final int downloadsCount;
  final int likesCount;
  final bool isLiked;
  final bool isPreviewable;
  final String previewUrl;
  final String description;
  final DateTime createdAt;
  final UserShort? user;
  final FileCategory? category;

  FileItem({
    required this.id,
    required this.userId,
    required this.filename,
    required this.fileUrl,
    required this.mimeType,
    required this.fileSize,
    this.categoryId = '',
    this.downloadsCount = 0,
    this.likesCount = 0,
    this.isLiked = false,
    this.isPreviewable = false,
    this.previewUrl = '',
    this.description = '',
    required this.createdAt,
    this.user,
    this.category,
  });

  factory FileItem.fromJson(Map<String, dynamic> json) => FileItem(
        id: json['id'] ?? '',
        userId: json['user_id'] ?? '',
        filename: json['filename'] ?? '',
        fileUrl: _absUrl(json['file_url']),
        mimeType: json['mime_type'] ?? '',
        fileSize: json['file_size'] ?? 0,
        categoryId: json['category_id'] ?? '',
        downloadsCount: json['downloads_count'] ?? 0,
        likesCount: json['likes_count'] ?? 0,
        isLiked: json['is_liked'] ?? false,
        isPreviewable: json['is_previewable'] ?? false,
        previewUrl: json['preview_url'] ?? '',
        description: json['description'] ?? '',
        createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
        user: json['user'] != null ? UserShort.fromJson(json['user']) : null,
        category: json['category'] != null ? FileCategory.fromJson(json['category']) : null,
      );

  FileItem copyWith({int? likesCount, bool? isLiked}) => FileItem(
        id: id,
        userId: userId,
        filename: filename,
        fileUrl: fileUrl,
        mimeType: mimeType,
        fileSize: fileSize,
        categoryId: categoryId,
        downloadsCount: downloadsCount,
        likesCount: likesCount ?? this.likesCount,
        isLiked: isLiked ?? this.isLiked,
        isPreviewable: isPreviewable,
        previewUrl: previewUrl,
        description: description,
        createdAt: createdAt,
        user: user,
        category: category,
      );

  String get fileSizeFormatted {
    if (fileSize >= 1073741824) return '${(fileSize / 1073741824).toStringAsFixed(1)} GB';
    if (fileSize >= 1048576) return '${(fileSize / 1048576).toStringAsFixed(1)} MB';
    if (fileSize >= 1024) return '${(fileSize / 1024).toStringAsFixed(0)} KB';
    return '$fileSize B';
  }

  String get fileExtension {
    final dot = filename.lastIndexOf('.');
    if (dot == -1) return '';
    return filename.substring(dot + 1).toLowerCase();
  }

  String get downloadsFormatted {
    if (downloadsCount >= 1000) return '${(downloadsCount / 1000).toStringAsFixed(1)}K';
    return downloadsCount.toString();
  }
}
