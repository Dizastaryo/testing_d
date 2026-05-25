import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/design/design.dart';
import 'filter_presets.dart';
import 'filter_state.dart';
import 'frame_effect.dart';
import 'overlay_effect.dart';

/// Picker пресетов + кнопка «Настроить» для перехода в slider-sheet.
/// Вторая строка — overlay-эффекты (пыль, засветки).
class FilterPicker extends StatelessWidget {
  final String? selectedPresetId;
  final FilterState state;
  final ValueChanged<FilterPreset?> onPresetSelected;
  final VoidCallback onOpenSliders;

  final OverlayEffect? selectedOverlay;
  final ValueChanged<OverlayEffect?> onOverlaySelected;

  final FrameEffect? selectedFrame;
  final ValueChanged<FrameEffect?> onFrameSelected;

  const FilterPicker({
    super.key,
    required this.selectedPresetId,
    required this.state,
    required this.onPresetSelected,
    required this.onOpenSliders,
    required this.selectedOverlay,
    required this.onOverlaySelected,
    required this.selectedFrame,
    required this.onFrameSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isCustomNoPreset = selectedPresetId == null && !state.isIdentity;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Строка 1: рамки ────────────────────────────────────────────
        SizedBox(
          height: 70,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _FilterBubble(
                isSelected: selectedFrame == null,
                label: 'Без',
                onTap: () {
                  HapticFeedback.selectionClick();
                  onFrameSelected(null);
                },
                child: Icon(PhosphorIcons.prohibit(),
                    color: Colors.white.withValues(alpha: 0.85), size: 22),
              ),
              const SizedBox(width: 10),
              _FilterBubble(
                isSelected: selectedFrame is PolaroidFrame,
                label: 'Polaroid',
                onTap: () {
                  HapticFeedback.selectionClick();
                  onFrameSelected(selectedFrame is PolaroidFrame
                      ? null
                      : const PolaroidFrame());
                },
                child:
                    Icon(PhosphorIcons.image(), color: Colors.white, size: 22),
              ),
              const SizedBox(width: 10),
              _FilterBubble(
                isSelected: selectedFrame is FilmStripFrame,
                label: 'Плёнка',
                onTap: () {
                  HapticFeedback.selectionClick();
                  onFrameSelected(selectedFrame is FilmStripFrame
                      ? null
                      : const FilmStripFrame());
                },
                child: Icon(PhosphorIcons.filmStrip(),
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 10),
              _FilterBubble(
                isSelected: selectedFrame is DisposableCameraFrame,
                label: 'Одноразовая',
                onTap: () {
                  HapticFeedback.selectionClick();
                  onFrameSelected(selectedFrame is DisposableCameraFrame
                      ? null
                      : const DisposableCameraFrame());
                },
                child: Icon(PhosphorIcons.camera(),
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 10),
              _FilterBubble(
                isSelected: selectedFrame is ScrapbookFrame,
                label: 'Скрапбук',
                onTap: () {
                  HapticFeedback.selectionClick();
                  onFrameSelected(selectedFrame is ScrapbookFrame
                      ? null
                      : const ScrapbookFrame());
                },
                child: Icon(PhosphorIcons.bookOpen(),
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 10),
              _FilterBubble(
                isSelected: selectedFrame is TapeEffect,
                label: 'Скотч',
                onTap: () {
                  HapticFeedback.selectionClick();
                  onFrameSelected(selectedFrame is TapeEffect
                      ? null
                      : const TapeEffect());
                },
                child: Icon(PhosphorIcons.scissors(),
                    color: Colors.white, size: 22),
              ),
            ],
          ),
        ),

        const SizedBox(height: 4),

        // ── Строка 2: overlay-эффекты ──────────────────────────────────
        SizedBox(
          height: 70,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              // Без эффекта
              _FilterBubble(
                isSelected: selectedOverlay == null,
                label: 'Без',
                onTap: () {
                  HapticFeedback.selectionClick();
                  onOverlaySelected(null);
                },
                child: Icon(PhosphorIcons.prohibit(),
                    color: Colors.white.withValues(alpha: 0.85), size: 22),
              ),
              const SizedBox(width: 10),
              // Пыль и царапины
              _FilterBubble(
                isSelected: selectedOverlay is DustScratchesEffect,
                label: 'Пыль',
                onTap: () {
                  HapticFeedback.selectionClick();
                  onOverlaySelected(selectedOverlay is DustScratchesEffect
                      ? null
                      : const DustScratchesEffect(intensity: 0.5));
                },
                child: Icon(PhosphorIcons.sparkle(),
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 10),
              // Засветка тёплая (верх-лево)
              _FilterBubble(
                isSelected: selectedOverlay is LightLeakEffect &&
                    (selectedOverlay as LightLeakEffect).style ==
                        LightLeakStyle.topOrange,
                label: 'Свет ↖',
                onTap: () {
                  HapticFeedback.selectionClick();
                  onOverlaySelected(
                    selectedOverlay is LightLeakEffect &&
                            (selectedOverlay as LightLeakEffect).style ==
                                LightLeakStyle.topOrange
                        ? null
                        : const LightLeakEffect(
                            style: LightLeakStyle.topOrange),
                  );
                },
                child: Icon(PhosphorIcons.sun(), color: Colors.white, size: 22),
              ),
              const SizedBox(width: 10),
              // Засветка холодная (верх-право)
              _FilterBubble(
                isSelected: selectedOverlay is LightLeakEffect &&
                    (selectedOverlay as LightLeakEffect).style ==
                        LightLeakStyle.topCool,
                label: 'Свет ↗',
                onTap: () {
                  HapticFeedback.selectionClick();
                  onOverlaySelected(
                    selectedOverlay is LightLeakEffect &&
                            (selectedOverlay as LightLeakEffect).style ==
                                LightLeakStyle.topCool
                        ? null
                        : const LightLeakEffect(style: LightLeakStyle.topCool),
                  );
                },
                child:
                    Icon(PhosphorIcons.moon(), color: Colors.white, size: 22),
              ),
              const SizedBox(width: 10),
              // Засветка снизу
              _FilterBubble(
                isSelected: selectedOverlay is LightLeakEffect &&
                    (selectedOverlay as LightLeakEffect).style ==
                        LightLeakStyle.bottomWarm,
                label: 'Свет ↓',
                onTap: () {
                  HapticFeedback.selectionClick();
                  onOverlaySelected(
                    selectedOverlay is LightLeakEffect &&
                            (selectedOverlay as LightLeakEffect).style ==
                                LightLeakStyle.bottomWarm
                        ? null
                        : const LightLeakEffect(
                            style: LightLeakStyle.bottomWarm),
                  );
                },
                child: Icon(PhosphorIcons.sunHorizon(),
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 10),
              // VHS / camcorder
              _FilterBubble(
                isSelected: selectedOverlay is VHSEffect,
                label: 'VHS',
                onTap: () {
                  HapticFeedback.selectionClick();
                  onOverlaySelected(
                    selectedOverlay is VHSEffect
                        ? null
                        : const VHSEffect(),
                  );
                },
                child: Icon(PhosphorIcons.videoCamera(),
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 10),
              // Текстура бумаги / фотобумага
              _FilterBubble(
                isSelected: selectedOverlay is PaperTextureEffect,
                label: 'Бумага',
                onTap: () {
                  HapticFeedback.selectionClick();
                  onOverlaySelected(
                    selectedOverlay is PaperTextureEffect
                        ? null
                        : const PaperTextureEffect(),
                  );
                },
                child: Icon(PhosphorIcons.newspaper(),
                    color: Colors.white, size: 22),
              ),
            ],
          ),
        ),

        const SizedBox(height: 4),

        // ── Строка 2: цветовые пресеты ─────────────────────────────────
        SizedBox(
          height: 70,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: FilterPresets.all.length + 2,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              if (i == 0) {
                return _FilterBubble(
                  isSelected: state.isIdentity,
                  label: 'Без',
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onPresetSelected(null);
                  },
                  child: Icon(PhosphorIcons.x(),
                      color: Colors.white.withValues(alpha: 0.85), size: 22),
                );
              }
              if (i == FilterPresets.all.length + 1) {
                return _FilterBubble(
                  isSelected: isCustomNoPreset,
                  label: isCustomNoPreset ? 'Свой' : 'Точнее',
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    onOpenSliders();
                  },
                  child: Icon(PhosphorIcons.sliders(),
                      color: Colors.white, size: 22),
                );
              }
              final p = FilterPresets.all[i - 1];
              final isSelected = selectedPresetId == p.id;
              return _FilterBubble(
                isSelected: isSelected,
                label: p.label,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onPresetSelected(p);
                },
                child: Icon(p.previewIcon, color: Colors.white, size: 22),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FilterBubble extends StatelessWidget {
  final bool isSelected;
  final String label;
  final VoidCallback onTap;
  final Widget child;

  const _FilterBubble({
    required this.isSelected,
    required this.label,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: SeeUMotion.quick,
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.15),
              border: Border.all(
                color: isSelected
                    ? SeeUColors.accent
                    : Colors.white.withValues(alpha: 0.18),
                width: isSelected ? 2.5 : 1,
              ),
            ),
            child: Center(child: child),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: isSelected
                  ? SeeUColors.accent
                  : Colors.white.withValues(alpha: 0.75),
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
