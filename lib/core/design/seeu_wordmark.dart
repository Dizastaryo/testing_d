import 'package:flutter/material.dart';

import 'tokens.dart';

/// Бренд-wordmark «SeeU» — подписной Pacifico, сплошной коралл (§03 дизайн-ядра).
/// Единый фирменный знак для шапок Ленты, Интересного и Сканера. Без градиента:
/// логотип читается как один знак, а не декоративная плашка.
class SeeUWordmark extends StatelessWidget {
  final double fontSize;
  const SeeUWordmark({super.key, this.fontSize = 27});

  @override
  Widget build(BuildContext context) {
    return Text(
      'SeeU',
      style: TextStyle(
        fontFamily: AppFonts.I.brand,
        fontSize: fontSize,
        height: 1.0,
        color: SeeUColors.accent,
      ),
    );
  }
}
