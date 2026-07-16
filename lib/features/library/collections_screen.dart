import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import '../../core/models/collection.dart';
import '../../core/providers/collection_provider.dart';
import 'library_design.dart';

enum _CollectionsSort { updated, name, size }

final _collectionsSortProvider =
    StateProvider<_CollectionsSort>((ref) => _CollectionsSort.updated);

class CollectionsScreen extends ConsumerWidget {
  const CollectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final async = ref.watch(collectionsProvider);
    final sort = ref.watch(_collectionsSortProvider);
    final topInset = MediaQuery.paddingOf(context).top + 60;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      extendBodyBehindAppBar: true,
      body: PaperBackground(
        child: Stack(
          children: [
            async.when(
              loading: () => Padding(
                padding: EdgeInsets.only(top: topInset),
                child: const SeeUListSkeleton(count: 6),
              ),
              error: (e, _) => SeeUErrorState(
                error: '$e',
                onRetry: () => ref.invalidate(collectionsProvider),
              ),
              data: (collections) {
                final sorted = [...collections];
                switch (sort) {
                  case _CollectionsSort.updated:
                    sorted.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
                  case _CollectionsSort.name:
                    sorted.sort((a, b) =>
                        a.name.toLowerCase().compareTo(b.name.toLowerCase()));
                  case _CollectionsSort.size:
                    sorted.sort((a, b) => b.filesCount.compareTo(a.filesCount));
                }
  
                if (sorted.isEmpty) {
                  return SeeUEmptyState(
                    icon: PhosphorIconsRegular.bookBookmark,
                    title: 'Нет коллекций',
                    subtitle: 'Нажмите «Создать», чтобы добавить первую',
                    action: SeeUStateAction(
                      label: 'Создать',
                      icon: PhosphorIconsBold.plus,
                      onTap: () => _showCreateSheet(context, ref),
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(collectionsProvider),
                  child: GridView.builder(
                    padding: EdgeInsets.fromLTRB(16, topInset, 16, 96),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      mainAxisExtent: 158,
                    ),
                    // Последняя плитка — «Новая коллекция» пунктиром.
                    itemCount: sorted.length + 1,
                    itemBuilder: (ctx, i) => i < sorted.length
                        ? _CollectionCard(collection: sorted[i])
                        : _NewCollectionTile(
                            onTap: () => _showCreateSheet(context, ref),
                          ),
                  ),
                );
              },
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SeeUGlassBar(
                kicker: 'Библиотека',
                titleText: 'Коллекции',
                leading: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 2),
                  child: LibBackButton(),
                ),
                actions: [
                  Tappable(
                    onTap: () => _showSortSheet(context, ref, sort),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(PhosphorIconsRegular.funnel,
                          size: 20, color: c.ink3),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Плюс-кнопка «создать» — 36/r11 коралл (вместо FAB).
                  Tappable.scaled(
                    onTap: () => _showCreateSheet(context, ref),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: SeeUColors.accent,
                        borderRadius: BorderRadius.circular(11),
                        boxShadow: [
                          BoxShadow(
                            color:
                                SeeUColors.accent.withValues(alpha: 0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 5),
                            spreadRadius: -4,
                          ),
                        ],
                      ),
                      child: const Icon(PhosphorIconsBold.plus,
                          size: 16, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSortSheet(
      BuildContext context, WidgetRef ref, _CollectionsSort current) {
    showSeeUBottomSheet(
      context: context,
      builder: (ctx) {
        final c = ctx.seeuColors;
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (s, label) in [
                (_CollectionsSort.updated, 'Недавно изменённые'),
                (_CollectionsSort.name, 'По названию'),
                (_CollectionsSort.size, 'Больше файлов'),
              ])
                ListTile(
                  leading: Icon(
                    s == current
                        ? PhosphorIconsBold.checkCircle
                        : PhosphorIconsRegular.circle,
                    size: 20,
                    color: s == current ? SeeUColors.accent : c.ink3,
                  ),
                  title: Text(
                    label,
                    style: SeeUTypography.body.copyWith(
                      fontWeight:
                          s == current ? FontWeight.w700 : FontWeight.w400,
                      color: s == current ? SeeUColors.accent : c.ink,
                    ),
                  ),
                  onTap: () {
                    ref.read(_collectionsSortProvider.notifier).state = s;
                    Navigator.pop(ctx);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showCreateSheet(BuildContext context, WidgetRef ref) async {
    await showSeeUBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CollectionFormSheet(
        title: 'Новая коллекция',
        submitLabel: 'Создать',
        onSubmit: (name, desc) async =>
            (await ref.read(collectionsProvider.notifier).create(name, desc)) !=
            null,
      ),
    );
  }
}

class _CollectionCard extends ConsumerWidget {
  final Collection collection;
  const _CollectionCard({required this.collection});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = context.seeuColors;

    return GestureDetector(
      // Через роут, а не MaterialPageRoute: тот же путь, по которому подборка
      // открывается из расшаренной ссылки.
      onTap: () => context.push('/collection/${collection.id}'),
      onLongPress: () {
        HapticFeedback.mediumImpact();
        _showOptions(context, ref);
      },
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: theme.cardColor,
          border: Border.all(color: c.line.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(SeeURadii.medium),
          boxShadow: SeeUShadows.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Превью — три вертикальных сегмента (обложки первых файлов,
            // заглушки-градиенты если файлов меньше).
            SizedBox(
              height: 92,
              child: _CollectionCover(collection: collection),
            ),
            // Info
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    collection.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SeeUTypography.displayXS.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        _filesCountLabel(collection.filesCount),
                        style: TextStyle(fontSize: 12, color: c.ink3),
                      ),
                      const Spacer(),
                      // Сразу видно, какая подборка отдана по ссылке.
                      Icon(
                        collection.isPublic
                            ? PhosphorIconsRegular.linkSimple
                            : PhosphorIconsRegular.lockSimple,
                        size: 12,
                        color: collection.isPublic
                            ? SeeUColors.success
                            : c.ink4,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _filesCountLabel(int count) {
    if (count == 0) return 'Пусто';
    if (count == 1) return '1 файл';
    if (count >= 2 && count <= 4) return '$count файла';
    return '$count файлов';
  }

  Future<void> _showOptions(BuildContext context, WidgetRef ref) async {
    final action = await showSeeUBottomSheet<String>(
      context: context,
      builder: (ctx) {
        final c = ctx.seeuColors;
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: SeeUColors.accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(SeeURadii.small),
                  ),
                  child: Icon(PhosphorIconsRegular.pencilSimple,
                      size: 20, color: SeeUColors.accent),
                ),
                title: Text('Переименовать',
                    style: SeeUTypography.subtitle
                        .copyWith(fontWeight: FontWeight.w600, color: c.ink)),
                onTap: () => Navigator.of(ctx).pop('edit'),
              ),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: SeeUColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(SeeURadii.small),
                  ),
                  child: const Icon(PhosphorIconsRegular.trash,
                      size: 20, color: SeeUColors.error),
                ),
                title: Text('Удалить',
                    style: SeeUTypography.subtitle.copyWith(
                        fontWeight: FontWeight.w600,
                        color: SeeUColors.error)),
                onTap: () => Navigator.of(ctx).pop('delete'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );

    if (action == 'delete' && context.mounted) {
      final confirmed = await showSeeUConfirm(
        context,
        title: 'Удалить коллекцию?',
        message:
            '«${collection.name}» будет удалена без возможности восстановления.',
        confirmLabel: 'Удалить',
        destructive: true,
        icon: PhosphorIconsRegular.trash,
      );
      if (confirmed) {
        await ref.read(collectionsProvider.notifier).delete(collection.id);
      }
    } else if (action == 'edit' && context.mounted) {
      await showSeeUBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => _CollectionFormSheet(
          title: 'Изменить',
          submitLabel: 'Сохранить',
          initialName: collection.name,
          initialDesc: collection.description,
          onSubmit: (name, desc) => ref
              .read(collectionsProvider.notifier)
              .update(collection.id, name, desc),
        ),
      );
    }
  }
}

/// Bottom sheet для создания / редактирования коллекции.
class _CollectionFormSheet extends StatefulWidget {
  final String title;
  final String submitLabel;
  final String initialName;
  final String initialDesc;
  final Future<bool> Function(String name, String desc) onSubmit;
  const _CollectionFormSheet({
    required this.title,
    required this.submitLabel,
    required this.onSubmit,
    this.initialName = '',
    this.initialDesc = '',
  });

  @override
  State<_CollectionFormSheet> createState() => _CollectionFormSheetState();
}

class _CollectionFormSheetState extends State<_CollectionFormSheet> {
  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.initialName);
  late final TextEditingController _descCtrl =
      TextEditingController(text: widget.initialDesc);
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    bool ok;
    try {
      ok = await widget.onSubmit(_nameCtrl.text.trim(), _descCtrl.text.trim());
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      return;
    }
    // Раньше провал молча закрывал лист и коллекция не появлялась/не менялась.
    setState(() => _saving = false);
    showSeeUSnackBar(context, 'Не удалось сохранить коллекцию',
        tone: SeeUTone.danger);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom +
            24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Коллекция'.toUpperCase(),
              style: SeeUTypography.kicker.copyWith(color: c.ink3)),
          const SizedBox(height: 4),
          Text(widget.title,
              style: SeeUTypography.displayS.copyWith(color: c.ink)),
          const SizedBox(height: 20),
          SeeUInput(
            controller: _nameCtrl,
            hintText: 'Название *',
            autofocus: true,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 10),
          SeeUInput(
            controller: _descCtrl,
            hintText: 'Описание (необязательно)',
            maxLines: 2,
          ),
          const SizedBox(height: 20),
          SeeUButton(
            label: _saving ? 'Сохранение…' : widget.submitLabel,
            onTap:
                (_saving || _nameCtrl.text.trim().isEmpty) ? null : _submit,
            isLoading: _saving,
            width: double.infinity,
          ),
        ],
      ),
    );
  }
}

/// Тёплые градиенты-заглушки сегментов превью, когда обложек меньше трёх.
const _segmentGradients = <List<Color>>[
  [Color(0xFF43331F), Color(0xFF2C211A)],
  [Color(0xFFB8462E), Color(0xFF6E2A18)],
  [Color(0xFF5D4530), Color(0xFF3A2C20)],
];

/// Превью коллекции — три вертикальных сегмента: обложки первых трёх файлов,
/// недостающие закрываются тёплыми градиентами-«корешками».
class _CollectionCover extends StatelessWidget {
  final Collection collection;
  const _CollectionCover({required this.collection});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final urls = collection.coverUrls.take(3).toList();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 1),
          Expanded(
            child: i < urls.length
                ? CachedNetworkImage(
                    imageUrl: urls[i],
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _gradientSegment(i, c),
                  )
                : _gradientSegment(i, c),
          ),
        ],
      ],
    );
  }

  /// Сегмент-заглушка: градиент + лёгкий блик слева, как у корешка.
  Widget _gradientSegment(int i, SeeUThemeColors c) {
    final colors = _segmentGradients[i % _segmentGradients.length];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: 0.22,
          heightFactor: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.16),
                  Colors.white.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Плитка «Новая коллекция» — пунктирная, в конце сетки.
class _NewCollectionTile extends StatelessWidget {
  final VoidCallback onTap;
  const _NewCollectionTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Tappable.scaled(
      onTap: onTap,
      child: LibDashedBorder(
        color: c.ink4,
        radius: SeeURadii.medium,
        child: SizedBox.expand(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: SeeUColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(PhosphorIconsBold.plus,
                    size: 16, color: SeeUColors.accent),
              ),
              const SizedBox(height: 8),
              Text(
                'Новая коллекция',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: c.ink2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
