import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Container(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.line, width: 0.5)),
              ),
              padding: const EdgeInsets.fromLTRB(4, 10, 16, 10),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: Icon(PhosphorIcons.caretLeft(), size: 22, color: c.ink),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Заблокированные',
                    style: TextStyle(
                      fontFamily: 'Fraunces',
                      fontSize: 24,
                      fontWeight: FontWeight.w400,
                      color: c.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Не удалось загрузить: $e')),
              data: (items) {
                if (items.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Вы никого не заблокировали.',
                        style: TextStyle(color: c.ink2),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () => ref.read(blocksProvider.notifier).refresh(),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: items.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 0.5, color: c.line, indent: 72, endIndent: 16),
                    itemBuilder: (_, i) {
                      final u = items[i];
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 22,
                          backgroundColor: c.surface2,
                          backgroundImage: u.avatarUrl.isNotEmpty
                              ? NetworkImage(u.avatarUrl)
                              : null,
                          child: u.avatarUrl.isEmpty
                              ? Icon(PhosphorIcons.user(), color: c.ink3)
                              : null,
                        ),
                        title: Text('@${u.username}',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(u.fullName.isNotEmpty ? u.fullName : '—',
                            style: TextStyle(color: c.ink2)),
                        trailing: TextButton(
                          onPressed: () => _unblock(context, ref, u.username),
                          child: const Text('Разблокировать'),
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

  Future<void> _unblock(BuildContext context, WidgetRef ref, String username) async {
    final err = await ref.read(blocksProvider.notifier).unblock(username);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(err ?? '@$username разблокирован'),
    ));
  }
}
