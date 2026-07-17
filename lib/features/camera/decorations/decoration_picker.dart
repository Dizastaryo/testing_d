import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/design/tokens.dart';
import 'decoration_item.dart';

/// Горизонтальный snap-пикер украшений в стиле Instagram.
///
/// Layout: [...сохранённые] | [нет] | [...несохранённые]
/// Элемент, центрированный над кнопкой съёмки, применяется.
/// Долгий нажать на элемент — сохранить/убрать из сохранённых.
class DecorationPicker extends StatefulWidget {
  final List<DecorationItem> allItems;
  final Set<String> savedIds;
  final String? selectedId;
  final ValueChanged<DecorationItem?> onChanged;
  final void Function(String id) onToggleSave;

  const DecorationPicker({
    super.key,
    required this.allItems,
    required this.savedIds,
    required this.selectedId,
    required this.onChanged,
    required this.onToggleSave,
  });

  @override
  State<DecorationPicker> createState() => _DecorationPickerState();
}

class _DecorationPickerState extends State<DecorationPicker> {
  late List<DecorationItem?> _items; // null = «без украшения»
  late int _noneIndex;
  late PageController _pageController;
  int _currentPage = 0;

  /// Последний ЗАКОММИЧЕННЫЙ элемент (тот, что реально отдан наверх и загружен).
  /// Пролетающие мимо кружки сюда не попадают: грузить маску на каждом шаге —
  /// это парсинг GLB на каждый кружок, отсюда и были тормоза «по одному».
  int? _committedPage;

  /// Идёт программный доводочный скролл — не даём ScrollEndNotification
  /// зациклиться на самом себе.
  bool _snapping = false;

  @override
  void initState() {
    super.initState();
    _rebuildItems();
    _pageController = PageController(
      initialPage: _currentPage,
      viewportFraction: 0.155,
    );
  }

