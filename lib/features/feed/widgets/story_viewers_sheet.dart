import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/utils/time_format.dart';

class StoryViewersSheet extends ConsumerStatefulWidget {
  final String storyId;
  const StoryViewersSheet({super.key, required this.storyId});

  @override
  ConsumerState<StoryViewersSheet> createState() => _StoryViewersSheetState();
}

class _StoryViewersSheetState extends ConsumerState<StoryViewersSheet> {
  static const int _pageSize = 50;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  int _page = 1;
  final List<Map<String, dynamic>> _viewers = [];
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _loadFirst();
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore || !_hasMore || !_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) _loadMore();
  }

  Future<void> _loadFirst() async {
    final ok = await _fetch(page: 1, replace: true);
    if (mounted) setState(() { _loading = false; if (!ok) _error ??= 'Ошибка загрузки'; });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final next = _page + 1;
    final ok = await _fetch(page: next, replace: false);
    if (mounted) setState(() { _loadingMore = false; if (ok) _page = next; });
  }

  Future<bool> _fetch({required int page, required bool replace}) async {
    try {
      final api = ref.read(apiClientProvider);
      final r = await api.get(ApiEndpoints.storyViewers(widget.storyId),
          queryParameters: {'page': '$page', 'limit': '$_pageSize'});
      final body = r.data;
      final data = body is Map && body.containsKey('data') ? body['data'] : body;
      final list = data is List ? data.cast<Map<String, dynamic>>() : const <Map<String, dynamic>>[];
      bool hasNext = list.length >= _pageSize;
      if (body is Map && body['meta'] is Map) {
        final meta = (body['meta'] as Map).cast<String, dynamic>();
        if (meta.containsKey('has_next_page')) hasNext = meta['has_next_page'] == true;
      }
      if (mounted) setState(() { if (replace) _viewers.clear(); _viewers.addAll(list); _hasMore = hasNext; });
      return true;
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                PhosphorIcon(PhosphorIcons.eye(), color: Colors.white),
                const SizedBox(width: 8),
                Text(_loading ? 'Загружаем…' : 'Просмотры (${_viewers.length})',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
              ]),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: Colors.white12),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2)));
    if (_error != null) return Padding(padding: const EdgeInsets.all(24), child: Center(child: Text('Ошибка: $_error', style: const TextStyle(color: Colors.white70))));
    if (_viewers.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(40), child: Text('Пока никто не посмотрел', style: TextStyle(color: Colors.white60))));
    return ListView.builder(
      controller: _scrollCtrl,
      itemCount: _viewers.length + (_hasMore ? 1 : 0),
      itemBuilder: (_, i) {
        if (i >= _viewers.length) {
          return Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Center(
            child: _loadingMore ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54)) : const SizedBox.shrink()));
        }
        final v = _viewers[i];
        final user = (v['user'] as Map?)?.cast<String, dynamic>() ?? const {};
        final username = user['username']?.toString() ?? '';
        final fullName = user['full_name']?.toString() ?? '';
        final avatar = user['avatar_url']?.toString() ?? '';
        final viewedAt = DateTime.tryParse(v['viewed_at']?.toString() ?? '');
        return ListTile(
          leading: CircleAvatar(radius: 22, backgroundColor: Colors.white12,
            backgroundImage: avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
            child: avatar.isEmpty ? PhosphorIcon(PhosphorIcons.user(), color: Colors.white54, size: 20) : null),
          title: Text('@$username', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          subtitle: fullName.isEmpty ? null : Text(fullName, style: const TextStyle(color: Colors.white60, fontSize: 12)),
          trailing: viewedAt == null ? null : Text(formatRelativeTime(viewedAt), style: const TextStyle(color: Colors.white54, fontSize: 12)),
        );
      },
    );
  }
}
