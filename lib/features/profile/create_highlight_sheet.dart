import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/models/story.dart';

/// Bottom sheet for creating a new Highlight from the user's currently
/// active stories. Returns true if a highlight was successfully created.
///
/// Limitation: backend only exposes the user's *active* stories (not the
/// 24h+ archive). When we ship a stories archive, this picker can swap to
/// that endpoint without UI changes.
Future<bool> showCreateHighlightSheet({
  required BuildContext context,
  required String username,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
      ),
      child: _CreateHighlightForm(username: username),
    ),
  );
  return result ?? false;
}

class _CreateHighlightForm extends ConsumerStatefulWidget {
  final String username;
  const _CreateHighlightForm({required this.username});

  @override
  ConsumerState<_CreateHighlightForm> createState() =>
      _CreateHighlightFormState();
}

class _CreateHighlightFormState
    extends ConsumerState<_CreateHighlightForm> {
  final _title = TextEditingController();
  final Set<String> _selected = {};
  List<Story> _stories = const [];
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStories();
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _loadStories() async {
    try {
      final api = ref.read(apiClientProvider);
      final r = await api.get(ApiEndpoints.userStories(widget.username));
      final data = r.data is Map && (r.data as Map).containsKey('data')
          ? r.data['data']
          : r.data;
      final list = data is List
          ? data
              .map((e) => Story.fromJson(e as Map<String, dynamic>))
              .toList()
          : <Story>[];
      if (mounted) {
        setState(() {
          _stories = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Введите название');
      return;
    }
    if (_selected.isEmpty) {
      setState(() => _error = 'Выберите хотя бы одну сторис');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      // Cover defaults to the first selected story's media. Backend validator
      // requires a full URL when cover_url is non-empty — Story.fromJson
      // already normalised media_url to absolute on parse.
      final firstSelected =
          _stories.firstWhere((s) => s.id == _selected.first);
      final api = ref.read(apiClientProvider);
      await api.post(ApiEndpoints.highlights, data: {
        'title': title,
        'cover_url': firstSelected.mediaUrl,
        'story_ids': _selected.toList(),
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on DioException catch (e) {
      setState(() {
        _submitting = false;
        _error = apiErrorMessage(e);
      });
    } catch (e) {
      setState(() {
        _submitting = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(PhosphorIcons.plusCircle(), color: SeeUColors.accent),
                  const SizedBox(width: 8),
                  const Text('Новая коллекция',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _title,
                enabled: !_submitting,
                maxLength: 50,
                decoration: const InputDecoration(
                  labelText: 'Название',
                  hintText: 'например: «Лето 2026»',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    'Выберите сторис',
                    style: SeeUTypography.body
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  if (_selected.isNotEmpty)
                    Text('${_selected.length} выбрано',
                        style:
                            TextStyle(color: SeeUColors.accent, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(child: _buildStoriesGrid(c)),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: SeeUColors.accent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: (_submitting || _stories.isEmpty) ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Icon(PhosphorIcons.plusCircle(), size: 18),
                label: Text(_submitting ? 'Сохраняем…' : 'Создать коллекцию'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStoriesGrid(SeeUThemeColors c) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_stories.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Нет активных сторис.\nСначала опубликуйте сторис, потом\nможно собрать коллекцию.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.ink2),
          ),
        ),
      );
    }
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 9 / 16,
      ),
      itemCount: _stories.length,
      itemBuilder: (_, i) {
        final s = _stories[i];
        final isSelected = _selected.contains(s.id);
        return GestureDetector(
          onTap: () {
            setState(() {
              if (isSelected) {
                _selected.remove(s.id);
              } else {
                _selected.add(s.id);
              }
            });
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: s.mediaUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: c.surface2),
                  errorWidget: (_, __, ___) => Container(color: c.surface2),
                ),
              ),
              if (isSelected)
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: SeeUColors.accent, width: 3),
                  ),
                ),
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? SeeUColors.accent
                        : Colors.black.withValues(alpha: 0.4),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check,
                          color: Colors.white, size: 14)
                      : null,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
