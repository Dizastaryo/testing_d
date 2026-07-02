import 'dart:ui';

import 'package:flutter/material.dart';
import 'tokens.dart';

/// Bottom-sheet с фирменным glass-treatment'ом: backdrop-blur + лёгкий
/// оранжевый tint поверх контента + закруглённые верхние углы. Заменяет
/// плоский opaque-sheet — визуально согласуется с mini-player'ом и
/// onboarding-blob'ами.
///
/// API-совместим со старым: те же [builder], [isScrollControlled].
Future<T?> showSeeUBottomSheet<T>({
  required BuildContext context,
  required Widget Function(BuildContext) builder,
  bool isScrollControlled = false,
  double? maxChildSize,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(SeeURadii.sheet)),
    ),
    builder: (ctx) => ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(SeeURadii.sheet),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          decoration: BoxDecoration(
            // Оранжевый soft-tint поверх blur'а — без перекрытия контента,
            // ровно настолько чтобы поверхность ощущалась brand'овой.
            gradient: LinearGradient(
              colors: [
                SeeUColors.surface.withValues(alpha: 0.92),
                SeeUColors.surface.withValues(alpha: 0.94),
                SeeUColors.accentSoft.withValues(alpha: 0.55),
              ],
              stops: const [0.0, 0.6, 1.0],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            border: Border(
              top: BorderSide(
                color: SeeUColors.accent.withValues(alpha: 0.18),
                width: 1,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: SeeUColors.textTertiary.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              builder(ctx),
            ],
          ),
        ),
      ),
    ),
  );
}
