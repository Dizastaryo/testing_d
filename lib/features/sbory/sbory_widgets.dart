import 'package:flutter/material.dart';

import '../../core/design/design.dart';

/// Overlapping avatar stack — shared between sbory screens.
class SboryAvatarStack extends StatelessWidget {
  final List<String> names;
  final double size;
  final Color? ringColor;

  const SboryAvatarStack({
    super.key,
    required this.names,
    this.size = 28,
    this.ringColor,
  });

  static const _max = 4;

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final shown = names.take(_max).toList();
    final overflow = names.length > _max ? names.length - _max : 0;
    final ring = ringColor ?? c.surface;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < shown.length; i++)
          Transform.translate(
            offset: Offset(i == 0 ? 0 : -size * 0.3 * i, 0),
            child: _avatar(shown[i], ring),
          ),
        if (overflow > 0)
          Transform.translate(
            offset: Offset(-size * 0.3 * shown.length, 0),
            child: Container(
              width: size, height: size,
              decoration: BoxDecoration(
                color: c.surface2,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: ring, blurRadius: 0, spreadRadius: 2)],
              ),
              child: Center(
                child: Text(
                  '+$overflow',
                  style: TextStyle(
                    fontSize: size * 0.36,
                    fontWeight: FontWeight.w600,
                    color: c.ink2,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _avatar(String name, Color ring) {
    final seed = (name.codeUnitAt(0) + name.length) % SeeUColors.avatarPalettes.length;
    final pal = SeeUColors.avatarPalettes[seed];
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: pal),
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: ring, blurRadius: 0, spreadRadius: 2)],
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: size * 0.42,
          ),
        ),
      ),
    );
  }
}
