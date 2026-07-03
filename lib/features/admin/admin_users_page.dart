import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';

class _UsersFilter {
  final String query;
  final bool onlyBanned;
  final bool onlyAdmins;
  const _UsersFilter({this.query = '', this.onlyBanned = false, this.onlyAdmins = false});
}

final _usersFilterProvider =
    StateProvider<_UsersFilter>((_) => const _UsersFilter());

final _usersProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  final f = ref.watch(_usersFilterProvider);
  final r = await api.get('/admin/users', queryParameters: {
    if (f.query.isNotEmpty) 'q': f.query,
    if (f.onlyBanned) 'banned': 'true',
    if (f.onlyAdmins) 'admins': 'true',
    'limit': 100,
  });
  final data = r.data is Map && r.data.containsKey('data') ? r.data['data'] : r.data;
  final items = (data as Map)['items'] as List? ?? [];
  return items.cast<Map<String, dynamic>>();
});

class AdminUsersPage extends ConsumerStatefulWidget {
  const AdminUsersPage({super.key});

  @override
  ConsumerState<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends ConsumerState<AdminUsersPage> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(_usersFilterProvider);
    final async = ref.watch(_usersProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Юзеры',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                icon: const Icon(PhosphorIconsRegular.arrowClockwise),
                onPressed: () => ref.invalidate(_usersProvider),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 320,
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Поиск: username, имя или телефон',
                    prefixIcon: Icon(PhosphorIconsRegular.magnifyingGlass),
                  ),
                  onSubmitted: (v) {
                    ref.read(_usersFilterProvider.notifier).state =
                        _UsersFilter(query: v.trim(), onlyBanned: filter.onlyBanned, onlyAdmins: filter.onlyAdmins);
                  },
                ),
              ),
              const SizedBox(width: 12),
              FilterChip(
                label: const Text('Только забаненные'),
                selected: filter.onlyBanned,
                onSelected: (v) => ref.read(_usersFilterProvider.notifier).state =
                    _UsersFilter(query: filter.query, onlyBanned: v, onlyAdmins: filter.onlyAdmins),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Только админы'),
                selected: filter.onlyAdmins,
                onSelected: (v) => ref.read(_usersFilterProvider.notifier).state =
                    _UsersFilter(query: filter.query, onlyBanned: filter.onlyBanned, onlyAdmins: v),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _errorBox(e.toString()),
              data: (users) {
                if (users.isEmpty) {
                  return const Center(child: Text('Никого не нашли'));
                }
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListView.separated(
                    itemCount: users.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => _UserRow(
                      user: users[i],
                      onChanged: () => ref.invalidate(_usersProvider),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBox(String msg) => Card(
        color: const Color(0xFFFFEFEC),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Ошибка: $msg'),
        ),
      );
}

class _UserRow extends ConsumerWidget {
  final Map<String, dynamic> user;
  final VoidCallback onChanged;
  const _UserRow({required this.user, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBanned = user['is_banned'] == true;
    final isAdmin = user['is_admin'] == true;
    final avatar = user['avatar_url'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.grey.shade200,
            backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('@${user['username']}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (isAdmin) ...[
                      const SizedBox(width: 6),
                      _badge('admin', const Color(0xFFFF5A3C)),
                    ],
                    if (isBanned) ...[
                      const SizedBox(width: 6),
                      _badge('banned', const Color(0xFFE74C3C)),
                    ],
                  ],
                ),
                Text(user['full_name'] as String? ?? '',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
              ],
            ),
          ),
          Expanded(
              flex: 2,
              child: Text(user['phone'] as String? ?? '',
                  style: const TextStyle(fontFamily: 'monospace'))),
          Expanded(
            flex: 2,
            child: Text(
              'постов: ${user['posts_count'] ?? 0} · подписчики: ${user['followers_count'] ?? 0}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          if (isBanned)
            TextButton(
              onPressed: () => _toggle(ref, ban: false),
              child: const Text('Разбанить'),
            )
          else
            TextButton(
              onPressed: () => _confirmBan(context, ref),
              child: const Text('Забанить'),
            ),
          IconButton(
            icon: const Icon(PhosphorIconsRegular.trash, color: Color(0xFFE74C3C)),
            tooltip: 'Удалить аккаунт',
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
    );
  }

  Widget _badge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
      );

  Future<void> _confirmBan(BuildContext context, WidgetRef ref) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Забанить @${user['username']}?'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(
            labelText: 'Причина (видна только админам)',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE74C3C)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Забанить'),
          ),
        ],
      ),
    );
    if (ok == true) await _toggle(ref, ban: true, reason: reasonCtrl.text);
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Удалить @${user['username']} безвозвратно?'),
        content: const Text(
            'Все посты, истории, чаты, лайки и подписки этого юзера будут стёрты. Восстановить нельзя.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE74C3C)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final api = ref.read(apiClientProvider);
    try {
      await api.delete('/admin/users/${user['id']}');
      onChanged();
    } on DioException catch (e) {
      debugPrint('admin delete user failed: ${apiErrorMessage(e)}');
    }
  }

  Future<void> _toggle(WidgetRef ref, {required bool ban, String reason = ''}) async {
    final api = ref.read(apiClientProvider);
    try {
      await api.post('/admin/users/${user['id']}/${ban ? 'ban' : 'unban'}',
          data: ban ? {'reason': reason} : null);
      onChanged();
    } on DioException catch (e) {
      debugPrint('admin ban toggle failed: ${apiErrorMessage(e)}');
    }
  }
}