  @override
  void didUpdateWidget(DecorationPicker old) {
    super.didUpdateWidget(old);
    if (old.savedIds != widget.savedIds ||
        old.allItems != widget.allItems ||
        old.selectedId != widget.selectedId) {
      final prevId = _currentItem?.id;
      _rebuildItems();
      // Попытаться остаться на том же элементе
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_currentPage);
      }
      // Уведомить только если центрированный элемент реально сменился И он
      // расходится с тем, что уже выбрано родителем. Это не даёт «сохранению
      // в избранное» (которое лишь переупорядочивает список) перезагружать маску.
      final currentId = _currentItem?.id;
      if (prevId != currentId && currentId != widget.selectedId) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onChanged(_currentItem);
        });
      }
    }
  }

  void _rebuildItems() {
    final saved = widget.allItems
        .where((i) => widget.savedIds.contains(i.id))
        .toList()
        .reversed
        .toList();
    final unsaved = widget.allItems
        .where((i) => !widget.savedIds.contains(i.id))
        .toList();
    _items = [...saved, null, ...unsaved];
    _noneIndex = saved.length;

    // Найти позицию текущего выбранного
    if (widget.selectedId == null) {
      _currentPage = _noneIndex;
    } else {
      final idx = _items.indexWhere((i) => i?.id == widget.selectedId);
      _currentPage = idx >= 0 ? idx : _noneIndex;
    }
    // То, что уже показано, считается закоммиченным — иначе доводка после
    // переупорядочивания списка повторно дёрнула бы загрузку той же маски.
    _committedPage = _currentPage;
  }

  DecorationItem? get _currentItem => _items[_currentPage];

  /// Скролл остановился — доводим до ближайшего кружка и только теперь отдаём
  /// выбор наверх (одна загрузка вместо загрузки каждого пролетевшего).
  void _settle() {
    if (_snapping || !_pageController.hasClients) return;
    final raw = _pageController.page;
    if (raw == null) return;
    final target = raw.round().clamp(0, _items.length - 1);
    if ((raw - target).abs() > 0.02) {
      _snapping = true;
      _pageController
          .animateToPage(target,
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut)
          .whenComplete(() {
        _snapping = false;
        _commit(target);
      });
    } else {
      _commit(target);
    }
  }

  /// Отдать выбор наверх (= загрузить маску). Идемпотентно.
  void _commit(int index) {
    if (_committedPage == index) return;
    _committedPage = index;
    if (mounted) setState(() => _currentPage = index);
    widget.onChanged(_items[index]);
  }

  /// Прыжок к произвольному кружку по тапу — сразу к нему, а не по одному.
  void _jumpTo(int index) {
    if (index == _currentPage || !_pageController.hasClients) return;
    HapticFeedback.selectionClick();
    _snapping = true;
    _pageController
        .animateToPage(index,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic)
        .whenComplete(() {
      _snapping = false;
      _commit(index);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Маленький индикатор — треугольник, указывающий «здесь применяется»
        _CenterIndicator(),
        const SizedBox(height: 4),
        SizedBox(
          height: 62,
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollEndNotification) _settle();
              return false;
            },
            child: PageView.builder(
              controller: _pageController,
              clipBehavior: Clip.none,
              itemCount: _items.length,
              // «Рулетка»: инерция несёт сразу через несколько кружков.
              // Дефолтный PageScrollPhysics снапит строго на СОСЕДНИЙ — отсюда
              // и было «скролл идёт по одному». Доводку до центра делаем сами
              // в _settle().
              pageSnapping: false,
              physics: const BouncingScrollPhysics(),
              onPageChanged: (page) {
                // Только подсветка — маску грузим в _settle(), когда скролл
                // остановится. Иначе каждый пролетевший кружок = загрузка GLB.
                if (page != _currentPage && mounted) {
                  setState(() => _currentPage = page);
                  HapticFeedback.selectionClick();
                }
              },
              itemBuilder: (context, index) {
                final item = _items[index];
                final isCurrent = index == _currentPage;
                final isSaved =
                    item != null && widget.savedIds.contains(item.id);

                return GestureDetector(
                  onLongPress: () {
                    if (item == null) return;
                    HapticFeedback.mediumImpact();
                    widget.onToggleSave(item.id);
                  },
                  onTap: () => _jumpTo(index),
                  child: _DecorationCircle(
                    item: item,
                    isCurrent: isCurrent,
                    isSaved: isSaved,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// #36: a small downward caret marking "applied here", clearer than a dot.
class _CenterIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: CustomPaint(
        size: const Size(12, 6),
        painter: _CaretPainter(),
      ),
    );
  }
}

class _CaretPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = SeeUColors.accent;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class _DecorationCircle extends StatelessWidget {
  final DecorationItem? item;
  final bool isCurrent;
  final bool isSaved;

  const _DecorationCircle({
    required this.item,
    required this.isCurrent,
    required this.isSaved,
  });

  @override
  Widget build(BuildContext context) {
    final isNone = item == null;
    final isMask = !isNone && item!.category == DecorationCategory.mask;
    final color = isNone ? Colors.white.withValues(alpha: 0.12) : item!.previewColor;
    // #41: distinct brand gradient per mask (derived from its id) so masks are
    // visually recognizable instead of all sharing one flat dark swatch.
    final maskPalette = isMask
        ? SeeUColors.avatarPalettes[item!.id.hashCode.abs() %
            SeeUColors.avatarPalettes.length]
        : const [Color(0xFF1A1A2A), Color(0xFF2A2A3A)];

    return AnimatedScale(
      // #35: stronger focus falloff for non-centered items.
      scale: isCurrent ? 1.0 : 0.7,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: isNone
                  ? null
                  : isMask
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: maskPalette,
                        )
                      : RadialGradient(
                          colors: [
                            color.withValues(alpha: 0.95),
                            color.withValues(alpha: 0.6),
                          ],
                          stops: const [0.0, 1.0],
                        ),
              color: isNone ? Colors.white.withValues(alpha: 0.12) : null,
              border: Border.all(
                color: isCurrent
                    ? SeeUColors.accent
                    : isSaved
                        ? Colors.white.withValues(alpha: 0.5)
                        : Colors.white.withValues(alpha: 0.18),
                width: isCurrent ? 2.5 : 1,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  isNone ? PhosphorIcons.prohibit() : item!.previewIcon,
                  color: Colors.white.withValues(alpha: isNone ? 0.6 : 0.9),
                  size: isMask ? 20 : 17,
                ),
                if (isSaved)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: SeeUColors.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                // 3D AR mask indicator
                if (isMask && !isSaved)
                  const Positioned(
                    top: 2,
                    right: 2,
                    child: _AR3DBadge(),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 150),
            style: TextStyle(
              fontSize: 9.5,
              // #40: lift inactive label contrast.
              color: isCurrent
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.6),
              fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
            ),
            child: Text(
              isNone ? 'Нет' : item!.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small "3D" badge shown on AR mask thumbnails.
class _AR3DBadge extends StatelessWidget {
  const _AR3DBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: SeeUColors.accent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        '3D',
        style: TextStyle(
          color: Colors.white,
          fontSize: 7.5,
          fontWeight: FontWeight.w800,
          height: 1.2,
        ),
      ),
    );
  }
}
