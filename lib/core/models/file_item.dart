import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../api/api_endpoints.dart';
import '../design/tokens.dart';
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
  final String slug;
  final int sortOrder;
  final String? icon; // Phosphor icon NAME (e.g. "BookOpen")
  final String? color; // hex string (e.g. "#FF5A3C")
  final String? description;
  final int filesCount;

  FileCategory({
    required this.id,
    required this.name,
    this.slug = '',
    this.sortOrder = 0,
    this.icon,
    this.color,
    this.description,
    this.filesCount = 0,
  });

  factory FileCategory.fromJson(Map<String, dynamic> json) => FileCategory(
        id: json['id'] ?? '',
        name: json['name'] ?? '',
        slug: json['slug'] ?? '',
        sortOrder: json['sort_order'] ?? 0,
        icon: json['icon'] as String?,
        color: json['color'] as String?,
        description: json['description'] as String?,
        filesCount: (json['files_count'] as num?)?.toInt() ?? 0,
      );

  /// Maps the seeded Phosphor icon NAME string → IconData.
  /// Falls back to a neutral "folder" icon for unknown / null names.
  static const Map<String, IconData> _iconByName = {
    'BookOpen': PhosphorIconsRegular.bookOpen,
    'GraduationCap': PhosphorIconsRegular.graduationCap,
    'Flask': PhosphorIconsRegular.flask,
    'NotePencil': PhosphorIconsRegular.notePencil,
    'Briefcase': PhosphorIconsRegular.briefcase,
    'DotsThreeCircle': PhosphorIconsRegular.dotsThreeCircle,
  };

  /// Resolved Phosphor [IconData] for this category's [icon] name.
  IconData get iconData =>
      _iconByName[icon ?? ''] ?? PhosphorIconsRegular.folderOpen;

  /// Resolved accent [Color] parsed from the [color] hex string.
  /// Falls back to the SeeU brand accent when missing / malformed.
  Color get colorValue => _parseHexColor(color) ?? SeeUColors.accent;

  static Color? _parseHexColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    var h = hex.trim().replaceFirst('#', '');
    if (h.length == 6) h = 'FF$h'; // add opaque alpha
    if (h.length != 8) return null;
    final value = int.tryParse(h, radix: 16);
    if (value == null) return null;
    return Color(value);
  }
}

class FileItem {
  final String id;
  final String userId;
  final String filename;
  final String title;
  final String authorName;
  final String language;
  final String fileUrl;
  final String mimeType;
  final int fileSize;
  final String categoryId;
  final int downloadsCount;
  final int likesCount;
  final int viewsCount;
  final int ratingsCount;
  final int ratingsSum;
  final int userRating; // 0 = not rated
  final bool isLiked;
  final bool isPreviewable;
  final String previewUrl;
  final String coverUrl;
  final String description;
  final int pagesCount;
  final String docFormat;
  final DateTime createdAt;
  final UserShort? user;
  final FileCategory? category;
  // Статус фоновой подготовки (конвертации в PDF) — приходит с бэкенда
  final String pdfConversionStatus; // 'none' | 'pending' | 'converting' | 'done' | 'failed'
  // Заполняется отдельным запросом/handler'ом
  final String? readingStatus; // 'want' | 'reading' | 'done' | null

  FileItem({
    required this.id,
    required this.userId,
    required this.filename,
    this.title = '',
    this.authorName = '',
    this.language = '',
    required this.fileUrl,
    required this.mimeType,
    required this.fileSize,
    this.categoryId = '',
    this.downloadsCount = 0,
    this.likesCount = 0,
    this.viewsCount = 0,
    this.ratingsCount = 0,
    this.ratingsSum = 0,
    this.userRating = 0,
    this.isLiked = false,
    this.isPreviewable = false,
    this.previewUrl = '',
    this.coverUrl = '',
    this.description = '',
    this.pagesCount = 0,
    this.docFormat = '',
    required this.createdAt,
    this.user,
    this.category,
    this.pdfConversionStatus = 'none',
    this.readingStatus,
  });

