import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/design/design.dart';
import '../../../core/models/highlight.dart';
import '../../../core/models/story.dart';
import '../../../core/providers/user_provider.dart';
import '../../feed/widgets/stories_row.dart';
import '../create_highlight_sheet.dart';

class ProfileHighlightsRow extends ConsumerWidget {
  final List<Highlight> highlights;
  final String? currentUserId;
  final bool isOwnProfile;
  final String username;

  const ProfileHighlightsRow({
    super.key,
    required this.highlights,
    required this.username,
    this.currentUserId,
    this.isOwnProfile = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final addTileCount = isOwnProfile ? 1 : 0;
    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        itemCount: highlights.length + addTileCount,
        itemBuilder: (context, index) {
          if (isOwnProfile && index == 0) {
            return Padding(
              padding: EdgeInsets.only(right: highlights.isEmpty ? 0 : 16),
              child: ProfileAddHighlightTile(username: username),
            );
          }
          final h = highlights[index - addTileCount];
          final isLast = index == highlights.length + addTileCount - 1;
          return Padding(
            padding: EdgeInsets.only(right: isLast ? 0 : 16),
            child: GestureDetector(
              onLongPress: isOwnProfile
                  ? () => _showHighlightActions(context, ref, h)
                  : null,
              onTap: () {
                if (h.stories.isNotEmpty) {
                  final group = StoryGroup(
                    author: h.author, stories: h.stories, allSeen: false);
                  Navigator.of(context).push(
                    CupertinoPageRoute(
                      builder: (_) => StoryViewerRoute(
                        groups: [group], initialGroupIndex: 0,
                        currentUserId: currentUserId),
                    ),
                  );
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: c.line, width: 1.5),
                    ),
                    child: ClipOval(
                      child: h.coverUrl.isNotEmpty
                          ? CachedNetworkImage(imageUrl: h.coverUrl, fit: BoxFit.cover)
                          : Container(
                              color: c.surface2,
                              child: Center(child: Icon(PhosphorIcons.image(), size: 28, color: c.ink3)),
                            ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(h.title, style: SeeUTypography.caption,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showHighlightActions(BuildContext context, WidgetRef ref, Highlight h) {
    HapticFeedback.mediumImpact();
    final c = context.seeuColors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: c.surface, borderRadius: BorderRadius.circular(SeeURadii.card)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(PhosphorIcons.pencilSimple(), color: c.ink),
                title: const Text('Переименовать'),
                onTap: () { Navigator.of(sheetCtx).pop(); _renameHighlight(context, ref, h); },
              ),
              Divider(height: 1, color: c.line),
              ListTile(
                leading: Icon(PhosphorIcons.trash(), color: Colors.red),
                title: const Text('Удалить', style: TextStyle(color: Colors.red)),
                onTap: () { Navigator.of(sheetCtx).pop(); _deleteHighlight(context, ref, h); },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _renameHighlight(BuildContext context, WidgetRef ref, Highlight h) async {
    final controller = TextEditingController(text: h.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('Переименовать коллекцию'),
        content: TextField(
          controller: controller, autofocus: true, maxLength: 50,
          decoration: const InputDecoration(hintText: 'Новое название', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dlgCtx).pop(), child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SeeUColors.accent),
            onPressed: () => Navigator.of(dlgCtx).pop(controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (newTitle == null || newTitle.isEmpty || newTitle == h.title) return;
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final api = ref.read(apiClientProvider);
      await api.put(ApiEndpoints.highlightById(h.id), data: {'title': newTitle});
      ref.invalidate(userProfileProvider(username));
      messenger.showSnackBar(const SnackBar(content: Text('Коллекция переименована')));
    } on DioException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Не удалось: ${apiErrorMessage(e)}')));
    }
  }

  Future<void> _deleteHighlight(BuildContext context, WidgetRef ref, Highlight h) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('Удалить коллекцию?'),
        content: Text('Коллекция «${h.title}» будет удалена. Сами сторис останутся в архиве.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dlgCtx).pop(false), child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dlgCtx).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final api = ref.read(apiClientProvider);
      await api.delete(ApiEndpoints.highlightById(h.id));
      ref.invalidate(userProfileProvider(username));
      messenger.showSnackBar(const SnackBar(content: Text('Коллекция удалена')));
    } on DioException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Не удалось: ${apiErrorMessage(e)}')));
    }
  }
}

class ProfileAddHighlightTile extends ConsumerWidget {
  final String username;
  const ProfileAddHighlightTile({super.key, required this.username});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    return GestureDetector(
      onTap: () async {
        final created = await showCreateHighlightSheet(context: context, username: username);
        if (created) ref.invalidate(userProfileProvider(username));
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle, color: c.surface2,
              border: Border.all(color: SeeUColors.accent.withValues(alpha: 0.6), width: 1.5),
            ),
            child: Center(child: Icon(PhosphorIcons.plus(), color: SeeUColors.accent, size: 28)),
          ),
          const SizedBox(height: 6),
          Text('Создать',
              style: SeeUTypography.caption.copyWith(color: SeeUColors.accent),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
