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

  @override
  void initState() {
    super.initState();
    _rebuildItems();
    _pageController = PageController(
      initialPage: _currentPage,
      viewportFraction: 0.175,
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
      // Если текущий элемент переместился — уведомить
      if (prevId != _currentItem?.id) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.onChanged(_currentItem);
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
  }

  DecorationItem? get _currentItem => _items[_currentPage];

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
        const SizedBox(height: 6),
        SizedBox(
          height: 80,
          child: PageView.builder(
            controller: _pageController,
            clipBehavior: Clip.none,
            itemCount: _items.length,
            onPageChanged: (page) {
              setState(() => _currentPage = page);
              HapticFeedback.selectionClick();
              widget.onChanged(_items[page]);
            },
            itemBuilder: (context, index) {
              final item = _items[index];
              final isCurrent = index == _currentPage;
              final isSaved = item != null && widget.savedIds.contains(item.id);

              return GestureDetector(
                onLongPress: () {
                  if (item == null) return;
                  HapticFeedback.mediumImpact();
                  widget.onToggleSave(item.id);
                },
                onTap: () {
                  if (index != _currentPage) {
                    _pageController.animateToPage(
                      index,
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOut,
                    );
                  }
                },
                child: _DecorationCircle(
                  item: item,
                  isCurrent: isCurrent,
                  isSaved: isSaved,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CenterIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 4,
        height: 4,
        decoration: const BoxDecoration(
          color: SeeUColors.accent,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
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
    final isLottie = !isNone && item!.isLottieAnimated;
    final color = isNone ? Colors.white.withValues(alpha: 0.12) : item!.previewColor;

    return AnimatedScale(
      scale: isCurrent ? 1.0 : 0.78,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: isNone
                  ? null
                  : isLottie
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF1A1A2A), Color(0xFF2A2A3A)],
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
                  size: isLottie ? 24 : 20,
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
                // Pulsing dot signals that this is a live Lottie animation.
                if (isLottie && !isSaved)
                  const Positioned(
                    top: 2,
                    right: 2,
                    child: _AnimatedLottieDot(),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 150),
            style: TextStyle(
              fontSize: 9,
              color: isCurrent
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.45),
              fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
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

/// Pulsing accent dot shown on Lottie mask thumbnails to signal they are
/// animated. Scales 0.6 → 1.0 → 0.6 on a continuous loop.
class _AnimatedLottieDot extends StatefulWidget {
  const _AnimatedLottieDot();

  @override
  State<_AnimatedLottieDot> createState() => _AnimatedLottieDotState();
}

class _AnimatedLottieDotState extends State<_AnimatedLottieDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: SeeUColors.accent,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
