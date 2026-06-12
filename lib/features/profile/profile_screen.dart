import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/api/api_client.dart';
import '../../core/design/design.dart';
import '../../core/providers/user_provider.dart';
import 'widgets/profile_buttons.dart';
import 'widgets/profile_content_tabs.dart';
import 'widgets/profile_highlights.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/blocks_provider.dart';
import '../../core/providers/story_provider.dart';
import '../../widgets/report_sheet.dart';
import '../../widgets/verified_badge.dart';
import '../feed/widgets/stories_row.dart';
import '../../core/models/user.dart';

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
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 3) {
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
                leading: Icon(PhosphorIcons.prohibit(), color: SeeUColors.error),
                title: const Text('Заблокировать',
                    style: TextStyle(color: SeeUColors.error)),
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
                    ProfileHeaderIconButton(
                      icon: PhosphorIcons.dotsThreeOutline(),
                      tooltip: 'Ещё',
                      onTap: () => _showOtherProfileMenu(context, user),
                    ),
                  if (isOwnProfile)
                    Row(
                      children: [
                        // Create content button
                        ProfileHeaderIconButton(
                          icon: PhosphorIcons.plusCircle(),
                          tooltip: 'Создать',
                          onTap: () => _showCreateSheet(context),
                        ),
                        const SizedBox(width: 8),
                        ProfileHeaderIconButton(
                          icon: PhosphorIcons.gearSix(),
                          tooltip: 'Настройки',
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
                          ProfileTabButton(
                            icon: PhosphorIcons.squaresFour(),
                            isActive: _selectedTab == 0,
                            onTap: () => _tabController.animateTo(0),
                          ),
                          ProfileTabButton(
                            icon: PhosphorIcons.filmStrip(),
                            isActive: _selectedTab == 1,
                            onTap: () => _tabController.animateTo(1),
                          ),
                          ProfileTabButton(
                            icon: PhosphorIcons.folderSimple(),
                            isActive: _selectedTab == 2,
                            onTap: () => _tabController.animateTo(2),
                          ),
                          ProfileTabButton(
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
                              ? const ProfilePrivateContent()
                              : ProfilePostsGrid(posts: profileState.posts),
                          ProfileVideosTab(userId: profileState.user?.id ?? ''),
                          ProfileFilesTab(userId: profileState.user?.id ?? ''),
                          isOwnProfile
                              ? ProfilePostsGrid(posts: profileState.savedPosts)
                              : const ProfilePrivateContent(),
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
                          CupertinoPageRoute(
                            builder: (_) => StoryViewerRoute(
                              groups: storyState.storyGroups,
                              initialGroupIndex: groupIndex,
                              currentUserId: ref.read(authProvider).user?.id,
                            ),
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
                    ProfileStatItem(
                        count: user.postsCount, label: 'посты'),
                    GestureDetector(
                      onTap: () => context
                          .push('/profile/${user.username}/followers'),
                      child: ProfileStatItem(
                          count: user.followersCount,
                          label: 'подписчики'),
                    ),
                    GestureDetector(
                      onTap: () => context
                          .push('/profile/${user.username}/following'),
                      child: ProfileStatItem(
                          count: user.followingCount,
                          label: 'подписки'),
                    ),
                    // Social score: лайки из всех источников
                    GestureDetector(
                      onTap: isOwnProfile
                          ? () => context.push('/scanner/likes')
                          : null,
                      child: ProfileStatItem(
                          count: user.totalLikes,
                          label: 'лайки'),
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

        // ── Social Score card ───────────────────────────────────────
        if (user.totalLikes > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
            child: _SocialScoreCard(totalLikes: user.totalLikes, colors: c),
          ),

        // ── Action buttons ─────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
          child: isOwnProfile
              ? ProfileOwnButtons(user: user)
              : ProfileOtherButtons(user: user),
        ),

        // ── Highlights ─────────────────────────────────────────────
        if (profileState.highlights.isNotEmpty || isOwnProfile) ...[
          ProfileHighlightsRow(
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
              painter: ProfileStoryRingPainter(seen: !hasUnseenStories),
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

// Level thresholds must match backend domain/user_stats.go SocialLevel().
const _levelThresholds = [
  (0, 'Новичок'),
  (50, 'Известный'),
  (200, 'Популярный'),
  (1000, 'Звезда'),
  (5000, 'Легенда'),
  (20000, 'Икона'),
];

({String name, int current, int next, double progress}) _computeLevel(int likes) {
  String name = _levelThresholds.first.$2;
  int curMin = 0;
  int nextMin = _levelThresholds[1].$1;
  for (int i = _levelThresholds.length - 1; i >= 0; i--) {
    if (likes >= _levelThresholds[i].$1) {
      name = _levelThresholds[i].$2;
      curMin = _levelThresholds[i].$1;
      nextMin = i + 1 < _levelThresholds.length
          ? _levelThresholds[i + 1].$1
          : _levelThresholds[i].$1;
      break;
    }
  }
  final isMax = curMin == nextMin;
  final progress = isMax
      ? 1.0
      : (likes - curMin) / (nextMin - curMin).clamp(1, double.infinity);
  return (
    name: name,
    current: curMin,
    next: nextMin,
    progress: progress.clamp(0.0, 1.0),
  );
}

class _SocialScoreCard extends StatelessWidget {
  final int totalLikes;
  final SeeUThemeColors colors;

  const _SocialScoreCard({required this.totalLikes, required this.colors});

  @override
  Widget build(BuildContext context) {
    final level = _computeLevel(totalLikes);
    final isMax = level.current == level.next;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: SeeUColors.accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: SeeUColors.accent.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        children: [
          Icon(PhosphorIconsFill.star, color: SeeUColors.accent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      level.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: SeeUColors.accent,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$totalLikes лайков',
                      style: TextStyle(fontSize: 11, color: colors.ink3),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: level.progress,
                    minHeight: 4,
                    backgroundColor: colors.line,
                    valueColor: const AlwaysStoppedAnimation(SeeUColors.accent),
                  ),
                ),
                if (!isMax) ...[
                  const SizedBox(height: 2),
                  Text(
                    'До следующего уровня: ${level.next - totalLikes}',
                    style: TextStyle(fontSize: 10, color: colors.ink3),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

