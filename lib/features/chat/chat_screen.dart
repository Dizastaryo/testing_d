import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
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
import '../calls/call_service.dart';
import '../calls/group_call_service.dart';
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
  // ScrollablePositionedList controllers (CHAT-3.1). reverse=true — index 0
  // в нижней части viewport'а (newest message). scroll-to-message работает
  // по индексу + alignment.
  final _itemScrollController = ItemScrollController();
  final _itemPositionsListener = ItemPositionsListener.create();
  final _focusNode = FocusNode();
  bool _hasText = false;
  bool _isUploading = false;
  bool _recording = false;
  ReplyPreview? _replyingTo;
  // CHAT-3.1: scroll-to-search-result + flash highlight. Timer сбрасывает
  // подсветку через 2 сек.
  String? _flashMessageId;
  Timer? _flashTimer;
  // CHAT-11: TTL для следующего сообщения. null/0 = вечно. После send'а
  // сбрасывается обратно в null чтобы случайно не пометить весь чат
  // disappearing'ом (per-message UX, не chat-wide).
  int? _ttlSeconds;

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
    _flashTimer?.cancel();
    _textController.dispose();
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
      if (!_itemScrollController.isAttached) return;
      // reverse=true: index 0 = newest message (визуально внизу viewport'а).
      if (animate) {
        _itemScrollController.scrollTo(
          index: 0,
          alignment: 0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        _itemScrollController.jumpTo(index: 0, alignment: 0.0);
      }
    });
  }

  /// Прокручивает chat к сообщению с заданным id и подсвечивает его на 2 сек
  /// (CHAT-3.1). Если сообщение не в текущем msgState (например, не подгружено
  /// через pagination — пока не реализовано) — silent no-op.
  void _scrollToMessage(String messageId) {
    final messages =
        ref.read(chatMessagesProvider(widget.chatId)).messages;
    final positionedIdx = _positionedIndexForMessage(messageId, messages);
    if (positionedIdx == null) return;

    _flashTimer?.cancel();
    setState(() => _flashMessageId = messageId);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_itemScrollController.isAttached) return;
      _itemScrollController.scrollTo(
        index: positionedIdx,
        // 0.35 — почти центр viewport'а. Так сообщение видно, плюс есть
        // 1-2 соседних сверху/снизу для context'а.
        alignment: 0.35,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });

    _flashTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _flashMessageId = null);
    });
  }

  /// Возвращает positioned-index (для ScrollablePositionedList с reverse=true)
  /// сообщения в widget-листе. Walks ту же day-grouping логику что
  /// `_buildMessageList` чтобы попасть в тот же индекс.
  int? _positionedIndexForMessage(
      String messageId, List<ChatMessage> messages) {
    final groups = <String, List<ChatMessage>>{};
    for (final m in messages) {
      final key = _dateKey(m.createdAt);
      groups.putIfAbsent(key, () => []).add(m);
    }
    int idx = 0;
    int? targetChronIdx;
    for (final entry in groups.entries) {
      idx++; // date separator
      for (final m in entry.value) {
        if (m.id == messageId) {
          targetChronIdx = idx;
        }
        idx++;
      }
    }
    final total = idx;
    if (targetChronIdx == null) return null;
    // reverse=true: positioned_index = total - 1 - chronological_index.
    return total - 1 - targetChronIdx;
  }

  /// Bottom-sheet с поиском по этому чату (CHAT-3). Debounced API + результаты.
  /// CHAT-3.1: тап на результат закрывает sheet, прокручивает chat к
  /// сообщению через ScrollablePositionedList + flash-highlight 2 сек.
  void _showSearchSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _ChatSearchSheet(
        chatId: widget.chatId,
        onResultTap: (m) {
          Navigator.of(sheetCtx).pop();
          _scrollToMessage(m.id);
        },
      ),
    );
  }

  Future<void> _sendMessage([String? overrideText]) async {
    final text = overrideText ?? _textController.text.trim();
    if (text.isEmpty) return;

    HapticFeedback.lightImpact();
    if (overrideText == null) {
      _textController.clear();
    }

    final reply = _replyingTo;
    // CHAT-11: TTL prok'ается + сбрасывается после send'а (per-message, не
    // chat-wide). Если юзер хочет каждое сообщение с TTL — нужно tap'ать
    // ⏱ перед каждым отправлением. Чтобы не было «забыл выключить»
    // ситуаций когда disappearing включается случайно для всего чата.
    final ttl = _ttlSeconds ?? 0;
    await ref
        .read(chatMessagesProvider(widget.chatId).notifier)
        .sendMessage(text, replyTo: reply, expiresInSeconds: ttl);
    if (mounted) {
      setState(() {
        if (reply != null) _replyingTo = null;
        _ttlSeconds = null;
      });
    }
    _scrollToBottom();
  }

  /// Bottom-sheet выбора TTL (CHAT-11). Опции: off / 1h / 24h / 7d.
  void _showTtlPicker() {
    HapticFeedback.selectionClick();
    final c = context.seeuColors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        Widget option(String label, int? seconds, IconData icon) {
          final isSelected = _ttlSeconds == seconds;
          return ListTile(
            leading: Icon(icon,
                color: isSelected ? SeeUColors.accent : c.ink),
            title: Text(label,
                style: SeeUTypography.subtitle.copyWith(
                  color: isSelected ? SeeUColors.accent : c.ink,
                  fontWeight: isSelected
                      ? FontWeight.w700
                      : FontWeight.w500,
                )),
            trailing: isSelected
                ? Icon(PhosphorIconsBold.check,
                    color: SeeUColors.accent, size: 18)
                : null,
            onTap: () {
              Navigator.of(sheetCtx).pop();
              setState(() => _ttlSeconds = seconds);
            },
          );
        }

        return SafeArea(
          child: Container(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(SeeURadii.sheet)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.ink3.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Icon(PhosphorIcons.timer(),
                          color: SeeUColors.accent),
                      const SizedBox(width: 8),
                      Text('Исчезающее сообщение',
                          style: SeeUTypography.title),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                option('Отключить (вечно)', null,
                    PhosphorIcons.infinity()),
                option('Через 1 час', 3600,
                    PhosphorIcons.timer()),
                option('Через 24 часа', 86400,
                    PhosphorIcons.calendarBlank()),
                option('Через 7 дней', 604800,
                    PhosphorIcons.calendarX()),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  String _shortTtlLabel(int seconds) {
    if (seconds >= 604800) return '7д';
    if (seconds >= 86400) return '${seconds ~/ 86400}д';
    if (seconds >= 3600) return '${seconds ~/ 3600}ч';
    if (seconds >= 60) return '${seconds ~/ 60}м';
    return '${seconds}с'; // ignore: unnecessary_brace_in_string_interps
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

      final reply = _replyingTo;
      await ref.read(chatMessagesProvider(widget.chatId).notifier).sendMessage(
            caption,
            attachedMediaUrl: url,
            attachedMediaType: 'image',
            replyTo: reply,
          );
      if (reply != null && mounted) setState(() => _replyingTo = null);

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

      final reply = _replyingTo;
      await ref.read(chatMessagesProvider(widget.chatId).notifier).sendMessage(
            '',
            attachedMediaUrl: url,
            attachedMediaType: 'audio',
            mediaDurationSeconds: durationSec,
            waveform: samples,
            replyTo: reply,
          );
      if (reply != null && mounted) setState(() => _replyingTo = null);
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

  /// Расширенный emoji-picker. Не тащим heavy emoji_picker_flutter (300+ kb),
  /// вместо этого hardcoded grid из ~48 популярных эмодзи 4 категорий.
  /// Для prod-MVP этого хватает; полный picker — отдельная задача.
  static const _expandedEmojiCategories = {
    'Эмоции': ['😀', '😂', '😍', '😎', '😭', '😡', '🤔', '🤩',
        '🥳', '😴', '🥺', '😱'],
    'Сердечки': ['❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍',
        '💔', '💖', '💯', '✨'],
    'Жесты': ['👍', '👎', '👏', '🙌', '🙏', '💪', '🤝', '👌',
        '✌️', '🤘', '🫶', '🫡'],
    'Прочее': ['🔥', '🎉', '🚀', '⭐', '⚡', '💀', '🥰', '😅',
        '🤯', '🤡', '👀', '🎯'],
  };

  void _showExpandedEmojiPicker(String messageId) {
    final c = context.seeuColors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: c.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox.shrink(),
              ..._expandedEmojiCategories.entries.expand((entry) => [
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 8),
                      child: Text(
                        entry.key,
                        style: SeeUTypography.caption.copyWith(
                          color: c.ink3,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: entry.value
                          .map((emoji) => GestureDetector(
                                onTap: () {
                                  Navigator.of(sheetCtx).pop();
                                  _onReactionSelected(messageId, emoji);
                                },
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: c.surface2,
                                    borderRadius:
                                        BorderRadius.circular(SeeURadii.small),
                                  ),
                                  child: Center(
                                    child: Text(emoji,
                                        style: const TextStyle(fontSize: 24)),
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
                  ]),
            ],
          ),
        ),
      ),
    );
  }

  void _onReactionSelected(String messageId, String emoji) {
    setState(() => _reactionPickerMessageId = null);
    HapticFeedback.selectionClick();
    ref
        .read(chatMessagesProvider(widget.chatId).notifier)
        .toggleReaction(messageId, emoji);
  }

  void _onMessageLongPress(String messageId) {
    HapticFeedback.mediumImpact();
    final messages =
        ref.read(chatMessagesProvider(widget.chatId)).messages;
    ChatMessage? msg;
    for (final m in messages) {
      if (m.id == messageId) {
        msg = m;
        break;
      }
    }
    if (msg == null) return;
    final m = msg;
    // Username of reply target: own user или peer из direct-чата.
    final me = ref.read(authProvider).user;
    final chats = ref.read(chatListProvider).chats;
    final chat = chats
        .where((c) => c.id == widget.chatId)
        .cast<Chat?>()
        .firstWhere((_) => true, orElse: () => null);
    final replyUsername = m.isMe
        ? (me?.username ?? '')
        : (chat?.otherUser?.username ?? '');

    final c = context.seeuColors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(SeeURadii.card),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Reactions row: 6 popular + «+» для expanded picker
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ...['❤️', '🔥', '😂', '😮', '😢', '👍'].map(
                        (e) => GestureDetector(
                          onTap: () {
                            Navigator.of(sheetCtx).pop();
                            _onReactionSelected(messageId, e);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text(e,
                                style: const TextStyle(fontSize: 28)),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.of(sheetCtx).pop();
                          _showExpandedEmojiPicker(messageId);
                        },
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: c.surface2,
                          ),
                          child: Icon(PhosphorIcons.plus(),
                              size: 18, color: c.ink),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: c.line),
                ListTile(
                  leading: Icon(PhosphorIcons.arrowBendUpLeft(),
                      color: SeeUColors.accent),
                  title: const Text('Ответить'),
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    setState(() {
                      _replyingTo = ReplyPreview(
                        id: m.id,
                        senderId: m.senderId,
                        senderUsername: replyUsername,
                        text: m.text,
                        kind: m.kind,
                      );
                    });
                    _focusNode.requestFocus();
                  },
                ),
                if (m.text.isNotEmpty)
                  ListTile(
                    leading:
                        Icon(PhosphorIcons.copy(), color: c.ink),
                    title: const Text('Скопировать'),
                    onTap: () {
                      Navigator.of(sheetCtx).pop();
                      Clipboard.setData(ClipboardData(text: m.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Скопировано'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                // Закрепить / Открепить — для всех; backend сам отдаст 403,
                // если в group-чате не админ.
                Builder(builder: (_) {
                  final isAlreadyPinned =
                      chat?.pinnedMessage?.id == m.id;
                  return ListTile(
                    leading: Icon(PhosphorIconsBold.pushPin,
                        color: SeeUColors.accent),
                    title: Text(
                        isAlreadyPinned ? 'Открепить' : 'Закрепить'),
                    onTap: () {
                      Navigator.of(sheetCtx).pop();
                      _setPin(isAlreadyPinned ? null : m.id);
                    },
                  );
                }),
                // Удалить — только для собственных сообщений (бэк всё равно
                // вернёт 403 если не автор, но фронт-фильтрация скрывает
                // пункт от чужих).
                if (m.isMe) ...[
                  Divider(height: 1, color: c.line),
                  ListTile(
                    leading: Icon(PhosphorIcons.trash(), color: Colors.red),
                    title: const Text('Удалить',
                        style: TextStyle(color: Colors.red)),
                    onTap: () {
                      Navigator.of(sheetCtx).pop();
                      _confirmDeleteMessage(messageId);
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
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
                                      Builder(builder: (ctx) {
                                        // CHAT-2.1/2.2: для group typing'а
                                        // показываем «@user печатает…»,
                                        // «@a и @b печатают…», «@a, @b и
                                        // ещё N печатают…».
                                        final typing = ref.watch(
                                            typingProvider(widget.chatId));
                                        final label = typing.buildLabel();
                                        final isTyping = label != null;
                                        final subtitle = isTyping
                                            ? label
                                            : '${chat!.participantsCount} участников';
                                        return Text(
                                          subtitle,
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
                                      })
                                    else if (otherUser != null)
                                      Builder(builder: (ctx) {
                                        // Direct: один peer, label короче —
                                        // «печатает…» без @username (он уже
                                        // в заголовке) или «@x печатает…»
                                        // если бэк прислал.
                                        final typing = ref.watch(
                                            typingProvider(widget.chatId));
                                        final label = typing.buildLabel(
                                            fallbackLabel: '');
                                        final isTyping = label != null;
                                        // Текст: typing > online > last-seen.
                                        final presence =
                                            otherUser.presenceLabel();
                                        final subtitle = isTyping
                                            ? (label.startsWith('@')
                                                ? label
                                                : 'печатает…')
                                            : (presence.isEmpty
                                                ? 'был недавно'
                                                : presence);
                                        final isAccent = isTyping ||
                                            otherUser.isOnline;
                                        return Text(
                                          subtitle,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isAccent
                                                ? SeeUColors.accent
                                                : c.ink3,
                                            fontWeight: isAccent
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
                      // Поиск в чате (CHAT-3). Bottom-sheet с TextField +
                      // debounced API + results list.
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          _showSearchSheet();
                        },
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(
                            PhosphorIconsRegular.magnifyingGlass,
                            size: 22,
                            color: c.ink,
                          ),
                        ),
                      ),
                      // Voice-call (C-2 audio-only) для direct.
                      if (otherUser != null)
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            CallService.instance.startCall(
                              peerId: otherUser.id,
                              peerUsername: otherUser.username,
                              peerAvatarUrl: otherUser.avatarUrl ?? '',
                              kind: CallKind.voice,
                            );
                          },
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(
                              PhosphorIconsRegular.phone,
                              size: 22,
                              color: c.ink,
                            ),
                          ),
                        ),
                      // Video-call для direct.
                      if (otherUser != null)
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            CallService.instance.startCall(
                              peerId: otherUser.id,
                              peerUsername: otherUser.username,
                              peerAvatarUrl: otherUser.avatarUrl ?? '',
                              kind: CallKind.video,
                            );
                          },
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(
                              PhosphorIconsRegular.videoCamera,
                              size: 22,
                              color: c.ink,
                            ),
                          ),
                        ),
                      // C-7: group-call для group-чатов. Voice + video icons
                      // вызывают GroupCallService.startGroupCall с chat_id.
                      if (chat?.isGroup == true) ...[
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            final me =
                                ref.read(authProvider).user;
                            if (me == null) return;
                            GroupCallService.instance.startGroupCall(
                              chatId: widget.chatId,
                              chatTitle: chat!.title,
                              myId: me.id,
                              myUsername: me.username,
                              kind: CallKind.voice,
                            );
                          },
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(
                              PhosphorIconsRegular.phone,
                              size: 22,
                              color: c.ink,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            final me =
                                ref.read(authProvider).user;
                            if (me == null) return;
                            GroupCallService.instance.startGroupCall(
                              chatId: widget.chatId,
                              chatTitle: chat!.title,
                              myId: me.id,
                              myUsername: me.username,
                              kind: CallKind.video,
                            );
                          },
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(
                              PhosphorIconsRegular.videoCamera,
                              size: 22,
                              color: c.ink,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 4),
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
            // Pinned sticky banner — между header'ом и messages.
            if (chat?.pinnedMessage != null)
              _buildPinnedBanner(chat!.pinnedMessage!),
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
        // CHAT-3.1: wrapper с animated bg для flash-highlight на scroll-to.
        // Всегда рендерится (color transparent когда не flashing) чтобы
        // AnimatedContainer мог анимировать color transition в обе стороны.
        widgets.add(
          AnimatedContainer(
            key: ValueKey('flash-${msg.id}'),
            duration: const Duration(milliseconds: 350),
            decoration: BoxDecoration(
              color: msg.id == _flashMessageId
                  ? SeeUColors.accent.withValues(alpha: 0.14)
                  : SeeUColors.accent.withValues(alpha: 0.0),
              borderRadius: BorderRadius.circular(16),
            ),
            child: _MessageBubble(
              message: msg,
              isMine: isMine,
              showTail: showTail,
              reaction: msg.myReaction.isEmpty ? null : msg.myReaction,
              allReactions: msg.reactions,
              showReactionPicker: _reactionPickerMessageId == msg.id,
              onLongPress: () => _onMessageLongPress(msg.id),
              onReactionSelected: (emoji) =>
                  _onReactionSelected(msg.id, emoji),
            ),
          ),
        );
      }
    }

    return ScrollablePositionedList.builder(
      itemScrollController: _itemScrollController,
      itemPositionsListener: _itemPositionsListener,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      physics: const BouncingScrollPhysics(),
      // reverse=true: index 0 рендерится в нижней части viewport'а
      // (newest message внизу — как в любом мессенджере). Поэтому при
      // builder'е достаём элементы в обратном порядке: index 0 = widgets.last.
      reverse: true,
      itemCount: widgets.length,
      itemBuilder: (context, index) =>
          widgets[widgets.length - 1 - index],
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_replyingTo != null) _buildReplyBanner(_replyingTo!),
        Container(
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
              const SizedBox(width: 6),
              // CHAT-11: TTL для следующего сообщения. Active state — accent
              // bg + label «1ч/24ч/7д» под icon'ом.
              GestureDetector(
                onTap: _showTtlPicker,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _ttlSeconds != null
                        ? SeeUColors.accent.withValues(alpha: 0.15)
                        : c.surface2,
                    shape: BoxShape.circle,
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        _ttlSeconds != null
                            ? PhosphorIconsFill.timer
                            : PhosphorIconsRegular.timer,
                        size: 20,
                        color: _ttlSeconds != null
                            ? SeeUColors.accent
                            : c.ink2,
                      ),
                      if (_ttlSeconds != null)
                        Positioned(
                          bottom: 2,
                          right: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 3, vertical: 1),
                            decoration: BoxDecoration(
                              color: SeeUColors.accent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _shortTtlLabel(_ttlSeconds!),
                              style: const TextStyle(
                                fontSize: 7,
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ),
                    ],
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
        ),
      ],
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

  /// Sticky pinned-banner на topе чата. Тап = scroll к оригиналу
  /// (отложено — нужен ScrollController.scrollToIndex по messageId).
  /// Long-press = unpin (для admin/direct-юзера).
  Widget _buildPinnedBanner(ReplyPreview pinned) {
    final c = context.seeuColors;
    return GestureDetector(
      onLongPress: () => _confirmUnpin(),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(
            bottom: BorderSide(color: c.line, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Icon(PhosphorIconsBold.pushPin,
                size: 16, color: SeeUColors.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Закреплено · @${pinned.senderUsername}',
                    style: const TextStyle(
                      color: SeeUColors.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    pinned.shortLabel(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.ink2,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteMessage(String messageId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('Удалить сообщение?'),
        content: const Text(
            'Сообщение пропадёт у всех участников чата.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dlgCtx, false),
              child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dlgCtx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    // Optimistic: убираем из state сразу, чтобы UI отзывался мгновенно.
    final notifier =
        ref.read(chatMessagesProvider(widget.chatId).notifier);
    final snapshot = ref.read(chatMessagesProvider(widget.chatId)).messages;
    notifier.removeLocally(messageId);
    try {
      final api = ref.read(apiClientProvider);
      await api.delete(ApiEndpoints.chatMessageDelete(messageId));
    } on DioException catch (e) {
      // Rollback: возвращаем snapshot.
      notifier.restoreMessages(snapshot);
      messenger.showSnackBar(SnackBar(
          content: Text('Не удалось удалить: ${apiErrorMessage(e)}')));
    }
  }

  Future<void> _confirmUnpin() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Открепить сообщение?'),
        content: const Text('Закреплённое сообщение исчезнет из шапки чата.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Открепить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _setPin(null);
  }

  Future<void> _setPin(String? messageId) async {
    HapticFeedback.mediumImpact();
    try {
      final api = ref.read(apiClientProvider);
      await api.put(
        ApiEndpoints.chatPin(widget.chatId),
        data: {'message_id': messageId},
      );
      // Чат-лист обновится через chat.pinned WS-event.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(messageId == null
              ? 'Сообщение откреплено'
              : 'Сообщение закреплено'),
          duration: const Duration(seconds: 1),
        ),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      final code = e.response?.statusCode ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(code == 403
              ? 'Только админ группы может закреплять'
              : 'Не удалось: ${apiErrorMessage(e)}'),
        ),
      );
    }
  }

  /// Reply-banner над input'ом. Показывает превью оригинала + кнопка ✕.
  Widget _buildReplyBanner(ReplyPreview reply) {
    final c = context.seeuColors;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(
          top: BorderSide(color: c.line, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              gradient: SeeUGradients.heroOrange,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Ответ @${reply.senderUsername}',
                  style: const TextStyle(
                    color: SeeUColors.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  reply.shortLabel(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.ink2,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _replyingTo = null),
            icon: Icon(PhosphorIcons.x(), size: 18, color: c.ink3),
            tooltip: 'Отменить ответ',
          ),
        ],
      ),
    );
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
                  // Time on the left + countdown if expiring (CHAT-11).
                  Padding(
                    padding: const EdgeInsets.only(right: 6, bottom: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          time,
                          style: SeeUTypography.micro.copyWith(
                            fontSize: 10,
                            color: c.ink3,
                          ),
                        ),
                        if (message.expiresAt != null)
                          _TtlCountdown(
                            expiresAt: message.expiresAt!,
                            chatId: message.chatId,
                            messageId: message.id,
                          ),
                      ],
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
                        child: message.replyTo != null
                            ? Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildReplyQuoted(message.replyTo!, isMine, c),
                                  const SizedBox(height: 6),
                                  _buildBubbleContent(message, isMine, c),
                                ],
                              )
                            : _buildBubbleContent(message, isMine, c),
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
                  // Time + read receipt + TTL countdown on the right (CHAT-11).
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
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
                        // Read receipts 3-state + group counter (CHAT-10.1/10.2):
                        //   ✓ (single, ink3)    — sent.
                        //   ✓✓ (double, ink3)   — delivered ≥1 peer.
                        //   ✓✓ (double, accent) — read ≥1 peer.
                        // Для group (recipientsCount > 1) рядом — «X/N»
                        // когда есть прогресс прочтения но не все ещё.
                        Icon(
                          (message.isRead || message.isDelivered)
                              ? PhosphorIconsBold.checks
                              : PhosphorIconsRegular.check,
                          size: 13,
                          color: message.isRead
                              ? SeeUColors.accent
                              : c.ink3,
                        ),
                        if (message.recipientsCount > 1 &&
                            message.readCount > 0 &&
                            message.readCount < message.recipientsCount)
                          Padding(
                            padding: const EdgeInsets.only(left: 3),
                            child: Text(
                              '${message.readCount}/${message.recipientsCount}',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: SeeUColors.accent,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (message.expiresAt != null)
                      _TtlCountdown(
                        expiresAt: message.expiresAt!,
                        chatId: message.chatId,
                        messageId: message.id,
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

  /// Quoted-block reply'я: тонкая accent-stripe слева + sender + краткое
  /// превью текста/типа.
  Widget _buildReplyQuoted(
      ReplyPreview reply, bool isMine, SeeUThemeColors c) {
    final stripeColor = isMine ? Colors.white : SeeUColors.accent;
    final titleColor = isMine ? Colors.white : SeeUColors.accent;
    final textColor = isMine ? Colors.white70 : c.ink2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isMine
            ? Colors.white.withValues(alpha: 0.15)
            : c.surface2,
        borderRadius: BorderRadius.circular(10),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 3, color: stripeColor),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '@${reply.senderUsername}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    reply.shortLabel(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: textColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
        chatId: message.chatId,
        messageId: message.id,
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

// ===========================================================================
// CHAT-3: Search-sheet. TextField + debounced API + results list.
// ===========================================================================

class _ChatSearchSheet extends ConsumerStatefulWidget {
  final String chatId;
  final void Function(ChatMessage) onResultTap;
  const _ChatSearchSheet({
    required this.chatId,
    required this.onResultTap,
  });

  @override
  ConsumerState<_ChatSearchSheet> createState() => _ChatSearchSheetState();
}

class _ChatSearchSheetState extends ConsumerState<_ChatSearchSheet> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<ChatMessage> _results = [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    final q = v.trim();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 300), () => _fetch(q));
  }

  Future<void> _fetch(String q) async {
    if (!mounted) return;
    try {
      final api = ref.read(apiClientProvider);
      final r = await api.get(
        ApiEndpoints.chatMessages(widget.chatId),
        queryParameters: {'q': q, 'limit': 100},
      );
      final data = r.data is Map && (r.data as Map).containsKey('data')
          ? r.data['data']
          : r.data;
      final list = data is List
          ? data
              .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
              .toList()
          : <ChatMessage>[];
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!mounted) return;
      setState(() {
        _results = list;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
        _results = [];
      });
    }
  }

  String _fmtTime(DateTime dt) {
    final now = DateTime.now();
    final sameDay =
        now.year == dt.year && now.month == dt.month && now.day == dt.day;
    if (sameDay) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(SeeURadii.sheet)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.ink3.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(PhosphorIcons.magnifyingGlass(),
                      color: SeeUColors.accent),
                  const SizedBox(width: 8),
                  Text('Поиск в чате', style: SeeUTypography.title),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ctrl,
                autofocus: true,
                onChanged: _onChanged,
                decoration: InputDecoration(
                  hintText: 'Слово или фраза…',
                  filled: true,
                  fillColor: c.surface2,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(child: _buildBody(c)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(SeeUThemeColors c) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: SeeUColors.accent,
          strokeWidth: 2.5,
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text('Ошибка: $_error', style: TextStyle(color: c.ink2)),
        ),
      );
    }
    if (_ctrl.text.trim().isEmpty) {
      return Center(
        child: Text(
          'Введите запрос для поиска',
          style: SeeUTypography.body.copyWith(color: c.ink3),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text('Ничего не найдено',
            style: SeeUTypography.body.copyWith(color: c.ink3)),
      );
    }
    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: c.line),
      itemBuilder: (_, i) {
        final m = _results[i];
        return ListTile(
          dense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          title: Text(
            m.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: SeeUTypography.body.copyWith(fontSize: 13),
          ),
          subtitle: Text(
            _fmtTime(m.createdAt),
            style: SeeUTypography.caption
                .copyWith(color: c.ink3, fontSize: 11),
          ),
          trailing:
              Icon(PhosphorIcons.caretRight(), size: 14, color: c.ink3),
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onResultTap(m);
          },
        );
      },
    );
  }
}

