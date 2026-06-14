import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Введи название')));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(libraryActionsProvider).updateFileMeta(widget.file.id, {
        'title': _titleCtrl.text.trim(),
        'author_name': _authorCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'category_id': _categoryId,
        'language': _language,
      });
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Редактировать файл',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),

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
                    .map((c) =>
                        DropdownMenuItem(value: c.id, child: Text(c.name)))
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
                    style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.6))),
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
                                : theme.colorScheme.onSurface,
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
