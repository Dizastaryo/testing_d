import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/providers/user_provider.dart';
import 'create_highlight_sheet.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/blocks_provider.dart';
import '../../core/providers/nearby_devices_provider.dart';
import '../../core/providers/story_provider.dart';
import '../../widgets/report_sheet.dart';
import '../../widgets/verified_badge.dart';
import '../feed/widgets/stories_row.dart';
import '../../core/models/user.dart';
import '../../core/models/post.dart';
import '../post/profile_posts_feed.dart';
import '../../core/models/highlight.dart';
import '../../core/models/story.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  final String? username;

  const ProfileScreen({super.key, this.username});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedTab = 0;
  // VIDEO-4: switch default tab to «Videos» (idx=1) once when we see this
  // is a channel-user. Toggle ensures we only do it on first load.
  bool _appliedChannelDefaultTab = false;
  // PROFILE-1: реальный counter из `nearbyDevicesCountProvider`. State
  // обновляется пока scanner_screen активно сканирует — если scanner не открыт
  // последние секунды, count останется 0 (BLE-stream живёт только пока
  // FlutterBluePlus.startScan вызван).
  int get _nearbyCount => ref.watch(nearbyDevicesCountProvider);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1) {
        final username = _resolveUsername();
        ref.read(userProfileProvider(username).notifier).loadSavedPosts();
      }
      if (mounted) {
        setState(() => _selectedTab = _tabController.index);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showOtherProfileMenu(BuildContext context, User user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(PhosphorIcons.flag(), color: SeeUColors.like),
                title: const Text('Пожаловаться'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  showReportSheet(
                    context: context,
                    ref: ref,
                    targetType: 'user',
                    targetId: user.id,
                  );
                },
              ),
              ListTile(
                leading: Icon(PhosphorIcons.shieldWarning(),
                    color: SeeUColors.accent),
                title: const Text('Ограничить'),
                subtitle: const Text(
                  'Его комменты будут видны только ему и вам',
                  style: TextStyle(fontSize: 11),
                ),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _restrictUser(context, user);
                },
              ),
              ListTile(
                leading: const Icon(Icons.block, color: Color(0xFFE74C3C)),
                title: const Text('Заблокировать',
                    style: TextStyle(color: Color(0xFFE74C3C))),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _confirmBlock(context, user);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmBlock(BuildContext context, User user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Заблокировать @${user.username}?'),
        content: const Text(
          'Вы перестанете видеть посты и истории этого пользователя, '
          'а он — ваши. Подписки удалятся в обе стороны. Чаты закроются.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE74C3C),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Заблокировать'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final err = await ref.read(blocksProvider.notifier).block(user.username);
    if (!context.mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось заблокировать: $err')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('@${user.username} заблокирован')),
      );
      // Refresh profile so the follow state is gone.
      ref.invalidate(userProfileProvider(user.username));
    }
  }

  /// PROFILE-4: ограничить юзера — его комменты будут видны только ему
  /// и автору поста. Подтверждение через простой dialog (менее агрессивно
  /// чем block — без длинного предупреждения).
  Future<void> _restrictUser(BuildContext context, User user) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.post('/users/${user.username}/restrict');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('@${user.username} ограничен'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось ограничить: $e')),
      );
    }
  }

  void _showCreateSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(PhosphorIcons.camera(), color: SeeUColors.accent),
                title: const Text('Создать пост'),
                onTap: () { Navigator.pop(context); context.push('/post/create'); },
              ),
              ListTile(
                leading: Icon(PhosphorIcons.filmStrip(), color: SeeUColors.accent),
                title: const Text('Создать рилс'),
                onTap: () { Navigator.pop(context); context.push('/story/create'); },
              ),
              ListTile(
                leading: Icon(PhosphorIcons.plusCircle(), color: SeeUColors.accent),
                title: const Text('Создать историю'),
                onTap: () { Navigator.pop(context); context.push('/story/create'); },
              ),
              ListTile(
                leading: Icon(PhosphorIconsBold.textT, color: SeeUColors.accent),
                title: const Text('Текстовая история'),
                onTap: () { Navigator.pop(context); context.push('/story/create-text'); },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _resolveUsername() {
    return widget.username ??
        ref.read(authProvider).user?.username ??
        'unknown';
  }

  @override
  Widget build(BuildContext context) {
    final username = _resolveUsername();
    final profileState = ref.watch(userProfileProvider(username));
    final authState = ref.watch(authProvider);
    final isOwnProfile = authState.user != null &&
        (widget.username == null ||
            widget.username == authState.user?.username);

    if (profileState.isLoading && profileState.user == null) {
      final c = context.seeuColors;
      return Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          backgroundColor: c.bg,
          elevation: 0,
          title: Text(username, style: SeeUTypography.subtitle),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: SeeUColors.accent),
        ),
      );
    }

    final user = profileState.user ??
        User(
            id: '',
            username: username,
            fullName: '',
            createdAt: DateTime.now());

    final c = context.seeuColors;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
              child: Row(
                children: [
                  if (widget.username != null)
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Icon(PhosphorIcons.arrowLeft(),
                            size: 22, color: c.ink),
                      ),
                    ),
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            '@${user.username}',
                            overflow: TextOverflow.ellipsis,
                            style: SeeUTypography.mono.copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: c.ink,
                            ),
                          ),
                        ),
                        if (user.isVerified) const VerifiedBadge(size: 14),
                      ],
                    ),
                  ),
                  if (!isOwnProfile)
                    _HeaderIconButton(
                      icon: PhosphorIcons.dotsThreeOutline(),
                      onTap: () => _showOtherProfileMenu(context, user),
                    ),
                  if (isOwnProfile)
                    Row(
                      children: [
                        // Create content button
                        _HeaderIconButton(
                          icon: PhosphorIcons.plusCircle(),
                          onTap: () => _showCreateSheet(context),
                        ),
                        const SizedBox(width: 8),
                        // BLE button with "Рядом · N" badge when nearby > 0
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            _HeaderIconButton(
                              icon: PhosphorIcons.bluetoothConnected(),
                              onTap: () => context.push('/settings/chip'),
                            ),
                            if (_nearbyCount > 0)
                              Positioned(
                                top: -4,
                                right: -6,
                                child: IgnorePointer(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: SeeUColors.success,
                                      borderRadius:
                                          BorderRadius.circular(SeeURadii.pill),
                                      border: Border.all(
                                          color: c.bg,
                                          width: 1.5),
                                    ),
                                    child: Text(
                                      'Рядом · $_nearbyCount',
                                      style: const TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 8),
                        _HeaderIconButton(
                          icon: PhosphorIcons.gearSix(),
                          onTap: () => context.push('/settings'),
                        ),
                      ],
                    ),
                ],
              ),
            ),

            // ── Scrollable body ─────────────────────────────────────
            Expanded(
              child: NestedScrollView(
                headerSliverBuilder: (context, innerBoxIsScrolled) => [
                  SliverToBoxAdapter(
                    child: _buildProfileBody(
                        context, user, isOwnProfile, profileState),
                  ),
                ],
                body: Column(
                  children: [
                    // ── Tabs ──────────────────────────────────────────
                    Container(
                      decoration: BoxDecoration(
                        border: Border.symmetric(
                          horizontal: BorderSide(
                            color: c.line,
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          _TabButton(
                            icon: PhosphorIcons.squaresFour(),
                            isActive: _selectedTab == 0,
                            onTap: () => _tabController.animateTo(0),
                          ),
                          _TabButton(
                            icon: PhosphorIcons.filmStrip(),
                            isActive: _selectedTab == 1,
                            onTap: () => _tabController.animateTo(1),
                          ),
                          _TabButton(
                            icon: PhosphorIcons.folderSimple(),
                            isActive: _selectedTab == 2,
                            onTap: () => _tabController.animateTo(2),
                          ),
                          _TabButton(
                            icon: PhosphorIcons.heart(),
                            isActive: _selectedTab == 3,
                            onTap: () => _tabController.animateTo(3),
                          ),
                        ],
                      ),
                    ),
                    // ── Grid ──────────────────────────────────────────
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          // Приватный профиль + viewer не подписан → бэк
                          // вернул 403 на /posts. Показываем locked-stub
                          // вместо пустой сетки.
                          profileState.isLocked
                              ? const _PrivateContent()
                              : _PostsGrid(posts: profileState.posts),
                          const Center(child: Text('Видео', style: TextStyle(color: Colors.grey))),
                          const Center(child: Text('Файлы', style: TextStyle(color: Colors.grey))),
                          isOwnProfile
                              ? _PostsGrid(posts: profileState.savedPosts)
                              : const _PrivateContent(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileBody(
    BuildContext context,
    User user,
    bool isOwnProfile,
    UserProfileState profileState,
  ) {
    final c = context.seeuColors;
    final storyState = ref.watch(storyProvider);
    final userStoryGroup = storyState.storyGroups
        .where((g) => g.author.username == user.username)
        .toList();
    final hasStories = userStoryGroup.isNotEmpty;
    final hasUnseenStories = hasStories && !userStoryGroup.first.allSeen;

    // VIDEO-4: channel-user default tab = Videos. Меняем один раз когда
    // профиль впервые подъехал. Не дёргаем при self-tab-switch потом.
    if (user.isChannel && !_appliedChannelDefaultTab) {
      _appliedChannelDefaultTab = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _tabController.index == 0) {
          _tabController.animateTo(1);
        }
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // VIDEO-4: channel-banner hero. Рендерится только когда юзер задал
        // channel_banner_url. 16:9 cover-image + gradient-overlay снизу для
        // чтения username при necessary scroll'е.
        if (user.channelBannerUrl.isNotEmpty)
          AspectRatio(
            aspectRatio: 16 / 6,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: user.channelBannerUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: c.surface2),
                  errorWidget: (_, __, ___) =>
                      Container(color: c.surface2),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.35),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        // ── Hero: avatar + stats ──────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar with story ring
              GestureDetector(
                onTap: hasStories
                    ? () {
                        final groupIndex = storyState.storyGroups
                            .indexOf(userStoryGroup.first);
                        Navigator.of(context).push(
                          PageRouteBuilder(
                            pageBuilder: (ctx, anim, secAnim) =>
                                StoryViewerRoute(
                              groups: storyState.storyGroups,
                              initialGroupIndex: groupIndex,
                              currentUserId: ref.read(authProvider).user?.id,
                            ),
                            transitionsBuilder:
                                (ctx, anim, secAnim, child) =>
                                    FadeTransition(
                                        opacity: anim, child: child),
                            transitionDuration:
                                const Duration(milliseconds: 200),
                          ),
                        );
                      }
                    : null,
                child: _buildAvatar(user,
                    hasStories: hasStories,
                    hasUnseenStories: hasUnseenStories),
              ),
              const SizedBox(width: 18),
              // Stats
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _StatItem(
                        count: user.postsCount, label: 'посты'),
                    GestureDetector(
                      onTap: () => context
                          .push('/profile/${user.username}/followers'),
                      child: _StatItem(
                          count: user.followersCount,
                          label: 'подписчики'),
                    ),
                    GestureDetector(
                      onTap: () => context
                          .push('/profile/${user.username}/following'),
                      child: _StatItem(
                          count: user.followingCount,
                          label: 'подписки'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── Bio ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user.fullName.isNotEmpty ? user.fullName : user.username,
                style: SeeUTypography.displayS,
              ),
              // PROFILE-6: presence — «в сети» зелёным или «был X мин назад».
              // Пустая строка означает hidden or unknown → ничего не рендерим.
              if (user.presenceLabel().isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (user.isOnline) ...[
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF4CAF50),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      user.presenceLabel(),
                      style: SeeUTypography.caption.copyWith(
                        color: user.isOnline
                            ? const Color(0xFF4CAF50)
                            : c.ink2,
                        fontSize: 12,
                        fontWeight:
                            user.isOnline ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ],
              if (user.bio != null && user.bio!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  user.bio!,
                  style: SeeUTypography.body.copyWith(
                    color: c.ink2,
                    height: 1.4,
                    fontSize: 13,
                  ),
                ),
              ],
              // VIDEO-4: channel about — отдельный блок под bio, более
              // длинный и форматированный (multi-line, до 2000 chars).
              if (user.channelAbout.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(SeeURadii.card),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(PhosphorIconsBold.filmStrip,
                              size: 14, color: SeeUColors.accent),
                          const SizedBox(width: 6),
                          Text('О канале',
                              style: SeeUTypography.caption.copyWith(
                                color: SeeUColors.accent,
                                fontWeight: FontWeight.w700,
                              )),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        user.channelAbout,
                        style: SeeUTypography.body.copyWith(
                          color: c.ink,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (user.website != null && user.website!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  user.website!,
                  style: SeeUTypography.caption.copyWith(
                    color: SeeUColors.accent,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),

        // ── Action buttons ─────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
          child: isOwnProfile
              ? _OwnProfileButtons(user: user)
              : _OtherProfileButtons(user: user),
        ),

        // ── Highlights ─────────────────────────────────────────────
        if (profileState.highlights.isNotEmpty || isOwnProfile) ...[
          _HighlightsRow(
            highlights: profileState.highlights,
            currentUserId: ref.read(authProvider).user?.id,
            isOwnProfile: isOwnProfile,
            username: user.username,
          ),
          const SizedBox(height: 4),
        ],
      ],
    );
  }

  Widget _buildAvatar(User user,
      {bool hasStories = false, bool hasUnseenStories = false}) {
    final c = context.seeuColors;
    const double size = 84;
    const double ringPad = 2.5;
    const double innerBorder = 3;

    Widget avatarImage = ClipOval(
      child: user.avatarUrl != null
          ? CachedNetworkImage(
              imageUrl: user.avatarUrl!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              placeholder: (_, __) =>
                  Container(color: c.line),
              errorWidget: (_, __, ___) => _avatarPlaceholder(user, size),
            )
          : _avatarPlaceholder(user, size),
    );

    // Inner white border ring
    Widget withBorder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c.surface,
        border: Border.all(
          color: c.bg,
          width: innerBorder,
        ),
      ),
      child: ClipOval(child: avatarImage),
    );

    if (hasUnseenStories || hasStories) {
      // Conic-gradient story ring via CustomPaint
      return SizedBox(
        width: size + ringPad * 2 + 2,
        height: size + ringPad * 2 + 2,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size(size + ringPad * 2 + 2, size + ringPad * 2 + 2),
              painter: _StoryRingPainter(seen: !hasUnseenStories),
            ),
            withBorder,
          ],
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: c.line, width: 1),
      ),
      child: ClipOval(child: avatarImage),
    );
  }

  Widget _avatarPlaceholder(User user, double size) {
    final c = context.seeuColors;
    return Container(
      width: size,
      height: size,
      color: c.ink3.withValues(alpha: 0.3),
      child: Center(
        child: Text(
          user.username[0].toUpperCase(),
          style: const TextStyle(
            fontFamily: 'Fraunces',
            fontSize: 32,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

}

// ── Story ring painter (conic-gradient approximation) ──────────────────────

class _StoryRingPainter extends CustomPainter {
  final bool seen;

  const _StoryRingPainter({required this.seen});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..shader = seen
          ? const LinearGradient(
              colors: [SeeUColors.textQuaternary, SeeUColors.textQuaternary],
            ).createShader(rect)
          : const SweepGradient(
              colors: [
                Color(0xFFFFB547),
                Color(0xFFFF5A3C),
                Color(0xFFC04CFD),
                Color(0xFFFFB547),
              ],
              stops: [0.0, 0.33, 0.66, 1.0],
            ).createShader(rect);

    canvas.drawOval(
      Rect.fromLTWH(1.25, 1.25, size.width - 2.5, size.height - 2.5),
      paint,
    );
  }

  @override
  bool shouldRepaint(_StoryRingPainter old) => old.seen != seen;
}

// ── Header icon button ─────────────────────────────────────────────────────

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _HeaderIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: c.surface,
          shape: BoxShape.circle,
          border: Border.all(color: c.line, width: 0.5),
        ),
        child: Center(
          child: Icon(icon, size: 18, color: c.ink),
        ),
      ),
    );
  }
}

