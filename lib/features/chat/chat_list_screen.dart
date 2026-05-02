import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../core/design/design.dart';
import '../../core/providers/chat_provider.dart';
// MockService removed; chat backend not yet implemented

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
      final name = c.otherUser.fullName.toLowerCase();
      final username = c.otherUser.username.toLowerCase();
      final msg = c.lastMessage.toLowerCase();
      return name.contains(q) || username.contains(q) || msg.contains(q);
    }).toList();
  }

  void _showNewChatPicker() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NewChatBottomSheet(
        onUserSelected: (user) {
          Navigator.of(context).pop();
          ref.read(chatListProvider.notifier).load();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Создание чата пока недоступно')),
          );
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
              padding: const EdgeInsets.fromLTRB(18, 58, 18, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Чаты',
                    style: SeeUTypography.displayL,
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
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: SeeUColors.accent,
                        strokeWidth: 2.5,
                      ),
                    )
                  : chats.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          color: SeeUColors.accent,
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
                                  context.go('/chat/${chats[index].id}');
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

class _ChatTile extends StatelessWidget {
  final Chat chat;
  final VoidCallback onTap;

  const _ChatTile({
    required this.chat,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final user = chat.otherUser;
    final hasUnread = chat.unreadCount > 0;
    final lastMsg = chat.lastMessage;
    final lastMsgTime = chat.lastMessageAt;
    // Simulated online/typing states from id hash until real-time data available
    final isOnline = user.id.hashCode % 3 == 0;
    final isTyping = user.id.hashCode % 5 == 1;
    // "взаимный" badge shown when user id hash % 4 == 0
    final isChipMatch = user.id.hashCode % 4 == 0;

    return Tappable.scaled(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(
          children: [
            // Avatar 52px with online green dot
            _OnlineAvatar(
              avatarUrl: user.avatarUrl,
              isOnline: isOnline,
              size: 52,
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
                          user.fullName,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: c.ink,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isChipMatch) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: c.accentSoft,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            'взаимный',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: SeeUColors.accent,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isTyping
                        ? 'печатает...'
                        : lastMsg.isNotEmpty
                            ? lastMsg
                            : 'Начните общение',
                    style: TextStyle(
                      fontSize: 13,
                      color: isTyping
                          ? SeeUColors.accent
                          : hasUnread
                              ? c.ink
                              : c.ink3,
                      fontWeight: (hasUnread || isTyping)
                          ? FontWeight.w500
                          : FontWeight.w400,
                      fontStyle: isTyping
                          ? FontStyle.italic
                          : FontStyle.normal,
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
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'сейчас';
    if (diff.inHours < 24 && dt.day == now.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return timeago.format(dt, locale: 'ru');
  }
}

// ---------------------------------------------------------------------------
// Online avatar
// ---------------------------------------------------------------------------

class _OnlineAvatar extends StatelessWidget {
  final String? avatarUrl;
  final bool isOnline;
  final double size;

  const _OnlineAvatar({
    this.avatarUrl,
    this.isOnline = false,
    this.size = 52,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
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
            child: avatarUrl != null && avatarUrl!.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: avatarUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      color: c.line,
                      child: Icon(
                        PhosphorIconsRegular.user,
                        size: size * 0.45,
                        color: c.ink3,
                      ),
                    ),
                    errorWidget: (_, __, ___) => Icon(
                      PhosphorIconsRegular.user,
                      size: size * 0.45,
                      color: c.ink3,
                    ),
                  )
                : Icon(
                    PhosphorIconsRegular.user,
                    size: size * 0.45,
                    color: c.ink3,
                  ),
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

class _NewChatBottomSheet extends StatefulWidget {
  final void Function(dynamic user) onUserSelected;

  const _NewChatBottomSheet({required this.onUserSelected});

  @override
  State<_NewChatBottomSheet> createState() => _NewChatBottomSheetState();
}

class _NewChatBottomSheetState extends State<_NewChatBottomSheet> {
  final _controller = TextEditingController();
  List<dynamic> _results = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadFollowing();
  }

  Future<void> _loadFollowing() async {
    setState(() => _isLoading = true);
    // Chat backend not yet implemented; show empty list
    if (mounted) {
      setState(() {
        _results = [];
        _isLoading = false;
      });
    }
  }

  Future<void> _search(String query) async {
    if (query.isEmpty) {
      _loadFollowing();
      return;
    }
    setState(() => _isLoading = true);
    // Chat backend not yet implemented; show empty list
    if (mounted) {
      setState(() {
        _results = [];
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
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
                        child: Text(
                          'Скоро',
                          style: SeeUTypography.body.copyWith(
                            color: c.ink2,
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
