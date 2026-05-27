import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/models/sbor.dart';

class SborCreateScreen extends ConsumerStatefulWidget {
  const SborCreateScreen({super.key});

  @override
  ConsumerState<SborCreateScreen> createState() => _SborCreateScreenState();
}

class _SborCreateScreenState extends ConsumerState<SborCreateScreen> {
  final _titleCtrl = TextEditingController();
  final _placeCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  SborType _type = SborType.offline;
  SborCategory? _category;
  int _slots = 8;
  bool _flexibleTime = false;
  bool _noLimit = false;
  bool _submitting = false;

  DateTime? _scheduledDate;
  TimeOfDay? _scheduledTime;

  static const _catOptions = [
    (SborCategory.basketball, '🏀', 'Баскетбол'),
    (SborCategory.run, '🏃', 'Бег'),
    (SborCategory.hike, '🥾', 'Хайкинг'),
    (SborCategory.games, '🎮', 'Игры'),
    (SborCategory.board, '🎲', 'Настолки'),
    (SborCategory.cinema, '🎬', 'Кино'),
    (SborCategory.draw, '🎨', 'Творчество'),
    (SborCategory.music, '🎶', 'Музыка'),
    (SborCategory.food, '🍳', 'Готовим'),
    (SborCategory.read, '📖', 'Книжный'),
  ];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _placeCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(c),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTypeToggle(c),
                        const SizedBox(height: 18),
                        _buildTitleField(c),
                        const SizedBox(height: 18),
                        _buildCategoryPicker(c),
                        const SizedBox(height: 18),
                        _buildWhenSection(c),
                        const SizedBox(height: 16),
                        _buildPlaceField(c),
                        const SizedBox(height: 16),
                        _buildSlotsSection(c),
                        const SizedBox(height: 16),
                        _buildDescField(c),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            _buildStickyBottom(context, c),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(SeeUThemeColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 14),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: c.surface,
                shape: BoxShape.circle,
                boxShadow: SeeUShadows.sm,
              ),
              child: Icon(
                PhosphorIcons.caretLeft(PhosphorIconsStyle.bold),
                size: 16, color: c.ink,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Новый сбор',
                  style: const TextStyle(
                    fontFamily: 'Fraunces',
                    fontSize: 22, fontWeight: FontWeight.w500,
                    letterSpacing: -0.2, height: 1.1,
                  ),
                ),
                Text(
                  'Заполни — займёт минуту',
                  style: TextStyle(fontSize: 12, color: c.ink3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeToggle(SeeUThemeColors c) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _typeTab(SborType.offline, PhosphorIcons.mapPin(PhosphorIconsStyle.fill), 'Оффлайн', c),
          _typeTab(SborType.online, PhosphorIcons.globe(), 'Онлайн', c),
        ],
      ),
    );
  }

  Widget _typeTab(SborType t, IconData icon, String label, SeeUThemeColors c) {
    final active = _type == t;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _type = t),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 36,
          decoration: BoxDecoration(
            color: active ? c.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: active
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 2, offset: const Offset(0, 1))]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: active ? SeeUColors.accent : c.ink3),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13, fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  color: active ? c.ink : c.ink3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitleField(SeeUThemeColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Название'),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.line),
          ),
          child: TextField(
            controller: _titleCtrl,
            style: const TextStyle(
              fontFamily: 'Fraunces',
              fontSize: 18, fontWeight: FontWeight.w500,
              letterSpacing: -0.2,
            ),
            decoration: InputDecoration(
              hintText: 'Например, стритбол в парке…',
              hintStyle: TextStyle(
                fontFamily: 'Fraunces',
                fontSize: 18, fontWeight: FontWeight.w400,
                color: c.ink4,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryPicker(SeeUThemeColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Что за активность'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ..._catOptions.map((opt) {
              final (cat, _, name) = opt;
              final meta = kSborCategories[cat]!;
              final active = _category == cat;
              return GestureDetector(
                onTap: () => setState(() => _category = cat),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: active ? meta.color : c.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: active ? null : Border.all(color: c.line),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(meta.icon, size: 14, color: active ? Colors.white : meta.color),
                      const SizedBox(width: 6),
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500,
                          color: active ? Colors.white : c.ink2,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            GestureDetector(
              onTap: () {},
              child: Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: c.ink4, style: BorderStyle.solid, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIcons.plus(PhosphorIconsStyle.bold), size: 12, color: c.ink3),
                    const SizedBox(width: 6),
                    Text('своё', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.ink3)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWhenSection(SeeUThemeColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Когда'),
        const SizedBox(height: 8),
        if (!_flexibleTime)
          Row(
            children: [
              Expanded(
                child: _FormField(
                  icon: PhosphorIcons.calendarBlank(),
                  value: _scheduledDate != null
                      ? '${_scheduledDate!.day} ${_monthName(_scheduledDate!.month)}'
                      : 'Выбрать дату',
                  c: c,
                  onTap: () => _pickDate(context),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 110,
                child: _FormField(
                  icon: PhosphorIcons.clock(),
                  value: _scheduledTime != null
                      ? _scheduledTime!.format(context)
                      : 'Время',
                  c: c,
                  onTap: () => _pickTime(context),
                ),
              ),
            ],
          ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => setState(() => _flexibleTime = !_flexibleTime),
          child: Row(
            children: [
              Container(
                width: 16, height: 16,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: _flexibleTime ? SeeUColors.accent : c.ink4),
                  color: _flexibleTime ? SeeUColors.accent : Colors.transparent,
                ),
                child: _flexibleTime
                    ? const Icon(PhosphorIconsBold.check, size: 12, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 6),
              Text(
                'гибко — договоримся',
                style: TextStyle(fontSize: 12, color: c.ink3),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlaceField(SeeUThemeColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(_type == SborType.online ? 'Платформа' : 'Место'),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.line),
          ),
          child: TextField(
            controller: _placeCtrl,
            style: TextStyle(fontSize: 15, color: c.ink, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              prefixIcon: Icon(
                _type == SborType.online ? PhosphorIcons.globe() : PhosphorIcons.mapPinLine(),
                size: 16, color: c.ink3,
              ),
              hintText: _type == SborType.online
                  ? 'Steam, Discord, PlayStation…'
                  : 'Парк Горького, корт №2',
              hintStyle: TextStyle(fontSize: 15, color: c.ink4),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.fromLTRB(0, 14, 16, 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSlotsSection(SeeUThemeColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Сколько человек нужно'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.line),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Всего мест', style: TextStyle(fontSize: 12, color: c.ink3)),
                    const SizedBox(height: 2),
                    Text(
                      _noLimit ? '∞' : '$_slots',
                      style: const TextStyle(
                        fontFamily: 'Fraunces',
                        fontSize: 26, fontWeight: FontWeight.w500, height: 1,
                      ),
                    ),
                  ],
                ),
              ),
              if (!_noLimit) ...[
                _StepperBtn(
                  label: '−',
                  onTap: () => setState(() => _slots = (_slots - 1).clamp(2, 99)),
                  c: c,
                ),
                const SizedBox(width: 4),
                _StepperBtn(
                  label: '+',
                  onTap: () => setState(() => _slots = (_slots + 1).clamp(2, 99)),
                  c: c,
                ),
              ],
              const SizedBox(width: 8),
              Container(width: 1, height: 32, color: c.line),
              const SizedBox(width: 12),
              Column(
                children: [
                  Text('или', style: TextStyle(fontSize: 12, color: c.ink3)),
                  GestureDetector(
                    onTap: () => setState(() => _noLimit = !_noLimit),
                    child: Text(
                      'без лимита',
                      style: TextStyle(
                        fontSize: 12, color: SeeUColors.accent, fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDescField(SeeUThemeColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _label('Пара слов о сборе'),
            const SizedBox(width: 6),
            Text('необязательно', style: TextStyle(fontSize: 11, color: c.ink4)),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.line),
          ),
          child: TextField(
            controller: _descCtrl,
            minLines: 3,
            maxLines: 6,
            style: TextStyle(fontSize: 14, color: c.ink),
            decoration: InputDecoration(
              hintText: 'Уровень, снаряжение, планы после…',
              hintStyle: TextStyle(fontSize: 14, color: c.ink4),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStickyBottom(BuildContext context, SeeUThemeColors c) {
    final canCreate = _titleCtrl.text.trim().isNotEmpty &&
        _category != null &&
        (_flexibleTime || _scheduledDate != null) &&
        _placeCtrl.text.trim().isNotEmpty;

    return Positioned(
      left: 0, right: 0, bottom: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [c.bg, c.bg.withValues(alpha: 0)],
            stops: const [0.6, 1.0],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 34),
        child: GestureDetector(
          onTap: canCreate && !_submitting ? _submit : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 52,
            decoration: BoxDecoration(
              color: canCreate ? c.ink : c.surface2,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_submitting)
                  const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                else ...[
                  Text(
                    'Создать сбор',
                    style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600,
                      color: canCreate ? Colors.white : c.ink3,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    PhosphorIcons.arrowRight(PhosphorIconsStyle.bold),
                    size: 16, color: canCreate ? Colors.white : c.ink3,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _scheduledDate ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _scheduledDate = picked);
  }

  Future<void> _pickTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _scheduledTime ?? const TimeOfDay(hour: 14, minute: 0),
    );
    if (picked != null) setState(() => _scheduledTime = picked);
  }

  Future<void> _submit() async {
    HapticFeedback.mediumImpact();
    setState(() => _submitting = true);
    try {
      final api = ref.read(apiClientProvider);
      DateTime? dt;
      if (!_flexibleTime && _scheduledDate != null) {
        final t = _scheduledTime ?? const TimeOfDay(hour: 12, minute: 0);
        dt = DateTime(
          _scheduledDate!.year, _scheduledDate!.month, _scheduledDate!.day,
          t.hour, t.minute,
        );
      }

      await api.post(ApiEndpoints.sbory, data: {
        'title': _titleCtrl.text.trim(),
        'type': _type.name,
        'category': _category!.name,
        'place': _placeCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'max_slots': _noLimit ? null : _slots,
        'flexible_time': _flexibleTime,
        if (dt != null) 'scheduled_at': dt.toIso8601String(),
      });

      if (!mounted) return;
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _label(String text) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11, fontWeight: FontWeight.w600,
        letterSpacing: 0.8, color: SeeUColors.textTertiary,
      ),
    );
  }

  String _monthName(int m) {
    const names = ['янв', 'фев', 'мар', 'апр', 'май', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];
    return names[m - 1];
  }
}

class _FormField extends StatelessWidget {
  final IconData icon;
  final String value;
  final SeeUThemeColors c;
  final VoidCallback? onTap;

  const _FormField({required this.icon, required this.value, required this.c, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: c.ink3),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value,
                style: TextStyle(fontSize: 15, color: c.ink, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepperBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final SeeUThemeColors c;

  const _StepperBtn({required this.label, required this.onTap, required this.c});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.ink),
          ),
        ),
      ),
    );
  }
}
