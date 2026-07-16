import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';

/// Один пункт правил карточки.
class _Rule {
  final String num;
  final String title;
  final String body;
  const _Rule(this.num, this.title, this.body);
}

/// Правила карточки (5 пунктов) — тексты и порядок из дизайна.
const List<_Rule> _rules = [
  _Rule(
    '01',
    'Тебя видят люди рядом',
    'Карточку видят те, кто физически рядом, — включая незнакомцев. Это момент встречи вживую.',
  ),
  _Rule(
    '02',
    'Не повторяй себя из Профиля',
    'Ник и текст не должны совпадать с именем, ником в Профиле или других соцсетях.',
  ),
  _Rule(
    '03',
    'Никаких контактов и ссылок',
    'Нельзя телефон, ссылки, почту, @-упоминания и фамилию.',
  ),
  _Rule(
    '04',
    'Фото — только твоё настоящее',
    'Живое и твоё собственное — по нему человек рядом понимает, что это ты.',
  ),
  _Rule(
    '05',
    'Карточки проверяются',
    'Нарушение правил может привести к блокировке.',
  ),
];

/// Обязательный экран правил карточки (дизайн: кикер «ВАЖНО», серифный
/// заголовок, 5 нумерованных карточек, фиксированный низ с галочкой и кнопкой).
///
/// [helpMode] — открыт как справка: подтверждать ничего не нужно, внизу
/// «Закрыть». В обычном режиме продолжить нельзя без галочки.
class CardWarningScreen extends StatefulWidget {
  final bool helpMode;
  const CardWarningScreen({super.key, this.helpMode = false});

  @override
  State<CardWarningScreen> createState() => _CardWarningScreenState();
}

class _CardWarningScreenState extends State<CardWarningScreen> {
  bool _read = false;

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;

    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        children: [
          _GlassBar(
            kicker: 'ВАЖНО',
            kickerColor: SeeUColors.accent,
            title: 'Правила карточки',
            onBack: () => Navigator.of(context).pop(false),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              children: [
                Text(
                  'Карточка — отдельный, анонимный слой SeeU для людей рядом. '
                  'Прежде чем её заполнить, прочитай, что защищает тебя:',
                  style: TextStyle(fontSize: 14, height: 1.55, color: c.ink2),
                ),
                const SizedBox(height: 14),
                for (final r in _rules) ...[
                  _ruleCard(c, r),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
          _footer(c),
        ],
      ),
    );
  }

