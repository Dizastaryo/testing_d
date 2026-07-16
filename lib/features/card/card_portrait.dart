import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'card_style.dart';

/// Карточка «Портрет» — единый компонент из дизайна. Используется в ленте
/// сканера, в аудитории («кто рядом смотрел») и как живое превью в студии.
///
/// Композиция (сверху вниз внутри левой колонки): фото в кольце акцента →
/// никнейм → короткий акцентный подчёрк → текст → (опц.) мета-строка.
/// Справа — действие (Spark-огонёк или блок).
class CardPortrait extends StatelessWidget {
  final CardTemplate template;
  final String photoUrl;

  /// Локально выбранное фото (живое превью в студии до загрузки на сервер).
  /// Если задано — показывается вместо [photoUrl].
  final Uint8List? photoBytes;

  final String nickname;
  final String text;

  /// Действие справа: [SparkHaloButton] в ленте/превью, [CardCircleButton] в аудитории.
  final Widget? trailing;

  /// Мета-строка под текстом (аудитория: «Spark · смотрел 3 раза»).
  final Widget? meta;

  final double photoSize;
  final double radius;
  final EdgeInsets padding;
  final double nickSize;
  final double textSize;
  final double barWidth;

  /// Свечение вокруг кольца фото (в ленте и превью есть, в аудитории нет).
  final bool photoGlow;

  const CardPortrait({
    super.key,
    required this.template,
    required this.photoUrl,
    this.photoBytes,
    required this.nickname,
    required this.text,
    this.trailing,
    this.meta,
    this.photoSize = 80,
    this.radius = 26,
    this.padding = const EdgeInsets.all(20),
    this.nickSize = 22,
    this.textSize = 14,
    this.barWidth = 34,
    this.photoGlow = true,
  });

  @override
  Widget build(BuildContext context) {
    final onColor = template.onColor;

    return Container(
      decoration: template.decoration(radius: radius),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          children: [
            // Мягкое radial-свечение поверх фона.
            if (template.overlay != null)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: template.overlay),
                ),
              ),
            // Тонкий световой кант сверху (inset 0 1px 0 rgba(255,255,255,.16)).
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 1,
                color: Colors.white.withValues(alpha: 0.16),
              ),
            ),
            Padding(
              padding: padding,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _photo(),
                        SizedBox(height: photoSize >= 86 ? 14 : 13),
                        Text(
                          nickname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: nickSize,
                            fontWeight: FontWeight.w800,
                            color: onColor,
                            letterSpacing: -0.4,
                            height: 1.1,
                          ),
                        ),
                        // Акцентный подчёрк.
                        Container(
                          width: barWidth,
                          height: 3,
                          margin: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: template.accent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        if (text.isNotEmpty)
                          Text(
                            text,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: textSize,
                              height: 1.45,
                              color: template.onColorSoft,
                            ),
                          ),
                        if (meta != null) ...[
                          const SizedBox(height: 11),
                          meta!,
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 16),
                    trailing!,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photo() {
    return Container(
      width: photoSize,
      height: photoSize,
      padding: const EdgeInsets.all(2.5), // кольцо акцента
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: template.accent,
        boxShadow: photoGlow
            ? [
                BoxShadow(
                  color: template.accent.withValues(alpha: 0.4),
                  blurRadius: 22,
                ),
              ]
            : null,
      ),
      child: ClipOval(
        child: Container(
          color: template.photoInner,
          child: photoBytes != null
              ? Image.memory(photoBytes!, fit: BoxFit.cover)
              : photoUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: photoUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => const SizedBox(),
                      errorWidget: (_, __, ___) => Icon(
                        PhosphorIcons.user(),
                        color: template.onColor.withValues(alpha: 0.5),
                        size: photoSize * 0.4,
                      ),
                    )
                  : Icon(
                      PhosphorIcons.user(),
                      color: template.onColor.withValues(alpha: 0.5),
                      size: photoSize * 0.4,
                    ),
        ),
      ),
    );
  }
}

/// Мета-строка карточки в аудитории: огонёк (в цвете шаблона) + подпись.
class CardMetaRow extends StatelessWidget {
  final CardTemplate template;
  final bool sparked;
  final String label;

  const CardMetaRow({
    super.key,
    required this.template,
    required this.sparked,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (sparked) ...[
          Icon(PhosphorIconsFill.fireSimple, size: 13, color: template.accent),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: template.onColor
                  .withValues(alpha: sparked ? 0.8 : 0.6),
            ),
          ),
        ),
      ],
    );
  }
}

/// Кнопка Spark: круг 66px с пульсирующим halo-кольцом и Lottie-огоньком.
/// Из дизайна: border 1px white20%, фон white9%, halo — кольцо white42%,
/// анимация scale .82→1.55 с затуханием (2.6s, бесконечно).
class SparkHaloButton extends StatefulWidget {
  final VoidCallback? onTap;
  final double size;
  final double flameSize;

  const SparkHaloButton({
    super.key,
    this.onTap,
    this.size = 66,
    this.flameSize = 52,
  });

  @override
  State<SparkHaloButton> createState() => _SparkHaloButtonState();
}

class _SparkHaloButtonState extends State<SparkHaloButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _halo;

  @override
  void initState() {
    super.initState();
    _halo = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  void dispose() {
    _halo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Пульсирующее halo-кольцо.
            AnimatedBuilder(
              animation: _halo,
              builder: (_, __) {
                final t = _halo.value;
                final scale = 0.82 + (1.55 - 0.82) * t;
                final opacity = (1 - t) * 0.55;
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.42 * opacity / 0.55),
                        width: 1,
                      ),
                    ),
                  ),
                );
              },
            ),
            // Сам круг.
            Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.09),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.20),
                  width: 1,
                ),
              ),
              alignment: Alignment.center,
              child: SizedBox(
                width: widget.flameSize,
                height: widget.flameSize,
                child: Lottie.asset('assets/small flame.json', repeat: true),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Круглая кнопка действия на карточке (в аудитории — «Заблокировать»).
/// Из дизайна: 66px, border white16%, фон white8%, иконка 24px white82%.
class CardCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;

  const CardCircleButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 66,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.08),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.16),
            width: 1,
          ),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 24, color: Colors.white.withValues(alpha: 0.82)),
      ),
    );
  }
}
