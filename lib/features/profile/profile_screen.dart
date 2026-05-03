import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/design/design.dart';
import '../../core/providers/user_provider.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/story_provider.dart';
import '../feed/widgets/stories_row.dart';
import '../../core/models/user.dart';
import '../../core/models/post.dart';
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
  // Simulated nearby count (BLE badge); replace with real provider when available
  static const int _nearbyCount = 3;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
                    child: Text(
                      '@${user.username}',
                      style: SeeUTypography.mono.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                  ),
                  if (isOwnProfile)
                    Row(
                      children: [
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
                        ],
                      ),
                    ),
                    // ── Grid ──────────────────────────────────────────
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _PostsGrid(posts: profileState.posts),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        if (profileState.highlights.isNotEmpty) ...[
          _HighlightsRow(highlights: profileState.highlights, currentUserId: ref.read(authProvider).user?.id),
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
            fontFamily: 'Georgia',
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Expanded(
          child: user.isFollowing
              ? _ActionButton(
                  label: 'Отписаться',
                  onTap: () => ref
                      .read(userProfileProvider(user.username).notifier)
                      .toggleFollow(),
                )
              : _ActionButton(
                  label: 'Подписаться',
                  isPrimary: true,
                  onTap: () => ref
                      .read(userProfileProvider(user.username).notifier)
                      .toggleFollow(),
                ),
        ),
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

class _HighlightsRow extends StatelessWidget {
  final List<Highlight> highlights;
  final String? currentUserId;

  const _HighlightsRow({required this.highlights, this.currentUserId});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        itemCount: highlights.length,
        itemBuilder: (context, index) {
          final h = highlights[index];
          return Padding(
            padding: EdgeInsets.only(
                right: index < highlights.length - 1 ? 16 : 0),
            child: GestureDetector(
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
}

// ── Posts grid ─────────────────────────────────────────────────────────────

class _PostsGrid extends StatelessWidget {
  final List<Post> posts;

  const _PostsGrid({required this.posts});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    if (posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '\u2022',
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 56,
                color: c.ink3,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Пока нет постов',
              style: SeeUTypography.body
                  .copyWith(color: c.ink2),
            ),
          ],
        ),
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
          onTap: () => context.push('/post/${post.id}'),
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
                  ? CachedNetworkImage(
                      imageUrl: post.media.first.url,
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          Container(color: c.surface2),
                      errorWidget: (_, __, ___) =>
                          Container(color: c.surface2),
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
              fontFamily: 'Georgia',
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

