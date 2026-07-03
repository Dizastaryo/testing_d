import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/design/design.dart';
import '../../../core/models/playlist.dart';
import '../../../core/providers/playlist_provider.dart';

/// «Мои плейлисты» horizontal strip shown on the audiotheque home screen.
class PlaylistsStrip extends ConsumerWidget {
  const PlaylistsStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final async = ref.watch(myPlaylistsProvider);
    final list = async.value ?? const <Playlist>[];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SeeUSectionHeader(
            kicker: 'КОЛЛЕКЦИИ',
            title: 'Мои плейлисты',
            padding: EdgeInsets.zero,
            action: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: SeeUColors.accent,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: () => createPlaylistDialog(context, ref),
              icon: Icon(PhosphorIcons.plus(), size: 16),
              label: const Text('Новый'),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 134,
            child: list.isEmpty
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        'Создайте первый, чтобы сохранять любимые треки',
                        style: TextStyle(color: c.ink3, fontSize: 12),
                      ),
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (_, i) => _PlaylistCard(playlist: list[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  final Playlist playlist;
  const _PlaylistCard({required this.playlist});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return GestureDetector(
      onTap: () => context.push('/playlist/${playlist.id}'),
      child: SizedBox(
        width: 110,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 110,
                height: 90,
                child: playlist.coverUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: playlist.coverUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: c.surface2),
                        errorWidget: (_, __, ___) =>
                            Container(color: c.surface2),
                      )
                    : Container(
                        color: c.surface2,
                        child: Icon(PhosphorIcons.musicNotesSimple(),
                            color: c.ink3, size: 32),
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Text(playlist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
            Text('${playlist.tracksCount} треков',
                style: TextStyle(color: c.ink3, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

/// Prompts for a name and creates a playlist. Shared by the header quick
/// button, the strip's «Новый» action and the playlists bottom sheet.
Future<void> createPlaylistDialog(BuildContext context, WidgetRef ref) async {
  final ctrl = TextEditingController();
  final String? name;
  try {
    name = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Новый плейлист'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(hintText: 'Название'),
          onSubmitted: (v) => Navigator.of(dialogCtx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(null),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(ctrl.text.trim()),
            child: const Text('Создать'),
          ),
        ],
      ),
    );
  } finally {
    ctrl.dispose();
  }
  if (name == null || name.isEmpty) return;
  final p = await ref.read(myPlaylistsProvider.notifier).create(name);
  if (!context.mounted) return;
  if (p != null) {
    showSeeUSnackBar(context, 'Плейлист «${p.name}» создан',
        tone: SeeUTone.success);
  } else {
    showSeeUSnackBar(context, 'Не удалось создать плейлист',
        tone: SeeUTone.danger);
  }
}

/// Bottom sheet listing every playlist — opened from the header's
/// «Плейлисты» quick button.
void openPlaylistsSheet(BuildContext context, WidgetRef ref) {
  final c = context.seeuColors;
  showSeeUBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) => Consumer(
      builder: (_, ref, __) {
        final async = ref.watch(myPlaylistsProvider);
        final list = async.value ?? const <Playlist>[];
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetCtx).size.height * 0.65,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      Icon(PhosphorIcons.queue(), color: SeeUColors.accent),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text('Мои плейлисты',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: SeeUColors.accent,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: () async {
                          Navigator.pop(sheetCtx);
                          await createPlaylistDialog(context, ref);
                        },
                        icon: Icon(PhosphorIcons.plus(), size: 16),
                        label: const Text('Новый'),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: c.line),
                Flexible(
                  child: list.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text('У вас ещё нет плейлистов',
                              style: TextStyle(color: c.ink2)),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: list.length,
                          itemBuilder: (_, i) {
                            final p = list[i];
                            return ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: p.coverUrl.isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: p.coverUrl,
                                          fit: BoxFit.cover,
                                          errorWidget: (_, __, ___) =>
                                              Container(color: c.surface2),
                                        )
                                      : Container(
                                          color: c.surface2,
                                          child: Icon(
                                              PhosphorIcons.musicNotesSimple(),
                                              color: c.ink3,
                                              size: 18),
                                        ),
                                ),
                              ),
                              title: Text(p.name),
                              subtitle: Text('${p.tracksCount} треков',
                                  style: TextStyle(
                                      color: c.ink3, fontSize: 11)),
                              onTap: () {
                                Navigator.pop(sheetCtx);
                                context.push('/playlist/${p.id}');
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
