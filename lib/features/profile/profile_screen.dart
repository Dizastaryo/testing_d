import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:lottie/lottie.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/providers/pair_provider.dart';
import '../spark/spark_senders_sheet.dart';
import '../../core/design/design.dart';
import '../../core/providers/user_provider.dart';
import 'widgets/profile_access_card.dart';
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
  @override
  void initState() {
    super.initState();
    // Дизайн-ядро (§05): две вкладки — «Публикации» и «Автор». Сохранённое
    // ушло из вкладок в отдельный экран (иконка-закладка в шапке).
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
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
              Builder(builder: (_) {
                final isRestricted = ref
                    .watch(restrictionsProvider)
                    .maybeWhen(
                        data: (s) => s.contains(user.username),
                        orElse: () => false);
                return ListTile(
                  leading: Icon(PhosphorIcons.shieldWarning(),
                      color: SeeUColors.accent),
                  title: Text(
                      isRestricted ? 'Снять ограничение' : 'Ограничить'),
                  subtitle: Text(
                    isRestricted
                        ? 'Его комментарии снова будут видны всем'
                        : 'Его комменты будут видны только ему и вам',
                    style: const TextStyle(fontSize: 11),
                  ),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _toggleRestrict(context, user, !isRestricted);
                  },
                );
              }),
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
      // Блок рвёт подписки в обе стороны — обновляем и СВОЙ профиль, иначе
      // мои followers/following счётчики отстают до пересоздания провайдера.
      final myUsername = ref.read(authProvider).user?.username;
      if (myUsername != null) {
        ref.invalidate(userProfileProvider(myUsername));
      }
    }
  }

  /// PROFILE-4: ограничить/снять ограничение — комменты ограниченного видны
  /// только ему и автору поста. Тоггл через restrictionsProvider (раньше был
  /// только «Ограничить» без обратного действия из UI).
  Future<void> _toggleRestrict(
      BuildContext context, User user, bool restrict) async {
    final err = await ref
        .read(restrictionsProvider.notifier)
        .toggle(user.username, restrict);
    if (!context.mounted) return;
    if (err != null) {
      showSeeUSnackBar(context, 'Не удалось: $err', tone: SeeUTone.danger);
      return;
    }
    showSeeUSnackBar(
      context,
      restrict
          ? '@${user.username} ограничен'
          : 'Ограничение с @${user.username} снято',
      icon: PhosphorIcons.shieldWarning(),
    );
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
                leading:
                    Icon(PhosphorIcons.waveform(), color: SeeUColors.accent),
                title: const Text('Новая волна'),
                subtitle: const Text('Текст-первый пост',
                    style: TextStyle(fontSize: 11)),
                onTap: () {
                  Navigator.pop(context);
                  context.push('/wave/create');
                },
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
              // Логин — латиницей, без @ (§05): в шапке это идентификатор, а не
              // упоминание. Имя-витрина Playfair показываем ниже, у аватара.
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      user.username,
                      overflow: TextOverflow.ellipsis,
                      style: SeeUTypography.subtitle.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
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
                  // Закладка — сохранённые публикации (вкладка «Сохранённое»
                  // из старого профиля переехала сюда, чтобы освободить место
                  // под «Публикации/Автор»).
                  ProfileHeaderIconButton(
                    icon: PhosphorIcons.bookmarkSimple(),
                    tooltip: 'Сохранённое',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            _SavedPostsScreen(username: user.username),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
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
                    // ── Вкладки: «Публикации» · «Автор» (текст + иконка,
                    // подчёркивание чернильное, непрозрачная полоса) ──────
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: c.bg,
                        border: Border(
                          bottom: BorderSide(color: c.line, width: 0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          _ProfileTextTab(
                            icon: PhosphorIcons.squaresFour(),
                            activeIcon: PhosphorIconsFill.squaresFour,
                            label: 'Публикации',
                            isActive: _selectedTab == 0,
                            onTap: () => _tabController.animateTo(0),
                          ),
                          _ProfileTextTab(
                            icon: PhosphorIcons.feather(),
                            activeIcon: PhosphorIconsFill.feather,
                            label: 'Автор',
                            isActive: _selectedTab == 1,
                            onTap: () => _tabController.animateTo(1),
                          ),
                        ],
                      ),
                    ),
                    // ── Содержимое вкладок ────────────────────────────
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
                          // «Автор» — что юзер сам выложил: треки в Аудиотеку
                          // и файлы в Библиотеку (§05 A2).
                          profileState.isLocked
                              ? const ProfilePrivateContent()
                              : ProfileAuthorTab(
                                  userId: profileState.user?.id ?? ''),
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

  Future<void> _openWebsite(String website) async {
    var url = website.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      showSeeUSnackBar(context, 'Не удалось открыть ссылку',
          tone: SeeUTone.danger);
    }
  }

  Widget _buildProfileBody(
    BuildContext context,
    User user,
    bool isOwnProfile,
    UserProfileState profileState,
  ) {
    final c = context.seeuColors;
    // select на группу конкретного юзера (single object) — ребилды от
    // isLoading/error StoryState и групп других авторов больше не задевают
    // профиль (раньше watch всего StoryState перестраивал его на любое
    // story-событие).
    final userGroup = ref.watch(storyProvider.select((s) {
      for (final g in s.storyGroups) {
        if (g.author.username == user.username) return g;
      }
      return null;
    }));
    final hasStories = userGroup != null;
    final hasUnseenStories = hasStories && !userGroup.allSeen;

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
        // ── Круглый аватар (story-ring) + счётчики в ряд (§05) ───────
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
          child: Row(
            children: [
              GestureDetector(
                onTap: hasStories
                    ? () {
                        // Читаем полный список только в момент тапа (не watch).
                        final groups =
                            ref.read(storyProvider).storyGroups;
                        final groupIndex = groups.indexOf(userGroup);
                        if (groupIndex < 0) return;
                        Navigator.of(context).push(
                          CupertinoPageRoute(
                            builder: (_) => StoryViewerRoute(
                              groups: groups,
                              initialGroupIndex: groupIndex,
                              currentUserId: ref.read(authProvider).user?.id,
                            ),
                          ),
                        );
                      }
                    : null,
                child: Container(
                  width: 82,
                  height: 82,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: hasUnseenStories ? SeeUColors.accent : c.line,
                      width: 2,
                    ),
                  ),
                  child: ClipOval(
                    child: (user.avatarUrl != null &&
                            user.avatarUrl!.isNotEmpty)
                        ? CachedNetworkImage(
                            imageUrl: user.avatarUrl!,
                            fit: BoxFit.cover,
                            placeholder: (_, __) =>
                                Container(color: c.surface2),
                            errorWidget: (_, __, ___) =>
                                _avatarFallback(c, user),
                          )
                        : _avatarFallback(c, user),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: ProfileStatItem(
                          count: user.postsCount, label: 'посты'),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => context
                            .push('/profile/${user.username}/followers'),
                        child: ProfileStatItem(
                            count: user.followersCount,
                            label: 'подписчики'),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => context
                            .push('/profile/${user.username}/following'),
                        child: ProfileStatItem(
                            count: user.followingCount, label: 'подписки'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── Имя-витрина (Playfair) + галочка ──────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  user.fullName.isNotEmpty ? user.fullName : user.username,
                  overflow: TextOverflow.ellipsis,
                  style: SeeUTypography.displayS.copyWith(
                    height: 1.0,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              if (user.isVerified) ...[
                const SizedBox(width: 6),
                Icon(PhosphorIcons.sealCheck(PhosphorIconsStyle.fill),
                    color: SeeUColors.accent, size: 16),
              ],
            ],
          ),
        ),

        // ── Bio ────────────────────────────────────────────────────
        if (user.bio != null && user.bio!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
            child: Text(
              user.bio!,
              style: SeeUTypography.body.copyWith(
                color: c.ink2,
                height: 1.4,
                fontSize: 13,
              ),
            ),
          ),

        // ── Website ────────────────────────────────────────────────
        if (user.website != null && user.website!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
            child: GestureDetector(
              onTap: () => _openWebsite(user.website!),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(PhosphorIcons.link(), size: 13, color: SeeUColors.accent),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      user.website!,
                      overflow: TextOverflow.ellipsis,
                      style: SeeUTypography.body.copyWith(
                        color: SeeUColors.accent,
                        height: 1.4,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // ── Spark — компактная плашка с живым пламенем (§05) ────────
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
          child: _SparkPill(
            count: user.sparksCount,
            isPaired: ref
                .watch(pairCheckProvider(user.id))
                .maybeWhen(data: (v) => v, orElse: () => false),
            onTap: isOwnProfile ? () => SparkSendersSheet.show(context) : null,
          ),
        ),

        // ── Action buttons ─────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
          child: isOwnProfile
              ? ProfileOwnButtons(user: user)
              : ProfileOtherButtons(user: user),
        ),

        // ── Круг общения (управление доступом) ──────────────────────
        if (isOwnProfile)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
            child: ProfileAccessCard(),
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

}

/// Компактная плашка Spark (§05): тёплый фон, коралловая рамка, живое пламя
/// Lottie и число. Владельцу тап открывает список отправителей. Статус «Пара»
/// добавляет второй огонёк.
class _SparkPill extends StatelessWidget {
  final int count;
  final bool isPaired;
  final VoidCallback? onTap;

  const _SparkPill({required this.count, this.isPaired = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 5, 14, 5),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3EE),
          borderRadius: BorderRadius.circular(SeeURadii.pill),
          border: Border.all(color: const Color(0xFFF5E0D6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 34,
              height: 34,
              child: Lottie.asset('assets/small flame.json', repeat: true),
            ),
            if (isPaired)
              SizedBox(
                width: 34,
                height: 34,
                child: Lottie.asset('assets/small flame.json', repeat: true),
              ),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: SeeUTypography.title.copyWith(
                color: const Color(0xFF161310),
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Вкладка профиля: иконка + подпись, чернильное подчёркивание активной (§05).
class _ProfileTextTab extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ProfileTextTab({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final color = isActive ? c.ink : c.ink3;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isActive ? c.ink : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(isActive ? activeIcon : icon, size: 18, color: color),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: SeeUTypography.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Плейсхолдер круглого аватара, когда фото нет/не загрузилось.
Widget _avatarFallback(SeeUThemeColors c, User user) {
  return Container(
    color: c.ink3.withValues(alpha: 0.3),
    alignment: Alignment.center,
    child: Text(
      user.username.isNotEmpty ? user.username[0].toUpperCase() : '?',
      style: SeeUTypography.displayS.copyWith(color: Colors.white),
    ),
  );
}

/// Сохранённые публикации — отдельный экран (закладка в шапке профиля §05).
/// Раньше это была третья вкладка профиля; теперь вкладок две, а сохранённое
/// открывается по иконке-закладке.
class _SavedPostsScreen extends ConsumerStatefulWidget {
  final String username;
  const _SavedPostsScreen({required this.username});

  @override
  ConsumerState<_SavedPostsScreen> createState() => _SavedPostsScreenState();
}

class _SavedPostsScreenState extends ConsumerState<_SavedPostsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(userProfileProvider(widget.username).notifier)
          .loadSavedPosts();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final state = ref.watch(userProfileProvider(widget.username));
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(PhosphorIcons.arrowLeft(), color: c.ink, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Сохранённое', style: SeeUTypography.subtitle),
      ),
      body: SafeArea(
        child: state.savedPostsLoading && state.savedPosts.isEmpty
            ? const Center(
                child: CircularProgressIndicator(color: SeeUColors.accent))
            : state.savedPostsError && state.savedPosts.isEmpty
                ? SeeUErrorState(
                    error: 'Не удалось загрузить сохранённое',
                    onRetry: () => ref
                        .read(userProfileProvider(widget.username).notifier)
                        .loadSavedPosts(),
                  )
                : state.savedPosts.isEmpty
                    ? const SeeUEmptyState(
                        icon: PhosphorIconsRegular.bookmarkSimple,
                        title: 'Пока ничего не сохранено',
                        subtitle:
                            'Сохраняйте публикации закладкой — они появятся здесь',
                      )
                    : ProfilePostsGrid(posts: state.savedPosts),
      ),
    );
  }
}
