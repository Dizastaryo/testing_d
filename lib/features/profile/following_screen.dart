import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../../core/design/design.dart';
import '../../core/models/user.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';

final _followingProvider = FutureProvider.family<List<User>, String>((ref, username) async {
  final api = ref.read(apiClientProvider);
  final resp = await api.get(ApiEndpoints.userFollowing(username));
  final data = resp.data;
  final listData = data is Map && data.containsKey('data') ? data['data'] : data;
  return (listData as List)
      .map((e) => User.fromJson(e as Map<String, dynamic>))
      .toList();
});

class FollowingScreen extends ConsumerWidget {
  final String username;

  const FollowingScreen({super.key, required this.username});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final followingAsync = ref.watch(_followingProvider(username));

    return Scaffold(
      backgroundColor: SeeUColors.background,
      appBar: AppBar(
        backgroundColor: SeeUColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text('Подписки', style: SeeUTypography.subtitle),
        leading: IconButton(
          icon: Icon(PhosphorIcons.arrowLeft(), size: 22, color: SeeUColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: followingAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: SeeUColors.accent),
        ),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '!',
                style: TextStyle(
                  fontFamily: 'Fraunces',
                  fontSize: 48,
                  color: SeeUColors.textTertiary,
                ),
              ),
              const SizedBox(height: 12),
              Text('Не удалось загрузить',
                  style: SeeUTypography.body.copyWith(color: SeeUColors.textSecondary)),
              const SizedBox(height: 12),
              SeeUButton(
                label: 'Повторить',
                variant: SeeUButtonVariant.primary,
                width: 120,
                height: 44,
                onTap: () => ref.refresh(_followingProvider(username)),
              ),
            ],
          ),
        ),
        data: (users) => users.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '\u2022',
                      style: TextStyle(
                        fontFamily: 'Fraunces',
                        fontSize: 48,
                        color: SeeUColors.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Пока нет подписок',
                      style: SeeUTypography.body.copyWith(color: SeeUColors.textSecondary),
                    ),
                  ],
                ),
              )
            : AnimationLimiter(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: users.length,
                  itemBuilder: (context, index) =>
                      AnimationConfiguration.staggeredList(
                        position: index,
                        duration: const Duration(milliseconds: 375),
                        child: SlideAnimation(
                          verticalOffset: 30,
                          child: FadeInAnimation(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _FollowingUserRow(user: users[index]),
                            ),
                          ),
                        ),
                      ),
                ),
              ),
      ),
    );
  }
}

class _FollowingUserRow extends ConsumerStatefulWidget {
  final User user;

  const _FollowingUserRow({required this.user});

  @override
  ConsumerState<_FollowingUserRow> createState() => _FollowingUserRowState();
}

class _FollowingUserRowState extends ConsumerState<_FollowingUserRow> {
  late bool _isFollowing;

  @override
  void initState() {
    super.initState();
    _isFollowing = widget.user.isFollowing;
  }

  Future<void> _toggleFollow() async {
    final previous = _isFollowing;
    setState(() => _isFollowing = !_isFollowing);
    try {
      await ref.read(apiClientProvider).post(ApiEndpoints.followUser(widget.user.username));
    } catch (_) {
      if (mounted) setState(() => _isFollowing = previous);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    return Tappable.scaled(
      onTap: () => context.push('/profile/${user.username}'),
      scaleFactor: 0.97,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: SeeUColors.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          boxShadow: SeeUShadows.sm,
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundImage: user.avatarUrl != null
                  ? CachedNetworkImageProvider(user.avatarUrl!)
                  : null,
              backgroundColor: SeeUColors.textTertiary.withValues(alpha: 0.3),
              child: user.avatarUrl == null
                  ? Text(
                      user.username[0].toUpperCase(),
                      style: SeeUTypography.title.copyWith(color: Colors.white),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          user.username,
                          style: SeeUTypography.subtitle.copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (user.isVerified) ...[
                        const SizedBox(width: 4),
                        Icon(PhosphorIcons.sealCheck(PhosphorIconsStyle.fill),
                            color: SeeUColors.accent, size: 16),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user.fullName,
                    style: SeeUTypography.body.copyWith(color: SeeUColors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _isFollowing
                ? _buildPillButton('Отписаться', SeeUButtonVariant.secondary)
                : _buildPillButton('Подписаться', SeeUButtonVariant.primary),
          ],
        ),
      ),
    );
  }

  Widget _buildPillButton(String label, SeeUButtonVariant variant) {
    final isPrimary = variant == SeeUButtonVariant.primary;
    return GestureDetector(
      onTap: _toggleFollow,
      child: Container(
        height: 36,
        constraints: const BoxConstraints(minWidth: 90),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isPrimary ? SeeUColors.accent : SeeUColors.surfaceElevated,
          borderRadius: BorderRadius.circular(SeeURadii.pill),
          border: isPrimary
              ? null
              : Border.all(color: SeeUColors.borderSubtle, width: 1),
          boxShadow: isPrimary ? SeeUShadows.sm : null,
        ),
        child: Center(
          child: Text(
            label,
            style: SeeUTypography.caption.copyWith(
              color: isPrimary ? Colors.white : SeeUColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
