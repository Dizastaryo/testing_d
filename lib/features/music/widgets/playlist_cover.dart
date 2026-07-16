import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/design/design.dart';
import '../../../core/models/playlist.dart';

/// Обложка плейлиста — мозаика из четырёх обложек треков.
///
/// Пока треков с обложками меньше четырёх, мозаика не собирается: одна
/// картинка растягивается на весь квадрат, а совсем пустой плейлист получает
/// пунктирную рамку с нотой. Наполовину собранная мозаика с дырами выглядит
/// как ошибка загрузки.
class PlaylistCover extends StatelessWidget {
  final Playlist playlist;
  final double radius;

  const PlaylistCover({super.key, required this.playlist, this.radius = 16});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final covers = playlist.coverUrls;

    Widget body;
    if (covers.length >= 4) {
      body = GridView.count(
        crossAxisCount: 2,
        physics: const NeverScrollableScrollPhysics(),
        children: [for (final url in covers.take(4)) _tile(url, c)],
      );
    } else if (covers.isNotEmpty) {
      body = _tile(covers.first, c);
    } else if (playlist.tracksCount > 0) {
      // Треки есть, но без обложек — плотный цвет, а не серая дыра.
      body = DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              SeeUColors.accentSecondary,
              SeeUColors.plum,
            ],
          ),
        ),
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(
              PhosphorIconsFill.musicNotes,
              size: 28,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ),
      );
    } else {
      body = DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface2,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Icon(PhosphorIcons.musicNotes(), size: 30, color: c.ink4),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: DecoratedBox(
        decoration: BoxDecoration(color: c.surface2),
        child: body,
      ),
    );
  }

  Widget _tile(String url, SeeUThemeColors c) => CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (_, __) => ColoredBox(color: c.surface2),
        errorWidget: (_, __, ___) => ColoredBox(color: c.surface2),
      );
}
