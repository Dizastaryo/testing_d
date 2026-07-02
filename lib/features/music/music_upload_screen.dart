import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import '../../core/providers/audio_provider.dart';

class MusicUploadScreen extends ConsumerStatefulWidget {
  const MusicUploadScreen({super.key});

  @override
  ConsumerState<MusicUploadScreen> createState() => _MusicUploadScreenState();
}

class _MusicUploadScreenState extends ConsumerState<MusicUploadScreen> {
  File? _file;
  String _fileName = '';
  int _fileSize = 0;
  String _fileExt = '';

  bool _extraExpanded = false;

  final _titleCtrl = TextEditingController();
  final _artistCtrl = TextEditingController();
  final _albumCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _genreCtrl = TextEditingController();

  String _category = 'music';
  String _subcategory = '';
  String _mood = '';
  String _visibility = 'public';

  static const _categories = [
    ('music', 'Музыка'),
    ('memes', 'Мемы'),
    ('audiobooks', 'Аудиокниги'),
    ('podcasts', 'Подкасты'),
    ('education', 'Образование'),
    ('meditation', 'Медитация'),
    ('news', 'Новости'),
    ('instrumental', 'Инструментал'),
    ('other', 'Другое'),
  ];

  static const _visibilities = [
    ('public', 'Публичный'),
    ('unlisted', 'По ссылке'),
    ('private', 'Приватный'),
  ];

  static const _subcategories = {
    'music': ['Поп', 'Рэп / Hip-Hop', 'R&B', 'Рок', 'Электронная', 'House', 'Techno', 'Jazz', 'Classical', 'K-pop', 'Indie', 'Soundtrack', 'Другое'],
    'memes': ['Funny', 'Reaction', 'Voice meme', 'Sound effect', 'Viral'],
    'audiobooks': ['Fiction', 'Business', 'Self-development', 'Kids', 'Fantasy', 'Detective', 'History', 'Science'],
    'podcasts': ['Interview', 'Talk show', 'Technology', 'Business', 'Sport', 'Comedy'],
    'education': ['Language', 'Programming', 'School', 'University', 'Science', 'Finance'],
    'meditation': ['Sleep', 'Focus', 'Breathing', 'Ambient', 'Nature'],
    'instrumental': ['Beat', 'Lo-fi', 'Cinematic', 'Game music', 'Background'],
  };

  static const _moods = ['', 'Happy', 'Sad', 'Energetic', 'Calm', 'Dark', 'Romantic', 'Aggressive', 'Chill'];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _artistCtrl.dispose();
    _albumCtrl.dispose();
    _descCtrl.dispose();
    _genreCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit => _file != null && _titleCtrl.text.trim().isNotEmpty;

  List<String> get _currentSubcategories => _subcategories[_category] ?? [];

