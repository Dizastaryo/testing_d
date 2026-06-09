import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:dio/dio.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/config/app_config.dart';
import '../../core/design/design.dart';
import '../../core/models/sbor.dart';
import '../../core/providers/chat_provider.dart';
import 'sbory_screen.dart' show sborRefreshProvider;

// ─── Provider ────────────────────────────────────────────────────

final _editSborProvider =
    FutureProvider.autoDispose.family<Sbor, String>((ref, id) async {
  final api = ref.read(apiClientProvider);
  final r = await api.get(ApiEndpoints.sborById(id));
  final data = r.data is Map && (r.data as Map).containsKey('data')
      ? r.data['data']
      : r.data;
  return Sbor.fromJson(data as Map<String, dynamic>);
});

// ─── Screen ──────────────────────────────────────────────────────

class SborEditScreen extends ConsumerWidget {
  final String sborId;
  const SborEditScreen({super.key, required this.sborId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final async = ref.watch(_editSborProvider(sborId));
    return async.when(
      loading: () => Scaffold(
        backgroundColor: c.bg,
        body: const SafeArea(child: SeeUSborDetailSkeleton()),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(backgroundColor: Colors.transparent),
        body: Center(child: Text('Ошибка: $e')),
      ),
      data: (sbor) => _SborEditForm(sbor: sbor),
    );
  }
}

class _SborEditForm extends ConsumerStatefulWidget {
  final Sbor sbor;
  const _SborEditForm({required this.sbor});

  @override
  ConsumerState<_SborEditForm> createState() => _SborEditScreenState();
}

class _SborEditScreenState extends ConsumerState<_SborEditForm> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _placeCtrl;
  late final TextEditingController _descCtrl;

  late SborCategory _category;
  late bool _isPaid;
  late final TextEditingController _priceCtrl;

  DateTime? _scheduledDate;
  TimeOfDay? _scheduledTime;
  bool _flexibleTime = false;
  int _slots = 8;
  bool _noLimit = false;
  bool _submitting = false;

  // Cover image state
  XFile? _coverImage;      // newly picked file (not yet uploaded)
  String? _coverUrl;       // existing cover URL from sbor
  bool _deleteCover = false;

