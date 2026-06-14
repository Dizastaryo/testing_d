import 'package:flutter/material.dart';
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

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).padding.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: c.ink4, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Text('Настройки чтения',
              style: TextStyle(
                fontFamily: 'Fraunces',
                fontSize: 18,
                fontWeight: FontWeight.w400,
                color: c.ink,
              )),
          const SizedBox(height: 20),

          // Font size
          Row(
            children: [
              Icon(PhosphorIconsRegular.textT, size: 14, color: c.ink3),
              const SizedBox(width: 8),
              Text('Размер шрифта',
                  style: TextStyle(fontSize: 13, color: c.ink2)),
              const Spacer(),
              Text('${settings.fontSize.toInt()}px',
                  style: TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 12,
                      color: SeeUColors.accent)),
            ],
          ),
          Slider(
            value: settings.fontSize,
            min: 12,
            max: 24,
            divisions: 12,
            activeColor: SeeUColors.accent,
            inactiveColor: SeeUColors.accent.withValues(alpha: 0.2),
            onChanged: (v) => notifier.setFontSize(v),
          ),

          const SizedBox(height: 4),

          // Line height
          Text('Межстрочный интервал',
              style: TextStyle(fontSize: 13, color: c.ink2)),
          const SizedBox(height: 8),
          Row(
            children: [
              _ToggleChip(
                label: 'Обычный',
                selected: settings.lineHeight < 1.8,
                onTap: () => notifier.setLineHeight(1.6),
              ),
              const SizedBox(width: 10),
              _ToggleChip(
                label: 'Широкий',
                selected: settings.lineHeight >= 1.8,
                onTap: () => notifier.setLineHeight(1.9),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Font family
          Text('Шрифт', style: TextStyle(fontSize: 13, color: c.ink2)),
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
                fontFamily: 'Georgia',
                selected: settings.fontFamily == ReaderFontFamily.serif,
                onTap: () => notifier.setFontFamily(ReaderFontFamily.serif),
              ),
              const SizedBox(width: 10),
              _FontChip(
                label: 'Моно',
                preview: 'Аа',
                fontFamily: 'JetBrains Mono',
                selected: settings.fontFamily == ReaderFontFamily.mono,
                onTap: () => notifier.setFontFamily(ReaderFontFamily.mono),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Theme
          Text('Тема', style: TextStyle(fontSize: 13, color: c.ink2)),
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
              const SizedBox(width: 10),
              _ThemeChip(
                label: 'Сепия',
                bgColor: const Color(0xFFF5EDD3),
                textColor: const Color(0xFF3D2B1A),
                selected: settings.theme == ReaderTheme.sepia,
                onTap: () => notifier.setTheme(ReaderTheme.sepia),
              ),
              const SizedBox(width: 10),
              _ThemeChip(
                label: 'Тёмная',
                bgColor: const Color(0xFF1A1A1A),
                textColor: const Color(0xFFE0E0E0),
                selected: settings.theme == ReaderTheme.dark,
                onTap: () => notifier.setTheme(ReaderTheme.dark),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ToggleChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? SeeUColors.accent : Colors.transparent,
          border: Border.all(
            color: selected
                ? SeeUColors.accent
                : context.seeuColors.line,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: selected ? Colors.white : context.seeuColors.ink2,
          ),
        ),
      ),
    );
  }
}

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
      onTap: onTap,
      child: Container(
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
      onTap: onTap,
      child: Container(
        width: 80,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(
            color: selected ? SeeUColors.accent : Colors.grey.withValues(alpha: 0.3),
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
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
