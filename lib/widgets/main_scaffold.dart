import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../core/audio/audio_player_service.dart';
import '../core/design/tokens.dart';
import '../core/design/seeu_theme_colors.dart';
import '../core/design/tappable.dart';
import '../core/providers/profile_badge_provider.dart';
import 'mini_player.dart';

/// Global notifier for hiding bottom nav from within a screen (e.g., feed camera swipe).
final bottomNavHiddenNotifier = ValueNotifier<bool>(false);

Widget _navIcon(String name, bool filled) => CustomPaint(
      size: const Size(22, 22),
      painter: _NavIconPainter(name: name, filled: filled),
    );

// ─── Shell scaffold ──────────────────────────────────────────────────────────

class MainScaffold extends StatelessWidget {
  final Widget child;
  final bool showTabs;

  const MainScaffold({
    super.key,
    required this.child,
    required this.showTabs,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: child,
      // Нижняя панель непрозрачная, поэтому тянуть контент под неё нельзя —
      // он просто спрячется за глухой стеной. Scaffold сам укладывает тело
      // экрана НАД панелью, и экранам не нужно угадывать нижний отступ.
      extendBody: false,
      bottomNavigationBar: _SeeUBottomArea(showTabs: showTabs),
    );
  }
}

// ─── Stable bottom area ──────────────────────────────────────────────────────

class _SeeUBottomArea extends ConsumerStatefulWidget {
  final bool showTabs;
  const _SeeUBottomArea({required this.showTabs});

  @override
  ConsumerState<_SeeUBottomArea> createState() => _SeeUBottomAreaState();
}

class _SeeUBottomAreaState extends ConsumerState<_SeeUBottomArea> {
  @override
  void initState() {
    super.initState();
    bottomNavHiddenNotifier.addListener(_onHiddenChanged);
  }

  @override
  void dispose() {
    bottomNavHiddenNotifier.removeListener(_onHiddenChanged);
    super.dispose();
  }

  void _onHiddenChanged() => setState(() {});

  /// Библиотека живёт со своим нижним меню: пока пользователь внутри Читальни,
  /// общее меню приложения заменяется библиотечным (4 вкладки), а выход обратно
  /// в «Сервисы» — по кнопке «Выйти» сверху справа.
  static const _libraryTabs = [
    '/files',
    '/library/discover',
    '/library/shelf',
    '/library/profile',
  ];

  static bool _isLibrary(String loc) =>
      _libraryTabs.any((t) => loc == t || loc.startsWith('$t/'));

  static int _libraryIndex(String loc) {
    final i = _libraryTabs.indexWhere((t) => loc == t || loc.startsWith('$t/'));
    return i < 0 ? 0 : i;
  }

  /// Аудиотека — свой каркас: три вкладки, а не четыре. Каталог маленький,
  /// дробить его по типам рано: тип решается режимом внутри трека, а не
  /// отдельным разделом.
  static const _audioTabs = ['/music', '/music/search', '/music/mine'];

  /// Плеер и очередь показываем во весь экран — там своё нижнее управление,
  /// вкладки только мешали бы.
  static bool _isAudio(String loc) =>
      loc == '/music' ||
      loc.startsWith('/music/search') ||
      loc.startsWith('/music/mine');

  static int _audioIndex(String loc) {
    if (loc.startsWith('/music/search')) return 1;
    if (loc.startsWith('/music/mine')) return 2;
    return 0;
  }

  static int _locationToIndex(String loc) {
    if (loc.startsWith('/feed')) return 0;
    if (loc.startsWith('/explore')) return 1;
    if (loc.startsWith('/scanner')) return 2;
    if (loc.startsWith('/services') ||
        loc.startsWith('/music') ||
        loc.startsWith('/files') ||
        loc.startsWith('/sbory')) {
      return 3;
    }
    if (loc.startsWith('/profile')) return 4;
    return 0;
  }

  void _onTabTap(int index) {
    HapticFeedback.lightImpact();
    const routes = ['/feed', '/explore', '/scanner', '/services', '/profile'];
    context.go(routes[index]);
  }

