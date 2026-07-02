import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../../core/design/design.dart';
import '../../core/models/user.dart';
import '../../core/services/haptics.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';

/// Shared screen for followers / following lists.
/// Differences are parameterised: title, endpoint, empty-state text/icon.
enum UserListKind { followers, following }

final _usersProvider = FutureProvider.autoDispose
    .family<List<User>, ({String username, UserListKind kind})>((ref, args) async {
  final api = ref.read(apiClientProvider);
  final endpoint = args.kind == UserListKind.followers
      ? ApiEndpoints.userFollowers(args.username)
      : ApiEndpoints.userFollowing(args.username);
  final resp = await api.get(endpoint);
  final data = resp.data;
  final listData = data is Map && data.containsKey('data') ? data['data'] : data;
  return (listData as List)
      .map((e) => User.fromJson(e as Map<String, dynamic>))
      .toList();
});

class UserListScreen extends ConsumerWidget {
  final String username;
  final UserListKind kind;

  const UserListScreen({
    super.key,
    required this.username,
    required this.kind,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (username: username, kind: kind);
    final asyncUsers = ref.watch(_usersProvider(key));
    final title = kind == UserListKind.followers ? 'Подписчики' : 'Подписки';
    final emptyIcon = kind == UserListKind.followers
        ? PhosphorIconsRegular.users
        : PhosphorIconsRegular.userList;
    final emptyText = kind == UserListKind.followers
        ? 'Пока нет подписчиков'
        : 'Пока нет подписок';

    return Scaffold(
      backgroundColor: SeeUColors.background,
      body: Column(
        children: [
          SeeUGlassBar(
            titleText: title,
            kicker: '@$username',
            leading: _GlassBackButton(onTap: () => Navigator.of(context).pop()),
          ),
          Expanded(
            child: asyncUsers.when(
              loading: () => const SeeUListSkeleton(),
              error: (e, _) => SeeUErrorState(
                onRetry: () => ref.refresh(_usersProvider(key)),
              ),
              data: (users) => users.isEmpty
                  ? SeeUEmptyState(icon: emptyIcon, title: emptyText)
                  : AnimationLimiter(
                      child: ListView.builder(
                        padding: const EdgeInsets.only(top: 4, bottom: 24),
                        itemCount: users.length,
                        itemBuilder: (context, index) =>
                            AnimationConfiguration.staggeredList(
                              position: index,
                              duration: const Duration(milliseconds: 375),
                              child: SlideAnimation(
                                verticalOffset: 30,
                                child: FadeInAnimation(
                                  child: _UserRow(user: users[index]),
                                ),
                              ),
                            ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Стеклянная круглая кнопка «назад» для шапки — плоский тинт (внутри
/// уже стеклянного [SeeUGlassBar] не добавляем свой blur).
class _GlassBackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _GlassBackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Tappable.scaled(
      onTap: onTap,
      scaleFactor: 0.9,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Icon(PhosphorIcons.caretLeft(), size: 22, color: c.ink),
      ),
    );
  }
}

class _UserRow extends ConsumerStatefulWidget {
  final User user;
  const _UserRow({required this.user});

  @override
  ConsumerState<_UserRow> createState() => _UserRowState();
}

class _UserRowState extends ConsumerState<_UserRow> {
  late bool _isFollowing;

  @override
  void initState() {
    super.initState();
    _isFollowing = widget.user.isFollowing;
  }

  Future<void> _toggleFollow() async {
    SeeUHaptics.press();
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
    final c = context.seeuColors;
    // Плоская строка в стиле SeeUListRow (hairline снизу). Собрана вручную,
    // т.к. рядом с именем нужен inline sealCheck-бейдж (title там — String).
    return Tappable.faded(
      onTap: () => context.push('/profile/${user.username}'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.line, width: 0.5)),
        ),
        child: Row(
          children: [
            SeeUOnlineAvatar(
              imageUrl: user.avatarUrl,
              fallbackText: user.username,
              size: SeeUAvatarSizes.lg,
              paletteSeed: user.username.hashCode,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          user.fullName.isNotEmpty
                              ? user.fullName
                              : user.username,
                          style: SeeUTypography.subtitle
                              .copyWith(color: c.ink),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (user.isVerified) ...[
                        const SizedBox(width: 4),
                        const Icon(PhosphorIconsFill.sealCheck,
                            color: SeeUColors.accent, size: 14),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${user.username}',
                    style: SeeUTypography.kicker.copyWith(color: c.ink3),
                    maxLines: 1,
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
    return Tappable.scaled(
      onTap: _toggleFollow,
      enableHaptic: false,
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