  Widget _ruleCard(SeeUThemeColors c, _Rule r) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.line, width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Номер пункта — серифом на мягком коралловом фоне.
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: c.accentSoft,
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: Text(
              r.num,
              style: SeeUTypography.displayS.copyWith(
                fontSize: 19,
                fontWeight: FontWeight.w600,
                color: SeeUColors.accent,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  r.body,
                  style: TextStyle(fontSize: 12, height: 1.4, color: c.ink2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer(SeeUThemeColors c) {
    if (widget.helpMode) {
      return Container(
        color: c.surface,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
        child: SafeArea(
          top: false,
          child: CardPrimaryButton(
            label: 'Закрыть',
            onTap: () => Navigator.of(context).pop(false),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line, width: 0.5)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Явное подтверждение действием — без галочки кнопка неактивна.
            GestureDetector(
              onTap: () => setState(() => _read = !_read),
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  CardCheckbox(checked: _read, size: 26, radius: 8),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Я прочитал(а) и понимаю правила карточки',
                      style: TextStyle(fontSize: 14.5, color: c.ink),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            CardPrimaryButton(
              label: 'Понимаю',
              enabled: _read,
              onTap: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Общие элементы дизайна карточки ────────────────────────────────────────

/// Стеклянная шапка подстраниц карточки: назад · кикер + серифный заголовок ·
/// (опц.) действие справа.
class _GlassBar extends StatelessWidget {
  final String? kicker;
  final Color? kickerColor;
  final String title;
  final VoidCallback onBack;
  final Widget? action;

  const _GlassBar({
    this.kicker,
    this.kickerColor,
    required this.title,
    required this.onBack,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Container(
      decoration: BoxDecoration(
        color: c.bg.withValues(alpha: 0.72),
        border: Border(bottom: BorderSide(color: c.line, width: 0.5)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            children: [
              GestureDetector(
                onTap: onBack,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(PhosphorIcons.caretLeft(), size: 22, color: c.ink),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (kicker != null)
                      Text(
                        kicker!,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                          color: kickerColor ?? c.ink3,
                        ),
                      ),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SeeUTypography.displayS
                          .copyWith(fontSize: 22, height: 1.1, color: c.ink),
                    ),
                  ],
                ),
              ),
              if (action != null) action!,
            ],
          ),
        ),
      ),
    );
  }
}

/// Шапка подстраниц карточки — публичная обёртка (используется студией,
/// браслетом и аудиторией).
class CardGlassBar extends StatelessWidget {
  final String? kicker;
  final Color? kickerColor;
  final String title;
  final VoidCallback onBack;
  final Widget? action;

  const CardGlassBar({
    super.key,
    this.kicker,
    this.kickerColor,
    required this.title,
    required this.onBack,
    this.action,
  });

  @override
  Widget build(BuildContext context) => _GlassBar(
        kicker: kicker,
        kickerColor: kickerColor,
        title: title,
        onBack: onBack,
        action: action,
      );
}

/// Коралловая кнопка из дизайна: radius 16, padding 16, мягкая тень.
/// Неактивная — коралл 45%.
class CardPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool enabled;

  const CardPrimaryButton({
    super.key,
    required this.label,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final on = enabled && onTap != null;
    return GestureDetector(
      onTap: on ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: on
              ? SeeUColors.accent
              : SeeUColors.accent.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(16),
          boxShadow: on
              ? [
                  BoxShadow(
                    color: SeeUColors.accent.withValues(alpha: 0.4),
                    blurRadius: 26,
                    offset: const Offset(0, 12),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// Чекбокс из дизайна: скруглённый квадрат, отмеченный — коралл + белая птичка.
class CardCheckbox extends StatelessWidget {
  final bool checked;
  final double size;
  final double radius;

  const CardCheckbox({
    super.key,
    required this.checked,
    this.size = 26,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: checked ? SeeUColors.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        border: checked
            ? null
            : Border.all(color: c.ink4, width: 2),
      ),
      alignment: Alignment.center,
      child: checked
          ? Icon(PhosphorIconsBold.check, size: size * 0.62, color: Colors.white)
          : null,
    );
  }
}

// ─── Точки входа ────────────────────────────────────────────────────────────

/// Обязательный gate: возвращает `true`, только если пользователь подтвердил.
Future<bool> showCardWarningGate(BuildContext context) async {
  final ok = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => const CardWarningScreen()),
  );
  return ok ?? false;
}

/// Правила как справка (из студии карточки).
Future<void> showCardWarningHelp(BuildContext context) {
  return Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => const CardWarningScreen(helpMode: true)),
  );
}

/// Компактное повторное предупреждение при правке ника/текста.
/// Дизайн: шторка radius 32, ручка, shield-warning, текст, галочка, кнопка
/// (неактивна без галочки) + подпись-подсказка.
Future<bool> showCardWarningCompact(BuildContext context) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    barrierColor: const Color(0xFF0B0A09).withValues(alpha: 0.45),
    builder: (_) => const _CompactWarning(),
  );
  return result ?? false;
}

class _CompactWarning extends StatefulWidget {
  const _CompactWarning();

  @override
  State<_CompactWarning> createState() => _CompactWarningState();
}

class _CompactWarningState extends State<_CompactWarning> {
  bool _read = false;

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 50,
            offset: const Offset(0, -20),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 34),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ручка шторки.
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: c.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(PhosphorIcons.shieldWarning(),
                    size: 22, color: SeeUColors.accent),
                const SizedBox(width: 10),
                Text(
                  'Прежде чем менять',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Никнейм и текст карточки не должны совпадать с твоим именем, '
              'ником в Профиле или других соцсетях и не должны содержать '
              'телефон, ссылки или почту. Иначе карточка перестаёт тебя защищать.',
              style: TextStyle(fontSize: 13.5, height: 1.55, color: c.ink2),
            ),
            const SizedBox(height: 18),
            GestureDetector(
              onTap: () => setState(() => _read = !_read),
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  CardCheckbox(checked: _read, size: 24, radius: 7),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Понимаю и не нарушаю',
                      style: TextStyle(fontSize: 14.5, color: c.ink),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            CardPrimaryButton(
              label: 'Продолжить',
              enabled: _read,
              onTap: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                'Кнопка активна только с галочкой',
                style: TextStyle(fontSize: 11.5, color: c.ink3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
