import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/models/file_item.dart';

/// Виджет обложки издания.
/// Если у файла есть cover_url — показывает изображение.
/// Иначе генерирует красивую авто-обложку с градиентом по типу формата.
class FileCoverWidget extends StatelessWidget {
  final FileItem file;
  final double? width;
  final double? height;
  final double borderRadius;

  const FileCoverWidget({
    super.key,
    required this.file,
    this.width,
    this.height,
    this.borderRadius = 10,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: file.hasCover
          ? CachedNetworkImage(
              imageUrl: file.coverUrl,
              width: width,
              height: height,
              fit: BoxFit.cover,
              placeholder: (_, __) => _GeneratedCover(
                file: file,
                width: width,
                height: height,
              ),
              errorWidget: (_, __, ___) => _GeneratedCover(
                file: file,
                width: width,
                height: height,
              ),
            )
          : _GeneratedCover(file: file, width: width, height: height),
    );
  }
}

/// Авто-сгенерированная обложка — градиент + иконка + формат.
class _GeneratedCover extends StatelessWidget {
  final FileItem file;
  final double? width;
  final double? height;

  const _GeneratedCover({required this.file, this.width, this.height});

  static const _gradients = <String, List<Color>>{
    'pdf':  [Color(0xFFE53935), Color(0xFF8B1A1A)],
    'epub': [Color(0xFFFF5A3C), Color(0xFFBF360C)],
    'fb2':  [Color(0xFF8E24AA), Color(0xFF4A148C)],
    'docx': [Color(0xFF1E88E5), Color(0xFF0D47A1)],
    'pptx': [Color(0xFF43A047), Color(0xFF1B5E20)],
    'txt':  [Color(0xFF546E7A), Color(0xFF263238)],
    'rtf':  [Color(0xFF6D4C41), Color(0xFF3E2723)],
    'md':   [Color(0xFF00ACC1), Color(0xFF004D57)],
    'odt':  [Color(0xFF039BE5), Color(0xFF01579B)],
    'odp':  [Color(0xFFFB8C00), Color(0xFFBF360C)],
  };

  static const _icons = <String, IconData>{
    'pdf':  PhosphorIconsBold.filePdf,
    'epub': PhosphorIconsBold.bookOpen,
    'fb2':  PhosphorIconsBold.bookOpenText,
    'docx': PhosphorIconsBold.fileDoc,
    'pptx': PhosphorIconsBold.presentation,
    'txt':  PhosphorIconsBold.fileText,
    'rtf':  PhosphorIconsBold.fileText,
    'md':   PhosphorIconsBold.fileCode,
    'odt':  PhosphorIconsBold.fileDoc,
    'odp':  PhosphorIconsBold.presentation,
  };

  @override
  Widget build(BuildContext context) {
    final fmt = file.fileExtension;
    final colors = _gradients[fmt] ?? [const Color(0xFF607D8B), const Color(0xFF37474F)];
    final icon = _icons[fmt] ?? PhosphorIconsBold.file;
    final label = file.formatLabel;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          // Subtle texture lines
          Positioned(
            right: -8,
            top: -8,
            child: Opacity(
              opacity: 0.1,
              child: Icon(icon, size: (width ?? 56) * 1.2, color: Colors.white),
            ),
          ),
          // Main content
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: (width ?? 56) * 0.45, color: Colors.white.withValues(alpha: 0.9)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'JetBrains Mono',
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
