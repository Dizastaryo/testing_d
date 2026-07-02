import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/design/design.dart';
import 'filter_state.dart';

/// Bottom-sheet с 6 sliders для ручной настройки. Изменения летят через
/// callback `onChange` сразу — preview обновляется live.
Future<void> showFilterSlidersSheet({
  required BuildContext context,
  required FilterState initial,
  required ValueChanged<FilterState> onChange,
  required VoidCallback onReset,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (sheetCtx) => _FilterSlidersBody(
      initial: initial,
      onChange: onChange,
      onReset: onReset,
    ),
  );
}

class _FilterSlidersBody extends StatefulWidget {
  final FilterState initial;
  final ValueChanged<FilterState> onChange;
  final VoidCallback onReset;

  const _FilterSlidersBody({
    required this.initial,
    required this.onChange,
    required this.onReset,
  });

  @override
  State<_FilterSlidersBody> createState() => _FilterSlidersBodyState();
}

class _FilterSlidersBodyState extends State<_FilterSlidersBody> {
  late FilterState _state;

  @override
  void initState() {
    super.initState();
    _state = widget.initial;
  }

  void _update(FilterState next) {
    setState(() => _state = next);
    widget.onChange(next);
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scroll) {
        return Container(
          decoration: const BoxDecoration(
            color: SeeUColors.cameraDarkOverlay,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(SeeURadii.sheet)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text(
                      'Настройка фильтра',
                      style: SeeUTypography.title
                          .copyWith(color: Colors.white),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        widget.onReset();
                        setState(() => _state = FilterState.identity);
                      },
                      child: const Text(
                        'Сброс',
                        style: TextStyle(
                          color: SeeUColors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scroll,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  children: [
                    _SliderRow(
                      label: 'Яркость',
                      value: _state.brightness,
                      min: -1,
                      max: 1,
                      onChanged: (v) => _update(_state.copyWith(brightness: v)),
                    ),
                    _SliderRow(
                      label: 'Контраст',
                      value: _state.contrast,
                      min: -1,
                      max: 1,
                      onChanged: (v) => _update(_state.copyWith(contrast: v)),
                    ),
                    _SliderRow(
                      label: 'Насыщенность',
                      value: _state.saturation,
                      min: -1,
                      max: 1,
                      onChanged: (v) => _update(_state.copyWith(saturation: v)),
                    ),
                    _SliderRow(
                      label: 'Тёплый ↔ Холодный',
                      value: _state.warmth,
                      min: -1,
                      max: 1,
                      onChanged: (v) => _update(_state.copyWith(warmth: v)),
                    ),
                    _SliderRow(
                      label: 'Виньетка',
                      value: _state.vignette,
                      min: 0,
                      max: 1,
                      onChanged: (v) => _update(_state.copyWith(vignette: v)),
                    ),
                    _SliderRow(
                      label: 'Зерно',
                      value: _state.grain,
                      min: 0,
                      max: 1,
                      onChanged: (v) => _update(_state.copyWith(grain: v)),
                    ),
                    _SliderRow(
                      label: 'Поднять тени',
                      value: _state.liftBlacks,
                      min: 0,
                      max: 1,
                      onChanged: (v) =>
                          _update(_state.copyWith(liftBlacks: v)),
                    ),
                    _SliderRow(
                      label: 'Притушить светлые',
                      value: _state.fadeHighlights,
                      min: 0,
                      max: 1,
                      onChanged: (v) =>
                          _update(_state.copyWith(fadeHighlights: v)),
                    ),
                    _SliderRow(
                      label: 'Галация',
                      value: _state.halation,
                      min: 0,
                      max: 1,
                      onChanged: (v) =>
                          _update(_state.copyWith(halation: v)),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(label,
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
              const Spacer(),
              Text(
                value.toStringAsFixed(2),
                style: const TextStyle(
                  color: Colors.white,
                  fontFeatures: [FontFeature.tabularFigures()],
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              activeTrackColor: SeeUColors.accent,
              inactiveTrackColor: Colors.white12,
              thumbColor: Colors.white,
              overlayColor:
                  SeeUColors.accent.withValues(alpha: 0.18),
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape:
                  const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
