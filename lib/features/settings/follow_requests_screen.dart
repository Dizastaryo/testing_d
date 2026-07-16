import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/profile_badge_provider.dart';
import '../../core/providers/user_provider.dart';

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
    final api = ref.read(apiClientProvider);
    // Remove optimistically; restore on error.
    final prev = List<Map<String, dynamic>>.from(_requests);
    setState(() => _requests = _requests.where((x) => x['id'] != id).toList());
    try {
      await api.post(accept
          ? ApiEndpoints.acceptFollowRequest(id)
          : ApiEndpoints.declineFollowRequest(id));
      // Приём заявки добавляет подписчика — обновляем свой профиль, чтобы
      // followersCount не отставал. Сбрасываем и счётчик заявок в настройках.
      if (accept) {
        final myUsername = ref.read(authProvider).user?.username;
        if (myUsername != null) {
          ref.invalidate(userProfileProvider(myUsername));
        }
      }
      ref.invalidate(followRequestsCountProvider);
      if (!mounted) return;
      showSeeUSnackBar(context, accept ? 'Принято' : 'Отклонено',
          tone: SeeUTone.success);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _requests = prev);
      showSeeUSnackBar(context, 'Ошибка: ${apiErrorMessage(e)}',
          tone: SeeUTone.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        children: [
          SeeUGlassBar(
            titleText: 'Запросы на подписку',
            leading: Tappable.faded(
              onTap: () => context.pop(),
              child: SizedBox(
                width: 36,
                height: 36,
                child: Icon(PhosphorIcons.caretLeft(), size: 22, color: c.ink),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              color: SeeUColors.accent,
              child: _buildBody(c),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(SeeUThemeColors c) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: SeeUColors.accent));
    }
    if (_error != null) {
      return SeeUErrorState(error: _error, onRetry: _load);
    }
    if (_requests.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          const SeeUEmptyState(
            icon: PhosphorIconsRegular.usersThree,
            title: 'Заявок нет',
            subtitle:
                'Когда кто-то захочет подписаться на ваш закрытый профиль — заявка появится здесь.',
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _requests.length,
      separatorBuilder: (_, __) =>
          Divider(height: 0.5, thickness: 0.5, color: c.line),
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
              _RequestPill(
                label: 'Отклонить',
                primary: false,
                onTap: () => _act(r, false),
              ),
              const SizedBox(width: 8),
              _RequestPill(
                label: 'Принять',
                primary: true,
                onTap: () => _act(r, true),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Compact accept/reject pill: primary = accent fill, secondary = hairline ghost.
class _RequestPill extends StatelessWidget {
  final String label;
  final bool primary;
  final VoidCallback onTap;
  const _RequestPill(
      {required this.label, required this.primary, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Tappable.scaled(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: primary ? SeeUColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(SeeURadii.pill),
          border: primary ? null : Border.all(color: c.line, width: 1),
        ),
        child: Text(
          label,
          style: SeeUTypography.caption.copyWith(
            color: primary ? Colors.white : c.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
