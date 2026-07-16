import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/design/design.dart';
import 'reader_settings.dart';

class ReaderSettingsSheet extends ConsumerWidget {
  const ReaderSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(readerSettingsProvider);
    final notifier = ref.read(readerSettingsProvider.notifier);
    final c = context.seeuColors;

    // Корневой glass-контейнер + грабер даёт showSeeUBottomSheet — здесь их нет.
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          20, 4, 20, MediaQuery.of(context).padding.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: SeeUColors.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(PhosphorIconsRegular.textAa,
                    size: 19, color: SeeUColors.accent),
              ),
              const SizedBox(width: 10),
              Text(
                'Настройки текста',
                style: SeeUTypography.displayS.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Quick presets row
          Row(
            children: [
              _PresetChip(
                label: 'Стандарт',
                icon: PhosphorIconsRegular.sun,
                active: settings.theme == ReaderTheme.light &&
                    settings.fontSize == 16 &&
                    settings.lineHeight == 1.6,
                onTap: () {
                  HapticFeedback.selectionClick();
                  notifier.reset();
                },
              ),
              const SizedBox(width: 8),
              _PresetChip(
                label: 'Комфорт',
                icon: PhosphorIconsRegular.bookOpenText,
                active: settings.theme == ReaderTheme.sepia &&
                    settings.fontSize == 18,
                onTap: () {
                  HapticFeedback.selectionClick();
                  notifier.applyPreset(ReaderSettings.comfortable);
                },
              ),
              const SizedBox(width: 8),
              _PresetChip(
                label: 'Ночной',
                icon: PhosphorIconsRegular.moon,
                active: settings.isNightMode && settings.fontSize == 17,
                onTap: () {
                  HapticFeedback.selectionClick();
                  notifier.applyPreset(ReaderSettings.night);
                },
              ),
              const SizedBox(width: 8),
              _PresetChip(
                label: 'Компакт',
                icon: PhosphorIconsRegular.alignLeft,
                active: settings.fontSize == 14 && settings.lineHeight == 1.4,
                onTap: () {
                  HapticFeedback.selectionClick();
                  notifier.applyPreset(ReaderSettings.compact);
                },
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Live preview
          _TextPreview(settings: settings),
          const SizedBox(height: 20),

          // Font size
          _SettingRow(
            icon: PhosphorIconsRegular.textT,
            label: 'Размер шрифта',
            valueText: '${settings.fontSize.toInt()}px',
            c: c,
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: SeeUColors.accent,
              inactiveTrackColor: SeeUColors.accent.withValues(alpha: 0.15),
              thumbColor: SeeUColors.accent,
              overlayColor: SeeUColors.accent.withValues(alpha: 0.1),
            ),
            child: Slider(
              value: settings.fontSize,
              min: 12,
              max: 24,
              divisions: 12,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                notifier.setFontSize(v);
              },
            ),
          ),

          const SizedBox(height: 4),

          // Line height
          _SettingRow(
            icon: PhosphorIconsRegular.textAlignLeft,
            label: 'Межстрочный',
            valueText: '${settings.lineHeight.toStringAsFixed(1)}×',
            c: c,
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: SeeUColors.accent,
              inactiveTrackColor: SeeUColors.accent.withValues(alpha: 0.15),
              thumbColor: SeeUColors.accent,
              overlayColor: SeeUColors.accent.withValues(alpha: 0.1),
            ),
            child: Slider(
              value: settings.lineHeight,
              min: 1.2,
              max: 2.4,
              divisions: 12,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                notifier.setLineHeight((v * 10).round() / 10);
              },
            ),
          ),

          const SizedBox(height: 16),

          // Font family
          const _SectionLabel(label: 'Шрифт'),
          const SizedBox(height: 8),
          Row(
            children: [
              _FontChip(
                label: 'Системный',
                preview: 'Аа',
                fontFamily: null,
                selected: settings.fontFamily == ReaderFontFamily.system,
                onTap: () => notifier.setFontFamily(ReaderFontFamily.system),
              ),
              const SizedBox(width: 10),
              _FontChip(
                label: 'Serif',
                preview: 'Аа',
                fontFamily: AppFonts.I.serif,
                selected: settings.fontFamily == ReaderFontFamily.serif,
                onTap: () => notifier.setFontFamily(ReaderFontFamily.serif),
              ),
              const SizedBox(width: 10),
              _FontChip(
                label: 'Sans',
                preview: 'Аа',
                fontFamily: AppFonts.I.sans,
                selected: settings.fontFamily == ReaderFontFamily.sans,
                onTap: () => notifier.setFontFamily(ReaderFontFamily.sans),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Theme
          const _SectionLabel(label: 'Тема'),
          const SizedBox(height: 8),
          Row(
            children: [
              _ThemeChip(
                label: 'Светлая',
                bgColor: Colors.white,
                textColor: Colors.black87,
                selected: settings.theme == ReaderTheme.light,
                onTap: () => notifier.setTheme(ReaderTheme.light),
              ),
              const SizedBox(width: 8),
              _ThemeChip(
                label: 'Сепия',
                bgColor: const Color(0xFFF5EDD3),
                textColor: const Color(0xFF3D2B1A),
                selected: settings.theme == ReaderTheme.sepia,
                onTap: () => notifier.setTheme(ReaderTheme.sepia),
              ),
              const SizedBox(width: 8),
              _ThemeChip(
                label: 'Тёмная',
                bgColor: const Color(0xFF1A1A1A),
                textColor: const Color(0xFFE0E0E0),
                selected: settings.theme == ReaderTheme.dark,
                onTap: () => notifier.setTheme(ReaderTheme.dark),
              ),
              const SizedBox(width: 8),
              _ThemeChip(
                label: 'AMOLED',
                bgColor: Colors.black,
                textColor: Colors.white,
                selected: settings.theme == ReaderTheme.amoled,
                onTap: () => notifier.setTheme(ReaderTheme.amoled),
              ),
            ],
          ),
        ],
        ),
    );
  }
}

