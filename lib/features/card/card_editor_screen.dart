import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/providers/auth_provider.dart';
import 'card_portrait.dart';
import 'card_style.dart';
import 'card_warning_screen.dart';

/// Студия «Моя карточка» — единый живой редактор: сверху превью (ровно то, что
/// видят рядом), снизу инструменты. Уровень 1 (шаблоны) работает; уровни 2/3
/// (элементы/кисть) — отдельная задача, вкладки показаны как «скоро».
class CardEditorScreen extends ConsumerStatefulWidget {
  const CardEditorScreen({super.key});

  @override
  ConsumerState<CardEditorScreen> createState() => _CardEditorScreenState();
}

class _CardEditorScreenState extends ConsumerState<CardEditorScreen>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _nickCtrl;
  late final TextEditingController _textCtrl;
  late final AnimationController _float;

  XFile? _pickedFile;
  Uint8List? _pickedBytes;
  String? _uploadedPhotoUrl;
  String _existingPhotoUrl = '';
  late CardTemplate _template;

  int _tab = 0; // 0 Основное · 1 Фон · 2 Стиль · 3 Элементы · 4 Кисть
  bool _isFirstCreation = false;
  bool _warningPassed = false;
  bool _busy = false;

  String _initialNick = '';
  String _initialText = '';

  static const int _nickMax = 40;
  static const int _textMax = 280;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).user;
    _initialNick = user?.scanAlias ?? '';
    _initialText = user?.scanText ?? '';
    _existingPhotoUrl = user?.scanPhotoUrl ?? '';
    _template = templateFromStyle(user?.scanStyle ?? '');
    _nickCtrl = TextEditingController(text: _initialNick);
    _textCtrl = TextEditingController(text: _initialText);
    _isFirstCreation = !(user?.hasCard ?? false);

    _float = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5000),
    )..repeat(reverse: true);

    if (_isFirstCreation) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _runWarningGate());
    } else {
      _warningPassed = true;
    }
  }

  @override
  void dispose() {
    _nickCtrl.dispose();
    _textCtrl.dispose();
    _float.dispose();
    super.dispose();
  }

  Future<void> _runWarningGate() async {
    final ok = await showCardWarningGate(context);
    if (!mounted) return;
    if (ok) {
      setState(() => _warningPassed = true);
    } else {
      context.pop();
    }
  }

  bool get _hasPhoto => _pickedBytes != null || _existingPhotoUrl.isNotEmpty;

  // ── Фото ──────────────────────────────────────────────────────────────────

  Future<void> _pickFrom(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 900);
    if (picked != null && mounted) {
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _pickedFile = picked;
        _pickedBytes = bytes;
        _uploadedPhotoUrl = null;
      });
    }
  }

  void _pickPhoto() {
    HapticFeedback.selectionClick();
    final c = context.seeuColors;
    showSeeUBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Фото карточки', style: SeeUTypography.subtitle),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Только твоё настоящее живое фото — по нему тебя узнают рядом.',
                  textAlign: TextAlign.center,
                  style: SeeUTypography.caption.copyWith(color: c.ink3),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: Icon(PhosphorIcons.camera(PhosphorIconsStyle.fill),
                    color: SeeUColors.accent),
                title: Text('Сделать фото', style: SeeUTypography.body),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickFrom(ImageSource.camera);
                },
              ),
              ListTile(
                leading: Icon(PhosphorIcons.image(PhosphorIconsStyle.fill),
                    color: SeeUColors.accent),
                title: Text('Выбрать из галереи', style: SeeUTypography.body),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickFrom(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Случайный никнейм ─────────────────────────────────────────────────────

  static const _adj = [
    'Северный', 'Мятный', 'Тихий', 'Полуночный', 'Медный', 'Бумажный',
    'Янтарный', 'Дальний', 'Тёплый', 'Снежный', 'Лунный', 'Бархатный',
  ];
  static const _noun = [
    'кот', 'шум', 'ветер', 'кофе', 'дождь', 'путник', 'маяк', 'сад',
    'город', 'сон', 'дым', 'берег',
  ];

  void _randomNick() {
    HapticFeedback.selectionClick();
    final r = Random();
    final nick = '${_adj[r.nextInt(_adj.length)]} ${_noun[r.nextInt(_noun.length)]}';
    setState(() => _nickCtrl.text = nick);
  }

  // ── Сохранение ────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_busy) return;
    if (!_hasPhoto) {
      showSeeUSnackBar(
        context,
        'Добавь настоящее фото — это единственное обязательное поле карточки.',
        tone: SeeUTone.danger,
      );
      return;
    }

    final nickChanged = _nickCtrl.text.trim() != _initialNick.trim();
    final textChanged = _textCtrl.text.trim() != _initialText.trim();
    if (!_isFirstCreation && (nickChanged || textChanged)) {
      final ok = await showCardWarningCompact(context);
      if (!ok) return;
    }

    setState(() => _busy = true);
    try {
      final api = ref.read(apiClientProvider);

      String? photoUrl = _uploadedPhotoUrl;
      if (photoUrl == null && _pickedBytes != null && _pickedFile != null) {
        final form = FormData.fromMap({
          'file': MultipartFile.fromBytes(_pickedBytes!,
              filename: _pickedFile!.name),
        });
        final up = await api.post(ApiEndpoints.mediaUpload, data: form);
        final d = up.data;
        photoUrl = (d is Map && d['data'] is Map)
            ? d['data']['url'] as String?
            : d is Map
                ? d['url'] as String?
                : null;
        _uploadedPhotoUrl = photoUrl;
      }

      final body = <String, dynamic>{
        'nickname': _nickCtrl.text.trim(),
        'text': _textCtrl.text.trim(),
        'style': styleFromTemplate(_template),
        'warning_acknowledged': true,
      };
      if (photoUrl != null && photoUrl.isNotEmpty) body['photo_url'] = photoUrl;

      await api.put(ApiEndpoints.myScanProfile, data: body);
      await ref.read(authProvider.notifier).reloadMe();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      showSeeUSnackBar(context, 'Карточка сохранена', tone: SeeUTone.success);
      context.pop();
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final data = e.response?.data;
      final msg =
          (data is Map ? data['error']?.toString() : null) ?? apiErrorMessage(e);
      final code = data is Map ? data['code']?.toString() : null;
      showSeeUSnackBar(context, msg, tone: SeeUTone.danger);
      if (code != null && code.startsWith('card_')) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) showCardWarningHelp(context);
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showSeeUSnackBar(context, 'Не удалось сохранить карточку',
          tone: SeeUTone.danger);
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;

    // До подтверждения правил поля карточки не показываем.
    if (!_warningPassed) {
      return Scaffold(
        backgroundColor: c.bg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          // Игровые «блобы» студии.
          _blob(top: 120, left: -40, color: SeeUColors.accent, opacity: 0.22),
          _blob(top: 90, right: -50, color: SeeUColors.plum, opacity: 0.18),
          Column(
            children: [
              CardGlassBar(
                title: 'Карточка',
                onBack: () => context.pop(),
                action: GestureDetector(
                  onTap: () => showCardWarningHelp(context),
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child:
                        Icon(PhosphorIcons.question(), size: 22, color: c.ink3),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                  children: [
                    _previewKicker(c),
                    const SizedBox(height: 8),
                    _livePreview(),
                    const SizedBox(height: 16),
                    _toolTabs(c),
                    const SizedBox(height: 14),
                    _tabBody(c),
                    const SizedBox(height: 22),
                    CardPrimaryButton(
                      label: _busy ? 'Сохранение…' : 'Сохранить карточку',
                      enabled: !_busy,
                      onTap: _save,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _blob({
    double? top,
    double? left,
    double? right,
    required Color color,
    required double opacity,
  }) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      child: IgnorePointer(
        child: Container(
          width: 220,
          height: 220,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: opacity),
                color.withValues(alpha: 0),
              ],
              stops: const [0.0, 0.7],
            ),
          ),
        ),
      ),
    );
  }

  Widget _previewKicker(SeeUThemeColors c) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: SeeUColors.accent,
            boxShadow: [
              BoxShadow(color: SeeUColors.accent, blurRadius: 8),
            ],
          ),
        ),
        const SizedBox(width: 6),
        const Text(
          'КАК ТЕБЯ ВИДЯТ РЯДОМ · ЖИВОЕ ПРЕВЬЮ',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
            color: SeeUColors.accent,
          ),
        ),
      ],
    );
  }

  /// Живое превью — тот же компонент, что видят люди рядом.
  Widget _livePreview() {
    final nick = _nickCtrl.text.trim();
    final text = _textCtrl.text.trim();
    return AnimatedBuilder(
      animation: _float,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, -6 * Curves.easeInOut.transform(_float.value)),
        child: child,
      ),
      child: CardPortrait(
        template: _template,
        photoUrl: _existingPhotoUrl,
        photoBytes: _pickedBytes,
        nickname: nick.isEmpty ? 'Твой никнейм' : nick,
        text: text.isEmpty ? 'Пара слов о настроении' : text,
        radius: 24,
        photoSize: 86,
        trailing: const SparkHaloButton(), // декоративный огонёк, как в дизайне
      ),
    );
  }

  // ── Панель инструментов ───────────────────────────────────────────────────

  static const _tabs = [
    ('Основное', PhosphorIconsFill.textbox),
    ('Фон', PhosphorIconsRegular.paintBucket),
    ('Стиль', PhosphorIconsRegular.textAa),
    ('Элементы', PhosphorIconsRegular.shapes),
    ('Кисть', PhosphorIconsRegular.paintBrush),
  ];

  Widget _toolTabs(SeeUThemeColors c) {
    return Row(
      children: [
        for (var i = 0; i < _tabs.length; i++) ...[
          if (i > 0) const SizedBox(width: 7),
          Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _tab = i);
              },
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: _tab == i ? SeeUColors.accent : c.surface,
                  borderRadius: BorderRadius.circular(15),
                  border: _tab == i
                      ? null
                      : Border.all(color: c.line, width: 0.8),
                  boxShadow: _tab == i
                      ? [
                          BoxShadow(
                            color: SeeUColors.accent.withValues(alpha: 0.35),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  children: [
                    Icon(
                      _tabs[i].$2,
                      size: 20,
                      color: _tab == i ? Colors.white : c.ink2,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _tabs[i].$1,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight:
                            _tab == i ? FontWeight.w700 : FontWeight.w600,
                        color: _tab == i ? Colors.white : c.ink3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _tabBody(SeeUThemeColors c) {
    switch (_tab) {
      case 0:
        return _basicTab(c);
      case 1:
        return _backgroundTab(c);
      default:
        return _soonTab(c);
    }
  }

  // ── Таб «Основное» ────────────────────────────────────────────────────────

  Widget _basicTab(SeeUThemeColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(c, 'ОСНОВНОЕ'),
        const SizedBox(height: 18),
        // Фото
        GestureDetector(
          onTap: _pickPhoto,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: _hasPhoto ? c.line : SeeUColors.accent,
                width: 0.8,
              ),
            ),
            child: Row(
              children: [
                ClipOval(
                  child: Container(
                    width: 56,
                    height: 56,
                    color: c.surface2,
                    child: _pickedBytes != null
                        ? Image.memory(_pickedBytes!, fit: BoxFit.cover)
                        : _existingPhotoUrl.isNotEmpty
                            ? Image.network(_existingPhotoUrl,
                                fit: BoxFit.cover)
                            : Icon(PhosphorIcons.camera(),
                                color: c.ink3, size: 22),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _hasPhoto ? 'Фото карточки' : 'Добавь фото *',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: c.ink),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Нажми, чтобы заменить · настоящее твоё',
                        style: TextStyle(fontSize: 12.5, color: c.ink3),
                      ),
                    ],
                  ),
                ),
                Icon(PhosphorIcons.caretRight(), size: 18, color: c.ink3),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        // Никнейм
        Row(
          children: [
            Text('Никнейм',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(width: 8),
            Expanded(
              child: Text('не как в Профиле',
                  style: TextStyle(fontSize: 12, color: c.ink3)),
            ),
            GestureDetector(
              onTap: _randomNick,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: c.accentSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIcons.shuffle(),
                        size: 13, color: SeeUColors.accent),
                    const SizedBox(width: 5),
                    const Text(
                      'случайный',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: SeeUColors.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _field(
          c,
          controller: _nickCtrl,
          hint: 'Например: Северный кот',
          maxLength: _nickMax,
          showCounter: true,
        ),
        const SizedBox(height: 16),
        // Текст
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('Текст',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(width: 8),
            Text('Статус, настроение, цитата',
                style: TextStyle(fontSize: 12, color: c.ink3)),
          ],
        ),
        const SizedBox(height: 8),
        _field(
          c,
          controller: _textCtrl,
          hint: 'Что угодно о твоём настроении…',
          maxLength: _textMax,
          maxLines: 3,
          minHeight: 58,
        ),
      ],
    );
  }

  Widget _field(
    SeeUThemeColors c, {
    required TextEditingController controller,
    required String hint,
    required int maxLength,
    int maxLines = 1,
    bool showCounter = false,
    double? minHeight,
  }) {
    return Container(
      constraints: BoxConstraints(minHeight: minHeight ?? 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line, width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              maxLength: maxLength,
              maxLines: maxLines,
              onChanged: (_) => setState(() {}), // живое превью
              style: TextStyle(fontSize: 15, color: c.ink, height: 1.4),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(fontSize: 15, color: c.ink4),
                border: InputBorder.none,
                counterText: '',
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          if (showCounter)
            Text(
              '${controller.text.characters.length}/$maxLength',
              style: TextStyle(fontSize: 12, color: c.ink4),
            ),
        ],
      ),
    );
  }

  // ── Таб «Фон» — 5 шаблонов ────────────────────────────────────────────────

  Widget _backgroundTab(SeeUThemeColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(c, 'ФОН КАРТОЧКИ'),
        const SizedBox(height: 14),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: cardTemplates.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final t = cardTemplates[i];
              final selected = t.id == _template.id;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _template = t);
                },
                behavior: HitTestBehavior.opaque,
                child: Column(
                  children: [
                    Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        color: t.bg.length == 1 ? t.bg.first : null,
                        gradient: t.bg.length > 1
                            ? LinearGradient(
                                colors: t.bg,
                                begin: t.bgBegin,
                                end: t.bgEnd,
                              )
                            : null,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: selected ? SeeUColors.accent : c.line,
                          width: selected ? 2.5 : 0.8,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Container(
                        width: 22,
                        height: 3,
                        decoration: BoxDecoration(
                          color: t.accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      t.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? SeeUColors.accent : c.ink3,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Табы уровней 2/3 ──────────────────────────────────────────────────────

  Widget _soonTab(SeeUThemeColors c) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.line, width: 0.8),
      ),
      child: Column(
        children: [
          Icon(PhosphorIcons.sparkle(), size: 28, color: c.ink4),
          const SizedBox(height: 10),
          Text(
            'Скоро',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, color: c.ink),
          ),
          const SizedBox(height: 4),
          Text(
            'Конструктор элементов и свободная кисть — следующий уровень '
            'кастомизации.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, height: 1.45, color: c.ink3),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(SeeUThemeColors c, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: c.ink4,
      ),
    );
  }
}
