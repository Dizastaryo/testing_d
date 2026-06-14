import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/providers/library_provider.dart';

const _allowedExtensions = [
  'pdf', 'epub', 'fb2', 'docx', 'pptx', 'txt', 'rtf', 'md', 'odt', 'odp'
];

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
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
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
    if (_picked?.bytes == null) return;
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введи название')),
      );
      return;
    }
    setState(() => _uploading = true);
    try {
      final dio = ref.read(libraryApiClientProvider);
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(_picked!.bytes!, filename: _picked!.name),
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
      );
      ref.invalidate(trendingFilesProvider);
      if (!mounted) return;
      final ext = _picked!.name.split('.').last.toLowerCase();
      final needsPrep = _convertibleExts.contains(ext);
      Navigator.of(context).pop(<String, dynamic>{
        'uploaded': true,
        'needsPrep': needsPrep,
        'title': _titleCtrl.text.trim(),
      });
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = e.response?.data?['error'] ?? e.message ?? 'Ошибка загрузки';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg.toString())),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cats = ref.watch(fileCategoriesProvider).valueOrNull ?? [];

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
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
            Text('Загрузить файл',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),

            // File picker button
            GestureDetector(
              onTap: _uploading ? null : _pickFile,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _picked != null
                      ? SeeUColors.accent.withValues(alpha: 0.08)
                      : theme.cardColor,
                  border: Border.all(
                    color: _picked != null
                        ? SeeUColors.accent.withValues(alpha: 0.5)
                        : theme.dividerColor,
                    style: _picked != null ? BorderStyle.solid : BorderStyle.solid,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(
                      _picked != null
                          ? PhosphorIconsBold.fileText
                          : PhosphorIconsBold.upload,
                      color: _picked != null
                          ? SeeUColors.accent
                          : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _picked != null
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _picked!.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600, fontSize: 13),
                                ),
                                Text(
                                  _formatSize(_picked!.size),
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.5)),
                                ),
                              ],
                            )
                          : Text(
                              'Выбрать файл (PDF, EPUB, FB2, DOCX…)',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.5)),
                            ),
                    ),
                    if (_picked != null)
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(PhosphorIconsRegular.x,
                            size: 18,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
                        onPressed: () => setState(() => _picked = null),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Title
            TextField(
              controller: _titleCtrl,
              decoration: InputDecoration(
                labelText: 'Название *',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),

            // Author
            TextField(
              controller: _authorCtrl,
              decoration: InputDecoration(
                labelText: 'Автор (необязательно)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),

            // Category dropdown
            if (cats.isNotEmpty)
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: _categoryId.isEmpty ? null : _categoryId,
                decoration: InputDecoration(
                  labelText: 'Категория',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
                hint: const Text('Без категории'),
                items: cats.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                onChanged: (v) => setState(() => _categoryId = v ?? ''),
              ),
            if (cats.isNotEmpty) const SizedBox(height: 10),

            // Description
            TextField(
              controller: _descCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Описание (необязательно)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 10),

            // Language chips
            Row(
              children: [
                Text('Язык:',
                    style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
                const SizedBox(width: 10),
                for (final lang in [('ru', 'Русский'), ('en', 'English'), ('other', 'Другой')])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () => setState(() => _language = lang.$1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _language == lang.$1
                              ? SeeUColors.accent
                              : theme.cardColor,
                          border: Border.all(
                            color: _language == lang.$1
                                ? SeeUColors.accent
                                : theme.dividerColor,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          lang.$2,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: _language == lang.$1
                                  ? Colors.white
                                  : theme.colorScheme.onSurface),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // Cover picker — optional
            _CoverPickerRow(
              cover: _cover,
              onPick: _uploading ? null : _pickCover,
              onRemove: () => setState(() => _cover = null),
            ),
            const SizedBox(height: 20),

            // Upload button
            SeeUButton(
              label: _uploading ? 'Загрузка…' : 'Загрузить',
              onTap: (_uploading || _picked == null) ? null : _upload,
              isLoading: _uploading,
              width: double.infinity,
            ),
          ],
        ),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }
}

class _CoverPickerRow extends StatelessWidget {
  final PlatformFile? cover;
  final VoidCallback? onPick;
  final VoidCallback onRemove;

  const _CoverPickerRow({
    required this.cover,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Preview / placeholder
        GestureDetector(
          onTap: onPick,
          child: Container(
            width: 52,
            height: 72,
            decoration: BoxDecoration(
              color: cover != null
                  ? Colors.transparent
                  : theme.cardColor,
              border: Border.all(
                color: cover != null
                    ? SeeUColors.accent.withValues(alpha: 0.5)
                    : theme.dividerColor,
                style: BorderStyle.solid,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: cover?.bytes != null
                ? Image.memory(cover!.bytes!, fit: BoxFit.cover)
                : Icon(
                    PhosphorIconsRegular.imageSquare,
                    size: 24,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Обложка',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'необязательно',
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                cover != null
                    ? cover!.name
                    : 'По умолчанию',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: onPick,
                child: Text(
                  cover != null ? 'Изменить' : 'Выбрать изображение',
                  style: TextStyle(
                    fontSize: 12,
                    color: SeeUColors.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (cover != null)
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(
              PhosphorIconsRegular.x,
              size: 18,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
            onPressed: onRemove,
          ),
      ],
    );
  }
}