  factory FileItem.fromJson(Map<String, dynamic> json) => FileItem(
        id: json['id'] ?? '',
        userId: json['user_id'] ?? '',
        filename: json['filename'] ?? '',
        title: json['title'] ?? '',
        authorName: json['author_name'] ?? '',
        language: json['language'] ?? '',
        fileUrl: _absUrl(json['file_url']),
        mimeType: json['mime_type'] ?? '',
        fileSize: (json['file_size'] as num?)?.toInt() ?? 0,
        categoryId: json['category_id'] ?? '',
        downloadsCount: json['downloads_count'] ?? 0,
        likesCount: json['likes_count'] ?? 0,
        viewsCount: json['views_count'] ?? 0,
        ratingsCount: json['ratings_count'] ?? 0,
        ratingsSum: json['ratings_sum'] ?? 0,
        userRating: json['user_rating'] ?? 0,
        isLiked: json['is_liked'] ?? false,
        isPreviewable: json['is_previewable'] ?? false,
        previewUrl: json['preview_url'] ?? '',
        coverUrl: _absUrl(json['cover_url']),
        description: json['description'] ?? '',
        pagesCount: json['pages_count'] ?? 0,
        docFormat: json['doc_format'] ?? '',
        // Битую/пустую дату НЕ подменяем на now() — иначе файл с плохой датой
        // прыгает наверх сортировки по created_at как «только что». Эпоха
        // сортирует нейтрально (в конец).
        createdAt: DateTime.tryParse(json['created_at'] ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        user: json['user'] != null ? UserShort.fromJson(json['user']) : null,
        category: json['category'] != null ? FileCategory.fromJson(json['category']) : null,
        pdfConversionStatus: json['pdf_conversion_status'] as String? ?? 'none',
        readingStatus: json['reading_status'] as String?,
      );

  bool get hasCover => coverUrl.isNotEmpty;

  /// Форматы, требующие серверной подготовки (конвертации в PDF).
  static const _convertibleFormats = {'fb2', 'docx', 'rtf', 'odt', 'pptx', 'odp'};

  /// Файл требует подготовки перед чтением (не PDF/EPUB/TXT/MD).
  bool get needsPreparation => _convertibleFormats.contains(fileExtension);

  /// Подготовка ещё в процессе.
  bool get isBeingPrepared =>
      needsPreparation &&
      (pdfConversionStatus == 'pending' || pdfConversionStatus == 'converting');

  /// Файл готов к чтению прямо сейчас.
  bool get isReadyToRead => !needsPreparation || pdfConversionStatus == 'done';

  double get averageRating => ratingsCount == 0 ? 0 : ratingsSum / ratingsCount;

  FileItem copyWith({int? likesCount, int? viewsCount, int? userRating, bool? isLiked, String? readingStatus}) => FileItem(
        id: id,
        userId: userId,
        filename: filename,
        title: title,
        authorName: authorName,
        language: language,
        fileUrl: fileUrl,
        mimeType: mimeType,
        fileSize: fileSize,
        categoryId: categoryId,
        downloadsCount: downloadsCount,
        likesCount: likesCount ?? this.likesCount,
        viewsCount: viewsCount ?? this.viewsCount,
        ratingsCount: ratingsCount,
        ratingsSum: ratingsSum,
        userRating: userRating ?? this.userRating,
        isLiked: isLiked ?? this.isLiked,
        isPreviewable: isPreviewable,
        previewUrl: previewUrl,
        coverUrl: coverUrl,
        description: description,
        pagesCount: pagesCount,
        docFormat: docFormat,
        createdAt: createdAt,
        user: user,
        category: category,
        pdfConversionStatus: pdfConversionStatus,
        readingStatus: readingStatus ?? this.readingStatus,
      );

  String get displayTitle => title.isNotEmpty ? title : _stripExtension(filename);

  String _stripExtension(String s) {
    final dot = s.lastIndexOf('.');
    return dot == -1 ? s : s.substring(0, dot);
  }

  String get fileSizeFormatted {
    if (fileSize >= 1073741824) return '${(fileSize / 1073741824).toStringAsFixed(1)} GB';
    if (fileSize >= 1048576) return '${(fileSize / 1048576).toStringAsFixed(1)} MB';
    if (fileSize >= 1024) return '${(fileSize / 1024).toStringAsFixed(0)} KB';
    return '$fileSize B';
  }

  String get fileExtension {
    if (docFormat.isNotEmpty) return docFormat;
    final dot = filename.lastIndexOf('.');
    if (dot == -1) return '';
    return filename.substring(dot + 1).toLowerCase();
  }

  /// Все поддерживаемые форматы открываются как оригинальный документ.
  /// PDF/EPUB/TXT/MD — нативный in-app ридер.
  /// FB2/DOCX/RTF/ODT/PPTX/ODP — конвертация в PDF на бэкенде (LibreOffice).
  bool get isTier1 =>
      const {'pdf', 'epub', 'txt', 'md', 'fb2', 'docx', 'rtf', 'odt', 'pptx', 'odp'}
          .contains(fileExtension);

  String get formatLabel {
    switch (fileExtension) {
      case 'pdf': return 'PDF';
      case 'epub': return 'EPUB';
      case 'fb2': return 'FB2';
      case 'docx': return 'DOCX';
      case 'pptx': return 'PPTX';
      case 'txt': return 'TXT';
      case 'rtf': return 'RTF';
      case 'md': return 'MD';
      case 'odt': return 'ODT';
      case 'odp': return 'ODP';
      default: return fileExtension.toUpperCase();
    }
  }

  String get downloadsFormatted {
    if (downloadsCount >= 1000) return '${(downloadsCount / 1000).toStringAsFixed(1)}K';
    return downloadsCount.toString();
  }
}
