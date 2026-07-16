import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/audio/local_waveform.dart';
import '../../core/design/design.dart';
import '../../core/models/audio_category.dart';
import '../../core/models/audio_track.dart';
import '../../core/providers/audio_provider.dart';
import 'audio_design.dart';

/// Загрузка трека — не «форма», а отдельная задача.
///
/// Обязательны только **четыре** поля: файл, название, категория и видимость.
/// Остальное можно пропустить и дозаполнить потом. Категория из 9×16 берётся
/// **за два тапа** в шторке, а не длинным списком. «По ссылке» объяснено
/// человеческим языком, а не термином.
class MusicUploadScreen extends ConsumerStatefulWidget {
  /// Отклонённый трек, который отправляют повторно: поля уже заполнены —
  /// менять надо одно, а не начинать с нуля.
  final AudioTrack? editing;

  const MusicUploadScreen({super.key, this.editing});

  @override
  ConsumerState<MusicUploadScreen> createState() => _MusicUploadScreenState();
}

class _MusicUploadScreenState extends ConsumerState<MusicUploadScreen> {
  late final _titleCtrl =
      TextEditingController(text: widget.editing?.title ?? '');
  late final _artistCtrl =
      TextEditingController(text: widget.editing?.artist ?? '');
  late final _albumCtrl =
      TextEditingController(text: widget.editing?.album ?? '');
  late final _descCtrl =
      TextEditingController(text: widget.editing?.description ?? '');

  PlatformFile? _file;

  /// Волна и длительность файла, посчитанные на устройстве. Пока считаются —
  /// показываем, что идёт разбор, а не пустоту.
  LocalAudioInfo? _info;
  bool _analyzing = false;

  late String _category = widget.editing?.category ?? '';
  late String _subcategory = widget.editing?.subcategory ?? '';
  late String _mood = widget.editing?.mood ?? '';
  late String _visibility = widget.editing?.visibility ?? 'public';
  bool _more = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _artistCtrl.dispose();
    _albumCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _file?.path != null &&
      _titleCtrl.text.trim().isNotEmpty &&
      _category.isNotEmpty;

