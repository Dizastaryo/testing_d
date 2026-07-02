import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/design/design.dart';

/// Финальный экран успешной публикации.
class PublishSuccessScreen extends StatefulWidget {
  /// Превью опубликованного кадра (для фото). null → коралловый плейсхолдер.
  final Uint8List? thumbnailBytes;

  /// История (true) или публикация/рилс (false) — меняет тексты.
  final bool isStory;

  /// ID созданного поста — для кнопки «Открыть публикацию». null = не показывать.
  final String? publishedId;

  const PublishSuccessScreen({
    super.key,
    required this.thumbnailBytes,
    required this.isStory,
    this.publishedId,
  });

  @override
  State<PublishSuccessScreen> createState() => _PublishSuccessScreenState();
}

class _PublishSuccessScreenState extends State<PublishSuccessScreen>
    with TickerProviderStateMixin {
  late final AnimationController _ac;
  // "Post flies to feed" card animation — starts after badge fully appears
  late final AnimationController _flyAc;
  bool _flyVisible = false;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();

    _flyAc = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    // Heavy haptic when badge appears, then schedule fly animation
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) HapticFeedback.heavyImpact();
    });
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _flyVisible = true);
      _flyAc.forward();
    });
  }

  @override
  void dispose() {
    _ac.dispose();
    _flyAc.dispose();
    super.dispose();
  }

  Future<void> _shareContent() async {
    if (widget.thumbnailBytes == null) return;
    HapticFeedback.lightImpact();
    try {
      await Share.shareXFiles(
        [XFile.fromData(widget.thumbnailBytes!, mimeType: 'image/png',
            name: 'seeu_post.png')],
        text: widget.isStory ? 'Моя история в SeeU' : 'Мой пост в SeeU',
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final title = widget.isStory ? 'История опубликована!' : 'Опубликовано!';
    final subtitle = widget.isStory
        ? 'Ваша история уже видна друзьям\nв течение 24 часов.'
        : 'Ваш пост уже в ленте.\nДрузья увидят его прямо сейчас.';

    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          // "Post flies to feed" mini card animation
          if (_flyVisible && widget.thumbnailBytes != null)
            _FlyToFeedCard(
              bytes: widget.thumbnailBytes!,
              animation: _flyAc,
            ),
          // Soft coral glow
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.5),
                    radius: 1.1,
                    colors: [
                      SeeUColors.accent.withValues(alpha: 0.12),
                      SeeUColors.accent.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 36),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _CheckBadge(animation: _ac),
                          const SizedBox(height: 28),
                          AnimatedBuilder(
                            animation: _ac,
                            builder: (_, __) {
                              final t = Curves.easeOutCubic
                                  .transform(_ac.value.clamp(0.0, 1.0));
                              return Opacity(
                                opacity: t,
                                child: Transform.translate(
                                  offset: Offset(0, 12 * (1 - t)),
                                  child: Column(
                                    children: [
                                      Text(
                                        title,
                                        textAlign: TextAlign.center,
                                        style: SeeUTypography.displayM
                                            .copyWith(fontSize: 32, color: c.ink),
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        subtitle,
                                        textAlign: TextAlign.center,
                                        style: SeeUTypography.body.copyWith(
                                            fontSize: 15,
                                            color: c.ink3,
                                            height: 1.5),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 24),
                          AnimatedBuilder(
                            animation: _ac,
                            builder: (_, child) {
                              final t = Curves.easeOutCubic.transform(
                                  ((_ac.value - 0.3) / 0.7).clamp(0.0, 1.0));
                              return Opacity(
                                opacity: t,
                                child: Transform.scale(
                                  scale: 0.85 + 0.15 * t,
                                  child: child,
                                ),
                              );
                            },
                            child: _Thumb(bytes: widget.thumbnailBytes),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Actions
                Padding(
                  padding: const EdgeInsets.fromLTRB(36, 0, 36, 28),
                  child: Column(
                    children: [
                      _PrimaryButton(
                        label: 'Смотреть в ленте',
                        onTap: () {
                          HapticFeedback.selectionClick();
                          context.go('/feed');
                        },
                      ),
                      if (!widget.isStory && widget.publishedId != null) ...[
                        const SizedBox(height: 10),
                        _SecondaryButton(
                          label: 'Открыть публикацию',
                          icon: PhosphorIconsRegular.arrowSquareOut,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            context.go('/post/${widget.publishedId}');
                          },
                        ),
                      ],
                      const SizedBox(height: 10),
                      // Share button (only when thumbnail available)
                      if (widget.thumbnailBytes != null) ...[
                        _SecondaryButton(
                          label: 'Поделиться',
                          icon: PhosphorIconsRegular.shareFat,
                          onTap: _shareContent,
                        ),
                        const SizedBox(height: 10),
                      ],
                      _SecondaryButton(
                        label: 'Создать ещё',
                        icon: PhosphorIconsBold.plus,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          context.go('/story/create');
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Check badge with confetti ─────────────────────────────────────────────────

class _CheckBadge extends StatelessWidget {
  final Animation<double> animation;
  const _CheckBadge({required this.animation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) {
        final t = animation.value;
        final pop = SeeUMotion.overshoot.transform(t.clamp(0.0, 1.0));
        return SizedBox(
          width: 160,
          height: 160,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // More confetti — 10 pieces flying in all directions
              _Confetti(t: t, dx: 62, dy: -58, size: 14, color: SeeUColors.amber, radius: 4),
              _Confetti(t: t, dx: -64, dy: 22, size: 10, color: SeeUColors.plum, radius: 3),
              _Confetti(t: t, dx: -58, dy: -44, size: 8, color: const Color(0xFF5DB1FF), radius: 8),
              _Confetti(t: t, dx: 60, dy: 50, size: 9, color: SeeUColors.accentSecondary, radius: 3),
              _Confetti(t: t, dx: 0, dy: -72, size: 11, color: const Color(0xFF30D158), radius: 5),
              _Confetti(t: t, dx: 72, dy: 10, size: 7, color: SeeUColors.accent, radius: 3),
              _Confetti(t: t, dx: -72, dy: -10, size: 12, color: const Color(0xFFFFD60A), radius: 6),
              _Confetti(t: t, dx: 40, dy: -68, size: 8, color: const Color(0xFFBF5AF2), radius: 4),
              _Confetti(t: t, dx: -44, dy: 64, size: 10, color: SeeUColors.amber, radius: 3),
              _Confetti(t: t, dx: 20, dy: 74, size: 7, color: const Color(0xFF5DB1FF), radius: 5),

              Transform.scale(
                scale: 0.55 + 0.45 * pop,
                child: Container(
                  width: 114,
                  height: 114,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [SeeUColors.accentSecondary, SeeUColors.accent],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: SeeUColors.accent.withValues(alpha: 0.6),
                        blurRadius: 48,
                        offset: const Offset(0, 20),
                      ),
                    ],
                  ),
                  child: const Icon(PhosphorIconsBold.check,
                      color: Colors.white, size: 52),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Confetti extends StatelessWidget {
  final double t;
  final double dx, dy, size, radius;
  final Color color;
  const _Confetti({
    required this.t,
    required this.dx,
    required this.dy,
    required this.size,
    required this.color,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final e = Curves.easeOut.transform(t.clamp(0.0, 1.0));
    return Transform.translate(
      offset: Offset(dx * e, dy * e),
      child: Opacity(
        opacity: e,
        child: Transform.rotate(
          angle: e * 1.2,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(radius),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Thumb ─────────────────────────────────────────────────────────────────────

class _Thumb extends StatelessWidget {
  final Uint8List? bytes;
  const _Thumb({required this.bytes});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      height: 188,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SeeURadii.card),
        boxShadow: SeeUShadows.lg,
      ),
      clipBehavior: Clip.antiAlias,
      child: bytes != null
          ? Image.memory(bytes!, fit: BoxFit.cover)
          : const DecoratedBox(
              decoration: BoxDecoration(gradient: SeeUGradients.heroOrange),
            ),
    );
  }
}

// ── Buttons ───────────────────────────────────────────────────────────────────

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PrimaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [SeeUColors.accentSecondary, SeeUColors.accent],
          ),
          borderRadius: BorderRadius.circular(SeeURadii.medium),
          boxShadow: [
            BoxShadow(
              color: SeeUColors.accent.withValues(alpha: 0.45),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 16.5,
                fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final IconData icon;
  const _SecondaryButton({
    required this.label,
    required this.onTap,
    this.icon = PhosphorIconsBold.plus,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(SeeURadii.medium),
          border: Border.all(color: c.line),
          boxShadow: SeeUShadows.sm,
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: SeeUColors.accent, size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    color: c.ink, fontSize: 15.5, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// "Post flies to feed" card — mini thumbnail that swoops to bottom-left nav
// ────────────────────────────────────────────────────────────────────────────

class _FlyToFeedCard extends StatelessWidget {
  final Uint8List bytes;
  final Animation<double> animation;

  const _FlyToFeedCard({required this.bytes, required this.animation});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    // Start: center-ish (slightly below center), End: bottom-left (feed icon)
    final startX = size.width / 2 - 40;
    final startY = size.height * 0.38;
    final endX = size.width * 0.08; // feed tab left-ish
    final endY = size.height - 60.0; // nav bar

    final posX = Tween<double>(begin: startX, end: endX).animate(
      CurvedAnimation(parent: animation, curve: Curves.easeInBack),
    );
    final posY = Tween<double>(begin: startY, end: endY).animate(
      CurvedAnimation(parent: animation, curve: Curves.easeInBack),
    );
    final scale = Tween<double>(begin: 1.0, end: 0.15).animate(
      CurvedAnimation(parent: animation, curve: Curves.easeInBack),
    );
    final opacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
          parent: animation,
          curve: const Interval(0.75, 1.0, curve: Curves.easeOut)),
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) {
        return Positioned(
          left: posX.value,
          top: posY.value,
          child: Opacity(
            opacity: opacity.value,
            child: Transform.scale(
              scale: scale.value,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: SeeUShadows.md,
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.memory(bytes, fit: BoxFit.cover),
              ),
            ),
          ),
        );
      },
    );
  }
}