  Future<void> _pickFile() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.audio, withData: false);
    if (res == null || res.files.isEmpty) return;
    final pf = res.files.first;
    if (pf.path == null) return;
    setState(() {
      _file = File(pf.path!);
      _fileName = pf.name;
      _fileSize = pf.size;
      _fileExt = pf.extension?.toUpperCase() ?? '';
      if (_titleCtrl.text.isEmpty) {
        _titleCtrl.text = pf.name.replaceAll(RegExp(r'\.[^.]+$'), '');
      }
    });
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      _showSnack('Введите название трека');
      return;
    }
    if (_file == null) {
      _showSnack('Выберите аудиофайл');
      return;
    }

    final track = await ref.read(audioUploadProvider.notifier).upload(
          file: _file!,
          title: title,
          artist: _artistCtrl.text.trim(),
          album: _albumCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          genre: _genreCtrl.text.trim(),
          category: _category,
          subcategory: _subcategory,
          mood: _mood,
          visibility: _visibility,
        );

    if (!mounted) return;
    if (track != null) {
      ref.invalidate(audioFeedProvider);
      ref.invalidate(myTracksProvider);
      _showSnack('«${track.title}» загружен!');
      context.pop();
    }
  }

  void _showSnack(String msg) {
    showSeeUSnackBar(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    final uploadState = ref.watch(audioUploadProvider);
    final isUploading = uploadState.isUploading;
    final c = context.seeuColors;

    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        children: [
          SeeUGlassBar(
            titleText: 'Загрузить трек',
            kicker: 'МУЗЫКА',
            leading: Tappable.scaled(
              onTap: isUploading ? null : () => context.pop(),
              scaleFactor: 0.9,
              child: SizedBox(
                width: 40,
                height: 40,
                child:
                    Icon(PhosphorIcons.caretLeft(), color: c.ink, size: 22),
              ),
            ),
            actions: [
              if (!isUploading && _canSubmit)
                TextButton(
                  onPressed: _submit,
                  child: Text(
                    'Загрузить',
                    style: SeeUTypography.subtitle.copyWith(
                        color: SeeUColors.accent,
                        fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          Expanded(
            child: isUploading
                ? _UploadProgress(progress: uploadState.progress)
                : _buildForm(uploadState.error),
          ),
        ],
      ),
    );
  }

  Widget _buildForm(String? error) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── File picker ──
          _FileTile(
            fileName: _fileName,
            fileSize: _fileSize,
            fileExt: _fileExt,
            hasFile: _file != null,
            onTap: _pickFile,
          ),
          const SizedBox(height: 16),

          // ── Title ──
          TextField(
            controller: _titleCtrl,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Название *',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            maxLength: 200,
            buildCounter: _compactCounter,
          ),
          const SizedBox(height: 12),

          // ── Category ──
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(
              labelText: 'Категория',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: _categories
                .map((c) => DropdownMenuItem(value: c.$1, child: Text(c.$2)))
                .toList(),
            onChanged: (v) => setState(() {
              _category = v ?? 'music';
              _subcategory = '';
            }),
          ),
          const SizedBox(height: 12),

          // ── Visibility ──
          DropdownButtonFormField<String>(
            initialValue: _visibility,
            decoration: const InputDecoration(
              labelText: 'Видимость',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: _visibilities
                .map((v) => DropdownMenuItem(value: v.$1, child: Text(v.$2)))
                .toList(),
            onChanged: (v) => setState(() => _visibility = v ?? 'public'),
          ),
          const SizedBox(height: 12),

          // ── Expandable extra ──
          _ExtraSection(
            expanded: _extraExpanded,
            onToggle: () => setState(() => _extraExpanded = !_extraExpanded),
            child: _extraExpanded
                ? _buildExtraFields(theme)
                : const SizedBox.shrink(),
          ),

          // ── Error ──
          if (error != null) ...[
            const SizedBox(height: 12),
            _ErrorBanner(message: error),
          ],

          const SizedBox(height: 20),

          // ── Submit button ──
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _canSubmit ? SeeUColors.accent : theme.disabledColor,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _canSubmit ? _submit : null,
            icon: Icon(PhosphorIcons.uploadSimple(), size: 18),
            label: const Text('Загрузить трек'),
          ),
        ],
      ),
    );
  }

  Widget _buildExtraFields(ThemeData theme) {
    final subs = _currentSubcategories;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        TextField(
          controller: _artistCtrl,
          decoration: const InputDecoration(
            labelText: 'Артист',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          maxLength: 200,
          buildCounter: _compactCounter,
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _albumCtrl,
          decoration: const InputDecoration(
            labelText: 'Альбом',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          maxLength: 200,
          buildCounter: _compactCounter,
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _genreCtrl,
          decoration: const InputDecoration(
            labelText: 'Жанр',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          maxLength: 100,
          buildCounter: _compactCounter,
        ),
        if (subs.isNotEmpty) ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _subcategory.isEmpty ? null : _subcategory,
            decoration: const InputDecoration(
              labelText: 'Подкатегория',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            hint: const Text('Выбрать'),
            items: subs
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (v) => setState(() => _subcategory = v ?? ''),
          ),
        ],
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: _mood.isEmpty ? null : _mood,
          decoration: const InputDecoration(
            labelText: 'Настроение',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          hint: const Text('Выбрать'),
          items: _moods
              .where((m) => m.isNotEmpty)
              .map((m) => DropdownMenuItem(value: m, child: Text(m)))
              .toList(),
          onChanged: (v) => setState(() => _mood = v ?? ''),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _descCtrl,
          decoration: const InputDecoration(
            labelText: 'Описание',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          maxLines: 3,
          maxLength: 2000,
          buildCounter: _compactCounter,
        ),
      ],
    );
  }

  // Shows counter only when field has content or max is near.
  static Widget? _compactCounter(
    BuildContext context, {
    required int currentLength,
    required bool isFocused,
    required int? maxLength,
  }) {
    if (maxLength == null || currentLength == 0) return null;
    if (!isFocused && currentLength < (maxLength * 0.8).round()) return null;
    return Text(
      '$currentLength/$maxLength',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.outline,
            fontSize: 11,
          ),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _FileTile extends StatelessWidget {
  final String fileName;
  final int fileSize;
  final String fileExt;
  final bool hasFile;
  final VoidCallback onTap;

  const _FileTile({
    required this.fileName,
    required this.fileSize,
    required this.fileExt,
    required this.hasFile,
    required this.onTap,
  });

  String get _sizeLabel {
    if (fileSize <= 0) return '';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(0)} KB';
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(
            color: hasFile ? SeeUColors.accent : theme.colorScheme.outlineVariant,
            width: hasFile ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: hasFile
              ? SeeUColors.accent.withValues(alpha: 0.04)
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: hasFile
                    ? SeeUColors.accent.withValues(alpha: 0.12)
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                hasFile ? PhosphorIcons.musicNotesSimple() : PhosphorIcons.uploadSimple(),
                color: hasFile ? SeeUColors.accent : theme.colorScheme.outline,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasFile ? 'Файл выбран' : 'Выбрать аудиофайл',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: hasFile ? SeeUColors.accent : theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasFile
                        ? [fileName, if (_sizeLabel.isNotEmpty) _sizeLabel, if (fileExt.isNotEmpty) fileExt]
                            .join(' · ')
                        : 'MP3, M4A, AAC, WAV, OGG · макс. 100 МБ',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.outline,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (hasFile)
              Icon(Icons.check_circle, color: SeeUColors.accent, size: 20)
            else
              Icon(PhosphorIcons.caretRight(), color: theme.colorScheme.outline, size: 18),
          ],
        ),
      ),
    );
  }
}

