import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/models/collection.dart';
import '../../core/models/file_item.dart';
import '../../core/providers/collection_provider.dart';
import '../../core/providers/library_provider.dart';
import 'library_design.dart';
import 'readers/open_reader.dart';

/// Коллекция — подборка книг, которой можно поделиться. У владельца здесь
/// правка состава и переключатель «доступна по ссылке»; у гостя, пришедшего
/// по ссылке, — только чтение и подпись, чья это подборка.
class CollectionDetailScreen extends ConsumerWidget {
  final String collectionId;
  const CollectionDetailScreen({super.key, required this.collectionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(collectionDetailProvider(collectionId));
    final collection = async.valueOrNull;
    final isOwner = collection?.isOwner ?? false;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: PaperBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              LibBackBar(
                kicker: 'КОЛЛЕКЦИЯ',
                title: collection?.name ?? '',
                action: isOwner
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          LibSquareButton(
                            icon: PhosphorIcons.shareFat(),
                            onTap: () => _share(context, ref, collection!),
                          ),
                          const SizedBox(width: 8),
                          _AddButton(onTap: () => _showAddFile(context, ref)),
                        ],
                      )
                    : null,
              ),
              Expanded(
                child: async.when(
                  loading: () => const Center(
                      child: CircularProgressIndicator(
                          color: SeeUColors.accent)),
                  error: (e, _) => SeeUErrorState(
                    error: '$e',
                    onRetry: () =>
                        ref.invalidate(collectionDetailProvider(collectionId)),
                  ),
                  data: (col) => ListView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                    children: [
                      if (!col.isOwner) _GuestHeader(collection: col),
                      if (col.isOwner) _ShareRow(collection: col),
                      const SizedBox(height: 14),
                      if (col.files.isEmpty)
                        _empty(context, ref, col.isOwner)
                      else
                        for (final file in col.files) ...[
                          _FileRow(
                            file: file,
                            // Убрать книгу из чужой подборки нельзя.
                            onRemove: col.isOwner
                                ? () async {
                                    await ref
                                        .read(collectionsProvider.notifier)
                                        .removeFile(col.id, file.id);
                                    ref.invalidate(collectionDetailProvider(
                                        collectionId));
                                  }
                                : null,
                          ),
                          const SizedBox(height: 8),
                        ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty(BuildContext context, WidgetRef ref, bool isOwner) {
    final c = context.seeuColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 60, 14, 0),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: SeeUColors.plum.withValues(alpha: 0.1),
            ),
            child: Icon(PhosphorIcons.books(), size: 40, color: SeeUColors.plum),
          ),
          const SizedBox(height: 22),
          Text(
            isOwner ? 'Подборка пуста' : 'Здесь пока пусто',
            textAlign: TextAlign.center,
            style: SeeUTypography.displayS.copyWith(fontSize: 25, color: c.ink),
          ),
          const SizedBox(height: 8),
          Text(
            isOwner
                ? 'Добавьте книги — и подборкой можно будет поделиться'
                : 'Автор пока не добавил сюда книги',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.5, color: c.ink3),
          ),
        ],
      ),
    );
  }

  /// Поделиться можно только открытой подборкой — иначе по ссылке гость
  /// упрётся в «не найдено». Поэтому сначала открываем, потом отдаём ссылку.
  Future<void> _share(
      BuildContext context, WidgetRef ref, Collection col) async {
    if (!col.isPublic) {
      final ok = await showSeeUConfirm(
        context,
        title: 'Открыть подборку по ссылке?',
        message:
            'Любой, кому вы дадите ссылку, увидит книги этой подборки. '
            'Менять её сможете только вы. Закрыть доступ можно в любой момент.',
        confirmLabel: 'Открыть и поделиться',
        icon: PhosphorIcons.shareFat(),
      );
      if (!ok) return;
      final done =
          await ref.read(collectionsProvider.notifier).setPublic(col.id, true);
      if (!context.mounted) return;
      if (!done) {
        showSeeUSnackBar(context, 'Не удалось открыть доступ',
            tone: SeeUTone.danger);
        return;
      }
      ref.invalidate(collectionDetailProvider(col.id));
    }

    await Share.share(
      'Подборка «${col.name}» в SeeU — ${col.filesCount} '
      '${_booksWord(col.filesCount)}\nseeu://collection/${col.id}',
      subject: col.name,
    );
  }

  static String _booksWord(int n) {
    final m10 = n % 10, m100 = n % 100;
    if (m100 >= 11 && m100 <= 14) return 'книг';
    if (m10 == 1) return 'книга';
    if (m10 >= 2 && m10 <= 4) return 'книги';
    return 'книг';
  }

  Future<void> _showAddFile(BuildContext context, WidgetRef ref) async {
    await showSeeUBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddFileSheet(
        collectionId: collectionId,
        onAdded: () => ref.invalidate(collectionDetailProvider(collectionId)),
      ),
    );
  }
}