  Future<void> _pickFile() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      withData: false,
    );
    if (res == null || res.files.isEmpty) return;
    if (!mounted) return;
    final f = res.files.first;
    // Ловим слишком большой файл ДО загрузки: сервер режет на 100 МБ, и без
    // этой проверки человек ждёт полную заливку впустую, только чтобы получить
    // отказ. Размер уже известен локально.
    const maxBytes = 100 * 1024 * 1024;
    if (f.size > maxBytes) {
      showSeeUSnackBar(
        context,
        'Файл слишком большой — максимум 100 МБ',
        tone: SeeUTone.danger,
      );
      return;
    }
    setState(() {
      _file = f;
      _info = null;
      _analyzing = true;
      // Имя файла — разумная догадка о названии; человек её перепишет.
      if (_titleCtrl.text.trim().isEmpty) {
        _titleCtrl.text = f.name.replaceAll(RegExp(r'\.[^.]+$'), '');
      }
    });

    // Волну считаем прямо здесь, на устройстве: тогда карточка файла честная,
    // и трек не останется без волны, даже если media_worker на сервере не
    // поднят.
    final path = f.path;
    if (path == null) {
      setState(() => _analyzing = false);
      return;
    }
    final info = await LocalWaveform.analyze(path);
    if (!mounted) return;
    setState(() {
      _info = info;
      _analyzing = false;
    });
  }

  Future<void> _pickCategory() async {
    final result = await showCategorySheet(
      context,
      category: _category,
      subcategory: _subcategory,
    );
    if (result == null) return;
    setState(() {
      _category = result.$1;
      _subcategory = result.$2;
    });
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    HapticFeedback.mediumImpact();

    final track = await ref.read(audioUploadProvider.notifier).upload(
          file: File(_file!.path!),
          waveform: _info?.peaks,
          durationSeconds: _info?.durationSeconds ?? 0,
          title: _titleCtrl.text.trim(),
          artist: _artistCtrl.text.trim(),
          album: _albumCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          category: _category,
          subcategory: _subcategory,
          mood: _mood,
          visibility: _visibility,
        );

    if (!mounted) return;
    if (track == null) {
      // Показываем конкретную причину (формат/размер/сеть/таймаут), которую
      // провайдер уже вычислил — раньше она была мёртвым кодом, а юзер видел
      // только общее «попробуй ещё раз».
      final reason = ref.read(audioUploadProvider).error;
      showSeeUSnackBar(
        context,
        reason ?? 'Не удалось загрузить — попробуй ещё раз',
        tone: SeeUTone.danger,
      );
      return;
    }

    ref.invalidate(myTracksProvider);
    // Ведём туда, где трек теперь живёт, а не оставляем в пустой форме.
    context.go('/music/mine?tab=uploads');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final upload = ref.watch(audioUploadProvider);

    if (upload.isUploading) return _uploading(c, upload.progress);

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: Row(
                children: [
                  AudioSquareButton(
                    icon: PhosphorIcons.x(),
                    onTap: () => context.pop(),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    widget.editing == null ? 'Новый трек' : 'Отправить снова',
                    style: SeeUTypography.displayS
                        .copyWith(fontSize: 22, color: c.ink),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                children: [
                  _fileCard(c),
                  const SizedBox(height: 16),
                  _coverAndTitle(c),
                  const SizedBox(height: 13),
                  _field(c, 'АВТОР', _artistCtrl, 'Твоё имя или ник'),
                  const SizedBox(height: 13),
                  _categoryField(c),
                  const SizedBox(height: 13),
                  _visibilityField(c),
                  const SizedBox(height: 16),
                  _moreSection(c),
                ],
              ),
            ),
            _submitBar(c),
          ],
        ),
      ),
    );
  }

  // ── Файл ──────────────────────────────────────────────────────────────────

  Widget _fileCard(SeeUThemeColors c) {
    if (_file == null) {
      return Tappable.scaled(
        onTap: _pickFile,
        child: Container(
          height: 120,
          decoration: BoxDecoration(
            color: SeeUColors.accent.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: SeeUColors.accent.withValues(alpha: 0.45),
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(PhosphorIconsRegular.fileArrowUp,
                  size: 28, color: SeeUColors.accent),
              const SizedBox(height: 8),
              Text(
                'Выбрать файл',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AudioColors.kicker(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'MP3 · M4A · WAV · OGG',
                style: TextStyle(fontSize: 11, color: c.ink3),
              ),
            ],
          ),
        ),
      );
    }

    final f = _file!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.ink,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(PhosphorIconsFill.fileAudio,
                  size: 16, color: SeeUColors.accentSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  f.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: c.bg,
                  ),
                ),
              ),
              Tappable(
                onTap: _pickFile,
                child: Icon(PhosphorIcons.arrowsClockwise(),
                    size: 17, color: c.bg.withValues(alpha: 0.7)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Настоящая волна файла — посчитана здесь же, из самого файла.
          // Если посчитать не вышло, честно не рисуем ничего вместо неё.
          if (_analyzing)
            SizedBox(
              height: 40,
              child: Row(
                children: [
                  SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation(c.bg.withValues(alpha: 0.5)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Разбираем файл…',
                    style: TextStyle(
                      fontSize: 12,
                      color: c.bg.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            )
          else if (_info?.peaks != null)
            TrackWaveform(
              peaks: _info!.peaks,
              progress: 1,
              color: c.bg.withValues(alpha: 0.85),
              height: 40,
            ),
          const SizedBox(height: 8),
          Text(
            [
              _fileSize(f.size),
              if ((_info?.durationSeconds ?? 0) > 0)
                formatDuration(_info!.durationSeconds),
            ].where((e) => e.isNotEmpty).join(' · '),
            style: TextStyle(
              fontSize: 11.5,
              color: c.bg.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  static String _fileSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // ── Обложка + название ────────────────────────────────────────────────────

  Widget _coverAndTitle(SeeUThemeColors c) {
    final cat = findCategory(_category);
    final color = cat?.color ?? SeeUColors.accent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color, Color.lerp(color, Colors.black, 0.35)!],
                ),
              ),
              child: Icon(
                cat?.iconData ?? PhosphorIconsFill.musicNotes,
                size: 28,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label(c, 'НАЗВАНИЕ', required: true),
                  const SizedBox(height: 5),
                  _input(c, _titleCtrl, 'Как называется трек', accent: true),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Обложку соберём из цвета категории — искать картинку не обязательно.',
          style: TextStyle(fontSize: 11, color: c.ink3),
        ),
      ],
    );
  }

  // ── Категория ─────────────────────────────────────────────────────────────

  Widget _categoryField(SeeUThemeColors c) {
    final cat = findCategory(_category);
    final sub = cat?.subcategories
        .where((s) => s.id == _subcategory)
        .map((s) => s.titleRu)
        .firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(c, 'КАТЕГОРИЯ', required: true),
        const SizedBox(height: 5),
        Tappable.scaled(
          onTap: _pickCategory,
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: cat == null ? c.line : cat.color,
              ),
            ),
            child: Row(
              children: [
                if (cat != null) ...[
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: cat.color,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(cat.iconData, size: 15, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    cat == null
                        ? 'Куда отнести трек?'
                        : [cat.title, if (sub != null) sub].join(' · '),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          cat == null ? FontWeight.w400 : FontWeight.w600,
                      color: cat == null ? c.ink3 : c.ink,
                    ),
                  ),
                ),
                Icon(PhosphorIcons.caretRight(), size: 16, color: c.ink3),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Видимость ─────────────────────────────────────────────────────────────

  Widget _visibilityField(SeeUThemeColors c) {
    final items = <(String, IconData, String, String)>[
      (
        'public',
        PhosphorIconsFill.globeHemisphereWest,
        'Публичный',
        'В поиске, категориях, можно взять в видео',
      ),
      (
        'unlisted',
        PhosphorIconsRegular.link,
        'По ссылке',
        'Не в поиске. Откроют только те, кому дашь ссылку',
      ),
      (
        'private',
        PhosphorIconsRegular.lockSimple,
        'Только я',
        'Личный. Никто, кроме тебя, не увидит',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(c, 'КТО УВИДИТ', required: true),
        const SizedBox(height: 6),
        for (final (id, icon, title, hint) in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Tappable.scaled(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _visibility = id);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                decoration: BoxDecoration(
                  color: _visibility == id
                      ? SeeUColors.accent.withValues(alpha: 0.08)
                      : c.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _visibility == id ? SeeUColors.accent : c.line,
                    width: _visibility == id ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(icon,
                        size: 20,
                        color: _visibility == id ? SeeUColors.accent : c.ink3),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: c.ink,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            hint,
                            style: TextStyle(fontSize: 11, color: c.ink3),
                          ),
                        ],
                      ),
                    ),
                    if (_visibility == id)
                      const Icon(PhosphorIconsFill.checkCircle,
                          size: 20, color: SeeUColors.accent),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ── Необязательное ────────────────────────────────────────────────────────

  Widget _moreSection(SeeUThemeColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Tappable(
          onTap: () => setState(() => _more = !_more),
          child: Row(
            children: [
              Text(
                'Ещё · необязательно',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.ink2,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                _more ? PhosphorIcons.caretUp() : PhosphorIcons.caretDown(),
                size: 14,
                color: c.ink3,
              ),
            ],
          ),
        ),
        if (_more) ...[
          const SizedBox(height: 12),
          _field(c, 'АЛЬБОМ', _albumCtrl, 'Если трек из альбома'),
          const SizedBox(height: 13),
          _field(c, 'ОПИСАНИЕ', _descCtrl, 'О чём этот трек', lines: 3),
          const SizedBox(height: 13),
          _label(c, 'НАСТРОЕНИЕ'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in const [
                'Радостное',
                'Грустное',
                'Энергичное',
                'Спокойное',
                'Мрачное',
                'Романтичное',
                'Чилл',
              ])
                Tappable.scaled(
                  onTap: () => setState(() => _mood = _mood == m ? '' : m),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                    decoration: BoxDecoration(
                      color: _mood == m ? c.ink : c.surface,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: _mood == m ? c.ink : c.line),
                    ),
                    child: Text(
                      m,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: _mood == m ? c.bg : c.ink2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  // ── Кнопка ────────────────────────────────────────────────────────────────

  Widget _submitBar(SeeUThemeColors c) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Tappable.scaled(
        onTap: _canSubmit ? _submit : null,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: _canSubmit ? SeeUColors.accent : c.surface2,
            borderRadius: BorderRadius.circular(14),
            boxShadow: _canSubmit
                ? [
                    BoxShadow(
                      color: SeeUColors.accent.withValues(alpha: 0.55),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                      spreadRadius: -10,
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(PhosphorIconsFill.uploadSimple,
                  size: 16, color: _canSubmit ? Colors.white : c.ink4),
              const SizedBox(width: 8),
              Text(
                'Отправить на модерацию',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _canSubmit ? Colors.white : c.ink4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Загрузка идёт ─────────────────────────────────────────────────────────

  Widget _uploading(SeeUThemeColors c, double progress) {
    final pct = (progress * 100).round();

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // §J3: conic-кольцо прогресса (не Material-спиннер).
              SizedBox(
                width: 150,
                height: 150,
                child: CustomPaint(
                  painter: _ConicRingPainter(
                    progress: progress,
                    track: c.surface2,
                    fill: SeeUColors.accent,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$pct',
                          style: SeeUTypography.displayS
                              .copyWith(fontSize: 40, color: c.ink),
                        ),
                        Text(
                          'процента',
                          style: TextStyle(fontSize: 12, color: c.ink3),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Загружаем трек…',
                style:
                    SeeUTypography.displayS.copyWith(fontSize: 24, color: c.ink),
              ),
              const SizedBox(height: 8),
              Text(
                '${[
                  _titleCtrl.text.trim(),
                  _fileSize(_file?.size ?? 0),
                ].where((e) => e.isNotEmpty).join(' · ')}. Можно свернуть — загрузка продолжится в фоне.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, height: 1.5, color: c.ink3),
              ),
              const SizedBox(height: 22),
              // Два действия рядом: «Свернуть» оставляет заливку в провайдере
              // (продолжается в фоне), «Отменить» реально её рвёт (CancelToken).
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // «Свернуть»: аплоад живёт в провайдере — продолжается в
                  // фоне, экран можно закрыть.
                  Tappable.scaled(
                    onTap: () => context.go('/music/mine?tab=uploads'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 11),
                      decoration: BoxDecoration(
                        color: c.surface2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: c.line),
                      ),
                      child: Text('Свернуть',
                          style: SeeUTypography.caption.copyWith(
                              fontWeight: FontWeight.w600, color: c.ink2)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // «Отменить»: прерывает незавершённую загрузку и уводит с
                  // экрана — в отличие от «Свернуть», трек НЕ догрузится.
                  Tappable.scaled(
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      ref.read(audioUploadProvider.notifier).cancel();
                      context.pop();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 11),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFF4C7C4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(PhosphorIconsRegular.x,
                              size: 14, color: Color(0xFFE53935)),
                          const SizedBox(width: 6),
                          Text('Отменить',
                              style: SeeUTypography.caption.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFFE53935))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              // Что будет дальше — чтобы не гадать, куда делся трек.
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.line),
                ),
                child: Row(
                  children: [
                    const Icon(PhosphorIconsFill.hourglassMedium,
                        size: 22, color: SeeUColors.warning),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Дальше трек уйдёт на модерацию (≈ до суток). '
                        'Найдёшь его в «Моё → Загрузки».',
                        style: TextStyle(
                            fontSize: 12.5, height: 1.5, color: c.ink2),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Поля ──────────────────────────────────────────────────────────────────

  Widget _label(SeeUThemeColors c, String text, {bool required = false}) {
    return Row(
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: c.ink3,
          ),
        ),
        if (required)
          const Text(
            ' *',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: SeeUColors.accent,
            ),
          ),
      ],
    );
  }

  Widget _input(
    SeeUThemeColors c,
    TextEditingController ctrl,
    String hint, {
    int lines = 1,
    bool accent = false,
  }) {
    final filled = accent && ctrl.text.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: filled ? SeeUColors.accent : c.line,
          width: filled ? 1.5 : 1,
        ),
      ),
      child: TextField(
        controller: ctrl,
        maxLines: lines,
        onChanged: (_) => setState(() {}),
        style: TextStyle(fontSize: 14, color: c.ink),
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          hintText: hint,
          hintStyle: TextStyle(fontSize: 14, color: c.ink3),
        ),
      ),
    );
  }

  Widget _field(
    SeeUThemeColors c,
    String label,
    TextEditingController ctrl,
    String hint, {
    int lines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(c, label),
        const SizedBox(height: 5),
        _input(c, ctrl, hint, lines: lines),
      ],
    );
  }
}

// ─── Шторка категории: два тапа вместо десяти ───────────────────────────────

/// Категория → подкатегория в одной шторке. Второй шаг рисуется только для
/// выбранной ветки: 9×16 не выкладываются простынёй.
Future<(String, String)?> showCategorySheet(
  BuildContext context, {
  String category = '',
  String subcategory = '',
}) {
  return showSeeUBottomSheet<(String, String)>(
    context: context,
    isScrollControlled: true,
    builder: (_) =>
        _CategorySheet(category: category, subcategory: subcategory),
  );
}

class _CategorySheet extends StatefulWidget {
  final String category;
  final String subcategory;

  const _CategorySheet({required this.category, required this.subcategory});

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  late String _cat = widget.category;
  late String _sub = widget.subcategory;

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final cat = findCategory(_cat);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Куда отнести трек?',
                style:
                    SeeUTypography.displayS.copyWith(fontSize: 22, color: c.ink),
              ),
              const SizedBox(height: 2),
              Text(
                'Тап по категории → выбери подкатегорию',
                style: TextStyle(fontSize: 12.5, color: c.ink3),
              ),
              const SizedBox(height: 18),
              _step(c, '1 · КАТЕГОРИЯ'),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1.9,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final k in kAudioCategories)
                    Tappable.scaled(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _cat = k.id;
                          _sub = '';
                        });
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: _cat == k.id ? k.color : c.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _cat == k.id ? k.color : c.line,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              k.iconData,
                              size: 17,
                              color: _cat == k.id ? Colors.white : k.color,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              k.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _cat == k.id ? Colors.white : c.ink2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),

              // Второй шаг появляется только у выбранной ветки — и только если
              // подкатегории у неё есть.
              if (cat != null && cat.subcategories.isNotEmpty) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    _step(c, '2 · ПОДКАТЕГОРИЯ'),
                    const SizedBox(width: 6),
                    Text(
                      '· ${cat.title}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: cat.color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in cat.subcategories)
                      Tappable.scaled(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _sub = _sub == s.id ? '' : s.id);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 13, vertical: 8),
                          decoration: BoxDecoration(
                            color: _sub == s.id ? cat.color : c.surface,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: _sub == s.id ? cat.color : c.line,
                            ),
                          ),
                          child: Text(
                            s.titleRu,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: _sub == s.id
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: _sub == s.id ? Colors.white : c.ink2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],

              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: Tappable.scaled(
                  onTap: _cat.isEmpty
                      ? null
                      : () => Navigator.of(context).pop((_cat, _sub)),
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: _cat.isEmpty ? c.surface2 : c.ink,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _doneLabel(cat),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _cat.isEmpty ? c.ink4 : c.bg,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _doneLabel(AudioCategoryModel? cat) {
    if (cat == null) return 'Выбери категорию';
    final sub = cat.subcategories
        .where((s) => s.id == _sub)
        .map((s) => s.titleRu)
        .firstOrNull;
    return 'Готово · ${[cat.title, if (sub != null) sub].join(' · ')}';
  }

  Widget _step(SeeUThemeColors c, String text) => Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          color: c.ink3,
        ),
      );
}

/// §J3: conic-градиентное кольцо прогресса загрузки (коралл 0..progress,
/// остаток — surface2). Толщина 15, скруглённая заглушка.
class _ConicRingPainter extends CustomPainter {
  final double progress;
  final Color track;
  final Color fill;
  _ConicRingPainter({
    required this.progress,
    required this.track,
    required this.fill,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 15.0;
    final rect = Offset.zero & size;
    final inner = rect.deflate(stroke / 2);
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(inner, 0, 2 * math.pi, false, trackPaint);

    final sweep = (2 * math.pi) * progress.clamp(0.0, 1.0);
    if (sweep <= 0) return;
    final fillPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = fill;
    // Старт сверху (−90°).
    canvas.drawArc(inner, -math.pi / 2, sweep, false, fillPaint);
  }

  @override
  bool shouldRepaint(_ConicRingPainter old) =>
      old.progress != progress || old.fill != fill || old.track != track;
}
