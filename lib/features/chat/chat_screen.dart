import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/config/app_config.dart';
import '../../core/design/design.dart';
import '../../core/providers/chat_provider.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/realtime_provider.dart';
import 'widgets/voice_bubble.dart';
import 'widgets/voice_recorder.dart';
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
  bool _isUploading = false;
  bool _recording = false;

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

  /// Throttle typing pings: server can fan out at most once every 2s.
  /// We send on first keystroke after idle, then suppress until the timer
  /// expires or the field clears.
  DateTime _lastTypingSentAt =
      DateTime.fromMillisecondsSinceEpoch(0);

  void _onTextChanged() {
    final hasText = _textController.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
    if (hasText) {
      final now = DateTime.now();
      if (now.difference(_lastTypingSentAt) >
          const Duration(seconds: 2)) {
        _lastTypingSentAt = now;
        ref.read(realtimeSenderProvider).send(
          'chat.typing',
          {'chat_id': widget.chatId},
        );
      }
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

  /// Pick image from gallery → upload to /media/upload → send as image
  /// message. Caption is the current text input (sent + cleared).
  Future<void> _attachImage() async {
    if (_isUploading) return;
    HapticFeedback.selectionClick();
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    setState(() => _isUploading = true);
    final messenger = ScaffoldMessenger.of(context);
    final caption = _textController.text.trim();

    try {
      final api = ref.read(apiClientProvider);
      final bytes = await picked.readAsBytes();
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: picked.name),
      });
      final upload =
          await api.post(ApiEndpoints.mediaUpload, data: formData);
      final url = upload.data['data']['url'] as String;

      await ref.read(chatMessagesProvider(widget.chatId).notifier).sendMessage(
            caption,
            attachedMediaUrl: url,
            attachedMediaType: 'image',
          );

      if (caption.isNotEmpty) _textController.clear();
      _scrollToBottom();
    } on DioException catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Не удалось отправить: ${apiErrorMessage(e)}'),
      ));
    } catch (e) {
      messenger
          .showSnackBar(SnackBar(content: Text('Не удалось отправить: $e')));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  /// Голосовое сообщение: расшариваем уже-готовый файл (recorder сохранил
  /// в temp), грузим как multipart на /media/upload и отправляем сообщение
  /// с attached_media_type='audio' → backend выставит kind='voice'.
  Future<void> _uploadAndSendVoice(
      String filePath, int durationSec, List<double> samples) async {
    if (filePath.isEmpty) return;
    setState(() => _isUploading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final api = ref.read(apiClientProvider);
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath),
      });
      final upload =
          await api.post(ApiEndpoints.mediaUpload, data: formData);
      final url = upload.data['data']['url'] as String;

      await ref.read(chatMessagesProvider(widget.chatId).notifier).sendMessage(
            '',
            attachedMediaUrl: url,
            attachedMediaType: 'audio',
            mediaDurationSeconds: durationSec,
            waveform: samples,
          );
      _scrollToBottom();
    } on DioException catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Не удалось отправить: ${apiErrorMessage(e)}'),
      ));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Не удалось отправить: $e')));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _onReactionSelected(String messageId, String emoji) {
    setState(() => _reactionPickerMessageId = null);
    HapticFeedback.selectionClick();
    ref
        .read(chatMessagesProvider(widget.chatId).notifier)
        .toggleReaction(messageId, emoji);
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
                      // Header-tail: для group тапается всё подряд → /members,
                      // для direct — статичная плашка с именем (тап на профиль
                      // оставлен как future task).
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: chat?.isGroup == true
                              ? () => context.push(
                                  '/chat/${widget.chatId}/members')
                              : null,
                          child: Row(
                            children: [
                              // Avatar 36px — для group cover_url или
                              // gradient-fallback с usersThree-icon.
                              if (chat?.isGroup == true)
                                _SmallAvatar(
                                  avatarUrl: chat!.coverUrl,
                                  isOnline: false,
                                  size: 36,
                                  isGroup: true,
                                )
                              else if (otherUser != null)
                                _SmallAvatar(
                                  avatarUrl: otherUser.avatarUrl,
                                  isOnline: false,
                                  size: 36,
                                ),
                              const SizedBox(width: 10),
                              // Name + subtitle
                              Expanded(
                                child: Column(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      chat?.isGroup == true
                                          ? chat!.title
                                          : (otherUser?.fullName ?? 'Чат'),
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: c.ink,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (chat?.isGroup == true)
                                      Text(
                                        '${chat!.participantsCount} участников',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: c.ink3,
                                        ),
                                      )
                                    else if (otherUser != null)
                                      Builder(builder: (ctx) {
                                        final isTyping = ref
                                            .watch(typingProvider(
                                                widget.chatId))
                                            .isActive;
                                        return Text(
                                          isTyping
                                              ? 'печатает…'
                                              : 'был недавно',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isTyping
                                                ? SeeUColors.accent
                                                : c.ink3,
                                            fontWeight: isTyping
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                          ),
                                        );
                                      }),
                                  ],
                                ),
                              ),
                            ],
                          ),
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
            reaction: msg.myReaction.isEmpty ? null : msg.myReaction,
            allReactions: msg.reactions,
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
    // Recorder mode — заменяем весь input на VoiceRecorderBar.
    if (_recording) {
      return VoiceRecorderBar(
        onCancel: () => setState(() => _recording = false),
        onSubmit: (path, dur, samples) async {
          setState(() => _recording = false);
          await _uploadAndSendVoice(path, dur, samples);
        },
      );
    }
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
              // Image attachment button: pick → upload → send as image message.
              GestureDetector(
                onTap: _isUploading ? null : _attachImage,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: c.surface2,
                    shape: BoxShape.circle,
                  ),
                  child: _isUploading
                      ? Padding(
                          padding: const EdgeInsets.all(10),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: c.ink2,
                          ),
                        )
                      : Icon(
                          PhosphorIconsRegular.image,
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
              // Send / Voice button: paperPlane если есть текст, mic если нет.
              GestureDetector(
                onTap: _hasText
                    ? _sendMessage
                    : () => setState(() => _recording = true),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    color: SeeUColors.accent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _hasText
                        ? PhosphorIconsFill.paperPlaneRight
                        : PhosphorIconsFill.microphone,
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

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;
  final bool showTail;
  final String? reaction;
  final Map<String, int> allReactions;
  final bool showReactionPicker;
  final VoidCallback onLongPress;
  final void Function(String emoji) onReactionSelected;

  const _MessageBubble({
    required this.message,
    required this.isMine,
    this.showTail = true,
    this.reaction,
    this.allReactions = const {},
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
        bottom: allReactions.isNotEmpty ? 14 : 0,
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
                children: kQuickReactionEmojis.map((emoji) {
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
                        padding: (message.kind == 'shared_post' &&
                                        message.attachedPost != null) ||
                                    (message.kind == 'image' &&
                                        message.attachedMediaUrl.isNotEmpty)
                            ? const EdgeInsets.all(6)
                            : (message.kind == 'voice' ||
                                    message.kind == 'audio')
                                // VoiceBubble сам приносит padding + bg —
                                // обнуляем wrapper'у фон и отступы.
                                ? EdgeInsets.zero
                                : const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          // own = coral bg; other = surface bg + 0.5px border
                          color: (message.kind == 'voice' ||
                                  message.kind == 'audio')
                              ? Colors.transparent
                              : (isMine ? SeeUColors.accent : c.surface),
                          // own: 20 20 4 20 / other: 20 20 20 4
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(20),
                            topRight: const Radius.circular(20),
                            bottomLeft: Radius.circular(isMine ? 20 : 4),
                            bottomRight: Radius.circular(isMine ? 4 : 20),
                          ),
                          border: (message.kind == 'voice' ||
                                  message.kind == 'audio')
                              ? null
                              : isMine
                                  ? null
                                  : Border.all(
                                      color: c.line,
                                      width: 0.5,
                                    ),
                        ),
                        child: _buildBubbleContent(message, isMine, c),
                      ),
                      // Reaction badges below the bubble. Each emoji shown
                      // once with a count if >1; "mine" highlighted in
                      // accent. Tap = toggle (sends to server).
                      if (allReactions.isNotEmpty)
                        Positioned(
                          bottom: -14,
                          right: isMine ? 8 : null,
                          left: isMine ? null : 8,
                          child: Wrap(
                            spacing: 4,
                            children: allReactions.entries
                                .map((e) => GestureDetector(
                                      onTap: () => onReactionSelected(e.key),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: e.key == reaction
                                              ? SeeUColors.accentSoft
                                              : c.surface,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          boxShadow: SeeUShadows.sm,
                                          border: e.key == reaction
                                              ? Border.all(
                                                  color: SeeUColors.accent,
                                                  width: 0.8)
                                              : null,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(e.key,
                                                style: const TextStyle(
                                                    fontSize: 13)),
                                            if (e.value > 1) ...[
                                              const SizedBox(width: 3),
                                              Text('${e.value}',
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      color: c.ink2,
                                                      fontWeight:
                                                          FontWeight.w600)),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ))
                                .toList(),
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

  Widget _buildBubbleContent(
      ChatMessage message, bool isMine, SeeUThemeColors c) {
    if (message.kind == 'shared_post' && message.attachedPost != null) {
      return _SharedPostPreview(
        post: message.attachedPost!,
        isMine: isMine,
        trailingText: message.text,
      );
    }
    if (message.kind == 'image' && message.attachedMediaUrl.isNotEmpty) {
      return _ImageAttachment(
        url: message.attachedMediaUrl,
        isMine: isMine,
        trailingText: message.text,
      );
    }
    // Voice-message: kind='voice' от сервера (или 'audio' для optimistic
    // local-message до прихода response — провайдер uses 'voice' напрямую,
    // но оставляем 'audio' fallback на случай legacy-данных).
    if ((message.kind == 'voice' || message.kind == 'audio') &&
        message.attachedMediaUrl.isNotEmpty) {
      final url = message.attachedMediaUrl.startsWith('http')
          ? message.attachedMediaUrl
          : '${AppConfig.apiOrigin}${message.attachedMediaUrl}';
      return VoiceBubble(
        audioUrl: url,
        durationSec: message.mediaDurationSeconds,
        waveformSamples:
            message.waveform.isNotEmpty ? message.waveform : null,
        isMine: isMine,
      );
    }
    return Text(
      message.text,
      style: SeeUTypography.body.copyWith(
        fontSize: 14,
        color: isMine ? Colors.white : c.ink,
        height: 1.4,
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
  final bool isGroup;

  const _SmallAvatar({
    this.avatarUrl,
    this.isOnline = false,
    this.size = 36,
    this.isGroup = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final hasUrl = avatarUrl != null && avatarUrl!.isNotEmpty;
    final placeholder = Container(
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

// ---------------------------------------------------------------------------
// Shared post preview rendered inside a chat bubble
// ---------------------------------------------------------------------------

class _SharedPostPreview extends StatelessWidget {
  final AttachedPostShort post;
  final bool isMine;
  final String trailingText;
  const _SharedPostPreview({
    required this.post,
    required this.isMine,
    required this.trailingText,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final preview = post.thumbnailUrl.isNotEmpty
        ? post.thumbnailUrl
        : post.mediaUrl;
    final fg = isMine ? Colors.white : c.ink;
    final fgSoft = isMine ? Colors.white.withValues(alpha: 0.85) : c.ink2;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => context.push('/post/${post.id}'),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              decoration: BoxDecoration(
                color: isMine
                    ? Colors.white.withValues(alpha: 0.15)
                    : c.surface2,
                borderRadius: BorderRadius.circular(14),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: preview.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: preview,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(color: c.line),
                            errorWidget: (_, __, ___) =>
                                Container(color: c.line),
                          )
                        : Container(color: c.line),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          post.authorUsername.isNotEmpty
                              ? '@${post.authorUsername}'
                              : 'SeeU',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SeeUTypography.body.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: fg,
                          ),
                        ),
                        if (post.caption.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            post.caption,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: SeeUTypography.body.copyWith(
                              fontSize: 11,
                              color: fgSoft,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (trailingText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
              child: Text(
                trailingText,
                style: SeeUTypography.body.copyWith(
                  fontSize: 14,
                  color: fg,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Image attachment rendered inside a chat bubble
// ---------------------------------------------------------------------------

class _ImageAttachment extends StatelessWidget {
  final String url;
  final bool isMine;
  final String trailingText;
  const _ImageAttachment({
    required this.url,
    required this.isMine,
    required this.trailingText,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final fg = isMine ? Colors.white : c.ink;
    final absUrl = url.startsWith('http')
        ? url
        : (url.startsWith('/') ? '${AppConfig.apiOrigin}$url' : url);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                  maxHeight: 320, minHeight: 120, minWidth: 180),
              child: CachedNetworkImage(
                imageUrl: absUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: c.line,
                  height: 200,
                  width: 180,
                ),
                errorWidget: (_, __, ___) => Container(
                  color: c.line,
                  height: 120,
                  width: 180,
                  child: Icon(PhosphorIconsRegular.imageBroken,
                      color: c.ink3, size: 32),
                ),
              ),
            ),
          ),
          if (trailingText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
              child: Text(
                trailingText,
                style: SeeUTypography.body.copyWith(
                  fontSize: 14,
                  color: fg,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
