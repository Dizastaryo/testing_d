import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:lottie/lottie.dart';
import '../../core/api/api_client.dart';
import '../../core/providers/pair_provider.dart';
import '../spark/spark_senders_sheet.dart';
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
    _tabController = TabController(length: 3, vsync: this);
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
    showSeeUBottomSheet(
      context: context,
      builder: (sheetCtx) => SafeArea(
        top: false,
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
    final confirmed = await showSeeUConfirm(
      context,
      title: 'Заблокировать @${user.username}?',
      message:
          'Вы перестанете видеть посты и истории этого пользователя, '
          'а он — ваши. Подписки удалятся в обе стороны. Чаты закроются.',
      confirmLabel: 'Заблокировать',
      destructive: true,
      icon: PhosphorIcons.prohibit(),
    );
    if (!confirmed || !mounted) return;
    final err = await ref.read(blocksProvider.notifier).block(user.username);
    if (!context.mounted) return;
    if (err != null) {
      showSeeUSnackBar(context, 'Не удалось заблокировать: $err',
          tone: SeeUTone.danger);
    } else {
      showSeeUSnackBar(context, '@${user.username} заблокирован',
          icon: PhosphorIcons.prohibit());
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
      showSeeUSnackBar(context, '@${user.username} ограничен',
          icon: PhosphorIcons.shieldWarning());
    } catch (e) {
      if (!context.mounted) return;
      showSeeUSnackBar(context, 'Не удалось ограничить: $e',
          tone: SeeUTone.danger);
    }
  }

  void _showCreateSheet(BuildContext context) {
    showSeeUBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
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

  /// «март 2025» → байлайн «С марта 2025» под именем (editorial).
  String _memberSince(DateTime dt) {
    const months = [
      'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
    ];
    return '${months[dt.month - 1]} ${dt.year}';
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
        body: const SafeArea(child: SeeUProfileSkeleton()),
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
            // ── Header (glass bar) ──────────────────────────────────
            SeeUGlassBar(
              blur: 18,
              leading: widget.username != null
                  ? SeeUGlassCircleButton(
                      onTap: () => Navigator.of(context).pop(),
                      size: 44,
                      icon: Icon(PhosphorIcons.arrowLeft(),
                          size: 20, color: c.ink),
                    )
                  : null,
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      '@${user.username}',
                      overflow: TextOverflow.ellipsis,
                      style: SeeUTypography.kicker.copyWith(
                        fontSize: 13,
                        color: c.ink,
                      ),
                    ),
                  ),
                  if (user.isVerified) const VerifiedBadge(size: 14),
                ],
              ),
              actions: [
                if (!isOwnProfile)
                  ProfileHeaderIconButton(
                    icon: PhosphorIcons.dotsThreeOutline(),
                    tooltip: 'Ещё',
                    onTap: () => _showOtherProfileMenu(context, user),
                  ),
                if (isOwnProfile) ...[
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
              ],
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
                    // ── Tabs (glass strip) ────────────────────────────
                    ClipRect(
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                        child: Container(
                          decoration: BoxDecoration(
                            color: SeeUColors.background
                                .withValues(alpha: 0.7),
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
                                icon: PhosphorIcons.folderSimple(),
                                isActive: _selectedTab == 1,
                                onTap: () => _tabController.animateTo(1),
                              ),
                              ProfileTabButton(
                                icon: PhosphorIcons.heart(),
                                isActive: _selectedTab == 2,
                                onTap: () => _tabController.animateTo(2),
                              ),
                            ],
                          ),
                        ),
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
        // channel_banner_url. 16:6 cover-image + gradient-overlay снизу для
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
                          SeeUColors.lightScrim,
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
                child: Hero(
                  tag: 'avatar-${user.username}',
                  child: _buildAvatar(user,
                      hasStories: hasStories,
                      hasUnseenStories: hasUnseenStories),
                ),
              ),
              const SizedBox(width: 18),
              // Stats
              Expanded(
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        ProfileStatItem(
                            count: user.postsCount, label: 'ПОСТЫ'),
                        Container(
                            width: 0.5, height: 24, color: c.line),
                        GestureDetector(
                          onTap: () => context
                              .push('/profile/${user.username}/followers'),
                          child: ProfileStatItem(
                              count: user.followersCount,
                              label: 'ПОДПИСЧИКИ'),
                        ),
                        Container(
                            width: 0.5, height: 24, color: c.line),
                        GestureDetector(
                          onTap: () => context
                              .push('/profile/${user.username}/following'),
                          child: ProfileStatItem(
                              count: user.followingCount,
                              label: 'ПОДПИСКИ'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Spark 🔥 — единый сигнал тепла (заменил монеты). Список
                    // отправителей виден только владельцу профиля.
                    Center(
                      child: _SparkStatItem(
                        count: user.sparksCount,
                        isPaired: ref
                            .watch(pairCheckProvider(user.id))
                            .maybeWhen(data: (v) => v, orElse: () => false),
                        onTap: isOwnProfile
                            ? () => SparkSendersSheet.show(context)
                            : null,
                      ),
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
                style: SeeUTypography.displayL,
              ),
              const SizedBox(height: 4),
              // Editorial-байлайн: ник как есть (без капса) + дата регистрации.
              Text(
                '@${user.username} · С ${_memberSince(user.createdAt)}',
                style: SeeUTypography.kicker.copyWith(color: c.ink3),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
            ],
          ),
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
          user.username.isNotEmpty ? user.username[0].toUpperCase() : '?',
          style: SeeUTypography.displayL
              .copyWith(fontWeight: FontWeight.w600, color: Colors.white),
        ),
      ),
    );
  }

}

class _SparkStatItem extends StatelessWidget {
  final int count;
  final bool isPaired;
  final VoidCallback? onTap;

  const _SparkStatItem({required this.count, this.isPaired = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.seeuColors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Lottie.asset('assets/small flame.json', repeat: true),
              ),
              // Второй огонёк — статус «Пара» 🔥🔥 (Фаза 5).
              if (isPaired)
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Lottie.asset('assets/small flame.json', repeat: true),
                ),
              const SizedBox(width: 4),
              Text(
                '$count',
                style: SeeUTypography.body.copyWith(
                  color: colors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            isPaired ? 'Spark · Пара' : 'Spark',
            style: SeeUTypography.micro.copyWith(color: colors.ink3),
          ),
        ],
      ),
    );
  }
}
