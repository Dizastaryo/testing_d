import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'seeu_theme_colors.dart';
import 'tappable.dart';

/// Единая кнопка «назад» — заменяет три параллельных реализации
/// (`IconButton`+`Navigator.pop`, голый `GestureDetector`, самодельный
/// `Tappable.scaled`) на один виджет: 40×40 hit-area, `context.pop()`.
class SeeUBackButton extends StatelessWidget {
  final VoidCallback? onTap;
  final Color? color;

  /// Отключает тап (напр. пока идёт загрузка) без замены на дефолтный
  /// `context.pop()` — просто передать `onTap: null` для этого недостаточно,
  /// т.к. null означает «используй дефолт».
  final bool enabled;

  const SeeUBackButton({super.key, this.onTap, this.color, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Tappable.scaled(
      onTap: !enabled ? null : (onTap ?? () => context.pop()),
      scaleFactor: 0.9,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Icon(PhosphorIcons.caretLeft(), color: color ?? c.ink, size: 22),
      ),
    );
  }
}
