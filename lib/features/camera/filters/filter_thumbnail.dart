import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../../../core/design/tokens.dart';
import 'filter_state.dart';

/// Превью фильтра: маленький кружок с реальным изображением (или градиентом).
///
/// Если [imageBytes] задан — показывает захваченный кадр с применённым фильтром
/// через [ColorFiltered] + матрицу цвета.
/// Иначе — цветной gradient-placeholder на основе параметров фильтра.
class FilterThumbnail extends StatelessWidget {
  final FilterState filter;
  final Uint8List? imageBytes;
  final bool isSelected;
  final String label;
  final VoidCallback onTap;
  final double size;

  const FilterThumbnail({
    super.key,
    required this.filter,
    required this.isSelected,
    required this.label,
    required this.onTap,
    this.imageBytes,
    this.size = 58,
  });

  /// Build a 5x4 ColorFilter matrix from the FilterState params.
  /// Brightness, contrast, saturation, warmth applied inline.
  ColorFilter _buildColorFilter() {
    final s = filter;

    // Saturation matrix
    final sr = 0.3086;
    final sg = 0.6094;
    final sb = 0.0820;
    final sat = 1.0 + s.saturation;
    final sr1 = (1 - sat) * sr + sat;
    final sg1 = (1 - sat) * sg;
    final sb1 = (1 - sat) * sb;
    final sr2 = (1 - sat) * sr;
    final sg2 = (1 - sat) * sg + sat;
    final sb2 = (1 - sat) * sb;
    final sr3 = (1 - sat) * sr;
    final sg3 = (1 - sat) * sg;
    final sb3 = (1 - sat) * sb + sat;

    // Brightness offset
    final b = s.brightness * 0.5;

    // Contrast scale (1 + contrast, bias to keep mid-grey stable)
    final c = 1.0 + s.contrast;
    final cOff = (1 - c) * 0.5;

    // Warmth (red+, blue-)
    final w = s.warmth * 0.15;

    // Final combined: sat → contrast → brightness → warmth
    // Simplified flat multiplication (not perfect but fast)
    final List<double> matrix = [
      sr1 * c, sg1 * c, sb1 * c, 0, (cOff + b + w) * 255,
      sr2 * c, sg2 * c, sb2 * c, 0, (cOff + b) * 255,
      sr3 * c, sg3 * c, sb3 * c, 0, (cOff + b - w) * 255,
      0,       0,       0,       1, 0,
    ];

    return ColorFilter.matrix(matrix);
  }

  Color _placeholderColor() {
    final s = filter;
    if (s.isIdentity) return Colors.grey.shade700;
    if (s.warmth > 0.2) return const Color(0xFFD9854E);
    if (s.warmth < -0.15) return const Color(0xFF4A82D0);
    if (s.saturation < -0.3) return const Color(0xFF888888);
    if (s.grain > 0.3) return const Color(0xFF9A7055);
    if (s.liftBlacks > 0.15) return const Color(0xFF8A6EA8);
    if (s.fadeHighlights > 0.15) return const Color(0xFF7AAA88);
    return const Color(0xFF6A98C0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected
                    ? SeeUColors.accent
                    : Colors.white.withValues(alpha: 0.25),
                width: isSelected ? 2.5 : 1.0,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: SeeUColors.accent.withValues(alpha: 0.4),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
            child: ClipOval(
              child: imageBytes != null
                  ? ColorFiltered(
                      colorFilter: _buildColorFilter(),
                      child: Image.memory(
                        imageBytes!,
                        fit: BoxFit.cover,
                        width: size,
                        height: size,
                        gaplessPlayback: true,
                      ),
                    )
                  : _GradientPlaceholder(color: _placeholderColor()),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              color: isSelected
                  ? SeeUColors.accent
                  : Colors.white.withValues(alpha: 0.75),
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _GradientPlaceholder extends StatelessWidget {
  final Color color;
  const _GradientPlaceholder({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: 0.9),
            color.withValues(alpha: 0.4),
          ],
        ),
      ),
    );
  }
}
