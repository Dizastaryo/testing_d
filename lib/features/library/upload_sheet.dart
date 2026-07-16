import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/providers/library_provider.dart';
import 'file_preparation_screen.dart';
import 'library_design.dart';

const _allowedExtensions = [
  'pdf', 'epub', 'fb2', 'docx', 'pptx', 'txt', 'rtf', 'md', 'odt', 'odp'
];

/// Открыть шторку загрузки и обработать результат: конвертируемые форматы
/// уходят в подготовку («Готовим к чтению»), остальные сразу на полке.
/// Возвращает true, если файл загружен.
Future<bool> showUploadSheet(BuildContext context) async {
  final result = await showModalBottomSheet<Map<String, dynamic>?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const UploadSheet(),
  );
  if (result == null || result['uploaded'] != true) return false;
  if (!context.mounted) return true;

  final title = result['title'] as String? ?? 'Файл';
  if (result['needsPrep'] == true) {
    showSeeUSnackBar(
      context,
      '$title загружен — подготавливается к чтению',
      tone: SeeUTone.success,
      duration: const Duration(seconds: 6),
      action: SnackBarAction(
        label: 'Следить',
        onPressed: () {
          if (!context.mounted) return;
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const FilePreparationScreen()),
          );
        },
      ),
    );
  } else {
    showSeeUSnackBar(context, '$title загружен', tone: SeeUTone.success);
  }
  return true;
}

class UploadSheet extends ConsumerStatefulWidget {
  const UploadSheet({super.key});

  @override
  ConsumerState<UploadSheet> createState() => _UploadSheetState();
}