  @override
  void initState() {
    super.initState();
    final s = widget.sbor;
    _titleCtrl = TextEditingController(text: s.title);
    _placeCtrl = TextEditingController(text: s.place);
    _descCtrl = TextEditingController(text: s.description ?? '');
    _category = s.category;
    _isPaid = s.price > 0;
    _priceCtrl = TextEditingController(text: s.price > 0 ? '${s.price}' : '');
    _flexibleTime = s.scheduledAt == null;
    if (s.scheduledAt != null) {
      _scheduledDate = s.scheduledAt;
      _scheduledTime = TimeOfDay.fromDateTime(s.scheduledAt!.toLocal());
    }
    if (s.max != null) {
      _slots = s.max!;
    } else {
      _noLimit = true;
    }
    _coverUrl = s.coverUrl;
    _titleCtrl.addListener(() => setState(() {}));
    _placeCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _placeCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
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
                        _buildCoverPicker(c),
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
                        _buildPriceField(c),
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
                const Text(
                  'Редактировать сбор',
                  style: TextStyle(
                    fontFamily: 'Fraunces',
                    fontSize: 22, fontWeight: FontWeight.w500,
                    letterSpacing: -0.2, height: 1.1,
                  ),
                ),
                Text(
                  widget.sbor.title,
                  style: TextStyle(fontSize: 12, color: c.ink3),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? get _resolvedCoverUrl {
    if (_coverUrl == null || _coverUrl!.isEmpty) return null;
    return _coverUrl!.startsWith('/') ? AppConfig.apiOrigin + _coverUrl! : _coverUrl!;
  }

  Widget _buildCoverPicker(SeeUThemeColors c) {
    final hasExisting = _resolvedCoverUrl != null && !_deleteCover && _coverImage == null;
    final hasNew = _coverImage != null;
    final hasAny = hasExisting || hasNew;

    Widget thumb;
    if (hasNew) {
      thumb = Image.file(File(_coverImage!.path), width: 48, height: 48, fit: BoxFit.cover);
    } else if (hasExisting) {
      thumb = CachedNetworkImage(
        imageUrl: _resolvedCoverUrl!,
        width: 48, height: 48,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => Icon(PhosphorIcons.image(), size: 20, color: c.ink4),
      );
    } else {
      thumb = Container(
        width: 48, height: 48,
        color: c.surface2,
        child: Icon(PhosphorIcons.image(), size: 20, color: c.ink4),
      );
    }

    return GestureDetector(
      onTap: _pickCoverImage,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(10), child: thumb),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Обложка сбора',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: c.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasAny ? 'Нажмите, чтобы заменить' : 'Необязательно',
                    style: TextStyle(fontSize: 12, color: c.ink3),
                  ),
                ],
              ),
            ),
            if (hasAny)
              GestureDetector(
                onTap: () => setState(() {
                  _coverImage = null;
                  _deleteCover = true;
                }),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(PhosphorIcons.x(PhosphorIconsStyle.bold), size: 16, color: c.ink3),
                ),
              )
            else
              Icon(PhosphorIcons.caretRight(), size: 16, color: c.ink4),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCoverImage() async {
    HapticFeedback.selectionClick();
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1080,
      maxHeight: 1080,
      imageQuality: 85,
    );
    if (file != null) {
      setState(() {
        _coverImage = file;
        _deleteCover = false;
      });
    }
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
              hintText: 'Название сбора',
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
              Text('гибко — договоримся', style: TextStyle(fontSize: 12, color: c.ink3)),
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
        _label(widget.sbor.type == SborType.online ? 'Платформа' : 'Место'),
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
                widget.sbor.type == SborType.online
                    ? PhosphorIcons.globe()
                    : PhosphorIcons.mapPinLine(),
                size: 16, color: c.ink3,
              ),
              hintText: widget.sbor.type == SborType.online
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
                  icon: PhosphorIconsBold.minus,
                  onTap: () => setState(() => _slots = (_slots - 1).clamp(widget.sbor.joined.clamp(2, 99), 99)),
                  c: c,
                ),
                const SizedBox(width: 4),
                _StepperBtn(
                  icon: PhosphorIconsBold.plus,
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
                      style: const TextStyle(
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

  static const _catOptions = [
    (SborCategory.basketball, '⚽', 'Спорт'),
    (SborCategory.games, '🎮', 'Игры'),
    (SborCategory.hike, '🏕️', 'Природа'),
    (SborCategory.draw, '🎨', 'Творчество'),
    (SborCategory.board, '🎲', 'Настолки'),
    (SborCategory.cinema, '🎬', 'Кино'),
    (SborCategory.music, '🎶', 'Музыка'),
    (SborCategory.food, '🍳', 'Готовим'),
    (SborCategory.read, '📖', 'Книги'),
    (SborCategory.other, '✨', 'Другое'),
  ];

  Widget _buildCategoryPicker(SeeUThemeColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Категория'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _catOptions.map((opt) {
            final (cat, emoji, name) = opt;
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
                    Text(emoji, style: const TextStyle(fontSize: 14)),
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
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildPriceField(SeeUThemeColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Взнос'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              _priceTab(false, 'Бесплатно', c),
              _priceTab(true, 'Платный', c),
            ],
          ),
        ),
        if (_isPaid) ...[
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.line),
            ),
            child: TextField(
              controller: _priceCtrl,
              keyboardType: TextInputType.number,
              style: TextStyle(fontSize: 15, color: c.ink, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 14, right: 8),
                  child: Text('₸', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.ink3)),
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                hintText: 'Сумма взноса',
                hintStyle: TextStyle(fontSize: 15, color: c.ink4),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.fromLTRB(0, 14, 16, 14),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _priceTab(bool paid, String label, SeeUThemeColors c) {
    final active = _isPaid == paid;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _isPaid = paid;
          if (!paid) _priceCtrl.clear();
        }),
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
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13, fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: active ? c.ink : c.ink3,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStickyBottom(BuildContext context, SeeUThemeColors c) {
    final canSave = _titleCtrl.text.trim().length >= 3 &&
        _placeCtrl.text.trim().isNotEmpty &&
        (_flexibleTime || _scheduledDate != null) &&
        (!_isPaid || (int.tryParse(_priceCtrl.text.trim()) ?? 0) > 0);

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
          onTap: canSave && !_submitting ? _submit : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 52,
            decoration: BoxDecoration(
              color: canSave ? SeeUColors.accent : c.surface2,
              borderRadius: BorderRadius.circular(16),
              boxShadow: canSave
                  ? [BoxShadow(
                      color: SeeUColors.accent.withValues(alpha: 0.35),
                      blurRadius: 24, offset: const Offset(0, 8),
                    )]
                  : null,
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
                    'Сохранить',
                    style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600,
                      color: canSave ? Colors.white : c.ink3,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    PhosphorIcons.checkFat(PhosphorIconsStyle.bold),
                    size: 16, color: canSave ? Colors.white : c.ink3,
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

      // Handle cover image
      String? newCoverUrl;
      if (_coverImage != null) {
        final formData = FormData.fromMap({
          'file': await MultipartFile.fromFile(
            _coverImage!.path,
            filename: _coverImage!.name,
          ),
        });
        final uploadRes = await api.post(ApiEndpoints.mediaUpload, data: formData);
        final resData = uploadRes.data is Map ? uploadRes.data : {};
        newCoverUrl = (resData['data']?['url'] ?? resData['url'] ?? '') as String;
      } else if (_deleteCover) {
        newCoverUrl = '';
      }

      final body = <String, dynamic>{
        'title': _titleCtrl.text.trim(),
        'place': _placeCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'flexible_time': _flexibleTime,
        'max_slots': _noLimit ? null : _slots,
        'price': _isPaid ? (int.tryParse(_priceCtrl.text.trim()) ?? 0) : 0,
        'category': _category.name,
        if (newCoverUrl != null) 'cover_url': newCoverUrl,
        if (dt != null) 'scheduled_at': dt.toUtc().toIso8601String(),
        if (_flexibleTime) 'scheduled_at': null,
      };

      await api.patch(ApiEndpoints.sborById(widget.sbor.id), data: body);

      if (!mounted) return;
      ref.read(sborRefreshProvider.notifier).state++;
      ref.read(chatListProvider.notifier).load();
      context.pop();
    } catch (e) {
      if (!mounted) return;
      String msg = 'Ошибка: $e';
      if (e is DioException && e.response != null) {
        final d = e.response!.data;
        msg = d is Map ? 'Ошибка: ${d['error'] ?? d['message'] ?? d}' : 'Ошибка ${e.response!.statusCode}';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
  final IconData icon;
  final VoidCallback onTap;
  final SeeUThemeColors c;

  const _StepperBtn({required this.icon, required this.onTap, required this.c});

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
          child: Icon(icon, size: 16, color: c.ink),
        ),
      ),
    );
  }
}
