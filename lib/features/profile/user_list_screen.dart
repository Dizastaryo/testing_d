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

class UserListScreen extends ConsumerStatefulWidget {
  final String username;
  final UserListKind kind;

  const UserListScreen({
    super.key,
    required this.username,
    required this.kind,
  });

  @override
  ConsumerState<UserListScreen> createState() => _UserListScreenState();
}

/// BUGFIX-E: backend `GET /users/:username/followers|following` supports
/// `page`/`limit` pagination (see `user_handler.go` GetFollowers/GetFollowing,
/// `pagination.NewMeta`) but the client used to fetch everything in one
/// request. For accounts with many followers this was a single long spinner
/// with a timeout risk. Mirrors the page-based infinite-scroll pattern
/// already used in `story_viewers_sheet.dart`.
class _UserListScreenState extends ConsumerState<UserListScreen> {
  static const int _pageSize = 30;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  Object? _error;
  int _page = 1;
  final List<User> _users = [];
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

  String _endpoint() => widget.kind == UserListKind.followers
      ? ApiEndpoints.userFollowers(widget.username)
      : ApiEndpoints.userFollowing(widget.username);

  Future<void> _loadFirst() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final ok = await _fetch(page: 1, replace: true);
    if (mounted) {
      setState(() {
        _loading = false;
        _page = 1;
      });
    }
    if (!ok && mounted) setState(() => _error ??= 'load_error');
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final next = _page + 1;
    final ok = await _fetch(page: next, replace: false);
    if (mounted) {
      setState(() {
        _loadingMore = false;
        if (ok) _page = next;
      });
    }
  }

  Future<bool> _fetch({required int page, required bool replace}) async {
    try {
      final api = ref.read(apiClientProvider);
      final r = await api.get(_endpoint(), queryParameters: {
        'page': '$page',
        'limit': '$_pageSize',
      });
      final body = r.data;
      final data =
          body is Map && body.containsKey('data') ? body['data'] : body;
      final list = (data as List)
          .map((e) => User.fromJson(e as Map<String, dynamic>))
          .toList();
      bool hasNext = list.length >= _pageSize;
      if (body is Map && body['meta'] is Map) {
        final meta = (body['meta'] as Map).cast<String, dynamic>();
        if (meta.containsKey('has_next_page')) {
          hasNext = meta['has_next_page'] == true;
        }
      }
      if (mounted) {
        setState(() {
          if (replace) _users.clear();
          _users.addAll(list);
          _hasMore = hasNext;
        });
      }
      return true;
    } catch (e) {
      if (mounted) setState(() => _error = e);
      return false;
    }
  }

  Future<void> _refresh() async {
    _page = 1;
    _hasMore = true;
    await _loadFirst();
  }

  @override
  Widget build(BuildContext context) {
    final title =
        widget.kind == UserListKind.followers ? 'Подписчики' : 'Подписки';
    final emptyIcon = widget.kind == UserListKind.followers
        ? PhosphorIconsRegular.users
        : PhosphorIconsRegular.userList;
    final emptyText = widget.kind == UserListKind.followers
        ? 'Пока нет подписчиков'
        : 'Пока нет подписок';

    return Scaffold(
      backgroundColor: SeeUColors.background,
      body: Column(
        children: [
          SeeUGlassBar(
            titleText: title,
            kicker: '@${widget.username}',
            leading: _GlassBackButton(onTap: () => Navigator.of(context).pop()),
          ),
          Expanded(
            child: _loading
                ? const SeeUListSkeleton()
                : (_error != null && _users.isEmpty)
                    ? SeeUErrorState(onRetry: _refresh)
                    : _users.isEmpty
                        ? SeeUEmptyState(icon: emptyIcon, title: emptyText)
                        : AnimationLimiter(
                            child: ListView.builder(
                              controller: _scrollCtrl,
                              padding: const EdgeInsets.only(top: 4, bottom: 24),
                              itemCount: _users.length + (_hasMore ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index >= _users.length) {
                                  return const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 16),
                                    child: Center(
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          color: SeeUColors.accent,
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                return AnimationConfiguration.staggeredList(
                                  position: index,
                                  duration: const Duration(milliseconds: 375),
                                  child: SlideAnimation(
                                    verticalOffset: 30,
                                    child: FadeInAnimation(
                                      child: _UserRow(user: _users[index]),
                                    ),
                                  ),
                                );
                              },
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
    // BUGFIX: раньше здесь всегда слался POST, независимо от направления —
    // "Отписаться" на самом деле заново подписывал. DELETE отписывает,
    // POST подписывает (см. корректную реализацию в user_provider.dart).
    final wasFollowing = previous;
    setState(() => _isFollowing = !_isFollowing);
    try {
      final api = ref.read(apiClientProvider);
      if (wasFollowing) {
        await api.delete(ApiEndpoints.followUser(widget.user.username));
      } else {
        await api.post(ApiEndpoints.followUser(widget.user.username));
      }
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
