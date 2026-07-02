import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import '../../core/models/file_item.dart';
import '../../core/providers/library_provider.dart';

class EditFileSheet extends ConsumerStatefulWidget {
  final FileItem file;
  const EditFileSheet({super.key, required this.file});

  @override
  ConsumerState<EditFileSheet> createState() => _EditFileSheetState();
}

class _EditFileSheetState extends ConsumerState<EditFileSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _authorCtrl;
  late final TextEditingController _descCtrl;
  late String _categoryId;
  late String _language;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.file.displayTitle);
    _authorCtrl = TextEditingController(text: widget.file.authorName);
    _descCtrl = TextEditingController(text: widget.file.description);
    _categoryId = widget.file.categoryId;
    _language = widget.file.language.isNotEmpty ? widget.file.language : 'ru';
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _authorCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) {
      showSeeUSnackBar(context, 'Введи название', tone: SeeUTone.danger);
      return;
    }
    setState(() => _saving = true);
    try {
      final meta = <String, dynamic>{
        'title': _titleCtrl.text.trim(),
      };
      final author = _authorCtrl.text.trim();
      if (author.isNotEmpty) meta['author_name'] = author;
      final desc = _descCtrl.text.trim();
      if (desc.isNotEmpty) meta['description'] = desc;
      if (_categoryId.isNotEmpty) meta['category_id'] = _categoryId;
      if (_language.isNotEmpty) meta['language'] = _language;
      await ref.read(libraryActionsProvider).updateFileMeta(widget.file.id, meta);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      showSeeUSnackBar(context, 'Ошибка: $e', tone: SeeUTone.danger);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.seeuColors;
    final cats = ref.watch(fileCategoriesProvider).valueOrNull ?? [];

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: c.ink4,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Header with icon
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: SeeUColors.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(PhosphorIconsRegular.pencilSimple,
                      size: 20, color: SeeUColors.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Редактировать',
                          style: SeeUTypography.displayXS.copyWith(
                            color: c.ink,
                          )),
                      Text(
                        widget.file.formatLabel,
                        style: TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 10,
                          color: SeeUColors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            TextField(
              controller: _titleCtrl,
              decoration: InputDecoration(
                labelText: 'Название *',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),

            TextField(
              controller: _authorCtrl,
              decoration: InputDecoration(
                labelText: 'Автор',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),

            if (cats.isNotEmpty)
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: _categoryId.isEmpty ? null : _categoryId,
                decoration: InputDecoration(
                  labelText: 'Категория',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
                hint: const Text('Без категории'),
                items: cats
                    .map((cat) => DropdownMenuItem(
                        value: cat.id, child: Text(cat.name)))
                    .toList(),
                onChanged: (v) => setState(() => _categoryId = v ?? ''),
              ),
            if (cats.isNotEmpty) const SizedBox(height: 10),

            TextField(
              controller: _descCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Описание',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 10),

            // Language chips
            Row(
              children: [
                Text('Язык:',
                    style: TextStyle(fontSize: 13, color: c.ink3)),
                const SizedBox(width: 10),
                for (final lang in [
                  ('ru', 'Русский'),
                  ('en', 'English'),
                  ('other', 'Другой')
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () => setState(() => _language = lang.$1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _language == lang.$1
                              ? SeeUColors.accent
                              : Colors.transparent,
                          border: Border.all(
                            color: _language == lang.$1
                                ? SeeUColors.accent
                                : c.line,
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
                                : c.ink2,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),

            SeeUButton(
              label: _saving ? 'Сохранение…' : 'Сохранить',
              onTap: _saving ? null : _save,
              isLoading: _saving,
              width: double.infinity,
            ),
          ],
        ),
      ),
    );
  }
}