// ── Tab button with bottom-border indicator ────────────────────────────────

class _TabButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _TabButton(
      {required this.icon, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isActive
                    ? c.ink
                    : Colors.transparent,
                width: 1.5,
              ),
            ),
          ),
          child: Center(
            child: Icon(
              icon,
              size: 20,
              color: isActive
                  ? c.ink
                  : c.ink3,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Own-profile action buttons ─────────────────────────────────────────────

class _OwnProfileButtons extends StatelessWidget {
  final User user;

  const _OwnProfileButtons({required this.user});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            label: 'Редактировать',
            onTap: () => context.push('/profile/edit'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ActionButton(
            label: 'Поделиться',
            onTap: () {
              Clipboard.setData(ClipboardData(
                  text: 'https://seeu.app/profile/${user.username}'));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Ссылка на профиль скопирована')),
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        _ActionIconButton(
          icon: PhosphorIcons.userPlus(),
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Скоро')),
            );
          },
        ),
      ],
    );
  }
}

// ── Other-profile action buttons ───────────────────────────────────────────

class _OtherProfileButtons extends ConsumerWidget {
  final User user;

  const _OtherProfileButtons({required this.user});

  Future<void> _toggleFollow(BuildContext context, WidgetRef ref) async {
    final err = await ref
        .read(userProfileProvider(user.username).notifier)
        .toggleFollow();
    if (err != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Future<void> _unblock(BuildContext context, WidgetRef ref) async {
    final err = await ref.read(blocksProvider.notifier).unblock(user.username);
    if (!context.mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось разблокировать: $err')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('@${user.username} разблокирован')),
    );
    ref.invalidate(userProfileProvider(user.username));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBlocked = ref.watch(blocksProvider).maybeWhen(
          data: (items) => items.any((b) => b.username == user.username),
          orElse: () => false,
        );

    if (isBlocked) {
      return _ActionButton(
        label: 'Разблокировать',
        onTap: () => _unblock(context, ref),
      );
    }

    // Три состояния для приватных профилей: подписан / запрос-отправлен / нет.
    // Для публичных — только подписан / не подписан (pending не возникает).
    final Widget followBtn;
    if (user.isFollowing) {
      followBtn = _ActionButton(
        label: 'Отписаться',
        onTap: () => _toggleFollow(context, ref),
      );
    } else if (user.hasPendingFollowRequest) {
      followBtn = _ActionButton(
        label: 'Запрос отправлен',
        onTap: () => _toggleFollow(context, ref),
      );
    } else {
      followBtn = _ActionButton(
        label: 'Подписаться',
        isPrimary: true,
        onTap: () => _toggleFollow(context, ref),
      );
    }

    return Row(
      children: [
        Expanded(child: followBtn),
        const SizedBox(width: 8),
        Expanded(
          child: _ActionButton(
            label: 'Сообщение',
            onTap: () => context.push('/chat/${user.id}'),
          ),
        ),
      ],
    );
  }
}

// ── Shared action button components ───────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool isPrimary;

  const _ActionButton({
    required this.label,
    this.onTap,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: isPrimary ? SeeUColors.accent : c.surface2,
          borderRadius: BorderRadius.circular(SeeURadii.medium),
        ),
        child: Center(
          child: Text(
            label,
            style: SeeUTypography.caption.copyWith(
              fontWeight: FontWeight.w600,
              color: isPrimary
                  ? Colors.white
                  : c.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _ActionIconButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(SeeURadii.medium),
        ),
        child: Center(
          child: Icon(icon, size: 18, color: c.ink),
        ),
      ),
    );
  }
}

// ── Stat item ──────────────────────────────────────────────────────────────

class _StatItem extends StatelessWidget {
  final int count;
  final String label;

