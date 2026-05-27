import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/models/user.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/following_candidates_provider.dart';
import '../../core/providers/chat_provider.dart';
import 'widgets/typing_dots.dart';

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Chat> _filteredChats(List<Chat> chats) {
    if (_searchQuery.isEmpty) return chats;
    final q = _searchQuery.toLowerCase();
    return chats.where((c) {
      // Для direct ищем по имени/нику собеседника, для group — по title.
      final label = c.isGroup
          ? c.title.toLowerCase()
          : (c.otherUser?.fullName.toLowerCase() ?? '');
      final username = c.otherUser?.username.toLowerCase() ?? '';
      final msg = c.lastMessage.toLowerCase();
      return label.contains(q) || username.contains(q) || msg.contains(q);
    }).toList();
  }

  void _showNewChatPicker() {
    HapticFeedback.mediumImpact();
    // Сначала спрашиваем тип нового чата: direct (1-1) или group. Group →
    // отдельный full-screen с picker'ом + title; direct — старый bottom-sheet.
    showSeeUBottomSheet(
      context: context,
      builder: (sheetCtx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Новый чат', style: SeeUTypography.title),
              const SizedBox(height: 4),
              Text('Выберите формат',
                  style: SeeUTypography.caption
                      .copyWith(color: SeeUColors.textSecondary)),
              const SizedBox(height: 16),
              _NewChatTypeOption(
                icon: PhosphorIconsBold.user,
                title: 'Один на один',
                subtitle: 'Личный чат с одним пользователем',
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _openDirectPicker();
                },
              ),
              const SizedBox(height: 10),
              _NewChatTypeOption(
                icon: PhosphorIconsBold.usersThree,
                title: 'Группа',
                subtitle: 'До 100 человек, одна тема',
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  context.push('/chat/new-group');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _openDirectPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NewChatBottomSheet(
        onUserSelected: (user) async {
          Navigator.of(context).pop();
          final messenger = ScaffoldMessenger.of(context);
          final chatId = await ref
              .read(chatListProvider.notifier)
              .getOrCreateChat(user.id);
          if (!mounted) return;
          if (chatId == null || chatId.isEmpty) {
            messenger.showSnackBar(
              const SnackBar(content: Text('Не удалось создать чат')),
            );
            return;
          }
          context.push('/chat/$chatId');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final chatState = ref.watch(chatListProvider);
    final chats = _filteredChats(chatState.chats);

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: serif "Чаты" + compose button
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      if (Navigator.of(context).canPop())
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Icon(
                              PhosphorIconsRegular.caretLeft,
                              size: 22,
                              color: c.ink,
                            ),
                          ),
                        ),
                      Text(
                        'Чаты',
                        style: SeeUTypography.displayL,
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // C-1: история звонков. Tap → /chat/calls.
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          context.push('/chat/calls');
                        },
                        child: Container(
                          width: 40,
                          height: 40,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: c.surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: c.line, width: 0.5),
                          ),
                          child: Icon(
                            PhosphorIconsRegular.phone,
                            size: 18,
                            color: c.ink,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _showNewChatPicker,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: c.surface,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: c.line,
                              width: 0.5,
                            ),
                          ),
                          child: Icon(
                            PhosphorIconsRegular.pencilSimple,
                            size: 18,
                            color: c.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Search bar: height 40, surface2 bg, borderRadius 12
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(SeeURadii.small),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: SeeUTypography.body.copyWith(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Поиск',
                    hintStyle: SeeUTypography.body.copyWith(
                      fontSize: 14,
                      color: c.ink3,
                    ),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(left: 12, right: 8),
                      child: Icon(
                        PhosphorIconsRegular.magnifyingGlass,
                        color: c.ink3,
                        size: 16,
                      ),
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 40,
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? GestureDetector(
                            onTap: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                            child: Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: Icon(
                                PhosphorIconsFill.xCircle,
                                color: c.ink3,
                                size: 16,
                              ),
                            ),
                          )
                        : null,
                    suffixIconConstraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 40,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
            ),
            // Chat list
            Expanded(
              child: chatState.isLoading
                  ? const SeeUChatSkeleton()
                  : chats.isEmpty
                      ? _buildEmptyState()
                      : SeeURadarRefresh(
                          onRefresh: () =>
                              ref.read(chatListProvider.notifier).load(),
                          child: ListView.builder(
                            padding: const EdgeInsets.only(bottom: 100),
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            itemCount: chats.length,
                            itemBuilder: (context, index) {
                              return _ChatTile(
                                chat: chats[index],
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  context.push('/chat/${chats[index].id}');
                                },
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final c = context.seeuColors;
    final hasSearch = _searchQuery.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: c.accentSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                hasSearch
                    ? PhosphorIconsRegular.magnifyingGlass
                    : PhosphorIconsRegular.chatCircleDots,
                size: 36,
                color: SeeUColors.accent,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              hasSearch ? 'Ничего не найдено' : 'Нет сообщений',
              style: SeeUTypography.title,
            ),
            const SizedBox(height: 8),
            Text(
              hasSearch
                  ? 'Попробуйте другой запрос'
                  : 'Начните общение с друзьями.\nНажмите карандаш чтобы написать первое сообщение!',
              textAlign: TextAlign.center,
              style: SeeUTypography.body.copyWith(
                color: c.ink2,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chat tile
// ---------------------------------------------------------------------------

class _ChatTile extends ConsumerWidget {
  final Chat chat;
  final VoidCallback onTap;

  const _ChatTile({
    required this.chat,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final user = chat.otherUser;
    final isGroup = chat.isGroup;
    final hasUnread = chat.unreadCount > 0;
    final lastMsg = chat.lastMessage;
    final lastMsgTime = chat.lastMessageAt;
    // Для group last_message: «X: текст» если есть sender; для direct — как было.
    final lastMsgWithPrefix = isGroup && chat.lastSenderUsername.isNotEmpty
        ? '${chat.lastSenderUsername}: $lastMsg'
        : lastMsg;
    // Real online status from backend (otherUser.isOnline, обновляется
    // через WS user.presence).
    final isOnline = !isGroup && (user?.isOnline ?? false);
    // Реальный typing-индикатор: подписка на map активных typing'ов через
    // chat.typing WS events (TTL 4s). `.select` гарантирует rebuild только
    // когда меняется bool для ЭТОГО chat.id, не на любой typing-event.
    final isTyping = ref.watch(typingChatsProvider
        .select((m) => m.containsKey(chat.id)));
    final displayName = isGroup ? chat.title : (user?.fullName ?? '');

    return Tappable.scaled(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(
          children: [
            // Avatar 52px — для group используем cover_url или fallback-плейсхолдер
            // с group-icon на оранжевом градиенте.
            _OnlineAvatar(
              avatarUrl: isGroup ? chat.coverUrl : (user?.avatarUrl ?? ''),
              isOnline: isOnline,
              size: 52,
              isGroup: isGroup,
            ),
            const SizedBox(width: 12),
            // Name + badge + last message
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          displayName,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: c.ink,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isGroup) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: SeeUColors.accent.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(
                              color:
                                  SeeUColors.accent.withValues(alpha: 0.25),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            'группа · ${chat.participantsCount}',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: SeeUColors.accent,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                      // Badge «взаимный» удалён 2026-05-11 (был фейк по
                      // hashCode). Реальный BLE-match вернётся когда сделаем
                      // PROFILE-1 (nearbyDevicesProvider).
                    ],
                  ),
                  const SizedBox(height: 2),
                  if (isTyping)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'печатает',
                          style: TextStyle(
                            fontSize: 13,
                            color: SeeUColors.accent,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const TypingDots(color: SeeUColors.accent, size: 4),
                      ],
                    )
                  else
                    Text(
                      lastMsgWithPrefix.isNotEmpty
                          ? lastMsgWithPrefix
                          : 'Начните общение',
                      style: TextStyle(
                        fontSize: 13,
                        color: hasUnread ? c.ink : c.ink3,
                        fontWeight: hasUnread
                            ? FontWeight.w500
                            : FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Time + unread badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatTime(lastMsgTime),
                  style: TextStyle(
                    fontSize: 11,
                    color: c.ink3,
                  ),
                ),
                if (hasUnread) ...[
                  const SizedBox(height: 4),
                  Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    height: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: SeeUColors.accent,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      chat.unreadCount > 99 ? '99+' : '${chat.unreadCount}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);
    if (diff.inMinutes < 1) return 'сейчас';
    if (diff.inHours < 24 && local.day == now.day) {
      return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }
    return timeago.format(local, locale: 'ru');
  }
}

// ---------------------------------------------------------------------------
// Online avatar
// ---------------------------------------------------------------------------

class _OnlineAvatar extends StatelessWidget {
  final String? avatarUrl;
  final bool isOnline;
  final double size;
  final bool isGroup;

  const _OnlineAvatar({
    this.avatarUrl,
    this.isOnline = false,
    this.size = 52,
    this.isGroup = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final hasUrl = avatarUrl != null && avatarUrl!.isNotEmpty;
    Widget placeholder = Container(
      decoration: isGroup
          ? const BoxDecoration(
              shape: BoxShape.circle,
              gradient: SeeUGradients.heroOrange,
            )
          : BoxDecoration(shape: BoxShape.circle, color: c.surface2),
      child: Icon(
        isGroup ? PhosphorIconsBold.usersThree : PhosphorIconsRegular.user,
        size: size * 0.45,
        color: isGroup ? Colors.white : c.ink3,
      ),
    );
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.surface2,
            ),
            clipBehavior: Clip.antiAlias,
            child: hasUrl
                ? CachedNetworkImage(
                    imageUrl: avatarUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => placeholder,
                    errorWidget: (_, __, ___) => placeholder,
                  )
                : placeholder,
          ),
          if (isOnline)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: SeeUColors.success,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: c.bg,
                    width: 2.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// New chat bottom sheet - user picker
// ---------------------------------------------------------------------------

class _NewChatBottomSheet extends ConsumerStatefulWidget {
  final void Function(User user) onUserSelected;

  const _NewChatBottomSheet({required this.onUserSelected});

  @override
  ConsumerState<_NewChatBottomSheet> createState() =>
      _NewChatBottomSheetState();
}

class _NewChatBottomSheetState extends ConsumerState<_NewChatBottomSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<User> _results = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    try {
      final result = await ref.read(followingCandidatesProvider.future);
      if (mounted) {
        setState(() {
          _results = result;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
          _results = [];
        });
      }
    }
  }

  /// Debounced search by username/full name — uses the existing /search
  /// endpoint with type=users. Empty query → reset to following list.
  void _search(String query) {
    _debounce?.cancel();
    final q = query.trim();
    if (q.isEmpty) {
      _loadInitial();
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      final me = ref.read(authProvider).user;
      try {
        final api = ref.read(apiClientProvider);
        final r = await api.get(
          ApiEndpoints.search,
          queryParameters: {'q': q, 'type': 'users'},
        );
        final data = r.data is Map && (r.data as Map).containsKey('data')
            ? r.data['data']
            : r.data;
        List<User> users = const [];
        if (data is Map && data['users'] is List) {
          users = (data['users'] as List)
              .map((e) => User.fromJson(e as Map<String, dynamic>))
              .where((u) => me == null || u.id != me.id)
              .toList();
        }
        if (mounted) {
          setState(() {
            _results = users;
            _isLoading = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _error = e.toString();
            _results = [];
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(SeeURadii.sheet),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: c.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Новое сообщение',
            style: SeeUTypography.title,
          ),
          const SizedBox(height: 16),
          // Search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(SeeURadii.small),
              ),
              child: TextField(
                controller: _controller,
                autofocus: true,
                onChanged: _search,
                style: SeeUTypography.body.copyWith(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Поиск пользователей...',
                  hintStyle: SeeUTypography.body.copyWith(
                    fontSize: 14,
                    color: c.ink3,
                  ),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(left: 12, right: 8),
                    child: Icon(
                      PhosphorIconsRegular.magnifyingGlass,
                      color: c.ink3,
                      size: 16,
                    ),
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 40,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Results
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: SeeUColors.accent,
                      strokeWidth: 2,
                    ),
                  )
                : _results.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            _error != null
                                ? 'Не удалось загрузить пользователей'
                                : (_controller.text.trim().isEmpty
                                    ? 'Никого не нашли. Подпишитесь на кого-нибудь, чтобы написать.'
                                    : 'По запросу никого не нашли'),
                            textAlign: TextAlign.center,
                            style: SeeUTypography.body.copyWith(
                              color: c.ink2,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final user = _results[index];
                          return Tappable.scaled(
                            onTap: () => widget.onUserSelected(user),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  _OnlineAvatar(
                                    avatarUrl: user.avatarUrl,
                                    isOnline: false,
                                    size: 44,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          user.fullName,
                                          style: SeeUTypography.subtitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          '@${user.username}',
                                          style:
                                              SeeUTypography.caption.copyWith(
                                            color: c.ink2,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Кнопка-карточка для выбора типа нового чата (direct / group).
// ---------------------------------------------------------------------------

class _NewChatTypeOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _NewChatTypeOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Material(
      color: c.surface2,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SeeUGradients.heroOrange,
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: SeeUTypography.subtitle),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: SeeUTypography.caption
                            .copyWith(color: c.ink3)),
                  ],
                ),
              ),
              Icon(PhosphorIcons.caretRight(),
                  size: 16, color: c.ink3),
            ],
          ),
        ),
      ),
    );
  }
}
