import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/design/design.dart';
import '../../core/providers/chat_provider.dart';
import '../../core/providers/auth_provider.dart';
// Chat uses existing chat_provider; no MockService needed

class ChatScreen extends ConsumerStatefulWidget {
  final String chatId;

  const ChatScreen({super.key, required this.chatId});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  bool _hasText = false;

  /// Tracks message reactions: messageId -> emoji string
  final Map<String, String> _reactions = {};

  /// Which message currently shows the reaction picker (null = none)
  String? _reactionPickerMessageId;

  int _prevMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onTextChanged);
    _scrollToBottom(animate: false);
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = _textController.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final pos = _scrollController.position.maxScrollExtent;
        if (animate) {
          _scrollController.animateTo(
            pos,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        } else {
          _scrollController.jumpTo(pos);
        }
      }
    });
  }

  Future<void> _sendMessage([String? overrideText]) async {
    final text = overrideText ?? _textController.text.trim();
    if (text.isEmpty) return;

    HapticFeedback.lightImpact();
    if (overrideText == null) {
      _textController.clear();
    }

    await ref
        .read(chatMessagesProvider(widget.chatId).notifier)
        .sendMessage(text);
    _scrollToBottom();
  }

  void _onReactionSelected(String messageId, String emoji) {
    setState(() {
      if (_reactions[messageId] == emoji) {
        _reactions.remove(messageId);
      } else {
        _reactions[messageId] = emoji;
      }
      _reactionPickerMessageId = null;
    });
    HapticFeedback.selectionClick();
  }

  void _onMessageLongPress(String messageId) {
    setState(() {
      if (_reactionPickerMessageId == messageId) {
        _reactionPickerMessageId = null;
      } else {
        _reactionPickerMessageId = messageId;
      }
    });
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    final msgState = ref.watch(chatMessagesProvider(widget.chatId));
    final chats = ref.watch(chatListProvider).chats;
    final chat = chats.where((c) => c.id == widget.chatId).isNotEmpty
        ? chats.firstWhere((c) => c.id == widget.chatId)
        : null;
    final currentUser = ref.watch(authProvider).user;
    final myId = currentUser?.id ?? 'me';
    final otherUser = chat?.otherUser;
    // Scroll to bottom only when a new message arrives
    if (msgState.messages.length > _prevMessageCount && _prevMessageCount > 0) {
      _scrollToBottom();
    }
    _prevMessageCount = msgState.messages.length;

    final c = context.seeuColors;
    return GestureDetector(
      onTap: () {
        // Dismiss reaction picker when tapping outside
        if (_reactionPickerMessageId != null) {
          setState(() => _reactionPickerMessageId = null);
        }
      },
      child: Scaffold(
        backgroundColor: c.bg,
        body: Column(
          children: [
            // Header: back chevron + avatar 36px + name + online status + moreV
            Container(
              decoration: BoxDecoration(
                color: c.surface,
                border: Border(
                  bottom: BorderSide(
                    color: c.line,
                    width: 0.5,
                  ),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(
                    children: [
                      // Back chevron
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          context.pop();
                        },
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: const BoxDecoration(
                            color: Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            PhosphorIconsRegular.caretLeft,
                            color: c.ink,
                            size: 22,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      // Avatar 36px
                      if (otherUser != null) ...[
                        _SmallAvatar(
                          avatarUrl: otherUser.avatarUrl,
                          isOnline: false,
                          size: 36,
                        ),
                        const SizedBox(width: 10),
                      ],
                      // Name + online status
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              otherUser?.fullName ?? 'Чат',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: c.ink,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (otherUser != null)
                              Text(
                                'был недавно',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: c.ink3,
                                ),
                              ),
                          ],
                        ),
                      ),
                      // More vertical icon
                      Icon(
                        PhosphorIconsRegular.dotsThreeVertical,
                        size: 22,
                        color: c.ink,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Messages
            Expanded(
              child: msgState.isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: SeeUColors.accent,
                        strokeWidth: 2.5,
                      ),
                    )
                  : msgState.messages.isEmpty
                      ? _buildEmptyChat(otherUser)
                      : _buildMessageList(msgState.messages, myId),
            ),
            // Input bar
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyChat(dynamic otherUser) {
    final c = context.seeuColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (otherUser != null) ...[
              _SmallAvatar(
                avatarUrl: otherUser.avatarUrl,
                isOnline: false,
                size: 64,
              ),
              const SizedBox(height: 16),
              Text(
                otherUser.fullName,
                style: SeeUTypography.title,
              ),
              const SizedBox(height: 4),
              Text(
                '@${otherUser.username}',
                style: SeeUTypography.caption,
              ),
              const SizedBox(height: 16),
            ],
            Text(
              'Начните диалог',
              style: SeeUTypography.body.copyWith(
                color: c.ink2,
              ),
            ),
            // Icebreaker suggestion chips
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _IcebreakerChip(
                  text: 'Привет! Как дела? \u{1F44B}',
                  onTap: () => _sendMessage('Привет! Как дела? \u{1F44B}'),
                ),
                _IcebreakerChip(
                  text: 'Мы были рядом сегодня! \u{1F4CD}',
                  onTap: () =>
                      _sendMessage('Мы были рядом сегодня! \u{1F4CD}'),
                ),
                _IcebreakerChip(
                  text: 'Классный профиль! \u{2728}',
                  onTap: () => _sendMessage('Классный профиль! \u{2728}'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList(List<ChatMessage> messages, String myId) {
    // Group by day
    final groups = <String, List<ChatMessage>>{};
    for (final msg in messages) {
      final key = _dateKey(msg.createdAt);
      groups.putIfAbsent(key, () => []).add(msg);
    }

    final widgets = <Widget>[];
    for (final entry in groups.entries) {
      // Date separator
      widgets.add(
          _DateSeparator(label: _formatDateLabel(entry.value.first.createdAt)));
      for (var i = 0; i < entry.value.length; i++) {
        final msg = entry.value[i];
        final isMine = msg.senderId == myId;
        final showTail = i == entry.value.length - 1 ||
            entry.value[i + 1].senderId != msg.senderId;
        widgets.add(
          _MessageBubble(
            message: msg,
            isMine: isMine,
            showTail: showTail,
            reaction: _reactions[msg.id],
            showReactionPicker: _reactionPickerMessageId == msg.id,
            onLongPress: () => _onMessageLongPress(msg.id),
            onReactionSelected: (emoji) => _onReactionSelected(msg.id, emoji),
          ),
        );
      }
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      physics: const BouncingScrollPhysics(),
      itemCount: widgets.length,
      itemBuilder: (context, index) => widgets[index],
    );
  }

  Widget _buildInputBar() {
    final c = context.seeuColors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(
          top: BorderSide(
            color: c.line,
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Plus button: 38px, surface2
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Скоро')),
                  );
                },
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: c.surface2,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    PhosphorIconsRegular.plus,
                    size: 20,
                    color: c.ink2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Text input: surface2, pill radius
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 120),
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(SeeURadii.pill),
                  ),
                  child: TextField(
                    controller: _textController,
                    focusNode: _focusNode,
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                    style: SeeUTypography.body.copyWith(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Сообщение',
                      hintStyle: SeeUTypography.body.copyWith(
                        fontSize: 14,
                        color: c.ink3,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Send button: 38px, coral
              GestureDetector(
                onTap: _hasText ? _sendMessage : null,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: SeeUColors.accent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    PhosphorIconsFill.paperPlaneRight,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _dateKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  String _formatDateLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(date).inDays;

    if (diff == 0) return 'Сегодня';
    if (diff == 1) return 'Вчера';
    if (diff < 7) {
      const days = [
        'Понедельник',
        'Вторник',
        'Среда',
        'Четверг',
        'Пятница',
        'Суббота',
        'Воскресенье',
      ];
      return days[dt.weekday - 1];
    }
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  }
}

// ---------------------------------------------------------------------------
// Icebreaker chip
// ---------------------------------------------------------------------------

class _IcebreakerChip extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _IcebreakerChip({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Tappable.scaled(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: c.accentSoft,
          borderRadius: BorderRadius.circular(SeeURadii.pill),
          border: Border.all(
            color: SeeUColors.accent.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Text(
          text,
          style: SeeUTypography.caption.copyWith(
            color: SeeUColors.accent,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Date separator
// ---------------------------------------------------------------------------

class _DateSeparator extends StatelessWidget {
  final String label;
  const _DateSeparator({required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 0.5,
              color: c.line,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: SeeUTypography.micro.copyWith(
                color: c.ink3,
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 0.5,
              color: c.line,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Message bubble with reactions and read receipts
// ---------------------------------------------------------------------------

const List<String> _reactionEmojis = [
  '\u{1F525}',
  '\u{2764}\u{FE0F}',
  '\u{1F602}',
  '\u{1F92F}',
  '\u{1F44F}',
];

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;
  final bool showTail;
  final String? reaction;
  final bool showReactionPicker;
  final VoidCallback onLongPress;
  final void Function(String emoji) onReactionSelected;

  const _MessageBubble({
    required this.message,
    required this.isMine,
    this.showTail = true,
    this.reaction,
    this.showReactionPicker = false,
    required this.onLongPress,
    required this.onReactionSelected,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final time =
        '${message.createdAt.hour.toString().padLeft(2, '0')}:${message.createdAt.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: EdgeInsets.only(
        top: showTail ? 6 : 2,
        bottom: reaction != null ? 10 : 0,
        left: isMine ? 48 : 0,
        right: isMine ? 0 : 48,
      ),
      child: Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Reaction picker (shown above the bubble on long press)
          if (showReactionPicker)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(20),
                boxShadow: SeeUShadows.sm,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: _reactionEmojis.map((emoji) {
                  final isSelected = reaction == emoji;
                  return GestureDetector(
                    onTap: () => onReactionSelected(emoji),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: isSelected
                          ? BoxDecoration(
                              color: SeeUColors.accentSoft,
                              shape: BoxShape.circle,
                            )
                          : null,
                      child: Text(
                        emoji,
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          // Bubble row
          GestureDetector(
            onLongPress: onLongPress,
            child: Row(
              mainAxisAlignment:
                  isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isMine) ...[
                  // Time on the left
                  Padding(
                    padding: const EdgeInsets.only(right: 6, bottom: 2),
                    child: Text(
                      time,
                      style: SeeUTypography.micro.copyWith(
                        fontSize: 10,
                        color: c.ink3,
                      ),
                    ),
                  ),
                ],
                // Bubble
                Flexible(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          // own = coral bg; other = surface bg + 0.5px border
                          color: isMine
                              ? SeeUColors.accent
                              : c.surface,
                          // own: 20 20 4 20 / other: 20 20 20 4
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(20),
                            topRight: const Radius.circular(20),
                            bottomLeft: Radius.circular(isMine ? 20 : 4),
                            bottomRight: Radius.circular(isMine ? 4 : 20),
                          ),
                          border: isMine
                              ? null
                              : Border.all(
                                  color: c.line,
                                  width: 0.5,
                                ),
                        ),
                        child: Text(
                          message.text,
                          style: SeeUTypography.body.copyWith(
                            fontSize: 14,
                            color:
                                isMine ? Colors.white : c.ink,
                            height: 1.4,
                          ),
                        ),
                      ),
                      // Reaction badge below the bubble
                      if (reaction != null)
                        Positioned(
                          bottom: -12,
                          right: isMine ? 8 : null,
                          left: isMine ? null : 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: c.surface,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: SeeUShadows.sm,
                            ),
                            child: Text(
                              reaction!,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (isMine) ...[
                  // Time + read receipt on the right
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          time,
                          style: SeeUTypography.micro.copyWith(
                            fontSize: 10,
                            color: c.ink3,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          message.isRead
                              ? PhosphorIconsBold.checks
                              : PhosphorIconsRegular.check,
                          size: 12,
                          color: message.isRead
                              ? const Color(0xFF4FC3F7)
                              : c.ink3,
                        ),
                      ],
                    ),
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

// ---------------------------------------------------------------------------
// Small avatar for app bar
// ---------------------------------------------------------------------------

class _SmallAvatar extends StatelessWidget {
  final String? avatarUrl;
  final bool isOnline;
  final double size;

  const _SmallAvatar({
    this.avatarUrl,
    this.isOnline = false,
    this.size = 36,
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
                width: size * 0.3,
                height: size * 0.3,
                decoration: BoxDecoration(
                  color: SeeUColors.success,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: c.bg,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
