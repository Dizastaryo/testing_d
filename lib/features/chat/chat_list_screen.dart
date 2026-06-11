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
import '../../core/models/room.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/following_candidates_provider.dart';
import '../../core/providers/chat_provider.dart';
import '../../core/providers/room_provider.dart';
import '../../core/providers/room_invites_provider.dart';
import 'room_invites_sheet.dart';
import '../sbory/sbory_screen.dart' show sborRefreshProvider;
import 'widgets/typing_dots.dart';

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  final _searchController = TextEditingController();
  final _roomSearchController = TextEditingController();
  String _searchQuery = '';
  String _roomSearchQuery = '';
  bool _showRooms = false;
  Timer? _timeTicker;
  Timer? _roomSearchDebounce;

  @override
  void initState() {
    super.initState();
    // Refresh time labels (сейчас / 12:34 / Вчера) every minute so they
    // don't stay stale while the user has the chat list open.
    _timeTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timeTicker?.cancel();
    _roomSearchDebounce?.cancel();
    _searchController.dispose();
    _roomSearchController.dispose();
    super.dispose();
  }

  List<Chat> _filteredChats(List<Chat> chats) {
    // Exclude archived chats from main list.
    final active = chats.where((c) => !c.isArchived).toList();
    if (_searchQuery.isEmpty) return active;
    final q = _searchQuery.toLowerCase();
    return active.where((c) {
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
    _openDirectPicker();
  }

  void _showNewRoomPicker() {
    HapticFeedback.mediumImpact();
    context.push('/room/create');
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
        onCreateGroup: () {
          Navigator.of(context).pop();
          context.push('/chat/new-group');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final chatState = ref.watch(chatListProvider);
    final chats = _filteredChats(chatState.chats);
    final currentUsername =
        ref.watch(authProvider.select((s) => s.user?.username)) ?? '';

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
              child: Row(
                children: [
                  if (Navigator.of(context).canPop())
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Icon(PhosphorIconsRegular.caretLeft, size: 22, color: c.ink),
                      ),
                    ),
                  Text(
                    _showRooms ? 'Комнаты' : 'Сообщения',
                    style: TextStyle(
                      fontFamily: 'Fraunces',
                      fontSize: 24, fontWeight: FontWeight.w500,
                      letterSpacing: -0.3, height: 1.1, color: c.ink,
                    ),
                  ),
                  const Spacer(),
                  if (!_showRooms) ...[
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        context.push('/chat/calls');
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: Icon(PhosphorIconsRegular.phone, size: 22, color: c.ink),
                      ),
                    ),
                    GestureDetector(
                      onTap: _showNewChatPicker,
                      child: Icon(PhosphorIconsRegular.pencilSimple, size: 22, color: c.ink),
                    ),
                  ] else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Invite badge button
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            showModalBottomSheet<void>(
                              context: context,
                              backgroundColor: Colors.transparent,
                              isScrollControlled: true,
                              builder: (_) => const RoomInvitesSheet(),
                            );
                          },
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 36, height: 36,
                                decoration: BoxDecoration(
                                  color: c.surface2,
                                  borderRadius: BorderRadius.circular(SeeURadii.small),
                                ),
                                child: Icon(
                                  PhosphorIcons.envelope(PhosphorIconsStyle.fill),
                                  size: 18, color: c.ink2,
                                ),
                              ),
                              Consumer(builder: (_, ref, __) {
                                final count = ref.watch(roomInvitesProvider).valueOrNull?.length ?? 0;
                                if (count == 0) return const SizedBox.shrink();
                                return Positioned(
                                  top: -4, right: -4,
                                  child: Container(
                                    width: 18, height: 18,
                                    decoration: const BoxDecoration(
                                      color: SeeUColors.accent,
                                      shape: BoxShape.circle,
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      count > 9 ? '9+' : '$count',
                                      style: const TextStyle(
                                        fontSize: 10, fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: _showNewRoomPicker,
                          child: Container(
                            height: 36,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: SeeUColors.accent,
                              borderRadius: BorderRadius.circular(SeeURadii.pill),
                              boxShadow: SeeUShadows.sm,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(PhosphorIcons.plus(PhosphorIconsStyle.bold), size: 14, color: Colors.white),
                                const SizedBox(width: 5),
                                const Text(
                                  'Создать',
                                  style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            // Tab switcher: Чаты / Комнаты
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: Row(
                children: [
                  _TabChip(
                    label: 'Чаты',
                    icon: PhosphorIcons.chatCircle(PhosphorIconsStyle.fill),
                    active: !_showRooms,
                    c: c,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _showRooms = false);
                    },
                  ),
                  const SizedBox(width: 8),
                  _TabChip(
                    label: 'Комнаты',
                    icon: PhosphorIcons.usersThree(PhosphorIconsStyle.fill),
                    active: _showRooms,
                    c: c,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _showRooms = true);
                    },
                  ),
                ],
              ),
            ),
            if (!_showRooms)
              // Search bar (chats only)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
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
                      hintStyle: SeeUTypography.body.copyWith(fontSize: 14, color: c.ink3),
                      prefixIcon: Padding(
                        padding: const EdgeInsets.only(left: 12, right: 8),
                        child: Icon(PhosphorIconsRegular.magnifyingGlass, color: c.ink3, size: 16),
                      ),
                      prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 40),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? GestureDetector(
                              onTap: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                              child: Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: Icon(PhosphorIconsFill.xCircle, color: c.ink3, size: 16),
                              ),
                            )
                          : null,
                      suffixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 40),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
              ),
            // Content
            Expanded(
              child: _showRooms
                  ? _buildRoomsTab(c)
                  : chatState.isLoading
                      ? const SeeUChatSkeleton()
                      : chats.isEmpty
                          ? _buildEmptyState()
                          : _buildChatList(chats, currentUsername),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Rooms tab ───────────────────────────────────────────────────

  Widget _buildRoomsTab(SeeUThemeColors c) {
    final currentUsername =
        ref.watch(authProvider.select((s) => s.user?.username)) ?? '';
    final roomState = ref.watch(roomListProvider);
    final q = _roomSearchQuery.toLowerCase();
    final rooms = q.isEmpty
        ? roomState.rooms
        : roomState.rooms
            .where((r) =>
                r.name.toLowerCase().contains(q) ||
                (r.description?.toLowerCase().contains(q) ?? false))
            .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(SeeURadii.small),
            ),
            child: TextField(
              controller: _roomSearchController,
              onChanged: (v) {
                _roomSearchDebounce?.cancel();
                _roomSearchDebounce = Timer(
                  const Duration(milliseconds: 300),
                  () { if (mounted) setState(() => _roomSearchQuery = v); },
                );
              },
              style: SeeUTypography.body.copyWith(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Поиск комнат',
                hintStyle: SeeUTypography.body.copyWith(fontSize: 14, color: c.ink3),
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 12, right: 8),
                  child: Icon(PhosphorIconsRegular.magnifyingGlass, color: c.ink3, size: 16),
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 40),
                suffixIcon: _roomSearchQuery.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _roomSearchDebounce?.cancel();
                          _roomSearchController.clear();
                          setState(() => _roomSearchQuery = '');
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Icon(PhosphorIconsFill.xCircle, color: c.ink3, size: 16),
                        ),
                      )
                    : null,
                suffixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 40),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
        ),
        Expanded(
          child: roomState.isLoading
              ? const SeeURoomCardSkeleton()
              : rooms.isEmpty
                  ? (_roomSearchQuery.isNotEmpty
                      ? Center(child: Text('Ничего не найдено', style: TextStyle(color: c.ink3)))
                      : _buildRoomsEmpty(c))
                  : SeeURadarRefresh(
                      onRefresh: () => ref.read(roomListProvider.notifier).load(),
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                        itemCount: rooms.length,
                        itemBuilder: (_, i) => _RoomCard(
                          room: rooms[i],
                          currentUsername: currentUsername,
                          onTap: () => context.push('/room/${rooms[i].id}'),
                        ),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildRoomsEmpty(SeeUThemeColors c) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(color: c.surface2, shape: BoxShape.circle),
              child: Icon(PhosphorIcons.usersThree(PhosphorIconsStyle.fill), size: 34, color: c.ink4),
            ),
            const SizedBox(height: 16),
            Text(
              'Пока нет комнат',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.ink),
            ),
            const SizedBox(height: 6),
            Text(
              'Комната — это общий чат с голосовым каналом. Создайте свою или присоединитесь по ссылке.',
              style: TextStyle(fontSize: 13, color: c.ink3, height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Secondary: join by link
                GestureDetector(
                  onTap: _showNewRoomPicker,
                  child: Container(
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    decoration: BoxDecoration(
                      color: c.surface2,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: c.line),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(PhosphorIcons.linkSimple(), size: 15, color: c.ink2),
                        const SizedBox(width: 7),
                        Text('По ссылке', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.ink)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Gradient: create
                GestureDetector(
                  onTap: _showNewRoomPicker,
                  child: Container(
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF5A3C), Color(0xFFFF3B6B)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(PhosphorIcons.plus(PhosphorIconsStyle.bold), size: 15, color: Colors.white),
                        const SizedBox(width: 7),
                        const Text('Создать', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatList(List<Chat> chats, String currentUsername) {
    final c = context.seeuColors;
    final pinned = chats.where((ch) => ch.isPinned).toList();
    final unpinned = chats.where((ch) => !ch.isPinned).toList();
    final allChats = ref.read(chatListProvider).chats;
    final archivedCount = allChats.where((ch) => ch.isArchived).length;

    final items = <Widget>[];

    // Archive tile at the top (only if there are archived chats)
    if (archivedCount > 0) {
      items.add(
        GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => _ArchivedChatsScreen(
                chats: allChats.where((ch) => ch.isArchived).toList(),
              ),
            ),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    color: c.surface2,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(PhosphorIcons.archive(PhosphorIconsStyle.regular), size: 24, color: c.ink3),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Архив ($archivedCount)',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                ),
                Icon(PhosphorIconsRegular.caretRight, size: 16, color: c.ink3),
              ],
            ),
          ),
        ),
      );
    }

    if (pinned.isNotEmpty) {
      items.add(_SectionHeader(label: 'Закреплённые'));
      for (final chat in pinned) {
        items.add(_buildSwipableTile(chat, currentUsername));
      }
      if (unpinned.isNotEmpty) {
        items.add(_SectionHeader(label: 'Все чаты'));
      }
    }
    for (final chat in unpinned) {
      items.add(_buildSwipableTile(chat, currentUsername));
    }

    return SeeURadarRefresh(
      onRefresh: () => ref.read(chatListProvider.notifier).load(),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 100),
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        children: items,
      ),
    );
  }

  Widget _buildSwipableTile(Chat chat, String currentUsername) {
    return _SwipableChatTile(
      key: ValueKey(chat.id),
      chat: chat,
      currentUsername: currentUsername,
      onTap: () {
        HapticFeedback.selectionClick();
        context.push('/chat/${chat.id}');
      },
      onTogglePin: () async {
        HapticFeedback.mediumImpact();
        await ref.read(chatListProvider.notifier).togglePin(chat.id);
      },
      onArchive: () async {
        HapticFeedback.mediumImpact();
        await ref.read(chatListProvider.notifier).archiveChat(chat.id, true);
      },
      onToggleMute: () async {
        HapticFeedback.selectionClick();
        await ref.read(chatListProvider.notifier).muteChat(chat.id, !chat.isMuted);
      },
      onDelete: () => _confirmHideChat(chat),
    );
  }

  void _confirmHideChat(Chat chat) {
    final isGroup = chat.isGroup;
    final isSbor = chat.sborId != null;
    final isOrganizer = chat.isOrganizer;

    final String label;
    final String message;
    if (isOrganizer && isSbor) {
      label = 'Отменить сбор';
      message = 'Сбор «${chat.title}» будет отменён для всех участников.';
    } else if (isSbor) {
      label = 'Покинуть сбор';
      message = 'Вы покинете сбор «${chat.title}» и его групповой чат. Вернуться можно будет через страницу сбора.';
    } else if (isGroup) {
      label = 'Покинуть группу';
      message = 'Вы покинете группу «${chat.title}» и потеряете доступ к истории.';
    } else {
      label = 'Удалить чат';
      message = 'Чат будет удалён только для вас. История собеседника сохранится.';
    }

    showSeeUBottomSheet(
      context: context,
      builder: (sheetCtx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(label, style: SeeUTypography.title),
              const SizedBox(height: 8),
              Text(message,
                  style: SeeUTypography.body
                      .copyWith(color: context.seeuColors.ink2)),
              const SizedBox(height: 20),
              _DestructiveButton(
                label: label,
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  ref.read(chatListProvider.notifier).hideChat(
                    chat.id,
                    isGroup: isGroup,
                    sborId: chat.sborId,
                    isOrganizer: isOrganizer,
                  );
                  // Если выходим из чата сбора — обновляем список сборов тоже.
                  if (isSbor) {
                    ref.read(sborRefreshProvider.notifier).state++;
                  }
                },
              ),
              const SizedBox(height: 8),
              SeeUButton(
                label: 'Отмена',
                variant: SeeUButtonVariant.secondary,
                onTap: () => Navigator.of(sheetCtx).pop(),
              ),
            ],
          ),
        );
      },
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
                  : 'Начните общение с друзьями.\nНажмите карандаш, чтобы написать первое сообщение.',
              textAlign: TextAlign.center,
              style: SeeUTypography.body.copyWith(
                color: c.ink2,
                height: 1.5,
              ),
            ),
            if (!hasSearch) ...[
              const SizedBox(height: 20),
              SeeUButton(
                label: 'Написать',
                onTap: _showNewChatPicker,
                icon: PhosphorIconsRegular.pencilSimple,
                width: 160,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chat tile
// ---------------------------------------------------------------------------

String _kindLabel(String kind) {
  switch (kind) {
    case 'image':
      return '📷 Фото';
    case 'voice':
    case 'audio':
      return '🎙 Голосовое';
    case 'video_note':
      return '📹 Видеосообщение';
    default:
      return '';
  }
}

class _ChatTile extends ConsumerWidget {
  final Chat chat;
  final VoidCallback onTap;
  final String currentUsername;

  const _ChatTile({
    required this.chat,
    required this.onTap,
    required this.currentUsername,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final user = chat.otherUser;
    final isGroup = chat.isGroup;
    final hasUnread = chat.unreadCount > 0;
    // Если текст пуст, показываем метку по типу сообщения.
    final rawMsg = chat.lastMessage.isEmpty
        ? _kindLabel(chat.lastMessageKind)
        : chat.lastMessage;
    final lastMsgTime = chat.lastMessageAt;
    // Если отправитель — текущий юзер → «Вы: текст».
    // Для group: если чужой → «username: текст».
    // Для direct: если чужой → без префикса (имя и так в заголовке чата).
    final String lastMsgWithPrefix;
    if (rawMsg.isEmpty || chat.lastSenderUsername.isEmpty) {
      lastMsgWithPrefix = rawMsg;
    } else if (currentUsername.isNotEmpty &&
        chat.lastSenderUsername == currentUsername) {
      lastMsgWithPrefix = 'Вы: $rawMsg';
    } else if (isGroup) {
      lastMsgWithPrefix = '${chat.lastSenderUsername}: $rawMsg';
    } else {
      lastMsgWithPrefix = rawMsg;
    }
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
                      if (chat.isMuted) ...[
                        const SizedBox(width: 4),
                        Icon(PhosphorIconsRegular.bellSlash, size: 13, color: c.ink3),
                      ],
                      if (isGroup) ...[
                        const SizedBox(width: 6),
                        if (chat.sborId != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF5A3C).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(
                                color: const Color(0xFFFF5A3C).withValues(alpha: 0.35),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  PhosphorIcons.usersThree(PhosphorIconsStyle.fill),
                                  size: 9,
                                  color: SeeUColors.accent,
                                ),
                                const SizedBox(width: 3),
                                const Text(
                                  'СБОР',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: SeeUColors.accent,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          )
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
            // Time + unread badge + pin indicator
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (chat.isPinned) ...[
                      Icon(
                        PhosphorIconsFill.pushPin,
                        size: 11,
                        color: c.ink3,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      _formatTime(lastMsgTime),
                      style: TextStyle(
                        fontSize: 11,
                        color: c.ink3,
                      ),
                    ),
                  ],
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
// Section header (Закреплённые / Все чаты)
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontFamily: 'JetBrains Mono',
          fontSize: 10,
          fontWeight: FontWeight.w500,
          letterSpacing: 1.0,
          color: c.ink3,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Swipable tile wrapper — swipe left to reveal action buttons
// ---------------------------------------------------------------------------

class _SwipableChatTile extends StatefulWidget {
  final Chat chat;
  final String currentUsername;
  final VoidCallback onTap;
  final VoidCallback onTogglePin;
  final VoidCallback onArchive;
  final VoidCallback onToggleMute;
  final VoidCallback onDelete;

  const _SwipableChatTile({
    super.key,
    required this.chat,
    required this.currentUsername,
    required this.onTap,
    required this.onTogglePin,
    required this.onArchive,
    required this.onToggleMute,
    required this.onDelete,
  });

  @override
  State<_SwipableChatTile> createState() => _SwipableChatTileState();
}

class _SwipableChatTileState extends State<_SwipableChatTile>
    with SingleTickerProviderStateMixin {
  // Width of the revealed action panel (archive + pin + delete buttons).
  static const _actionPanelWidth = 216.0; // 3 × 72px buttons

  late final AnimationController _ctrl;
  late final Animation<double> _offset;

  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _offset = Tween<double>(begin: 0, end: -_actionPanelWidth)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _open() {
    if (!_isOpen) {
      setState(() => _isOpen = true);
      _ctrl.forward();
    }
  }

  void _close() {
    if (_isOpen) {
      _ctrl.reverse().then((_) {
        if (mounted) setState(() => _isOpen = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final isGroup = widget.chat.isGroup;

    return GestureDetector(
      onHorizontalDragUpdate: (d) {
        // Only handle leftward swipe.
        if (d.delta.dx < -2) _open();
        if (d.delta.dx > 2) _close();
      },
      onTap: _isOpen ? _close : null,
      // Long-press → context menu for additional options.
      onLongPress: () {
        HapticFeedback.heavyImpact();
        _showContextMenu();
      },
      child: Stack(
        children: [
          // Action buttons (revealed under the tile).
          Positioned.fill(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Archive / Unarchive button.
                _ActionButton(
                  icon: widget.chat.isArchived
                      ? PhosphorIcons.arrowUUpLeft(PhosphorIconsStyle.regular)
                      : PhosphorIcons.archive(PhosphorIconsStyle.regular),
                  label: widget.chat.isArchived ? 'Убрать из архива' : 'В архив',
                  color: c.surface2,
                  iconColor: c.ink3,
                  width: 72,
                  onTap: () {
                    _close();
                    widget.onArchive();
                  },
                ),
                // Pin / Unpin button.
                _ActionButton(
                  icon: widget.chat.isPinned
                      ? PhosphorIconsFill.pushPin
                      : PhosphorIconsRegular.pushPin,
                  label: widget.chat.isPinned ? 'Открепить' : 'Закрепить',
                  color: c.surface2,
                  iconColor: SeeUColors.accent,
                  width: 72,
                  onTap: () {
                    _close();
                    widget.onTogglePin();
                  },
                ),
                // Delete / Leave button.
                _ActionButton(
                  icon: isGroup
                      ? PhosphorIconsRegular.signOut
                      : PhosphorIconsRegular.trash,
                  label: isGroup ? 'Покинуть' : 'Удалить',
                  color: const Color(0xFFFF3B30),
                  iconColor: Colors.white,
                  width: 72,
                  onTap: () {
                    _close();
                    widget.onDelete();
                  },
                ),
              ],
            ),
          ),
          // Tile — slides left on top of action buttons.
          AnimatedBuilder(
            animation: _offset,
            builder: (_, child) => Transform.translate(
              offset: Offset(_offset.value, 0),
              child: child,
            ),
            child: ColoredBox(
              color: c.bg,
              child: _ChatTile(chat: widget.chat, onTap: widget.onTap, currentUsername: widget.currentUsername),
            ),
          ),
        ],
      ),
    );
  }

  void _showContextMenu() {
    _close();
    showSeeUBottomSheet(
      context: context,
      builder: (ctx) {
        final c = context.seeuColors;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  widget.chat.isPinned
                      ? PhosphorIconsFill.pushPin
                      : PhosphorIconsRegular.pushPin,
                  color: SeeUColors.accent,
                ),
                title: Text(
                  widget.chat.isPinned ? 'Открепить' : 'Закрепить',
                  style: SeeUTypography.body,
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  widget.onTogglePin();
                },
              ),
              Divider(color: c.line, height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  widget.chat.isMuted
                      ? PhosphorIconsRegular.bell
                      : PhosphorIconsRegular.bellSlash,
                  color: c.ink2,
                ),
                title: Text(
                  widget.chat.isMuted ? 'Включить звук' : 'Замолчать',
                  style: SeeUTypography.body,
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  widget.onToggleMute();
                },
              ),
              Divider(color: c.line, height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  widget.chat.isArchived
                      ? PhosphorIcons.arrowUUpLeft(PhosphorIconsStyle.regular)
                      : PhosphorIcons.archive(PhosphorIconsStyle.regular),
                  color: c.ink2,
                ),
                title: Text(
                  widget.chat.isArchived ? 'Убрать из архива' : 'В архив',
                  style: SeeUTypography.body,
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  widget.onArchive();
                },
              ),
              Divider(color: c.line, height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  widget.chat.isGroup
                      ? PhosphorIconsRegular.signOut
                      : PhosphorIconsRegular.trash,
                  color: const Color(0xFFFF3B30),
                ),
                title: Text(
                  widget.chat.isGroup ? 'Покинуть группу' : 'Удалить чат',
                  style: SeeUTypography.body
                      .copyWith(color: const Color(0xFFFF3B30)),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  widget.onDelete();
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color iconColor;
  final double width;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.iconColor,
    required this.width,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        color: color,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: iconColor, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: iconColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
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
  final VoidCallback onCreateGroup;

  const _NewChatBottomSheet({
    required this.onUserSelected,
    required this.onCreateGroup,
  });

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
            'Новый чат',
            style: SeeUTypography.title,
          ),
          const SizedBox(height: 12),
          // Создать группу
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Tappable.scaled(
              onTap: widget.onCreateGroup,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: SeeUGradients.heroOrange,
                      ),
                      child: const Icon(
                        PhosphorIconsBold.usersThree,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Создать группу', style: SeeUTypography.subtitle),
                    ),
                    Icon(PhosphorIcons.caretRight(), size: 16, color: c.ink3),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
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

class _DestructiveButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _DestructiveButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          color: const Color(0xFFFF3B30),
          borderRadius: BorderRadius.circular(SeeURadii.medium),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

// ─── Tab chip ─────────────────────────────────────────────────────

class _TabChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final SeeUThemeColors c;
  final VoidCallback onTap;

  const _TabChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.c,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: active ? c.ink : c.surface,
          borderRadius: BorderRadius.circular(SeeURadii.pill),
          border: Border.all(color: active ? c.ink : c.line, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: active ? c.bg : c.ink2),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                color: active ? c.bg : c.ink2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Room card ────────────────────────────────────────────────────

class _RoomCard extends StatelessWidget {
  final Room room;
  final String currentUsername;
  final VoidCallback onTap;

  const _RoomCard({
    required this.room,
    required this.currentUsername,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final isVoice = room.type == 'voice';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            // Cover / icon container
            Builder(builder: (_) {
              final hasCover = room.coverUrl != null && room.coverUrl!.isNotEmpty;
              final palIdx = room.name.isEmpty
                  ? 0
                  : (room.name.codeUnitAt(0) + room.name.length) %
                      SeeUColors.avatarPalettes.length;
              final palette = SeeUColors.avatarPalettes[palIdx];
              final initial = room.name.isNotEmpty ? room.name[0].toUpperCase() : '?';
              return Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  gradient: hasCover
                      ? null
                      : LinearGradient(
                          colors: palette,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  borderRadius: BorderRadius.circular(17),
                ),
                clipBehavior: Clip.antiAlias,
                child: hasCover
                    ? CachedNetworkImage(
                        imageUrl: room.coverUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: palette),
                          ),
                        ),
                        errorWidget: (_, __, ___) => Center(
                          child: Text(
                            initial,
                            style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white,
                            ),
                          ),
                        ),
                      )
                    : Center(
                        child: Text(
                          initial,
                          style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white,
                          ),
                        ),
                      ),
              );
            }),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          room.name,
                          style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600, color: c.ink,
                          ),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Live badge for voice rooms with participants
                      if (isVoice && room.participantCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: SeeUColors.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 5, height: 5,
                                decoration: const BoxDecoration(
                                  color: SeeUColors.accent, shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${room.participantCount}',
                                style: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w700,
                                  color: SeeUColors.accent,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Text(
                          '${room.participantCount} чел.',
                          style: TextStyle(fontSize: 12, color: c.ink3),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _roomLastMsgLabel(isVoice),
                    style: TextStyle(fontSize: 13, color: c.ink3),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(PhosphorIcons.caretRight(), size: 16, color: c.ink4),
          ],
        ),
      ),
    );
  }

  String _roomLastMsgLabel(bool isVoice) {
    final msg = room.lastMessage;
    if (msg == null || msg.isEmpty) {
      return room.description?.isNotEmpty == true
          ? room.description!
          : isVoice ? 'Голосовая комната' : 'Текстовая комната';
    }
    if (room.lastSenderUsername.isEmpty) return msg;
    if (currentUsername.isNotEmpty &&
        room.lastSenderUsername == currentUsername) {
      return 'Вы: $msg';
    }
    return '${room.lastSenderUsername}: $msg';
  }
}


// ---------------------------------------------------------------------------
// Archived chats screen
// ---------------------------------------------------------------------------

class _ArchivedChatsScreen extends ConsumerStatefulWidget {
  final List<Chat> chats;
  const _ArchivedChatsScreen({required this.chats});

  @override
  ConsumerState<_ArchivedChatsScreen> createState() => _ArchivedChatsScreenState();
}

class _ArchivedChatsScreenState extends ConsumerState<_ArchivedChatsScreen> {
  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    // Watch live state so unarchiving updates the list immediately.
    final liveChats = ref.watch(chatListProvider).chats.where((ch) => ch.isArchived).toList();
    final currentUsername =
        ref.watch(authProvider.select((s) => s.user?.username)) ?? '';

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: c.surface,
                        shape: BoxShape.circle,
                        boxShadow: SeeUShadows.sm,
                      ),
                      child: Icon(
                        PhosphorIcons.caretLeft(PhosphorIconsStyle.bold),
                        size: 16, color: c.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Архив',
                    style: TextStyle(
                      fontFamily: 'Fraunces',
                      fontSize: 22, fontWeight: FontWeight.w500,
                      letterSpacing: -0.2, height: 1.1, color: c.ink,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: liveChats.isEmpty
                  ? Center(
                      child: Text('Архив пуст', style: TextStyle(color: c.ink3)),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 40),
                      itemCount: liveChats.length,
                      itemBuilder: (_, i) {
                        final chat = liveChats[i];
                        return _SwipableChatTile(
                          key: ValueKey('arch_${chat.id}'),
                          chat: chat,
                          currentUsername: currentUsername,
                          onTap: () => context.push('/chat/${chat.id}'),
                          onTogglePin: () =>
                              ref.read(chatListProvider.notifier).togglePin(chat.id),
                          onArchive: () =>
                              ref.read(chatListProvider.notifier).archiveChat(chat.id, false),
                          onToggleMute: () => ref
                              .read(chatListProvider.notifier)
                              .muteChat(chat.id, !chat.isMuted),
                          onDelete: () {},
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
