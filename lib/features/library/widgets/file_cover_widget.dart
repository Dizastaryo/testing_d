import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/design/design.dart';
import '../../../core/models/file_item.dart';

/// Cover widget for library files.
/// Shows network image if available, otherwise generates a beautiful
/// gradient cover with format icon, title excerpt, and decorative elements.
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
    this.borderRadius = SeeURadii.small,
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

class _GeneratedCover extends StatelessWidget {
  final FileItem file;
  final double? width;
  final double? height;

  const _GeneratedCover({required this.file, this.width, this.height});

  static const _gradients = <String, List<Color>>{
    'pdf': [Color(0xFFE53935), Color(0xFF8B1A1A)],
    'epub': [SeeUColors.accent, Color(0xFFBF360C)],
    'fb2': [Color(0xFF8E24AA), Color(0xFF4A148C)],
    'docx': [SeeUColors.info, Color(0xFF0D47A1)],
    'pptx': [Color(0xFF43A047), Color(0xFF1B5E20)],
    'txt': [Color(0xFF546E7A), Color(0xFF263238)],
    'rtf': [Color(0xFF6D4C41), Color(0xFF3E2723)],
    'md': [Color(0xFF00ACC1), Color(0xFF004D57)],
    'odt': [Color(0xFF039BE5), Color(0xFF01579B)],
    'odp': [Color(0xFFFB8C00), Color(0xFFBF360C)],
  };

  static const _icons = <String, IconData>{
    'pdf': PhosphorIconsBold.filePdf,
    'epub': PhosphorIconsBold.bookOpen,
    'fb2': PhosphorIconsBold.bookOpenText,
    'docx': PhosphorIconsBold.fileDoc,
    'pptx': PhosphorIconsBold.presentation,
    'txt': PhosphorIconsBold.fileText,
    'rtf': PhosphorIconsBold.fileText,
    'md': PhosphorIconsBold.fileCode,
    'odt': PhosphorIconsBold.fileDoc,
    'odp': PhosphorIconsBold.presentation,
  };

  @override
  Widget build(BuildContext context) {
    final fmt = file.fileExtension;
    final colors =
        _gradients[fmt] ?? [const Color(0xFF607D8B), const Color(0xFF37474F)];
    final icon = _icons[fmt] ?? PhosphorIconsBold.file;
    final label = file.formatLabel;
    final w = width ?? 56;
    final showTitle = w >= 80;

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
          // Decorative background icon
          Positioned(
            right: -w * 0.12,
            top: -w * 0.08,
            child: Opacity(
              opacity: 0.08,
              child: Icon(icon, size: w * 1.1, color: Colors.white),
            ),
          ),
          // Subtle horizontal lines texture
          if (showTitle)
            Positioned.fill(
              child: CustomPaint(
                painter: _LinesPainter(),
              ),
            ),
          // Content
          Padding(
            padding: EdgeInsets.all(w * 0.1),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (showTitle) ...[
                  const Spacer(flex: 2),
                  // Title text on cover
                  Text(
                    file.displayTitle,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: SeeUTypography.displayS.copyWith(
                      color: Colors.white,
                      fontSize: w * 0.12,
                      height: 1.2,
                      shadows: const [
                        Shadow(
                          color: Colors.black26,
                          blurRadius: 4,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                  if (file.authorName.isNotEmpty) ...[
                    SizedBox(height: w * 0.04),
                    Text(
                      file.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: SeeUTypography.kicker.copyWith(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: w * 0.075,
                      ),
                    ),
                  ],
                  const Spacer(flex: 3),
                ] else ...[
                  Icon(icon,
                      size: w * 0.45,
                      color: Colors.white.withValues(alpha: 0.9)),
                  SizedBox(height: w * 0.06),
                ],
                // Format badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    label,
                    style: SeeUTypography.monoLabel.copyWith(
                      color: Colors.white,
                      fontSize: w >= 80 ? 10 : 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                if (showTitle) SizedBox(height: w * 0.06),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 0.5;
    for (var y = 20.0; y < size.height; y += 12) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
