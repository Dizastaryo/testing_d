import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/design/design.dart';

/// Кружок истории (§03): 62px; непросмотренная — градиент-кольцо 135°
/// #FFB547→#FF5A3C с зазором 2px фоном; просмотренная — блеклое кольцо
/// #E3D2C2→#D2BBA6 (аватар НЕ глушится); «Твоя» — dashed-круг с плюсом.
class StoryCircle extends StatefulWidget {
  final String? imageUrl;
  final String username;
  final bool isSeen;
  final bool isOwn;
  /// PROFILE-3: true если хотя бы одна из stories в группе — close-friends-only.
  /// Рисуем зелёное кольцо вместо градиента.
  final bool hasCloseFriendsStory;
  final VoidCallback? onTap;
  final double size;

  const StoryCircle({
    super.key,
    this.imageUrl,
    required this.username,
    this.isSeen = false,
    this.isOwn = false,
    this.hasCloseFriendsStory = false,
    this.onTap,
    this.size = 62,
  });

  @override
  State<StoryCircle> createState() => _StoryCircleState();
}

class _StoryCircleState extends State<StoryCircle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  // Кольца из дизайна §03.
  static const List<Color> _unseenRing = [SeeUColors.amber, SeeUColors.accent];
  static const List<Color> _seenRing = [Color(0xFFE3D2C2), Color(0xFFD2BBA6)];

  @override
  void initState() {
    super.initState();
    // Радар-дыхание для непрочитанной story. Запускаем условно — для seen/own
    // не нужно, но контроллер всегда есть, чтобы избежать null-cheking ниже.
    _pulse = AnimationController(
      vsync: this,
      duration: SeeUMotion.storyPulse,
    );
    if (_shouldPulse()) _pulse.repeat(reverse: true);
  }

  bool _shouldPulse() => !widget.isSeen && !widget.isOwn;

  @override
  void didUpdateWidget(covariant StoryCircle old) {
    super.didUpdateWidget(old);
    final wasPulsing = !old.isSeen && !old.isOwn;
    final shouldPulse = _shouldPulse();
    if (wasPulsing && !shouldPulse) {
      _pulse.stop();
    } else if (!wasPulsing && shouldPulse) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final showUnseenRing = !widget.isSeen && !widget.isOwn;

    return Tappable.scaled(
      onTap: widget.onTap,
      scaleFactor: 0.93,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              // Радар-halo: расходящийся оранжевый glow вокруг кольца
              // непросмотренной истории.
              if (showUnseenRing)
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) {
                    final eased = SeeUMotion.breathe.transform(_pulse.value);
                    final size = widget.size + 4 + 8.0 * eased;
                    final opacity = 0.18 + 0.22 * (1 - eased);
                    return IgnorePointer(
                      child: Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              SeeUColors.accent.withValues(alpha: opacity),
                              SeeUColors.accent.withValues(alpha: 0.0),
                            ],
                            stops: const [0.55, 1.0],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              if (widget.isOwn)
                // «Твоя» — dashed-круг с плюсом по центру (§03).
                CustomPaint(
                  painter: _DashedCirclePainter(color: c.ink4),
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.surface2,
                    ),
                    child: Center(
                      child: Icon(PhosphorIcons.plus(),
                          color: c.ink3, size: 20),
                    ),
                  ),
                )
              else
                // Кольцо: градиент (unseen/seen/CF) + зазор 2px фоном.
                Container(
                  width: widget.size + 5,
                  height: widget.size + 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: widget.hasCloseFriendsStory
                        ? const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [SeeUColors.success, Color(0xFF5DB1FF)],
                          )
                        : LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors:
                                widget.isSeen ? _seenRing : _unseenRing,
                          ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(2.5),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: c.bg, width: 2),
                      ),
                      child: ClipOval(child: _buildAvatar(c)),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: widget.size + 6,
            child: Text(
              widget.isOwn ? 'Твоя' : widget.username,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SeeUTypography.micro.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                // §03: непросмотренная — чернильная подпись, просмотренная и
                // «Твоя» — приглушённая.
                color: (!widget.isOwn && !widget.isSeen) ? c.ink : c.ink3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(SeeUThemeColors c) {
    if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: widget.imageUrl!,
        fit: BoxFit.cover,
        placeholder: (_, __) => _placeholder(c),
        errorWidget: (_, __, ___) => _placeholder(c),
      );
    }
    return _placeholder(c);
  }

  Widget _placeholder(SeeUThemeColors c) {
    return Container(
      color: c.surface2,
      child: Center(
        child: Icon(PhosphorIcons.user(), color: c.ink3, size: 24),
      ),
    );
  }
}

/// Пунктирная окружность для «Твоя» (§03: border 2px dashed).
class _DashedCirclePainter extends CustomPainter {
  final Color color;
  _DashedCirclePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 1;
    const dashCount = 14;
    final step = 2 * math.pi / dashCount;
    final dashAngle = step * 0.55;
    for (var i = 0; i < dashCount; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r),
        i * step,
        dashAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedCirclePainter oldDelegate) =>
      oldDelegate.color != color;
}
