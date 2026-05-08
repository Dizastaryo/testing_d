import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';

/// Inbox of pending follow requests addressed to the current user.
/// Only relevant when the user has a private profile.
class FollowRequestsScreen extends ConsumerStatefulWidget {
  const FollowRequestsScreen({super.key});

  @override
  ConsumerState<FollowRequestsScreen> createState() =>
      _FollowRequestsScreenState();
}

class _FollowRequestsScreenState
    extends ConsumerState<FollowRequestsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _requests = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final r = await api.get(ApiEndpoints.myFollowRequests);
      final data = r.data is Map && (r.data as Map).containsKey('data')
          ? r.data['data']
          : r.data;
      final list = data is List ? data : <dynamic>[];
      if (mounted) {
        setState(() {
          _requests = list.cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _act(Map<String, dynamic> r, bool accept) async {
    final id = r['id']?.toString();
    if (id == null || id.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final api = ref.read(apiClientProvider);
    // Remove optimistically; restore on error.
    final prev = List<Map<String, dynamic>>.from(_requests);
    setState(() => _requests = _requests.where((x) => x['id'] != id).toList());
    try {
      await api.post(accept
          ? ApiEndpoints.acceptFollowRequest(id)
          : ApiEndpoints.declineFollowRequest(id));
      messenger.showSnackBar(SnackBar(
        content: Text(accept ? 'Принято' : 'Отклонено'),
      ));
    } on DioException catch (e) {
      setState(() => _requests = prev);
      messenger.showSnackBar(
          SnackBar(content: Text('Ошибка: ${apiErrorMessage(e)}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(PhosphorIcons.arrowLeft(), color: c.ink),
          onPressed: () => context.pop(),
        ),
        title: const Text('Запросы на подписку'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: SeeUColors.accent,
        child: _buildBody(c),
      ),
    );
  }

  Widget _buildBody(SeeUThemeColors c) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.all(40),
            child: Center(
              child: Text('Не удалось загрузить: $_error',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.ink2)),
            ),
          ),
        ],
      );
    }
    if (_requests.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 80, 32, 32),
            child: Column(
              children: [
                Icon(PhosphorIcons.usersThree(),
                    size: 56, color: c.line),
                const SizedBox(height: 16),
                Text('Заявок нет',
                    style:
                        SeeUTypography.subtitle.copyWith(color: c.ink2)),
                const SizedBox(height: 6),
                Text(
                  'Когда кто-то захочет подписаться на ваш закрытый профиль — заявка появится здесь.',
                  textAlign: TextAlign.center,
                  style: SeeUTypography.caption.copyWith(color: c.ink3),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _requests.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: c.line),
      itemBuilder: (_, i) {
        final r = _requests[i];
        final user = (r['requester'] as Map?)?.cast<String, dynamic>() ??
            const {};
        final username = user['username']?.toString() ?? '';
        final fullName = user['full_name']?.toString() ?? '';
        final avatar = user['avatar_url']?.toString() ?? '';
        return Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: c.surface2,
                backgroundImage: avatar.isNotEmpty
                    ? CachedNetworkImageProvider(avatar)
                    : null,
                child: avatar.isEmpty
                    ? Icon(PhosphorIcons.user(), color: c.ink3, size: 20)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('@$username',
                        style: SeeUTypography.body
                            .copyWith(fontWeight: FontWeight.w600)),
                    if (fullName.isNotEmpty)
                      Text(fullName,
                          style: SeeUTypography.caption
                              .copyWith(color: c.ink2)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => _act(r, false),
                child: const Text('Отклонить'),
              ),
              const SizedBox(width: 4),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: SeeUColors.accent),
                onPressed: () => _act(r, true),
                child: const Text('Принять'),
              ),
            ],
          ),
        );
      },
    );
  }
}