  void _onLibraryTabTap(int index) {
    HapticFeedback.lightImpact();
    context.go(_libraryTabs[index]);
  }

  void _onAudioTabTap(int index) {
    HapticFeedback.lightImpact();
    context.go(_audioTabs[index]);
  }

  @override
  Widget build(BuildContext context) {
    if (bottomNavHiddenNotifier.value) return const SizedBox.shrink();

    // NB: a plain `.watch(...).track` instead of `.select((s) => s.track)` —
    // the selector form crashed in AOT/release ("Null check operator used on a
    // null value" inside Riverpod's _SelectorSubscription.read), taking the
    // whole bottom nav bar down so navigation stopped working on Android.
    final track = ref.watch(miniPlayerProvider).track;
    final hasMiniPlayer = track != null;
    final showTabs = widget.showTabs;

    if (!hasMiniPlayer && !showTabs) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final loc = GoRouterState.of(context).matchedLocation;
    final isLibrary = showTabs && _isLibrary(loc);
    final isAudio = showTabs && _isAudio(loc);
    final currentIndex = showTabs ? _locationToIndex(loc) : 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasMiniPlayer)
          Padding(
            padding: EdgeInsets.fromLTRB(
              0,
              showTabs ? 0 : 6,
              0,
              showTabs ? 6 : MediaQuery.of(context).padding.bottom + 6,
            ),
            child: SeeUMiniPlayer(onTap: () => context.push('/music/player')),
          ),
        if (isLibrary)
          _buildLibraryTabBar(context, isDark, _libraryIndex(loc))
        else if (isAudio)
          _buildServiceTabBar(
            context,
            index: _audioIndex(loc),
            onTap: _onAudioTabTap,
            items: const [
              (PhosphorIconsRegular.vinylRecord, PhosphorIconsFill.vinylRecord,
                  'Главная'),
              (
                PhosphorIconsRegular.magnifyingGlass,
                PhosphorIconsFill.magnifyingGlass,
                'Поиск'
              ),
              (PhosphorIconsRegular.playlist, PhosphorIconsFill.playlist,
                  'Моё'),
            ],
          )
        else if (showTabs)
          _buildTabBar(context, isDark, currentIndex),
      ],
    );
  }

  /// Нижнее меню сервиса (Аудиотека и всё, что придёт следом): непрозрачная
  /// полоса, Phosphor-иконки, активная — залитая цветом акцента.
  Widget _buildServiceTabBar(
    BuildContext context, {
    required int index,
    required void Function(int) onTap,
    required List<(IconData, IconData, String)> items,
  }) {
    final c = context.seeuColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: Tappable.scaled(
                    onTap: () => onTap(i),
                    scaleFactor: 0.88,
                    child: SizedBox(
                      height: 58,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            i == index ? items[i].$2 : items[i].$1,
                            size: 23,
                            color: i == index ? SeeUColors.accent : c.ink3,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            items[i].$3,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: i == index
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: i == index ? SeeUColors.accent : c.ink3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Библиотечное меню: Читальня · Обзор · Полка · Профиль. Тёплая бумага,
  /// тонкая линейка сверху, Phosphor-иконки (активная — залитая).
  Widget _buildLibraryTabBar(BuildContext context, bool isDark, int index) {
    final c = context.seeuColors;
    final items = <(IconData, IconData, String)>[
      (PhosphorIcons.bookOpen(), PhosphorIconsFill.bookOpen, 'Читальня'),
      (PhosphorIcons.compass(), PhosphorIconsFill.compass, 'Обзор'),
      (
        PhosphorIcons.bookmarkSimple(),
        PhosphorIconsFill.bookmarkSimple,
        'Полка'
      ),
      (PhosphorIcons.userCircle(), PhosphorIconsFill.userCircle, 'Профиль'),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (var i = 0; i < items.length; i++)
                Tappable.scaled(
                  onTap: () => _onLibraryTabTap(i),
                  scaleFactor: 0.88,
                  child: SizedBox(
                    width: 62,
                    height: 58,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          i == index ? items[i].$2 : items[i].$1,
                          size: 24,
                          color: i == index ? SeeUColors.accent : c.ink3,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          items[i].$3,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight:
                                i == index ? FontWeight.w700 : FontWeight.w500,
                            color: i == index ? SeeUColors.accent : c.ink3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar(BuildContext context, bool isDark, int currentIndex) {
    // Непрозрачная нижняя панель: сплошная заливка фоном темы и тонкая линия
    // сверху. Никакого blur — контент под панель не заезжает, размывать нечего,
    // а BackdropFilter на каждом кадре стоил дорого.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? SeeUColors.darkBg : SeeUColors.background,
        border: Border(
          top: BorderSide(
            color: isDark ? SeeUColors.darkLine : SeeUColors.borderSubtle,
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _NavItem(
                icon: _navIcon('feed', false),
                activeIcon: _navIcon('feed', true),
                label: 'Лента',
                isSelected: currentIndex == 0,
                onTap: () => _onTabTap(0),
              ),
              _NavItem(
                icon: _navIcon('search', false),
                activeIcon: _navIcon('search', true),
                label: 'Интересное',
                isSelected: currentIndex == 1,
                onTap: () => _onTabTap(1),
              ),
              _ScannerPill(
                isSelected: currentIndex == 2,
                onTap: () => _onTabTap(2),
              ),
              _NavItem(
                icon: _navIcon('services', false),
                activeIcon: _navIcon('services', true),
                label: 'Сервисы',
                isSelected: currentIndex == 3,
                onTap: () => _onTabTap(3),
              ),
              _NavItem(
                icon: _navIcon('user', false),
                activeIcon: _navIcon('user', true),
                label: 'Профиль',
                isSelected: currentIndex == 4,
                onTap: () => _onTabTap(4),
                // Бейдж «требует внимания» (§05): входящие запросы доступа +
                // follow-запросы. Best-effort — 0 прячет бейдж.
                badgeCount: ref.watch(profileBadgeProvider).maybeWhen(
                      data: (n) => n,
                      orElse: () => 0,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Scanner pill (center tab — USP) ─────────────────────────────────────

class _ScannerPill extends StatelessWidget {
  final bool isSelected;
  final VoidCallback onTap;

  const _ScannerPill({required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tappable.scaled(
      onTap: onTap,
      scaleFactor: 0.88,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [SeeUColors.accentSecondary, SeeUColors.accent],
          ),
          boxShadow: [
            BoxShadow(
              color: SeeUColors.accent.withValues(alpha: isSelected ? 0.55 : 0.35),
              blurRadius: isSelected ? 20 : 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: CustomPaint(
            size: const Size(24, 24),
            painter: _ScannerCenterIcon(active: isSelected),
          ),
        ),
      ),
    );
  }
}

class _ScannerCenterIcon extends CustomPainter {
  final bool active;
  const _ScannerCenterIcon({required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final center = Offset(s / 2, s / 2);
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = active ? 2.0 : 1.6
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: s * 0.38),
      -2.4, 4.8, false, paint);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: s * 0.22),
      -2.4, 4.8, false, paint);

    canvas.drawCircle(center, s * 0.08,
      Paint()..color = Colors.white..style = PaintingStyle.fill);

    final endX = center.dx + s * 0.38 * 0.62;
    final endY = center.dy - s * 0.38 * 0.78;
    canvas.drawLine(center, Offset(endX, endY),
      Paint()
        ..color = Colors.white
        ..strokeWidth = active ? 2.0 : 1.6
        ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_ScannerCenterIcon old) => old.active != active;
}

// ─── Nav item ────────────────────────────────────────────────────────────

class _NavItem extends StatefulWidget {
  final Widget icon;
  final Widget activeIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final int badgeCount;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;
  bool _wasSelected = false;

  @override
  void initState() {
    super.initState();
    _wasSelected = widget.isSelected;
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _bounceAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.2)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.2, end: 1.1)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 60,
      ),
    ]).animate(_bounceController);
  }

  @override
  void didUpdateWidget(covariant _NavItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected && !_wasSelected) {
      _bounceController.forward(from: 0);
    }
    _wasSelected = widget.isSelected;
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = SeeUColors.accent;
    final inactiveColor = isDark
        ? Colors.white.withValues(alpha: 0.55)
        : SeeUColors.textTertiary;

    return Tappable.scaled(
      onTap: widget.onTap,
      scaleFactor: 0.85,
      child: SizedBox(
        width: 50,
        height: 56,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedBuilder(
                  animation: _bounceAnimation,
                  builder: (context, child) {
                    final scale =
                        widget.isSelected ? _bounceAnimation.value : 1.0;
                    final effectiveScale =
                        widget.isSelected && !_bounceController.isAnimating
                            ? 1.1
                            : scale;
                    return Transform.scale(
                      scale: effectiveScale,
                      child: child,
                    );
                  },
                  child: ColorFiltered(
                    colorFilter: ColorFilter.mode(
                      widget.isSelected ? activeColor : inactiveColor,
                      BlendMode.srcIn,
                    ),
                    child: widget.isSelected ? widget.activeIcon : widget.icon,
                  ),
                ),
                // Бейдж непрочитанного (§05): #FF3B6B, обводка фоном панели.
                if (widget.badgeCount > 0)
                  Positioned(
                    top: -4,
                    right: -8,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 16),
                      height: 16,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: SeeUColors.like,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark
                              ? SeeUColors.darkBg
                              : SeeUColors.background,
                          width: 2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        widget.badgeCount > 9 ? '9+' : '${widget.badgeCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              widget.label,
              style: SeeUTypography.micro.copyWith(
                fontSize: 9,
                fontWeight:
                    widget.isSelected ? FontWeight.w700 : FontWeight.w500,
                color: widget.isSelected ? activeColor : inactiveColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: widget.isSelected ? 4 : 0,
              height: widget.isSelected ? 4 : 0,
              decoration: const BoxDecoration(
                color: SeeUColors.accent,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Nav icon painter ────────────────────────────────────────────────────

class _NavIconPainter extends CustomPainter {
  final String name;
  final bool filled;

  _NavIconPainter({required this.name, required this.filled});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = filled ? 2.0 : 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (name) {
      // «Лента» — передняя карточка + карточка позади (по мотиву дизайна ядра
      // §02): скруглённый квадрат впереди и вторая карточка, выглядывающая
      // сверху-справа. Неактив — задняя карточка тонким уголком-скобкой;
      // актив — обе залиты (задняя приглушена до 40%).
      case 'feed':
        final frontRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(s * 0.142, s * 0.292, s * 0.55, s * 0.55),
          Radius.circular(s * 0.129),
        );
        if (filled) {
          // Задняя карточка — та же форма, приподнята и приглушена до 40%.
          // ColorFiltered в _NavItem перекрасит белый в коралл, сохранив альфу.
          final backRect = RRect.fromRectAndRadius(
            Rect.fromLTWH(s * 0.392, s * 0.192, s * 0.45, s * 0.45),
            Radius.circular(s * 0.121),
          );
          canvas.drawRRect(
            backRect,
            Paint()
              ..color = Colors.white.withValues(alpha: 0.4)
              ..style = PaintingStyle.fill,
          );
          canvas.drawRRect(
            frontRect,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.fill,
          );
        } else {
          // Задняя карточка редуцирована до верхне-правого уголка (скобка ⌐).
          final bracket = Path()
            ..moveTo(s * 0.383, s * 0.192)
            ..lineTo(s * 0.733, s * 0.192)
            ..arcToPoint(
              Offset(s * 0.842, s * 0.30),
              radius: Radius.circular(s * 0.108),
            )
            ..lineTo(s * 0.842, s * 0.60);
          canvas.drawPath(
            bracket,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.8
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round,
          );
          canvas.drawRRect(
            frontRect,
            paint
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.8,
          );
        }
        break;

      // «Интересное» — мозаичная сетка открытий (§02): высокая карточка слева,
      // квадрат справа-сверху, карточка справа-снизу и низкая слева-снизу.
      // Лупа со звездой из прежней версии выброшена: дизайн-ядро задаёт именно
      // сетку. Неактив — контуры, актив — заливка.
      case 'search':
        final tileR = Radius.circular(s * 0.083);
        paint
          ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
          ..strokeWidth = 1.8;
        for (final rc in [
          Rect.fromLTWH(s * 0.146, s * 0.146, s * 0.333, s * 0.458),
          Rect.fromLTWH(s * 0.563, s * 0.146, s * 0.292, s * 0.292),
          Rect.fromLTWH(s * 0.563, s * 0.521, s * 0.292, s * 0.333),
          Rect.fromLTWH(s * 0.146, s * 0.688, s * 0.333, s * 0.167),
        ]) {
          canvas.drawRRect(RRect.fromRectAndRadius(rc, tileR), paint);
        }
        break;

      case 'radar':
        final center = Offset(s * 0.5, s * 0.5);
        final arcPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = filled ? 2.0 : 1.7
          ..strokeCap = StrokeCap.round;

        canvas.drawArc(
          Rect.fromCircle(center: center, radius: s * 0.38),
          -2.4, 4.8, false, arcPaint,
        );
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: s * 0.24),
          -2.4, 4.8, false, arcPaint,
        );
        canvas.drawCircle(
          center,
          s * 0.07,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.fill,
        );

        {
          final endX = center.dx + s * 0.38 * 0.6216;
          final endY = center.dy - s * 0.38 * 0.7833;
          canvas.drawLine(
            center,
            Offset(endX, endY),
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = filled ? 2.0 : 1.7
              ..strokeCap = StrokeCap.round,
          );
          canvas.drawCircle(
            Offset(endX, endY),
            s * 0.055,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.fill,
          );
        }
        break;

      // «Сервисы» — скруглённый квадрат-контейнер с четырьмя точками внутри
      // (§02): единая дверь, а не четыре отдельные плитки. Квадрат всегда
      // контуром, точки всегда залиты; актив только меняет цвет на коралл.
      case 'services':
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(s * 0.142, s * 0.142, s * 0.717, s * 0.717),
            Radius.circular(s * 0.208),
          ),
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = filled ? 2.0 : 1.8,
        );
        final dotPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;
        for (final o in [
          Offset(s * 0.375, s * 0.375),
          Offset(s * 0.625, s * 0.375),
          Offset(s * 0.375, s * 0.625),
          Offset(s * 0.625, s * 0.625),
        ]) {
          canvas.drawCircle(o, s * 0.067, dotPaint);
        }
        break;

      // «Профиль» — силуэт: голова-круг + плечи-дуга (§02). Неактив контуром,
      // актив залит (дуга плеч замыкается снизу).
      case 'user':
        final headCenter = Offset(s * 0.5, s * 0.342);
        final headR = s * 0.183;
        final body = Path()
          ..moveTo(s * 0.167, s * 0.85)
          ..cubicTo(s * 0.167, s * 0.617, s * 0.333, s * 0.583, s * 0.5, s * 0.583)
          ..cubicTo(s * 0.667, s * 0.583, s * 0.833, s * 0.617, s * 0.833, s * 0.85);
        if (filled) {
          canvas.drawCircle(
            headCenter,
            headR,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.fill,
          );
          body.close();
          canvas.drawPath(
            body,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.fill,
          );
        } else {
          canvas.drawCircle(
            headCenter,
            headR,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.8,
          );
          canvas.drawPath(
            body,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.8
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round,
          );
        }
        break;

      case 'reels':
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(s * 0.1, s * 0.1, s * 0.8, s * 0.8),
          Radius.circular(s * 0.15),
        );
        paint.style = filled ? PaintingStyle.fill : PaintingStyle.stroke;
        paint.strokeWidth = 1.7;
        canvas.drawRRect(rect, paint);

        final dotPaint = Paint()
          ..color = Colors.white
          ..style = filled ? PaintingStyle.stroke : PaintingStyle.fill;
        dotPaint.strokeWidth = 1.2;
        for (var i = 0; i < 3; i++) {
          final x = s * (0.28 + i * 0.22);
          canvas.drawCircle(Offset(x, s * 0.21), s * 0.035, dotPaint);
          canvas.drawCircle(Offset(x, s * 0.79), s * 0.035, dotPaint);
        }

        if (!filled) {
          final triPath = Path()
            ..moveTo(s * 0.4, s * 0.35)
            ..lineTo(s * 0.68, s * 0.5)
            ..lineTo(s * 0.4, s * 0.65)
            ..close();
          canvas.drawPath(triPath, Paint()..color = Colors.white..style = PaintingStyle.fill);
        } else {
          final triPath = Path()
            ..moveTo(s * 0.4, s * 0.35)
            ..lineTo(s * 0.68, s * 0.5)
            ..lineTo(s * 0.4, s * 0.65)
            ..close();
          canvas.drawPath(triPath, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.8..strokeJoin = StrokeJoin.round);
        }
        break;

      case 'video':
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(s * 0.08, s * 0.2, s * 0.84, s * 0.6),
          const Radius.circular(3),
        );
        paint.style = filled ? PaintingStyle.fill : PaintingStyle.stroke;
        canvas.drawRRect(rect, paint);
        if (!filled) {
          final triPath = Path()
            ..moveTo(s * 0.4, s * 0.35)
            ..lineTo(s * 0.65, s * 0.5)
            ..lineTo(s * 0.4, s * 0.65)
            ..close();
          canvas.drawPath(triPath, paint..style = PaintingStyle.fill);
        }
        break;

      case 'folder':
        final folderPath = Path()
          ..moveTo(s * 0.08, s * 0.3)
          ..lineTo(s * 0.08, s * 0.8)
          ..quadraticBezierTo(s * 0.08, s * 0.88, s * 0.16, s * 0.88)
          ..lineTo(s * 0.84, s * 0.88)
          ..quadraticBezierTo(s * 0.92, s * 0.88, s * 0.92, s * 0.8)
          ..lineTo(s * 0.92, s * 0.35)
          ..quadraticBezierTo(s * 0.92, s * 0.27, s * 0.84, s * 0.27)
          ..lineTo(s * 0.52, s * 0.27)
          ..lineTo(s * 0.42, s * 0.15)
          ..lineTo(s * 0.16, s * 0.15)
          ..quadraticBezierTo(s * 0.08, s * 0.15, s * 0.08, s * 0.23)
          ..close();
        paint.style = filled ? PaintingStyle.fill : PaintingStyle.stroke;
        canvas.drawPath(folderPath, paint);
        break;

      case 'music':
        final notePaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;
        canvas.save();
        canvas.translate(s * 0.25, s * 0.72);
        canvas.scale(1.0, 0.65);
        canvas.drawCircle(Offset.zero, s * 0.16, notePaint);
        canvas.restore();
        canvas.drawLine(
          Offset(s * 0.40, s * 0.72),
          Offset(s * 0.40, s * 0.18),
          Paint()
            ..color = Colors.white
            ..strokeWidth = filled ? 2.2 : 1.8
            ..strokeCap = StrokeCap.round,
        );
        final flagPath = Path()
          ..moveTo(s * 0.40, s * 0.18)
          ..cubicTo(
            s * 0.68, s * 0.18,
            s * 0.72, s * 0.38,
            s * 0.60, s * 0.52,
          );
        canvas.drawPath(
          flagPath,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = filled ? 2.2 : 1.8
            ..strokeCap = StrokeCap.round,
        );
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _NavIconPainter old) =>
      name != old.name || filled != old.filled;
}
