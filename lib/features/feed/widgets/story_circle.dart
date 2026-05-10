import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/design/design.dart';

class StoryCircle extends StatefulWidget {
  final String? imageUrl;
  final String username;
  final bool isSeen;
  final bool isOwn;
  final VoidCallback? onTap;
  final double size;

  const StoryCircle({
    super.key,
    this.imageUrl,
    required this.username,
    this.isSeen = false,
    this.isOwn = false,
    this.onTap,
    this.size = 64,
  });

  @override
  State<StoryCircle> createState() => _StoryCircleState();
}

class _StoryCircleState extends State<StoryCircle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

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
    final showGradientRing = !widget.isSeen && !widget.isOwn;
    final showSeenStyle = widget.isSeen && !widget.isOwn;

    return Tappable.scaled(
      onTap: widget.onTap,
      scaleFactor: 0.93,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              // Радар-halo: расходящийся оранжевый glow вокруг кольца.
              // Используется только для непрочитанной story.
              if (showGradientRing)
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
              // Outer ring container
              // L07: For own story, no ring so use size, not size + 4
              Container(
                width: widget.isOwn ? widget.size : widget.size + 4,
                height: widget.isOwn ? widget.size : widget.size + 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: showGradientRing
                      ? SeeUColors.accent
                      : showSeenStyle
                          ? SeeUColors.textQuaternary
                          : null,
                ),
                child: Padding(
                  padding: EdgeInsets.all(showGradientRing ? 2.0 : 0),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.bg,
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(showGradientRing ? 2 : 0),
                      child: ClipOval(
                        child: SizedBox(
                          width: widget.size,
                          height: widget.size,
                          child: showSeenStyle
                              ? ColorFiltered(
                                  colorFilter: const ColorFilter.mode(
                                      Colors.grey, BlendMode.saturation),
                                  child: Opacity(
                                    opacity: 0.6,
                                    child: _buildAvatar(c),
                                  ),
                                )
                              : _buildAvatar(c),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // "Your story" plus badge
              if (widget.isOwn)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: SeeUColors.accent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: c.bg,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Icon(PhosphorIcons.plus(),
                          color: Colors.white, size: 12),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          // L08: Use TextOverflow.ellipsis instead of manual _truncateUsername
          SizedBox(
            width: widget.size + 4,
            child: Text(
              widget.isOwn ? 'Ваша история' : widget.username,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SeeUTypography.micro.copyWith(
                fontWeight: FontWeight.w600,
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
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        placeholder: (_, __) => _placeholder(c),
        errorWidget: (_, __, ___) => _placeholder(c),
      );
    }
    return _placeholder(c);
  }

  Widget _placeholder(SeeUThemeColors c) {
    return Container(
      width: widget.size,
      height: widget.size,
      color: c.surface2,
      child: Center(
        child: Icon(PhosphorIcons.user(), color: c.ink3, size: 24),
      ),
    );
  }
}
