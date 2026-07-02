import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:dio/dio.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/models/sbor.dart';
import '../../core/providers/chat_provider.dart';
import '../../core/providers/sbory_city_provider.dart';
import 'sbory_screen.dart' show sborRefreshProvider;

class SborCreateScreen extends ConsumerStatefulWidget {
  const SborCreateScreen({super.key});

  @override
  ConsumerState<SborCreateScreen> createState() => _SborCreateScreenState();
}

class _SborCreateScreenState extends ConsumerState<SborCreateScreen> {
  final _titleCtrl = TextEditingController();
  final _placeCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();

  SborType _type = SborType.offline;
  SborCategory? _category;
  int _slots = 8;
  bool _flexibleTime = false;
  bool _noLimit = false;
  bool _isPaid = false;
  bool _submitting = false;
  XFile? _coverImage;

  DateTime? _scheduledDate;
  TimeOfDay? _scheduledTime;

  static const _catOrder = [
    SborCategory.basketball,
    SborCategory.games,
    SborCategory.hike,
    SborCategory.draw,
    SborCategory.board,
    SborCategory.cinema,
    SborCategory.music,
    SborCategory.food,
    SborCategory.read,
    SborCategory.other,
  ];

  @override
  void initState() {
    super.initState();
    _titleCtrl.addListener(() => setState(() {}));
    _placeCtrl.addListener(() => setState(() {}));
    _priceCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _placeCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  // ─── Close guard ───────────────────────────────────────────────────────────

  bool get _hasUnsavedData =>
      _titleCtrl.text.trim().isNotEmpty ||
      _category != null ||
      _scheduledDate != null ||
      _placeCtrl.text.trim().isNotEmpty ||
      _descCtrl.text.trim().isNotEmpty ||
      _coverImage != null;

  Future<void> _onCloseAttempt() async {
    if (!_hasUnsavedData) {
      context.pop();
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отменить создание?'),
        content: const Text('Введённые данные будут потеряны.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Продолжить'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Отменить',
              style: TextStyle(color: SeeUColors.error),
            ),
          ),
        ],
      ),
    );
    if (leave == true && mounted) context.pop();
  }

  // ─── Error helpers ─────────────────────────────────────────────────────────

  static String _friendlyCreateError(Object e) {
    if (e is DioException) {
      final type = e.type;
      if (type == DioExceptionType.connectionError ||
          type == DioExceptionType.unknown) {
        return 'Нет соединения. Проверьте интернет и попробуйте снова.';
      }
      if (type == DioExceptionType.connectionTimeout ||
          type == DioExceptionType.receiveTimeout) {
        return 'Превышено время ожидания. Попробуйте ещё раз.';
      }
      final data = e.response?.data;
      if (data is Map) {
        final msg = data['error'] ?? data['message'];
        if (msg is String && msg.isNotEmpty) return msg;
      }
      if ((e.response?.statusCode ?? 0) == 422) {
        return 'Проверьте введённые данные и попробуйте снова.';
      }
      if ((e.response?.statusCode ?? 0) >= 500) {
        return 'Ошибка сервера. Попробуйте позже.';
      }
    }
    return 'Не удалось создать сбор. Попробуйте снова.';
  }

  // ─── Validation ────────────────────────────────────────────────────────────

  /// Офлайн-сбор привязан к городу из геолокации. Если города нет (геолокация
  /// запрещена/не определена) — офлайн создать нельзя, иначе он уйдёт с пустым
  /// city и нигде не будет виден.
  bool get _cityKnown {
    final loc = ref.read(sboryCityProvider);
    return loc.city.trim().isNotEmpty && !loc.denied;
  }

  bool get _canSubmit =>
      _titleCtrl.text.trim().length >= 3 &&
      _category != null &&
      (_flexibleTime || _scheduledDate != null) &&
      _placeCtrl.text.trim().isNotEmpty &&
      (_type == SborType.online || _cityKnown) &&
      (!_isPaid || (int.tryParse(_priceCtrl.text.trim()) ?? 0) > 0) &&
      !_submitting;

  String? get _validationHint {
    if (_titleCtrl.text.trim().length < 3) {
      return 'Введите название (мин. 3 символа)';
    }
    if (_category == null) return 'Выберите категорию';
    if (!_flexibleTime && _scheduledDate == null) {
      return 'Укажите дату или отметьте «гибко»';
    }
    if (_placeCtrl.text.trim().isEmpty) return 'Укажите место встречи';
    if (_type == SborType.offline && !_cityKnown) {
      return 'Включите геолокацию, чтобы создать офлайн-сбор';
    }
    if (_isPaid && (int.tryParse(_priceCtrl.text.trim()) ?? 0) <= 0) {
      return 'Введите сумму взноса';
    }
    return null;
  }

  // ─── Pickers ───────────────────────────────────────────────────────────────

  Future<void> _pickCoverImage() async {
    HapticFeedback.selectionClick();
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1080,
      maxHeight: 1080,
      imageQuality: 85,
    );
    if (file != null) setState(() => _coverImage = file);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _scheduledDate ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _scheduledDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _scheduledTime ?? const TimeOfDay(hour: 14, minute: 0),
    );
    if (picked != null) setState(() => _scheduledTime = picked);
  }

  // ─── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_canSubmit) return;
    HapticFeedback.mediumImpact();
    setState(() => _submitting = true);
    try {
      final api = ref.read(apiClientProvider);

      String coverUrl = '';
      if (_coverImage != null) {
        final formData = FormData.fromMap({
          'file': await MultipartFile.fromFile(
            _coverImage!.path,
            filename: _coverImage!.name,
          ),
        });
        final up = await api.post(ApiEndpoints.mediaUpload, data: formData);
        final d = up.data is Map ? up.data : {};
        coverUrl = (d['data']?['url'] ?? d['url'] ?? '') as String;
      }

      DateTime? dt;
      if (!_flexibleTime && _scheduledDate != null) {
        final t = _scheduledTime ?? const TimeOfDay(hour: 12, minute: 0);
        dt = DateTime(
          _scheduledDate!.year,
          _scheduledDate!.month,
          _scheduledDate!.day,
          t.hour,
          t.minute,
        ).toUtc();
      }

      final city = ref.read(sboryCityProvider).city;
      // Safety net: never POST an offline sbor without a city — it would be
      // created but never appear in any city-scoped feed.
      if (_type == SborType.offline && city.trim().isEmpty) {
        if (mounted) {
          showSeeUSnackBar(
              context, 'Включите геолокацию, чтобы создать офлайн-сбор',
              tone: SeeUTone.danger);
        }
        return;
      }
      final price =
          _isPaid ? (int.tryParse(_priceCtrl.text.trim()) ?? 0) : 0;

      await api.post(ApiEndpoints.sbory, data: {
        'title': _titleCtrl.text.trim(),
        'type': _type.name,
        'category': _category!.name,
        'place': _placeCtrl.text.trim(),
        'city': city,
        'cover_url': coverUrl,
        'price': price,
        'description': _descCtrl.text.trim(),
        'max_slots': _noLimit ? null : _slots,
        'flexible_time': _flexibleTime,
        if (dt != null) 'scheduled_at': dt.toUtc().toIso8601String(),
      });

      if (!mounted) return;
      ref.read(sborRefreshProvider.notifier).state++;
      ref.read(chatListProvider.notifier).load();
      context.pop();
    } catch (e) {
      if (!mounted) return;
      showSeeUSnackBar(context, _friendlyCreateError(e),
          tone: SeeUTone.danger);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ─── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final loc = ref.watch(sboryCityProvider);

    // Геолокация запрещена → офлайн недоступен. Принудительно переключаем на
    // онлайн (после кадра, т.к. setState нельзя звать прямо в build).
    if (loc.denied && _type == SborType.offline) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            ref.read(sboryCityProvider).denied &&
            _type == SborType.offline) {
          setState(() => _type = SborType.online);
        }
      });
    }

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(c, loc),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 130),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildCoverHero(c),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildTypeToggle(c),
                              const SizedBox(height: 20),
                              _buildTitleField(c),
                              const SizedBox(height: 20),
                              _buildCategoryPicker(c),
                              const SizedBox(height: 20),
                              _buildWhenSection(c),
                              const SizedBox(height: 16),
                              _buildPlaceField(c),
                              const SizedBox(height: 16),
                              _buildDetailsCard(c),
                              const SizedBox(height: 16),
                              _buildDescField(c),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            _buildStickyBottom(c),
          ],
        ),
      ),
    );
  }

  // ─── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(SeeUThemeColors c, SboryLocation loc) {
    final denied = loc.denied;
    final cityLabel = denied
        ? 'Геолокация выключена'
        : (loc.city.isNotEmpty ? loc.city : 'Определяем…');
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 16, 6),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(bottom: BorderSide(color: c.line, width: 0.5)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _onCloseAttempt,
            icon: Icon(PhosphorIcons.x(PhosphorIconsStyle.bold),
                size: 20, color: c.ink),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Новый сбор',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                        denied
                            ? PhosphorIconsRegular.mapPinLine
                            : PhosphorIconsRegular.mapPin,
                        size: 11,
                        color: denied ? SeeUColors.accent : c.ink3),
                    const SizedBox(width: 3),
                    Text(
                      cityLabel,
                      style: TextStyle(
                          fontSize: 11,
                          color: denied ? SeeUColors.accent : c.ink3),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Category color indicator (shows selected category)
          if (_category != null)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: kSborCategories[_category!]!.soft,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(kSborCategories[_category!]!.icon,
                      size: 12,
                      color: kSborCategories[_category!]!.color),
                  const SizedBox(width: 4),
                  Text(
                    kSborCategories[_category!]!.name,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: kSborCategories[_category!]!.color,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ─── Cover hero ────────────────────────────────────────────────────────────

  Widget _buildCoverHero(SeeUThemeColors c) {
    final hasCover = _coverImage != null;
    // When category selected → tint the empty state with category soft color
    final catColor = _category != null
        ? kSborCategories[_category!]!.color
        : SeeUColors.accent;
    final catSoft = _category != null
        ? kSborCategories[_category!]!.soft
        : SeeUColors.accentSoft;

    return GestureDetector(
      onTap: hasCover ? null : _pickCoverImage,
      child: SizedBox(
        height: 190,
        width: double.infinity,
        child: hasCover
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(File(_coverImage!.path), fit: BoxFit.cover),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0x88000000)],
                        stops: [0.45, 1.0],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 14,
                    right: 14,
                    child: GestureDetector(
                      onTap: _pickCoverImage,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 13, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.52),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                              width: 0.5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(PhosphorIconsRegular.camera,
                                size: 13, color: Colors.white),
                            const SizedBox(width: 5),
                            const Text('Изменить',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 14,
                    left: 14,
                    child: GestureDetector(
                      onTap: () => setState(() => _coverImage = null),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.52),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                              width: 0.5),
                        ),
                        child: Icon(PhosphorIconsBold.x,
                            size: 13, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              )
            : AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                decoration: BoxDecoration(
                  color: catSoft,
                  border: Border.all(
                    color: catColor.withValues(alpha: 0.30),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: catColor.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        PhosphorIconsRegular.camera,
                        size: 24,
                        color: catColor.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(PhosphorIconsBold.plus,
                            size: 13,
                            color: catColor.withValues(alpha: 0.8)),
                        const SizedBox(width: 5),
                        Text(
                          'Добавить обложку',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: catColor.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Необязательно · Нажмите чтобы выбрать фото',
                      style: TextStyle(
                        fontSize: 11,
                        color: catColor.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  // ─── Type toggle ───────────────────────────────────────────────────────────

  Widget _buildTypeToggle(SeeUThemeColors c) {
    // Офлайн доступен только когда известен город. Иначе вкладку гасим и даём
    // подсказку — создать офлайн-сбор без геолокации нельзя.
    final offlineEnabled = _cityKnown;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _typeTab(SborType.offline,
              PhosphorIcons.mapPin(PhosphorIconsStyle.fill), 'Оффлайн', c,
              enabled: offlineEnabled),
          _typeTab(SborType.online, PhosphorIcons.globe(), 'Онлайн', c),
        ],
      ),
    );
  }

  Widget _typeTab(
      SborType t, IconData icon, String label, SeeUThemeColors c,
      {bool enabled = true}) {
    final active = _type == t;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          if (!enabled) {
            showSeeUSnackBar(
                context, 'Включите геолокацию, чтобы создать офлайн-сбор',
                tone: SeeUTone.danger);
            return;
          }
          setState(() => _type = t);
        },
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 38,
          decoration: BoxDecoration(
            color: active ? c.bg : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            boxShadow: active
                ? [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 4,
                        offset: const Offset(0, 1))
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 15,
                  color: active ? SeeUColors.accent : c.ink3),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight:
                      active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? c.ink : c.ink3,
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  // ─── Title ─────────────────────────────────────────────────────────────────

  Widget _buildTitleField(SeeUThemeColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('НАЗВАНИЕ'),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.line),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _titleCtrl,
                  style: SeeUTypography.displayXS
                      .copyWith(fontWeight: FontWeight.w500),
                  decoration: InputDecoration(
                    hintText: 'Например, стритбол в парке…',
                    hintStyle: SeeUTypography.displayXS.copyWith(color: c.ink4),
                    border: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.fromLTRB(16, 14, 8, 14),
                    counterText: '',
                  ),
                  maxLength: 80,
                ),
              ),
              if (_titleCtrl.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    '${_titleCtrl.text.length}/80',
                    style: TextStyle(fontSize: 11, color: c.ink4),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Category ──────────────────────────────────────────────────────────────

  Widget _buildCategoryPicker(SeeUThemeColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('КАТЕГОРИЯ'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _catOrder.map((cat) {
            final meta = kSborCategories[cat]!;
            final active = _category == cat;
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _category = active ? null : cat);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 13),
                decoration: BoxDecoration(
                  color: active ? meta.color : meta.soft,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: meta.color.withValues(alpha: 0.28),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          )
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      meta.icon,
                      size: 15,
                      color: active
                          ? Colors.white
                          : meta.color.withValues(alpha: 0.85),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      meta.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
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

  // ─── When ──────────────────────────────────────────────────────────────────

  Widget _buildWhenSection(SeeUThemeColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('КОГДА'),
        const SizedBox(height: 10),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: _flexibleTime
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: Row(
            children: [
              Expanded(
                child: _DateTimeChip(
                  icon: PhosphorIcons.calendarBlank(),
                  value: _scheduledDate != null
                      ? '${_scheduledDate!.day} ${_monthName(_scheduledDate!.month)}'
                      : 'Дата',
                  filled: _scheduledDate != null,
                  onTap: _pickDate,
                  c: c,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                child: _DateTimeChip(
                  icon: PhosphorIcons.clock(),
                  value: _scheduledTime != null
                      ? _scheduledTime!.format(context)
                      : 'Время',
                  filled: _scheduledTime != null,
                  onTap: _pickTime,
                  c: c,
                ),
              ),
            ],
          ),
          secondChild: Container(
            height: 46,
            decoration: BoxDecoration(
              color: SeeUColors.accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                  color: SeeUColors.accent.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(PhosphorIconsRegular.handshake,
                    size: 16, color: SeeUColors.accent),
                const SizedBox(width: 8),
                Text(
                  'Время гибкое — договоримся',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: SeeUColors.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() {
              _flexibleTime = !_flexibleTime;
              if (_flexibleTime) {
                _scheduledDate = null;
                _scheduledTime = null;
              }
            });
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: _flexibleTime
                        ? SeeUColors.accent
                        : c.ink4,
                    width: 1.5,
                  ),
                  color: _flexibleTime
                      ? SeeUColors.accent
                      : Colors.transparent,
                ),
                child: _flexibleTime
                    ? const Icon(PhosphorIconsBold.check,
                        size: 12, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 8),
              Text(
                'Гибкое время — договоримся',
                style: TextStyle(fontSize: 13, color: c.ink2),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Place ─────────────────────────────────────────────────────────────────

  Widget _buildPlaceField(SeeUThemeColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(_type == SborType.online ? 'ПЛАТФОРМА' : 'МЕСТО'),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.line),
          ),
          child: TextField(
            controller: _placeCtrl,
            style: TextStyle(
                fontSize: 15,
                color: c.ink,
                fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              prefixIcon: Padding(
                padding:
                    const EdgeInsets.only(left: 14, right: 10),
                child: Icon(
                  _type == SborType.online
                      ? PhosphorIcons.globe()
                      : PhosphorIcons.mapPinLine(),
                  size: 17,
                  color: c.ink3,
                ),
              ),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 0, minHeight: 0),
              hintText: _type == SborType.online
                  ? 'Steam, Discord, Zoom…'
                  : 'Парк Горького, корт №2',
              hintStyle:
                  TextStyle(fontSize: 15, color: c.ink4),
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.fromLTRB(0, 14, 16, 14),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Details card (slots + price) ──────────────────────────────────────────

  Widget _buildDetailsCard(SeeUThemeColors c) {
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
      ),
      child: Column(
        children: [
          // Slots row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            child: Row(
              children: [
                Icon(PhosphorIconsRegular.usersThree,
                    size: 18, color: c.ink3),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Мест в сборе',
                          style: TextStyle(
                              fontSize: 13, color: c.ink3)),
                      Text(
                        _noLimit ? 'Без ограничений' : '$_slots человек',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: c.ink,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_noLimit) ...[
                  _StepperBtn(
                    icon: PhosphorIconsBold.minus,
                    onTap: () => setState(
                        () => _slots = (_slots - 1).clamp(2, 99)),
                    c: c,
                  ),
                  const SizedBox(width: 4),
                  Container(
                    width: 36,
                    alignment: Alignment.center,
                    child: Text(
                      '$_slots',
                      style: SeeUTypography.displayXS
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _StepperBtn(
                    icon: PhosphorIconsBold.plus,
                    onTap: () => setState(
                        () => _slots = (_slots + 1).clamp(2, 99)),
                    c: c,
                  ),
                  const SizedBox(width: 8),
                ],
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _noLimit = !_noLimit);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _noLimit
                          ? SeeUColors.accent.withValues(alpha: 0.12)
                          : c.surface2,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '∞',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _noLimit ? SeeUColors.accent : c.ink3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: c.line),
          // Price toggle
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            child: Row(
              children: [
                Icon(
                  _isPaid
                      ? PhosphorIconsRegular.wallet
                      : PhosphorIconsRegular.gift,
                  size: 18,
                  color: c.ink3,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Взнос',
                    style: TextStyle(fontSize: 14, color: c.ink3),
                  ),
                ),
                // Price toggle
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      _priceTab(false, 'Бесплатно', c),
                      _priceTab(true, 'Платный', c),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_isPaid) ...[
            Divider(height: 1, color: c.line),
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  Text('₸',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: c.ink3)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _priceCtrl,
                      keyboardType: TextInputType.number,
                      style: SeeUTypography.displayXS
                          .copyWith(fontWeight: FontWeight.w600, color: c.ink),
                      decoration: InputDecoration(
                        hintText: 'Сумма взноса',
                        hintStyle:
                            SeeUTypography.displayXS.copyWith(color: c.ink4),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _priceTab(bool paid, String label, SeeUThemeColors c) {
    final active = _isPaid == paid;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _isPaid = paid;
          if (!paid) _priceCtrl.clear();
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? c.bg : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: active
              ? [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 3,
                      offset: const Offset(0, 1))
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? c.ink : c.ink3,
          ),
        ),
      ),
    );
  }

  // ─── Description ───────────────────────────────────────────────────────────

  Widget _buildDescField(SeeUThemeColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _label('ОПИСАНИЕ'),
            const SizedBox(width: 6),
            Text('необязательно',
                style: TextStyle(fontSize: 11, color: c.ink4)),
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
              hintText:
                  'Уровень, снаряжение, что взять с собой…',
              hintStyle:
                  TextStyle(fontSize: 14, color: c.ink4),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Sticky bottom CTA ─────────────────────────────────────────────────────

  Widget _buildStickyBottom(SeeUThemeColors c) {
    final hint = _validationHint;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [c.bg, c.bg, c.bg.withValues(alpha: 0)],
            stops: const [0.0, 0.72, 1.0],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Validation hint
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: hint != null
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(PhosphorIconsRegular.info,
                              size: 13, color: c.ink3),
                          const SizedBox(width: 5),
                          Text(
                            hint,
                            style: TextStyle(
                                fontSize: 12, color: c.ink3),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            GestureDetector(
              onTap: _canSubmit ? _submit : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 54,
                decoration: BoxDecoration(
                  gradient: _canSubmit
                      ? SeeUGradients.heroOrange
                      : null,
                  color: _canSubmit ? null : c.surface2,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: _canSubmit
                      ? [
                          BoxShadow(
                            color: SeeUColors.accent
                                .withValues(alpha: 0.35),
                            offset: const Offset(0, 6),
                            blurRadius: 20,
                          )
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_submitting)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    else ...[
                      Icon(
                        PhosphorIcons.usersThree(
                            PhosphorIconsStyle.bold),
                        size: 18,
                        color: _canSubmit ? Colors.white : c.ink3,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Создать сбор',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _canSubmit ? Colors.white : c.ink3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  Widget _label(String text) => Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
          color: context.seeuColors.ink3,
        ),
      );

  String _monthName(int m) {
    const n = [
      'янв', 'фев', 'мар', 'апр', 'май', 'июн',
      'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'
    ];
    return n[m - 1];
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _DateTimeChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final bool filled;
  final VoidCallback onTap;
  final SeeUThemeColors c;

  const _DateTimeChip({
    required this.icon,
    required this.value,
    required this.filled,
    required this.onTap,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: filled
              ? SeeUColors.accent.withValues(alpha: 0.09)
              : c.surface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: filled
                ? SeeUColors.accent.withValues(alpha: 0.35)
                : c.line,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 15,
                color: filled ? SeeUColors.accent : c.ink3),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight:
                      filled ? FontWeight.w600 : FontWeight.w500,
                  color: filled ? SeeUColors.accent : c.ink3,
                ),
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

  const _StepperBtn(
      {required this.icon, required this.onTap, required this.c});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(child: Icon(icon, size: 15, color: c.ink)),
      ),
    );
  }
}