// ===========================================================================
// CHAT-11: TTL countdown bubble — ⏱ N. Auto-remove когда expires_at достигнут.
// ===========================================================================

class _TtlCountdown extends ConsumerStatefulWidget {
  final DateTime expiresAt;
  final String chatId;
  final String messageId;

  const _TtlCountdown({
    required this.expiresAt,
    required this.chatId,
    required this.messageId,
  });

  @override
  ConsumerState<_TtlCountdown> createState() => _TtlCountdownState();
}

class _TtlCountdownState extends ConsumerState<_TtlCountdown> {
  Timer? _ticker;
  bool _removed = false;

  @override
  void initState() {
    super.initState();
    // Tick frequency adaptive: первые 60с — раз в секунду (видно «5с»,
    // «4с»...). Дальше — раз в 30с (минуты/часы не нуждаются в plus-1s).
    final remaining = widget.expiresAt.difference(DateTime.now());
    final interval = remaining.inMinutes < 1
        ? const Duration(seconds: 1)
        : const Duration(seconds: 30);
    _ticker = Timer.periodic(interval, (_) {
      if (!mounted) return;
      if (DateTime.now().isAfter(widget.expiresAt) && !_removed) {
        _removed = true;
        // Удаляем из local state. Janitor бэка добьёт row в БД при
        // следующем тике (или уже добил — load() возвращает filtered).
        ref
            .read(chatMessagesProvider(widget.chatId).notifier)
            .removeMessageLocally(widget.messageId);
      } else {
        setState(() {}); // pure redraw для countdown text
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _format(Duration d) {
    if (d.isNegative) return '0с';
    if (d.inDays >= 1) return '${d.inDays}д';
    if (d.inHours >= 1) {
      final mins = d.inMinutes.remainder(60);
      // ignore: unnecessary_brace_in_string_interps
      return mins == 0 ? '${d.inHours}ч' : '${d.inHours}ч ${mins}м';
    }
    if (d.inMinutes >= 1) return '${d.inMinutes}м';
    return '${d.inSeconds}с';
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.expiresAt.difference(DateTime.now());
    if (remaining.isNegative) {
      // Уже истёк, removeMessageLocally вот-вот сработает — пустой placeholder.
      return const SizedBox.shrink();
    }
    final c = context.seeuColors;
    // Цвет — accent если осталось <1ч (нагнетаем urgency), иначе ink3.
    final urgent = remaining.inHours < 1;
    final color = urgent ? SeeUColors.accent : c.ink3;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIconsFill.timer, size: 10, color: color),
          const SizedBox(width: 2),
          Text(
            _format(remaining),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
