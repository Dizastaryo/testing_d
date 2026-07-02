import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/api/api_client.dart';
import '../../core/config/app_config.dart';

final _statusFilterProvider = StateProvider<String>((_) => 'pending');

final _audioListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  final status = ref.watch(_statusFilterProvider);
  final r = await api.get('/admin/audio-tracks', queryParameters: {
    'status': status,
    'limit': 100,
  });
  final data = r.data is Map && r.data.containsKey('data') ? r.data['data'] : r.data;
  final items = (data as Map)['items'] as List? ?? [];
  return items.cast<Map<String, dynamic>>();
});

String _absUrl(String? url) {
  if (url == null || url.isEmpty) return '';
  if (url.startsWith('http')) return url;
  if (url.startsWith('/')) return '${AppConfig.apiOrigin}$url';
  return url;
}

class AdminAudioPage extends ConsumerWidget {
  const AdminAudioPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(_statusFilterProvider);
    final async = ref.watch(_audioListProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Треки',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
                const SizedBox(width: 16),
                Text('загруженные юзерами',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => ref.invalidate(_audioListProvider),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                for (final s in const ['pending', 'approved', 'rejected', 'all'])
                  ChoiceChip(
                    label: Text(_statusLabel(s)),
                    selected: filter == s,
                    onSelected: (v) {
                      if (v) {
                        ref.read(_statusFilterProvider.notifier).state = s;
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
                    _errorBox(e.toString(), () => ref.invalidate(_audioListProvider)),
                data: (items) {
                  if (items.isEmpty) {
                    return const Center(child: Text('Треков нет'));
                  }
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) => _AudioRow(
                          row: items[i],
                          onChanged: () => ref.invalidate(_audioListProvider)),
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
      'pending' => 'На модерации',
      'approved' => 'Одобрены',
      'rejected' => 'Отклонены',
      'all' => 'Все',
      _ => s,
    };

class _AudioRow extends ConsumerStatefulWidget {
  final Map<String, dynamic> row;
  final VoidCallback onChanged;
  const _AudioRow({required this.row, required this.onChanged});

  @override
  ConsumerState<_AudioRow> createState() => _AudioRowState();
}

class _AudioRowState extends ConsumerState<_AudioRow> {
  AudioPlayer? _player;
  bool _playing = false;

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _togglePlay(String url) async {
    _player ??= AudioPlayer();
    if (_playing) {
      await _player!.pause();
      setState(() => _playing = false);
      return;
    }
    try {
      if (_player!.processingState == ProcessingState.idle) {
        await _player!.setUrl(url);
      }
      await _player!.play();
      setState(() => _playing = true);
      _player!.playerStateStream.listen((s) {
        if (s.processingState == ProcessingState.completed) {
          if (mounted) setState(() => _playing = false);
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Не воспроизводится: $e')));
    }
  }

  Future<void> _approve() async {
    final api = ref.read(apiClientProvider);
    try {
      await api.post('/admin/audio-tracks/${widget.row['id']}/approve');
      widget.onChanged();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: ${apiErrorMessage(e)}')));
    }
  }

  Future<void> _reject() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogCtx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Причина отклонения'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'например: copyright, мат, низкое качество',
            ),
            maxLength: 200,
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(null),
                child: const Text('Отмена')),
            FilledButton(
                onPressed: () =>
                    Navigator.of(dialogCtx).pop(ctrl.text.trim()),
                child: const Text('Отклонить')),
          ],
        );
      },
    );
    if (reason == null) return;
    final api = ref.read(apiClientProvider);
    try {
      await api.post('/admin/audio-tracks/${widget.row['id']}/reject',
          data: {'reason': reason});
      widget.onChanged();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: ${apiErrorMessage(e)}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final cover = _absUrl(r['cover_url']?.toString());
    final audio = _absUrl(r['audio_url']?.toString());
    final status = r['status']?.toString() ?? '';
    final reason = r['rejection_reason']?.toString() ?? '';
    final isPending = status == 'pending';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 56,
              height: 56,
              child: cover.isEmpty
                  ? Container(
                      color: Colors.grey.shade200,
                      child: Icon(Icons.music_note,
                          color: Colors.grey.shade500),
                    )
                  : Image.network(
                      cover,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          Container(color: Colors.grey.shade200),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r['title']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(r['artist']?.toString() ?? '',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    _badge(_statusLabel(status), _statusColor(status)),
                    if ((r['genre'] as String?)?.isNotEmpty == true)
                      _badge(r['genre'] as String, Colors.grey.shade500),
                  ],
                ),
                if (reason.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('причина: $reason',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade700,
                          fontStyle: FontStyle.italic)),
                ],
                const SizedBox(height: 4),
                SelectableText('id: ${r['id']}',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        fontFamily: 'monospace')),
              ],
            ),
          ),
          if (audio.isNotEmpty)
            IconButton(
              icon: Icon(_playing
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_fill),
              iconSize: 32,
              color: const Color(0xFFFF5A3C),
              onPressed: () => _togglePlay(audio),
            ),
          const SizedBox(width: 8),
          if (isPending) ...[
            TextButton(onPressed: _reject, child: const Text('Отклонить')),
            const SizedBox(width: 4),
            FilledButton(onPressed: _approve, child: const Text('Одобрить')),
          ],
        ],
      ),
    );
  }
}

Widget _badge(String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );

Color _statusColor(String s) => switch (s) {
      'pending' => const Color(0xFFEF8C00),
      'approved' => const Color(0xFF43A047),
      'rejected' => const Color(0xFFE53935),
      _ => Colors.grey,
    };

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