class _ExtraSection extends StatelessWidget {
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  const _ExtraSection({
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Row(
              children: [
                Icon(
                  expanded ? PhosphorIcons.caretUp() : PhosphorIcons.caretDown(),
                  size: 16,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(width: 8),
                Text(
                  'Дополнительная информация',
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.colorScheme.outline,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: child,
          crossFadeState: expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }
}

class _UploadProgress extends StatelessWidget {
  final double progress;
  const _UploadProgress({required this.progress});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final pct = (progress * 100).toStringAsFixed(0);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIcons.musicNotesSimple(), size: 56, color: SeeUColors.accent),
            const SizedBox(height: 24),
            Text('Загружаем трек…',
                style: SeeUTypography.subtitle
                    .copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('$pct%',
                style: SeeUTypography.caption.copyWith(color: c.ink3)),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: progress > 0 ? progress : null,
              backgroundColor: c.surface2,
              valueColor: const AlwaysStoppedAnimation<Color>(SeeUColors.accent),
            ),
            const SizedBox(height: 12),
            Text('Не закрывайте экран',
                style: SeeUTypography.micro.copyWith(color: c.ink4)),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SeeUColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(SeeURadii.small),
        border: Border.all(color: SeeUColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(PhosphorIcons.warningCircle(), color: SeeUColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: SeeUTypography.caption.copyWith(color: SeeUColors.error),
            ),
          ),
        ],
      ),
    );
  }
}
