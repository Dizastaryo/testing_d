import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/design/design.dart';

/// Overlapping avatar stack — shared between sbory screens.
class SboryAvatarStack extends StatelessWidget {
  final List<String> names;
  final List<String> avatarUrls;
  final double size;
  final Color? ringColor;

  const SboryAvatarStack({
    super.key,
    required this.names,
    this.avatarUrls = const [],
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
            child: _avatar(shown[i], i < avatarUrls.length ? avatarUrls[i] : '', ring),
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

  Widget _avatar(String name, String avatarUrl, Color ring) {
    final seed = (name.codeUnitAt(0) + name.length) % SeeUColors.avatarPalettes.length;
    final pal = SeeUColors.avatarPalettes[seed];
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final resolvedUrl = avatarUrl.isEmpty
        ? null
        : avatarUrl.startsWith('http')
            ? avatarUrl
            : AppConfig.apiOrigin + avatarUrl;

    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        gradient: resolvedUrl == null ? LinearGradient(colors: pal) : null,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: ring, blurRadius: 0, spreadRadius: 2)],
      ),
      child: ClipOval(
        child: resolvedUrl != null
            ? CachedNetworkImage(
                imageUrl: resolvedUrl,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _fallback(initial, pal),
              )
            : _fallback(initial, pal),
      ),
    );
  }

  Widget _fallback(String initial, List<Color> pal) {
    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(colors: pal)),
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