// ─── Section label (kicker + hairline) ──────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Row(
      children: [
        Text(label.toUpperCase(), style: SeeUTypography.kicker),
        const SizedBox(width: 10),
        Expanded(child: Container(height: 0.5, color: c.line)),
      ],
    );
  }
}

// ─── Live Text Preview ───────────────────────────────────────────────────────

class _TextPreview extends StatelessWidget {
  final ReaderSettings settings;
  const _TextPreview({required this.settings});

  @override
  Widget build(BuildContext context) {
    final (bg, text) = _themeColors(settings.theme);
    final fontFamily = switch (settings.fontFamily) {
      ReaderFontFamily.serif => AppFonts.I.serif,
      ReaderFontFamily.sans => AppFonts.I.sans,
      _ => null,
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(SeeURadii.small),
        border: Border.all(
          color: context.seeuColors.line.withValues(alpha: 0.5),
        ),
      ),
      child: AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 200),
        style: TextStyle(
          fontSize: settings.fontSize,
          height: settings.lineHeight,
          color: text,
          fontFamily: fontFamily,
        ),
        child: const Text(
          'Книги — это удивительные путешествия, которые можно совершать не выходя из дома.',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  (Color bg, Color text) _themeColors(ReaderTheme theme) {
    return switch (theme) {
      ReaderTheme.light => (Colors.white, Colors.black87),
      ReaderTheme.sepia => (const Color(0xFFF5EDD3), const Color(0xFF3D2B1A)),
      ReaderTheme.dark => (const Color(0xFF1A1A1A), const Color(0xFFE0E0E0)),
      ReaderTheme.amoled => (Colors.black, Colors.white),
    };
  }
}

// ─── Setting Row ─────────────────────────────────────────────────────────────

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String valueText;
  final SeeUThemeColors c;

  const _SettingRow({
    required this.icon,
    required this.label,
    required this.valueText,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: c.ink3),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 13, color: c.ink2)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: SeeUColors.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(valueText,
              style: TextStyle(
                  fontFamily: AppFonts.I.sans,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: SeeUColors.accent)),
        ),
      ],
    );
  }
}

// ─── Font Chip ───────────────────────────────────────────────────────────────

class _FontChip extends StatelessWidget {
  final String label;
  final String preview;
  final String? fontFamily;
  final bool selected;
  final VoidCallback onTap;

  const _FontChip({
    required this.label,
    required this.preview,
    required this.fontFamily,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 80,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? SeeUColors.accent.withValues(alpha: 0.1)
              : Colors.transparent,
          border: Border.all(
            color: selected ? SeeUColors.accent : context.seeuColors.line,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              preview,
              style: TextStyle(
                fontFamily: fontFamily,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: selected
                    ? SeeUColors.accent
                    : context.seeuColors.ink2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: selected
                    ? SeeUColors.accent
                    : context.seeuColors.ink3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Preset Chip ─────────────────────────────────────────────────────────────

class _PresetChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _PresetChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active
                ? SeeUColors.accent.withValues(alpha: 0.1)
                : context.seeuColors.surface2,
            border: Border.all(
              color: active ? SeeUColors.accent : Colors.transparent,
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: active ? SeeUColors.accent : context.seeuColors.ink3,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: active ? SeeUColors.accent : context.seeuColors.ink3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Theme Chip ──────────────────────────────────────────────────────────────

class _ThemeChip extends StatelessWidget {
  final String label;
  final Color bgColor;
  final Color textColor;
  final bool selected;
  final VoidCallback onTap;
  const _ThemeChip({
    required this.label,
    required this.bgColor,
    required this.textColor,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 80,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(
            color:
                selected ? SeeUColors.accent : Colors.grey.withValues(alpha: 0.3),
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: SeeUColors.accent.withValues(alpha: 0.2),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: textColor,
          ),
        ),
      ),
    );
  }
}