  const _StatItem({required this.count, required this.label});

  static String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return n.toString();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TweenAnimationBuilder<double>(
          key: ValueKey(count),
          tween: Tween(begin: 0, end: count.toDouble()),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOut,
          builder: (context, value, child) {
            return Text(
              _formatCount(value.toInt()),
              style: SeeUTypography.displayS,
            );
          },
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: SeeUTypography.micro.copyWith(
            fontSize: 11,
            color: c.ink3,
          ),
        ),
      ],
    );
  }
}

// ── Highlights row ─────────────────────────────────────────────────────────

class _HighlightsRow extends ConsumerWidget {
  final List<Highlight> highlights;
  final String? currentUserId;
  final bool isOwnProfile;
  final String username;

  const _HighlightsRow({
    required this.highlights,
    required this.username,
    this.currentUserId,
    this.isOwnProfile = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    // When own profile, prepend a "+" tile so user always has a way to
    // create a new collection — even when the row is otherwise empty.
    final addTileCount = isOwnProfile ? 1 : 0;
    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        itemCount: highlights.length + addTileCount,
        itemBuilder: (context, index) {
          if (isOwnProfile && index == 0) {
            return Padding(
              padding: EdgeInsets.only(right: highlights.isEmpty ? 0 : 16),
              child: _AddHighlightTile(username: username),
            );
          }
          final h = highlights[index - addTileCount];
          final isLast = index == highlights.length + addTileCount - 1;
          return Padding(
            padding: EdgeInsets.only(right: isLast ? 0 : 16),
            child: GestureDetector(
              onLongPress: isOwnProfile
                  ? () => _showHighlightActions(context, ref, h)
                  : null,
              onTap: () {
                if (h.stories.isNotEmpty) {
                  final group = StoryGroup(
                    author: h.author,
                    stories: h.stories,
                    allSeen: false,
                  );
                  Navigator.of(context).push(
                    PageRouteBuilder(
                      pageBuilder: (ctx, anim, secAnim) =>
                          StoryViewerRoute(
                        groups: [group],
                        initialGroupIndex: 0,
                        currentUserId: currentUserId,
                      ),
                      transitionsBuilder:
                          (ctx, anim, secAnim, child) =>
                              FadeTransition(opacity: anim, child: child),
                      transitionDuration:
                          const Duration(milliseconds: 200),
                    ),
                  );
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: c.line, width: 1.5),
                    ),
                    child: ClipOval(
                      child: h.coverUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: h.coverUrl,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              color: c.surface2,
                              child: Center(
                                child: Icon(PhosphorIcons.image(),
                                    size: 28,
                                    color: c.ink3),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    h.title,
                    style: SeeUTypography.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showHighlightActions(
      BuildContext context, WidgetRef ref, Highlight h) {
    HapticFeedback.mediumImpact();
    final c = context.seeuColors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(SeeURadii.card),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(PhosphorIcons.pencilSimple(), color: c.ink),
                title: const Text('Переименовать'),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _renameHighlight(context, ref, h);
                },
              ),
              Divider(height: 1, color: c.line),
              ListTile(
                leading: Icon(PhosphorIcons.trash(), color: Colors.red),
                title: const Text('Удалить',
                    style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _deleteHighlight(context, ref, h);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _renameHighlight(
      BuildContext context, WidgetRef ref, Highlight h) async {
    final controller = TextEditingController(text: h.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('Переименовать коллекцию'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 50,
          decoration: const InputDecoration(
            hintText: 'Новое название',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dlgCtx).pop(),
              child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SeeUColors.accent),
            onPressed: () => Navigator.of(dlgCtx).pop(controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (newTitle == null || newTitle.isEmpty || newTitle == h.title) return;
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final api = ref.read(apiClientProvider);
      await api.put(ApiEndpoints.highlightById(h.id),
          data: {'title': newTitle});
      ref.invalidate(userProfileProvider(username));
      messenger.showSnackBar(
        const SnackBar(content: Text('Коллекция переименована')),
      );
    } on DioException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Не удалось: ${apiErrorMessage(e)}')),
      );
    }
  }

  Future<void> _deleteHighlight(
      BuildContext context, WidgetRef ref, Highlight h) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('Удалить коллекцию?'),
        content: Text(
            'Коллекция «${h.title}» будет удалена. Сами сторис останутся в архиве.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dlgCtx).pop(false),
              child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dlgCtx).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final api = ref.read(apiClientProvider);
      await api.delete(ApiEndpoints.highlightById(h.id));
      ref.invalidate(userProfileProvider(username));
      messenger.showSnackBar(
        const SnackBar(content: Text('Коллекция удалена')),
      );
    } on DioException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Не удалось: ${apiErrorMessage(e)}')),
      );
    }
  }
}

class _AddHighlightTile extends ConsumerWidget {
  final String username;
  const _AddHighlightTile({required this.username});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    return GestureDetector(
      onTap: () async {
        final created = await showCreateHighlightSheet(
          context: context,
          username: username,
        );
        if (created) {
          ref.invalidate(userProfileProvider(username));
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.surface2,
              border: Border.all(
                  color: SeeUColors.accent.withValues(alpha: 0.6), width: 1.5),
            ),
            child: Center(
              child: Icon(PhosphorIcons.plus(),
                  color: SeeUColors.accent, size: 28),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Создать',
            style: SeeUTypography.caption.copyWith(color: SeeUColors.accent),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── Posts grid ─────────────────────────────────────────────────────────────

class _PostsGrid extends StatelessWidget {
  final List<Post> posts;

  const _PostsGrid({required this.posts});

  String _postCoverUrl(Post post) => post.gridThumbnailUrl;

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    if (posts.isEmpty) {
      return const SeeUEmptyState(
        icon: PhosphorIconsRegular.imageSquare,
        title: 'Пока нет постов',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: posts.length,
      itemBuilder: (context, index) {
        final post = posts[index];
        return GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ProfilePostsFeed(
                  posts: posts,
                  initialIndex: index,
                ),
              ),
            );
          },
          child: post.isWave
              ? Container(
                  color: post.waveColorValue != null
                      ? Color(post.waveColorValue!)
                      : SeeUColors.accent,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(6),
                  child: Text(
                    post.caption ?? '',
                    style: SeeUTypography.micro.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                )
              : post.media.isNotEmpty
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: _postCoverUrl(post),
                          fit: BoxFit.cover,
                          placeholder: (_, __) =>
                              Container(color: c.surface2),
                          errorWidget: (_, __, ___) =>
                              Container(color: c.surface2),
                        ),
                        if (post.media.any((m) => m.type == MediaType.video))
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Icon(
                              PhosphorIcons.play(PhosphorIconsStyle.fill),
                              color: Colors.white,
                              size: 14,
                              shadows: const [Shadow(color: Color(0x80000000), blurRadius: 4)],
                            ),
                          ),
                      ],
                    )
                  : Container(color: c.surface2),
        );
      },
    );
  }
}

// ── Private content placeholder ────────────────────────────────────────────

class _PrivateContent extends StatelessWidget {
  const _PrivateContent();

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '\u2013',
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontSize: 56,
              color: c.ink3,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Подпишитесь, чтобы видеть посты',
            style: SeeUTypography.body
                .copyWith(color: c.ink2),
          ),
        ],
      ),
    );
  }
}

