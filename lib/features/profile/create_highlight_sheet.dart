import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/models/story.dart';

/// Bottom sheet for creating a new Highlight.
/// Flow: 1) select stories from full archive → 2) pick cover + enter title.
/// Returns true if a highlight was successfully created.
Future<bool> showCreateHighlightSheet({
  required BuildContext context,
  required String username,
}) async {
  final result = await showSeeUBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
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

class _CreateHighlightFormState extends ConsumerState<_CreateHighlightForm> {
  final _title = TextEditingController();
  // Step 1: select stories. Step 2: pick cover + enter title.
  int _step = 1;
  // Ordered list of selected story ids (maintains selection order).
  final List<String> _selectedIds = [];
  // Cover is the story id the user picked. Defaults to first selected.
  String? _coverId;
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
      // include_expired=true loads the full archive (expired + active).
      final r = await api.get(
        ApiEndpoints.userStories(widget.username),
        queryParameters: {'include_expired': 'true', 'limit': '200'},
      );
      final data = r.data is Map && (r.data as Map).containsKey('data')
          ? r.data['data']
          : r.data;
      final list = data is List
          ? data
              .map((e) => Story.fromJson(e as Map<String, dynamic>))
              .toList()
          : <Story>[];
      // Sort newest first.
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
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

  void _toggleStory(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_coverId == id) {
          _coverId = _selectedIds.isNotEmpty ? _selectedIds.first : null;
        }
      } else {
        _selectedIds.add(id);
        _coverId ??= id;
      }
    });
  }

  void _goToStep2() {
    if (_selectedIds.isEmpty) {
      setState(() => _error = 'Выберите хотя бы одну сторис');
      return;
    }
    setState(() {
      _error = null;
      _step = 2;
    });
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Введите название');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final coverStory = _stories.firstWhere((s) => s.id == (_coverId ?? _selectedIds.first));
      final api = ref.read(apiClientProvider);
      await api.post(ApiEndpoints.highlights, data: {
        'title': title,
        'cover_url': coverStory.mediaUrl,
        'story_ids': _selectedIds,
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
          maxHeight: MediaQuery.of(context).size.height * 0.90,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  if (_step == 2)
                    GestureDetector(
                      onTap: () => setState(() { _step = 1; _error = null; }),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(PhosphorIcons.arrowLeft(), size: 20, color: c.ink),
                      ),
                    ),
                  Icon(PhosphorIcons.plusCircle(), color: SeeUColors.accent),
                  const SizedBox(width: 8),
                  Text(
                    _step == 1 ? 'Выберите сторис' : 'Оформление',
                    style: SeeUTypography.displayS.copyWith(color: c.ink),
                  ),
                  const Spacer(),
                  if (_step == 1 && _selectedIds.isNotEmpty)
                    Text('${_selectedIds.length} выбрано',
                        style: SeeUTypography.caption
                            .copyWith(color: SeeUColors.accent)),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(false),
                    child: Icon(PhosphorIcons.x(), size: 22, color: c.ink2),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (_step == 1) ...[
                Expanded(child: _buildStoriesGrid(c)),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: SeeUTypography.caption.copyWith(color: SeeUColors.error)),
                ],
                const SizedBox(height: 12),
                SeeUButton(
                  label: 'Далее',
                  onTap: _selectedIds.isEmpty ? null : _goToStep2,
                ),
              ] else ...[
                // Cover picker
                Text('Обложка хайлайта',
                    style: SeeUTypography.body.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 90,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _selectedIds.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final id = _selectedIds[i];
                      final story = _stories.firstWhere((s) => s.id == id);
                      final isCover = _coverId == id;
                      return GestureDetector(
                        onTap: () => setState(() => _coverId = id),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: CachedNetworkImage(
                                imageUrl: story.mediaUrl,
                                width: 56,
                                height: 90,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Container(width: 56, height: 90, color: c.surface2),
                                errorWidget: (_, __, ___) => Container(width: 56, height: 90, color: c.surface2),
                              ),
                            ),
                            if (isCover)
                              Positioned.fill(
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: SeeUColors.accent, width: 2.5),
                                  ),
                                  child: const Center(
                                    child: Icon(PhosphorIconsFill.checkCircle, color: SeeUColors.accent, size: 22),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                // Title field
                Text('НАЗВАНИЕ',
                    style: SeeUTypography.kicker.copyWith(color: c.ink3)),
                const SizedBox(height: 6),
                SeeUInput(
                  controller: _title,
                  maxLength: 50,
                  autofocus: true,
                  hintText: 'например: «Лето 2026»',
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: SeeUTypography.caption.copyWith(color: SeeUColors.error)),
                ],
                const SizedBox(height: 12),
                SeeUButton(
                  label: _submitting ? 'Сохраняем…' : 'Создать хайлайт',
                  icon: PhosphorIcons.plusCircle(),
                  isLoading: _submitting,
                  onTap: _submitting ? null : _submit,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStoriesGrid(SeeUThemeColors c) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: SeeUColors.accent));
    }
    if (_stories.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'У вас пока нет сторис.\nОпубликуйте сторис — они появятся здесь.',
            textAlign: TextAlign.center,
            style: SeeUTypography.body.copyWith(color: c.ink2),
          ),
        ),
      );
    }
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 9 / 16,
      ),
      itemCount: _stories.length,
      itemBuilder: (_, i) {
        final s = _stories[i];
        final isSelected = _selectedIds.contains(s.id);
        return GestureDetector(
          onTap: () => _toggleStory(s.id),
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
                    border: Border.all(color: SeeUColors.accent, width: 2.5),
                  ),
                ),
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? SeeUColors.accent : Colors.black.withValues(alpha: 0.4),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: isSelected
                      ? Icon(PhosphorIcons.check(PhosphorIconsStyle.bold),
                          color: Colors.white, size: 14)
                      : null,
                ),
              ),
              // Date label at bottom
              Positioned(
                left: 0, right: 0, bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                    color: Colors.black.withValues(alpha: 0.45),
                  ),
                  child: Text(
                    _formatDate(s.createdAt),
                    textAlign: TextAlign.center,
                    style: SeeUTypography.micro.copyWith(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDate(DateTime dt) {
    final months = ['янв', 'фев', 'мар', 'апр', 'май', 'июн',
                    'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];
    return '${dt.day} ${months[dt.month - 1]}';
  }
}