/// Коралловый «+» — добавить книгу в подборку.
class _AddButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tappable.scaled(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: SeeUColors.accent,
          borderRadius: BorderRadius.circular(13),
        ),
        child: const Icon(PhosphorIconsBold.plus, size: 17, color: Colors.white),
      ),
    );
  }
}

/// Строка доступа: подборка личная или открыта по ссылке.
class _ShareRow extends ConsumerWidget {
  final Collection collection;
  const _ShareRow({required this.collection});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final open = collection.isPublic;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: LibColors.line(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: (open ? SeeUColors.success : c.ink3)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              open ? PhosphorIcons.linkSimple() : PhosphorIcons.lockSimple(),
              size: 19,
              color: open ? SeeUColors.success : c.ink3,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  open ? 'Доступна по ссылке' : 'Личная подборка',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  open
                      ? 'Кто получит ссылку — увидит книги'
                      : 'Видите только вы',
                  style: TextStyle(fontSize: 11.5, color: c.ink3),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: open,
            activeThumbColor: SeeUColors.accent,
            onChanged: (v) async {
              HapticFeedback.selectionClick();
              final done = await ref
                  .read(collectionsProvider.notifier)
                  .setPublic(collection.id, v);
              if (!context.mounted) return;
              if (done) {
                ref.invalidate(collectionDetailProvider(collection.id));
              } else {
                showSeeUSnackBar(context, 'Не удалось изменить доступ',
                    tone: SeeUTone.danger);
              }
            },
          ),
        ],
      ),
    );
  }
}

/// Шапка гостя: чья это подборка. Гость никогда не путает её со своей.
class _GuestHeader extends StatelessWidget {
  final Collection collection;
  const _GuestHeader({required this.collection});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final name = collection.ownerName.isNotEmpty
        ? collection.ownerName
        : '@${collection.ownerUsername}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: LibColors.line(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [SeeUColors.accentSecondary, SeeUColors.plum],
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: collection.ownerAvatar.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: collection.ownerAvatar, fit: BoxFit.cover)
                : Center(
                    child: Text(
                      name.isNotEmpty
                          ? name.characters.first.toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: 'Подборка ',
                children: [
                  TextSpan(
                    text: name,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: c.ink,
                    ),
                  ),
                ],
              ),
              style: TextStyle(fontSize: 13, color: c.ink3),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Строка книги; смахнуть можно только в своей подборке ───────────────────

class _FileRow extends StatelessWidget {
  final FileItem file;

  /// null — подборка чужая: книгу отсюда убрать нельзя.
  final VoidCallback? onRemove;

  const _FileRow({required this.file, this.onRemove});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.seeuColors;
    final color = _colorForExt(file.fileExtension);

    final row = _row(context, theme, c, color);
    if (onRemove == null) return row;

