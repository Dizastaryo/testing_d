import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_client.dart';
import '../../core/config/app_config.dart';

final _reportsFilterProvider = StateProvider<String>((_) => 'pending');

final _reportsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  final status = ref.watch(_reportsFilterProvider);
  final r = await api.get('/admin/reports',
      queryParameters: {'status': status, 'limit': 100});
  final data = r.data is Map && r.data.containsKey('data') ? r.data['data'] : r.data;
  final items = (data as Map)['items'] as List? ?? [];
  return items.cast<Map<String, dynamic>>();
});

class AdminReportsPage extends ConsumerWidget {
  const AdminReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(_reportsFilterProvider);
    final async = ref.watch(_reportsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Жалобы',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => ref.invalidate(_reportsProvider),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                for (final s in const ['pending', 'actioned', 'dismissed', 'all'])
                  ChoiceChip(
                    label: Text(_statusLabel(s)),
                    selected: filter == s,
                    onSelected: (v) {
                      if (v) {
                        ref.read(_reportsFilterProvider.notifier).state = s;
                      }
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: async.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    _errorBox(e.toString(), () => ref.invalidate(_reportsProvider)),
                data: (items) {
                  if (items.isEmpty) {
                    return const Center(child: Text('Жалоб нет'));
                  }
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) => _ReportTile(
                          report: items[i],
                          onChanged: () => ref.invalidate(_reportsProvider)),
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

String _statusLabel(String s) => switch (s) {
      'pending' => 'Ожидают',
      'actioned' => 'Действие принято',
      'dismissed' => 'Отклонены',
      'all' => 'Все',
      _ => s,
    };

String _reasonLabel(String r) => switch (r) {
      'spam' => 'Спам',
      'harassment' => 'Травля',
      'illegal' => 'Незаконно',
      'nsfw' => 'NSFW',
      'self_harm' => 'Самоповреждение',
      'other' => 'Другое',
      _ => r,
    };

String _targetTypeLabel(String t) => switch (t) {
      'post' => 'пост',
      'comment' => 'комментарий',
      'story' => 'сторис',
      'user' => 'юзер',
      _ => t,
    };

/// Builds a deep link from admin → main app for the given target.
/// Returns null if there's no obvious public route (e.g. comment without
/// post_id or story whose 24h has expired).
String? _targetUrl(String type, String id, Map<String, dynamic>? preview) {
  final base = AppConfig.mainAppUrl;
  switch (type) {
    case 'post':
      return '$base/post/$id';
    case 'comment':
      final postId = preview?['post_id']?.toString();
      if (postId == null || postId.isEmpty) return null;
      return '$base/post/$postId';
    case 'user':
      final username = preview?['username']?.toString();
      if (username == null || username.isEmpty) return null;
      return '$base/u/$username';
    case 'story':
      final author = preview?['author_username']?.toString();
      if (author == null || author.isEmpty) return null;
      return '$base/u/$author';
  }
  return null;
}

/// Resolves a server-relative `/uploads/...` path to an absolute URL on the
/// API origin so the admin can show post/story media inline.
String _absMediaUrl(String url) {
  if (url.isEmpty) return '';
  if (url.startsWith('http')) return url;
  if (url.startsWith('/')) return '${AppConfig.apiOrigin}$url';
  return url;
}

class _ReportTile extends ConsumerWidget {
  final Map<String, dynamic> report;
  final VoidCallback onChanged;
  const _ReportTile({required this.report, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reporter = report['reporter'] as Map? ?? const {};
    final isPending = report['status'] == 'pending';
    final ttype = report['target_type'] as String? ?? '';
    final tid = report['target_id'] as String? ?? '';
    final preview = (report['target_preview'] as Map?)
        ?.cast<String, dynamic>();
    final targetUrl = _targetUrl(ttype, tid, preview);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF5A3C).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(_reasonLabel(report['reason'] as String? ?? ''),
                    style: const TextStyle(
                        color: Color(0xFFFF5A3C),
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
                        Text('@${reporter['username'] ?? '???'}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(width: 6),
                        Text('пожаловался на',
                            style: TextStyle(color: Colors.grey.shade700)),
                        const SizedBox(width: 6),
                        Text(_targetTypeLabel(ttype),
                            style:
                                const TextStyle(fontWeight: FontWeight.w500)),
                      ],
                    ),
                    if ((report['details'] as String?)?.isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(report['details'] as String),
                    ],
                  ],
                ),
              ),
              if (isPending) ...[
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () => _act(ref, 'dismiss'),
                  child: const Text('Отклонить'),
                ),
                FilledButton(
                  onPressed: () => _act(ref, 'actioned'),
                  child: const Text('Принять меры'),
                ),
              ] else
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(_statusLabel(report['status'] as String? ?? ''),
                      style: const TextStyle(fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (preview != null)
            _PreviewCard(type: ttype, preview: preview, targetUrl: targetUrl)
          else
            _missingTarget(ttype),
          const SizedBox(height: 8),
          Row(
            children: [
              if (targetUrl != null)
                TextButton.icon(
                  onPressed: () async {
                    final uri = Uri.parse(targetUrl);
                    await launchUrl(uri,
                        mode: LaunchMode.externalApplication);
                  },
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Открыть в SeeU'),
                ),
              const Spacer(),
              SelectableText('id: $tid',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      fontFamily: 'monospace')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _act(WidgetRef ref, String action) async {
    final api = ref.read(apiClientProvider);
    try {
      await api.post('/admin/reports/${report['id']}/$action');
      onChanged();
    } on DioException catch (e) {
      debugPrint('admin report $action failed: ${apiErrorMessage(e)}');
    }
  }
}

Widget _missingTarget(String type) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, size: 16, color: Colors.orange.shade700),
          const SizedBox(width: 6),
          Text(
            'Цель ($type) удалена или недоступна',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
        ],
      ),
    );

class _PreviewCard extends StatelessWidget {
  final String type;
  final Map<String, dynamic> preview;
  final String? targetUrl;
  const _PreviewCard(
      {required this.type, required this.preview, required this.targetUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300, width: 0.5),
      ),
      child: switch (type) {
        'post' => _postPreview(preview),
        'comment' => _commentPreview(preview),
        'story' => _storyPreview(preview),
        'user' => _userPreview(preview),
        _ => const SizedBox.shrink(),
      },
    );
  }

  Widget _postPreview(Map<String, dynamic> p) {
    final media = _absMediaUrl(p['media_url']?.toString() ?? '');
    final mediaType = p['media_type']?.toString() ?? 'image';
    final caption = p['caption']?.toString() ?? '';
    final author = p['author_username']?.toString() ?? '';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 80,
            height: 80,
            child: media.isEmpty
                ? Container(color: Colors.grey.shade300)
                : (mediaType == 'video'
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          Container(color: Colors.black87),
                          const Center(
                              child: Icon(Icons.play_arrow,
                                  color: Colors.white, size: 36)),
                        ],
                      )
                    : Image.network(
                        media,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Container(color: Colors.grey.shade300),
                      )),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('@$author',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                caption.isEmpty ? '— без подписи —' : caption,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: caption.isEmpty
                      ? Colors.grey.shade500
                      : Colors.grey.shade800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _commentPreview(Map<String, dynamic> p) {
    final text = p['text']?.toString() ?? '';
    final author = p['author_username']?.toString() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('@$author', style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(text,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13)),
      ],
    );
  }

  Widget _storyPreview(Map<String, dynamic> p) {
    final media = _absMediaUrl(p['media_url']?.toString() ?? '');
    final mediaType = p['media_type']?.toString() ?? 'image';
    final author = p['author_username']?.toString() ?? '';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 60,
            height: 100,
            child: media.isEmpty
                ? Container(color: Colors.grey.shade300)
                : (mediaType == 'video'
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          Container(color: Colors.black87),
                          const Center(
                              child: Icon(Icons.play_arrow,
                                  color: Colors.white, size: 32)),
                        ],
                      )
                    : Image.network(
                        media,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Container(color: Colors.grey.shade300),
                      )),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('@$author',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Сторис ($mediaType) истекает через 24 часа после создания',
                  style:
                      TextStyle(color: Colors.grey.shade700, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _userPreview(Map<String, dynamic> p) {
    final username = p['username']?.toString() ?? '';
    final fullName = p['full_name']?.toString() ?? '';
    final avatar = _absMediaUrl(p['avatar_url']?.toString() ?? '');
    return Row(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: Colors.grey.shade200,
          backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
          child: avatar.isEmpty
              ? Icon(Icons.person, color: Colors.grey.shade500)
              : null,
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('@$username',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            if (fullName.isNotEmpty)
              Text(fullName,
                  style:
                      TextStyle(color: Colors.grey.shade700, fontSize: 13)),
          ],
        ),
      ],
    );
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