class _UploadSheetState extends ConsumerState<UploadSheet> {
  PlatformFile? _picked;
  PlatformFile? _cover;
  final _titleCtrl = TextEditingController();
  final _authorCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _categoryId = '';
  String _language = 'ru';
  bool _uploading = false;
  double _uploadProgress = 0.0;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _authorCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() => _cover = result.files.first);
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedExtensions,
      // On mobile/desktop we stream the file from disk (path) instead of
      // loading the whole thing into RAM. Web has no path, so it needs bytes.
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    // Проверка размера файла (макс 50 МБ, как на сервере)
    if (f.size > 50 * 1024 * 1024) {
      if (mounted) {
        showSeeUSnackBar(
            context,
            'Файл слишком большой (${(f.size / 1024 / 1024).toStringAsFixed(1)} МБ). Максимум — 50 МБ.',
            tone: SeeUTone.danger);
      }
      return;
    }
    setState(() {
      _picked = f;
      if (_titleCtrl.text.isEmpty) {
        final dot = f.name.lastIndexOf('.');
        _titleCtrl.text = dot == -1 ? f.name : f.name.substring(0, dot);
      }
    });
  }

  static const _convertibleExts = {'fb2', 'docx', 'rtf', 'odt', 'pptx', 'odp'};

  Future<void> _upload() async {
    final picked = _picked;
    if (picked == null) return;
    // Mobile/desktop: stream from path. Web: must have bytes.
    if (kIsWeb ? picked.bytes == null : picked.path == null) return;
    if (_titleCtrl.text.trim().isEmpty) {
      showSeeUSnackBar(context, 'Введи название', tone: SeeUTone.danger);
      return;
    }
    setState(() { _uploading = true; _uploadProgress = 0.0; });
    try {
      final dio = ref.read(libraryApiClientProvider);
      final MultipartFile fileMp = kIsWeb
          ? MultipartFile.fromBytes(picked.bytes!, filename: picked.name)
          : await MultipartFile.fromFile(picked.path!, filename: picked.name);
      final form = FormData.fromMap({
        'file': fileMp,
        'title': _titleCtrl.text.trim(),
        if (_authorCtrl.text.trim().isNotEmpty) 'author_name': _authorCtrl.text.trim(),
        if (_categoryId.isNotEmpty) 'category_id': _categoryId,
        if (_descCtrl.text.trim().isNotEmpty) 'description': _descCtrl.text.trim(),
        'language': _language,
        if (_cover?.bytes != null)
          'cover': MultipartFile.fromBytes(_cover!.bytes!, filename: _cover!.name),
      });
      await dio.post(
        ApiEndpoints.filesUpload,
        data: form,
        options: Options(
          sendTimeout: const Duration(minutes: 5),
          receiveTimeout: const Duration(minutes: 2),
        ),
        onSendProgress: (sent, total) {
          if (total > 0 && mounted) {
            setState(() => _uploadProgress = sent / total);
          }
        },
      );
      // Guard ref use after the await — sheet might have closed mid-upload.
      if (!mounted) return;
      ref.invalidate(trendingFilesProvider);
      // Не _picked!: пользователь мог очистить выбор, пока файл улетал.
      final ext = picked.name.split('.').last.toLowerCase();
      final needsPrep = _convertibleExts.contains(ext);
      Navigator.of(context).pop(<String, dynamic>{
        'uploaded': true,
        'needsPrep': needsPrep,
        'title': _titleCtrl.text.trim(),
      });
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = e.response?.data?['error'] ?? e.message ?? 'Ошибка загрузки';
      showSeeUSnackBar(context, msg.toString(), tone: SeeUTone.danger);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.seeuColors;
    final cats = ref.watch(fileCategoriesProvider).valueOrNull ?? [];

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Grabber
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: theme.dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Серифный editorial-заголовок шторки.
              Text(
                'Загрузить файл',
                style: SeeUTypography.displayXS.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 16),

              // Обложка (dashed 76×104) + область «Выбрать файл» (dashed коралл).
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CoverSlot(
                    cover: _cover,
                    onPick: _uploading ? null : _pickCover,
                    onRemove: () => setState(() => _cover = null),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _FileSlot(
                      picked: _picked,
                      sizeLabel:
                          _picked != null ? _formatSize(_picked!.size) : '',
                      onPick: _uploading ? null : _pickFile,
                      onClear: () => setState(() => _picked = null),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Название / Автор — поля в стиле Читальни (кикер + плашка 42/r12).
              _LibField(
                label: 'НАЗВАНИЕ *',
                hint: 'Как называется книга или документ',
                controller: _titleCtrl,
              ),
              const SizedBox(height: 12),
              _LibField(
                label: 'АВТОР',
                hint: 'Необязательно',
                controller: _authorCtrl,
              ),
              const SizedBox(height: 12),

              // Категория
              if (cats.isNotEmpty) ...[
                _fieldLabel(context, 'КАТЕГОРИЯ'),
                const SizedBox(height: 6),
                Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: _fieldDecoration(context),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _categoryId.isEmpty ? null : _categoryId,
                      isExpanded: true,
                      hint: Text('Без категории',
                          style: TextStyle(fontSize: 13, color: c.ink3)),
                      style: TextStyle(fontSize: 13, color: c.ink),
                      dropdownColor: theme.cardColor,
                      icon: Icon(PhosphorIconsRegular.caretDown,
                          size: 14, color: c.ink3),
                      items: cats
                          .map((cat) => DropdownMenuItem(
                              value: cat.id, child: Text(cat.name)))
                          .toList(),
                      onChanged: (v) => setState(() => _categoryId = v ?? ''),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Описание
              _LibField(
                label: 'ОПИСАНИЕ',
                hint: 'Пара слов о файле — необязательно',
                controller: _descCtrl,
                maxLines: 3,
              ),
              const SizedBox(height: 14),

              // Язык
              _fieldLabel(context, 'ЯЗЫК'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final lang in [
                    ('ru', 'Русский'),
                    ('en', 'English'),
                    ('kk', 'Қазақша'),
                    ('other', 'Другой'),
                  ])
                    GestureDetector(
                      onTap: () => setState(() => _language = lang.$1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _language == lang.$1
                              ? SeeUColors.accent
                              : theme.cardColor,
                          border: Border.all(
                            color: _language == lang.$1
                                ? SeeUColors.accent
                                : LibColors.line(context),
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          lang.$2,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color:
                                _language == lang.$1 ? Colors.white : c.ink,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),

              // Прогресс загрузки
              if (_uploading && _uploadProgress > 0) ...[
                LibProgressBar(value: _uploadProgress, height: 6),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Загрузка файла…',
                        style: TextStyle(fontSize: 12, color: c.ink3)),
                    Text(
                      '${(_uploadProgress * 100).toInt()}%',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: SeeUColors.accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],

              // Кнопка «Загрузить» — коралл 48/r15 с мягкой тенью.
              _UploadButton(
                enabled: !_uploading && _picked != null,
                loading: _uploading && _uploadProgress == 0,
                label: _uploading ? 'Загрузка…' : 'Загрузить',
                onTap: _upload,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Кикер-лейбл поля в стиле Читальни.
  static Widget _fieldLabel(BuildContext context, String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.6,
        color: context.seeuColors.ink3,
      ),
    );
  }

  /// Плашка поля: карточный фон, тонкая линия, r12.
  static BoxDecoration _fieldDecoration(BuildContext context) {
    return BoxDecoration(
      color: Theme.of(context).cardColor,
      border: Border.all(color: LibColors.line(context)),
      borderRadius: BorderRadius.circular(12),
    );
  }

  String _formatSize(int bytes) {
    if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }
}

// ─── Слот обложки (dashed 76×104) ───────────────────────────────────────────

class _CoverSlot extends StatelessWidget {
  final PlatformFile? cover;
  final VoidCallback? onPick;
  final VoidCallback onRemove;

  const _CoverSlot({
    required this.cover,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;

    if (cover?.bytes != null) {
      // Обложка выбрана — превью с крестиком в углу.
      return SizedBox(
        width: 76,
        height: 104,
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                cover!.bytes!,
                width: 76,
                height: 104,
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(PhosphorIconsBold.x,
                      size: 11, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: onPick,
      child: LibDashedBorder(
        color: c.ink4,
        radius: 12,
        child: SizedBox(
          width: 76,
          height: 104,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(PhosphorIconsRegular.image, size: 22, color: c.ink3),
              const SizedBox(height: 6),
              Text(
                'Обложка',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: c.ink3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Область «Выбрать файл» (dashed коралл) ─────────────────────────────────

class _FileSlot extends StatelessWidget {
  final PlatformFile? picked;
  final String sizeLabel;
  final VoidCallback? onPick;
  final VoidCallback onClear;

  const _FileSlot({
    required this.picked,
    required this.sizeLabel,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;

    return GestureDetector(
      onTap: onPick,
      child: LibDashedBorder(
        color: SeeUColors.accent.withValues(alpha: 0.6),
        radius: 12,
        child: Container(
          height: 104,
          decoration: BoxDecoration(
            color: SeeUColors.accent.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
          ),
          child: picked == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(PhosphorIconsRegular.fileArrowUp,
                        size: 26, color: SeeUColors.accent),
                    const SizedBox(height: 7),
                    const Text(
                      'Выбрать файл',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: SeeUColors.accent,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'PDF · FB2 · DOCX · EPUB · TXT…',
                      style: TextStyle(fontSize: 9, color: c.ink3),
                    ),
                  ],
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Icon(PhosphorIconsBold.fileText,
                          size: 22, color: SeeUColors.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              picked!.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                height: 1.3,
                                color: c.ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              sizeLabel,
                              style:
                                  TextStyle(fontSize: 10, color: c.ink3),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: onClear,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(PhosphorIconsRegular.x,
                              size: 16, color: c.ink4),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

// ─── Поле «в стиле Читальни» ────────────────────────────────────────────────

/// Кикер-лейбл сверху + плашка 42/r12 с тонкой линией (не Material-лейблы).
class _LibField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final int maxLines;

  const _LibField({
    required this.label,
    required this.hint,
    required this.controller,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final single = maxLines == 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _UploadSheetState._fieldLabel(context, label),
        const SizedBox(height: 6),
        Container(
          height: single ? 42 : null,
          padding: EdgeInsets.symmetric(
              horizontal: 12, vertical: single ? 0 : 10),
          alignment: single ? Alignment.centerLeft : null,
          decoration: _UploadSheetState._fieldDecoration(context),
          child: TextField(
            controller: controller,
            maxLines: maxLines,
            style: TextStyle(fontSize: 13, color: c.ink),
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              hintText: hint,
              hintStyle: TextStyle(fontSize: 13, color: c.ink4),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Кнопка «Загрузить» ─────────────────────────────────────────────────────

class _UploadButton extends StatelessWidget {
  final bool enabled;
  final bool loading;
  final String label;
  final VoidCallback onTap;

  const _UploadButton({
    required this.enabled,
    required this.loading,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;

    return Tappable.scaled(
      onTap: enabled ? onTap : null,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: enabled || loading ? SeeUColors.accent : c.surface2,
          borderRadius: BorderRadius.circular(15),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: SeeUColors.accent.withValues(alpha: 0.45),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                    spreadRadius: -6,
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: enabled ? Colors.white : c.ink4,
                ),
              ),
      ),
    );
  }
}
