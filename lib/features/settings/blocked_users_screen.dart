import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import '../../core/providers/blocks_provider.dart';

class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final async = ref.watch(blocksProvider);

    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        children: [
          SeeUGlassBar(
            titleText: 'Заблокированные',
            leading: Tappable.faded(
              onTap: () => context.pop(),
              child: SizedBox(
                width: 36,
                height: 36,
                child:
                    Icon(PhosphorIcons.caretLeft(), size: 22, color: c.ink),
              ),
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(
                  child: CircularProgressIndicator(color: SeeUColors.accent)),
              error: (e, _) => SeeUErrorState(
                error: e.toString(),
                onRetry: () => ref.read(blocksProvider.notifier).refresh(),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const SeeUEmptyState(
                    icon: PhosphorIconsRegular.prohibit,
                    title: 'Список пуст',
                    subtitle: 'Вы никого не заблокировали.',
                  );
                }
                return RefreshIndicator(
                  color: SeeUColors.accent,
                  onRefresh: () =>
                      ref.read(blocksProvider.notifier).refresh(),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => Divider(
                        height: 0.5,
                        thickness: 0.5,
                        color: c.line,
                        indent: 72,
                        endIndent: 16),
                    itemBuilder: (_, i) {
                      final u = items[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: c.surface2,
                              backgroundImage: u.avatarUrl.isNotEmpty
                                  ? CachedNetworkImageProvider(u.avatarUrl,
                                      maxWidth: 132, maxHeight: 132)
                                  : null,
                              child: u.avatarUrl.isEmpty
                                  ? Icon(PhosphorIcons.user(),
                                      color: c.ink3, size: 20)
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('@${u.username}',
                                      style: SeeUTypography.body.copyWith(
                                          fontWeight: FontWeight.w600)),
                                  if (u.fullName.isNotEmpty)
                                    Text(u.fullName,
                                        style: SeeUTypography.caption
                                            .copyWith(color: c.ink2)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            _UnblockPill(
                              onTap: () =>
                                  _unblock(context, ref, u.username),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _unblock(
      BuildContext context, WidgetRef ref, String username) async {
    final err = await ref.read(blocksProvider.notifier).unblock(username);
    if (!context.mounted) return;
    showSeeUSnackBar(
      context,
      err ?? '@$username разблокирован',
      tone: err == null ? SeeUTone.success : SeeUTone.danger,
    );
  }
}

/// Ghost hairline-pill: «Разблокировать» — не деструктив, нейтральный контур.
class _UnblockPill extends StatelessWidget {
  final VoidCallback onTap;
  const _UnblockPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Tappable.scaled(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(SeeURadii.pill),
          border: Border.all(color: c.line, width: 1),
        ),
        child: Text(
          'Разблокировать',
          style: SeeUTypography.caption
              .copyWith(color: c.ink, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