    return Dismissible(
      key: ValueKey(file.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: SeeUColors.danger.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(SeeURadii.small),
        ),
        child:
            const Icon(PhosphorIconsRegular.trash, color: SeeUColors.danger),
      ),
      confirmDismiss: (_) async {
        onRemove!();
        return false;
      },
      child: row,
    );
  }

  Widget _row(BuildContext context, ThemeData theme, SeeUThemeColors c,
      Color color) {
    return GestureDetector(
        onTap: () => canRead(file)
            ? openReader(context, file)
            : GoRouter.of(context).push('/files/${file.id}'),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.cardColor,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(SeeURadii.small),
            boxShadow: SeeUShadows.sm,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Text(
                  file.formatLabel,
                  style: TextStyle(
                    fontFamily: AppFonts.I.sans,
                    fontSize: 7,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    if (file.authorName.isNotEmpty)
                      Text(
                        file.authorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                      ),
                  ],
                ),
              ),
              Icon(PhosphorIconsRegular.arrowRight,
                  size: 16,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
            ],
          ),
        ),
    );
  }

  Color _colorForExt(String ext) {
    switch (ext) {
      case 'pdf':  return const Color(0xFFE53935);
      case 'epub': return const Color(0xFF8E24AA);
      case 'fb2':  return const Color(0xFF00ACC1);
      case 'docx': return SeeUColors.info;
      case 'pptx': return const Color(0xFFFF7043);
      case 'txt':  return const Color(0xFF43A047);
      default:     return const Color(0xFF78909C);
    }
  }
}

// ─── Add file bottom sheet ───────────────────────────────────────────────────

class _AddFileSheet extends ConsumerStatefulWidget {
  final String collectionId;
  final VoidCallback onAdded;
  const _AddFileSheet({required this.collectionId, required this.onAdded});

  @override
  ConsumerState<_AddFileSheet> createState() => _AddFileSheetState();
}

class _AddFileSheetState extends ConsumerState<_AddFileSheet> {
  final _ctrl = TextEditingController();
  final Set<String> _adding = {};
  List<FileItem> _files = [];
  bool _loading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _doSearch('');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _doSearch(q.trim());
    });
  }

  Future<void> _doSearch(String q) async {
    setState(() => _loading = true);
    try {
      final dio = ref.read(libraryApiClientProvider);
      final resp = await dio.get(ApiEndpoints.files, queryParameters: {'q': q, 'limit': 30});
      final items = resp.data?['data'] as List? ?? [];
      if (mounted) {
        setState(() {
          _files = items
              .map((e) => FileItem.fromJson(e as Map<String, dynamic>))
              .toList();
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addFile(String fileId) async {
    setState(() => _adding.add(fileId));
    await ref
        .read(collectionsProvider.notifier)
        .addFile(widget.collectionId, fileId);
    if (mounted) setState(() => _adding.remove(fileId));
    widget.onAdded();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final height = MediaQuery.sizeOf(context).height * 0.7;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SizedBox(
      height: height + bottomInset,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('КОЛЛЕКЦИЯ',
                      style: SeeUTypography.kicker.copyWith(color: c.ink3)),
                  const SizedBox(height: 4),
                  Text('Добавить в коллекцию',
                      style:
                          SeeUTypography.displayS.copyWith(color: c.ink)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: SeeUInput(
                controller: _ctrl,
                hintText: 'Поиск по названию…',
                prefix: Icon(PhosphorIconsRegular.magnifyingGlass,
                    size: 18, color: c.ink3),
                onChanged: _onSearchChanged,
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _files.isEmpty
                      ? SeeUEmptyState(
                          icon: PhosphorIconsRegular.magnifyingGlass,
                          title: 'Ничего не найдено',
                          iconSize: 48,
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: _files.length,
                          itemBuilder: (ctx, i) {
                            final f = _files[i];
                            final isAdding = _adding.contains(f.id);
                            return ListTile(
                              leading: Text(f.formatLabel,
                                  style: SeeUTypography.mono.copyWith(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: c.ink2)),
                              title: Text(f.displayTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: f.authorName.isNotEmpty
                                  ? Text(f.authorName)
                                  : null,
                              trailing: isAdding
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : IconButton(
                                      icon: const Icon(PhosphorIconsRegular.plus),
                                      color: SeeUColors.accent,
                                      onPressed: () => _addFile(f.id),
                                    ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
