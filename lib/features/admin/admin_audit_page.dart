import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';

final _actionFilterProvider = StateProvider<String>((_) => '');

final _auditProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  final action = ref.watch(_actionFilterProvider);
  final r = await api.get('/admin/audit-log', queryParameters: {
    'limit': 200,
    if (action.isNotEmpty) 'action': action,
  });
  final data = r.data is Map && r.data.containsKey('data') ? r.data['data'] : r.data;
  final items = (data as Map)['items'] as List? ?? [];
  return items.cast<Map<String, dynamic>>();
});

class AdminAuditPage extends ConsumerWidget {
  const AdminAuditPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(_actionFilterProvider);
    final async = ref.watch(_auditProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Аудит',
                    style: TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w600)),
                const SizedBox(width: 16),
                Text('кто что делал',
                    style:
                        TextStyle(color: Colors.grey.shade600, fontSize: 14)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => ref.invalidate(_auditProvider),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                for (final a in const [
                  ('', 'Все'),
                  ('user.ban', 'Баны'),
                  ('user.unban', 'Разбаны'),
                  ('user.delete', 'Удаления'),
                  ('report.dismissed', 'Отклонены'),
                  ('report.actioned', 'Меры приняты'),
                ])
                  ChoiceChip(
                    label: Text(a.$2),
                    selected: filter == a.$1,
                    onSelected: (v) {
                      if (v) {
                        ref.read(_actionFilterProvider.notifier).state = a.$1;
                      }
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: async.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    _errorBox(e.toString(), () => ref.invalidate(_auditProvider)),
                data: (items) {
                  if (items.isEmpty) {
                    return const Center(child: Text('Записей нет'));
                  }
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) => _AuditTile(row: items[i]),
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

String _actionLabel(String a) => switch (a) {
      'user.ban' => 'Бан',
      'user.unban' => 'Разбан',
      'user.delete' => 'Удаление',
      'report.dismissed' => 'Жалоба отклонена',
      'report.actioned' => 'Жалоба принята',
      _ => a,
    };

Color _actionColor(String a) {
  if (a.startsWith('user.ban') || a == 'user.delete') return const Color(0xFFE53935);
  if (a.startsWith('user.unban') || a == 'report.dismissed') return const Color(0xFF43A047);
  if (a == 'report.actioned') return const Color(0xFFFF5A3C);
  return Colors.grey.shade700;
}

class _AuditTile extends StatelessWidget {
  final Map<String, dynamic> row;
  const _AuditTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final admin = (row['admin'] as Map?)?.cast<String, dynamic>() ?? const {};
    final action = row['action'] as String? ?? '';
    final tt = row['target_type'] as String? ?? '';
    final tid = row['target_id'] as String? ?? '';
    final meta = (row['metadata'] as Map?)?.cast<String, dynamic>();
    final dt = DateTime.tryParse(row['created_at']?.toString() ?? '');
    final timeStr = dt != null
        ? '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} '
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
        : '';
    final color = _actionColor(action);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(timeStr,
                style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 12,
                    fontFamily: 'monospace')),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(_actionLabel(action),
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w500,
                    fontSize: 12)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('@${admin['username'] ?? '???'}',
                        style:
                            const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    Text('$tt:',
                        style: TextStyle(color: Colors.grey.shade700)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: SelectableText(
                        tid,
                        maxLines: 1,
                        style: TextStyle(
                            color: Colors.grey.shade600,
                            fontFamily: 'monospace',
                            fontSize: 12),
                      ),
                    ),
                  ],
                ),
                if (meta != null && meta.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(_metaToString(meta),
                      style: TextStyle(
                          color: Colors.grey.shade700, fontSize: 12)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _metaToString(Map<String, dynamic> m) {
    final parts = <String>[];
    m.forEach((k, v) {
      if (v == null) return;
      final s = v.toString();
      if (s.isEmpty) return;
      parts.add('$k: $s');
    });
    return parts.join(' · ');
  }
}

Widget _errorBox(String msg, VoidCallback retry) => Card(
      color: const Color(0xFFFFEFEC),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(child: Text('Ошибка: $msg')),
            TextButton(onPressed: retry, child: const Text('Повторить')),
          ],
        ),
      ),
    );
