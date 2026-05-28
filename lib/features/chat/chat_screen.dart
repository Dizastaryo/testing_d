import 'dart:async';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/utils/format.dart';
import '../../core/providers/chat_provider.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/realtime_provider.dart';
import '../calls/call_service.dart';
import '../calls/group_call_service.dart';
import 'widgets/chat_message_bubble.dart';
import 'widgets/swipe_to_reply.dart';
import 'widgets/typing_dots.dart';
import 'widgets/chat_search_sheet.dart';
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
  int _messageCount = 0;

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onTextChanged);
    _focusNode.addListener(() { if (mounted) setState(() {}); });
    _itemPositionsListener.itemPositions.addListener(_onScrollPositionsChanged);
    _scrollToBottom(animate: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(chatMessagesProvider(widget.chatId).notifier).markRead();
      }
    });
  }

  @override
  void dispose() {
    _itemPositionsListener.itemPositions.removeListener(_onScrollPositionsChanged);
    _flashTimer?.cancel();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onScrollPositionsChanged() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty || _messageCount == 0) return;
    final maxVisible = positions.map((p) => p.index).reduce((a, b) => a > b ? a : b);
    if (maxVisible >= _messageCount - 2) {
      ref.read(chatMessagesProvider(widget.chatId).notifier).loadOlderMessages();
    }
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
  void _showChatMenu(SeeUThemeColors c) {
    final chats = ref.read(chatListProvider).chats;
    final chat = chats.where((ch) => ch.id == widget.chatId)
        .cast<Chat?>().firstWhere((_) => true, orElse: () => null);
    final isGroup = chat?.isGroup ?? false;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: c.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: Icon(PhosphorIconsRegular.magnifyingGlass, color: c.ink),
              title: const Text('Поиск по чату'),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _showSearchSheet();
              },
            ),
            ListTile(
              leading: Icon(PhosphorIconsRegular.bellSlash, color: c.ink),
              title: const Text('Отключить уведомления'),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Уведомления: скоро появится')),
                );
              },
            ),
            if (isGroup)
              ListTile(
                leading: const Icon(PhosphorIconsRegular.signOut, color: SeeUColors.error),
                title: Text(
                  chat?.isOrganizer == true
                      ? 'Отменить сбор'
                      : chat?.sborId != null
                          ? 'Выйти из сбора'
                          : 'Выйти из группы',
                  style: const TextStyle(color: SeeUColors.error),
                ),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _leaveGroup(sborId: chat?.sborId, isOrganizer: chat?.isOrganizer == true);
                },
              ),
            ListTile(
              leading: const Icon(PhosphorIconsRegular.trash, color: SeeUColors.error),
              title: const Text('Очистить чат', style: TextStyle(color: SeeUColors.error)),
              onTap: () async {
                Navigator.of(sheetCtx).pop();
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: c.surface,
                    title: Text('Очистить историю?', style: TextStyle(color: c.ink, fontSize: 17)),
                    content: Text(
                      'Все сообщения будут удалены только у тебя.',
                      style: TextStyle(color: c.ink2, fontSize: 14),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text('Отмена', style: TextStyle(color: c.ink3)),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Очистить', style: TextStyle(color: SeeUColors.error)),
                      ),
                    ],
                  ),
                );
                if (confirmed == true && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Очистка чата: скоро появится')),
                  );
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _leaveGroup({String? sborId, bool isOrganizer = false}) async {
    final c = context.seeuColors;
    final isSbor = sborId != null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(
          isOrganizer ? 'Отменить сбор?' : isSbor ? 'Выйти из сбора?' : 'Выйти из группы?',
          style: TextStyle(color: c.ink, fontSize: 17),
        ),
        content: Text(
          isOrganizer
              ? 'Сбор будет отменён для всех участников.'
              : isSbor
                  ? 'Ты покинешь сбор и его групповой чат.'
                  : 'Ты покинешь этот групповой чат.',
          style: TextStyle(color: c.ink2, fontSize: 14),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Нет', style: TextStyle(color: c.ink3))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isOrganizer ? 'Отменить сбор' : 'Выйти', style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final api = ref.read(apiClientProvider);
      if (isOrganizer && sborId != null) {
        // Организатор отменяет сбор → DELETE /sbory/:id
        await api.delete(ApiEndpoints.cancelSbor(sborId));
      } else if (isSbor) {
        // Участник покидает сбор → DELETE /sbory/:id/join
        await api.delete(ApiEndpoints.leaveSbor(sborId));
      } else {
        await api.delete(ApiEndpoints.leaveGroupChat(widget.chatId));
      }
      if (mounted) {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/chat');
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  void _showSearchSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => ChatSearchSheet(
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
      messenger.showSnackBar(SnackBar(
        content: Text('Не удалось отправить: ${friendlyError(e)}'),
      ));
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
          SnackBar(content: Text('Не удалось отправить: ${friendlyError(e)}')));
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
                // Удалить: у своих сообщений < 1ч → для всех; иначе (своё > 1ч
                // или чужое) → только у себя. Удалённые сообщения нельзя удалить повторно.
                if (!m.isDeletedForAll) ...[
                  Divider(height: 1, color: c.line),
                  Builder(builder: (_) {
                    final canDeleteForAll = m.isMe &&
                        DateTime.now().difference(m.createdAt) < const Duration(hours: 1);
                    return ListTile(
                      leading: Icon(PhosphorIcons.trash(), color: Colors.red),
                      title: Text(
                        canDeleteForAll ? 'Удалить для всех' : 'Удалить у себя',
                        style: const TextStyle(color: Colors.red),
                      ),
                      onTap: () {
                        Navigator.of(sheetCtx).pop();
                        _confirmDeleteMessage(messageId, forAll: canDeleteForAll);
                      },
                    );
                  }),
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
    _messageCount = msgState.messages.length;

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
        body: Container(
        decoration: BoxDecoration(
          // A1: subtle warm gradient background
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [c.bg, c.surface2.withValues(alpha: 0.5)],
          ),
        ),
        child: Column(
          children: [
            // A2: frosted glass header
            ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: c.surface.withValues(alpha: 0.85),
                border: Border(
                  bottom: BorderSide(
                    color: c.line.withValues(alpha: 0.5),
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
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go('/chat');
                          }
                        },
                        child: Container(
                          width: 44,
                          height: 44,
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
                          // C3: tap header → profile (direct) or members (group)
                          onTap: chat?.isGroup == true
                              ? () => context.push(
                                  '/chat/${widget.chatId}/members')
                              : otherUser != null
                                  ? () => context.push(
                                      '/profile/${otherUser.username}')
                                  : null,
                          child: Row(
                            children: [
                              // C1: avatar 40px + online dot
                              if (chat?.isGroup == true)
                                ChatSmallAvatar(
                                  avatarUrl: chat!.coverUrl,
                                  isOnline: false,
                                  size: 40,
                                  isGroup: true,
                                )
                              else if (otherUser != null)
                                ChatSmallAvatar(
                                  avatarUrl: otherUser.avatarUrl,
                                  isOnline: otherUser.isOnline == true,
                                  size: 40,
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
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
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
                                        // F2: typing dots animation
                                        if (isTyping) {
                                          return Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                label.startsWith('@')
                                                    ? label
                                                    : 'печатает',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: SeeUColors.accent,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              const TypingDots(
                                                  color: SeeUColors.accent,
                                                  size: 4),
                                            ],
                                          );
                                        }
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
                        child: SizedBox(
                          width: 44,
                          height: 44,
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
                          child: SizedBox(
                            width: 44,
                            height: 44,
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
                          child: SizedBox(
                            width: 44,
                            height: 44,
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
                          child: SizedBox(
                            width: 44,
                            height: 44,
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
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: Icon(
                              PhosphorIconsRegular.videoCamera,
                              size: 22,
                              color: c.ink,
                            ),
                          ),
                        ),
                      ],
                      // More vertical icon
                      GestureDetector(
                        onTap: () => _showChatMenu(c),
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Icon(
                            PhosphorIconsRegular.dotsThreeVertical,
                            size: 22,
                            color: c.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ), // close BackdropFilter
            ), // close ClipRect
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
                      : Column(
                          children: [
                            if (msgState.isLoadingOlder)
                              const LinearProgressIndicator(
                                color: SeeUColors.accent,
                                backgroundColor: Colors.transparent,
                              ),
                            Expanded(
                              child: _buildMessageList(msgState.messages, myId, otherUser),
                            ),
                          ],
                        ),
            ),
            // Input bar
            _buildInputBar(),
          ],
        ),
        ), // close A1 gradient Container
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
              ChatSmallAvatar(
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
                ChatIcebreakerChip(
                  text: 'Привет! Как дела? \u{1F44B}',
                  onTap: () => _sendMessage('Привет! Как дела? \u{1F44B}'),
                ),
                ChatIcebreakerChip(
                  text: 'Мы были рядом сегодня! \u{1F4CD}',
                  onTap: () =>
                      _sendMessage('Мы были рядом сегодня! \u{1F4CD}'),
                ),
                ChatIcebreakerChip(
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

  Widget _buildMessageList(List<ChatMessage> messages, String myId, dynamic otherUser) {
    // Resolve current chat for group detection
    final chatList = ref.read(chatListProvider).chats;
    final currentChat = chatList.where((ch) => ch.id == widget.chatId)
        .cast<Chat?>().firstWhere((_) => true, orElse: () => null);

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
          ChatDateSeparator(label: _formatDateLabel(entry.value.first.createdAt)));
      for (var i = 0; i < entry.value.length; i++) {
        final msg = entry.value[i];
        final isMine = msg.senderId == myId;
        final showTail = i == entry.value.length - 1 ||
            entry.value[i + 1].senderId != msg.senderId;
        // CHAT-3.1: wrapper с animated bg для flash-highlight на scroll-to.
        // Всегда рендерится (color transparent когда не flashing) чтобы
        // AnimatedContainer мог анимировать color transition в обе стороны.
        final bubble = AnimatedContainer(
          key: ValueKey('flash-${msg.id}'),
          duration: const Duration(milliseconds: 350),
          decoration: BoxDecoration(
            color: msg.id == _flashMessageId
                ? SeeUColors.accent.withValues(alpha: 0.14)
                : SeeUColors.accent.withValues(alpha: 0.0),
            borderRadius: BorderRadius.circular(16),
          ),
          child: ChatMessageBubble(
            message: msg,
            isMine: isMine,
            showTail: showTail,
            isGroup: currentChat?.isGroup ?? false,
            senderName: isMine ? null : msg.senderName.isNotEmpty ? msg.senderName : null,
            senderAvatarUrl: isMine
                ? null
                : (currentChat?.isGroup == true
                    ? msg.senderAvatarUrl  // empty string → shows initials/icon fallback
                    : otherUser?.avatarUrl),
            reaction: msg.myReaction.isEmpty ? null : msg.myReaction,
            allReactions: msg.reactions,
            showReactionPicker: _reactionPickerMessageId == msg.id,
            onLongPress: () => _onMessageLongPress(msg.id),
            onDoubleTap: () => _onReactionSelected(msg.id, '❤️'),
            onReactionSelected: (emoji) =>
                _onReactionSelected(msg.id, emoji),
          ),
        );
        // E1: swipe right → reply
        widgets.add(
          SwipeToReply(
            onReply: () {
              final me = ref.read(authProvider).user;
              final chats = ref.read(chatListProvider).chats;
              final chat = chats.where((c) => c.id == widget.chatId)
                  .cast<Chat?>().firstWhere((_) => true, orElse: () => null);
              final username = isMine
                  ? (me?.username ?? '')
                  : (chat?.otherUser?.username ?? '');
              setState(() {
                _replyingTo = ReplyPreview(
                  id: msg.id,
                  senderId: msg.senderId,
                  senderUsername: username,
                  text: msg.text,
                  kind: msg.kind,
                );
              });
              _focusNode.requestFocus();
            },
            child: bubble,
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
        // D2: reply banner with slide-in animation
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: _replyingTo != null
              ? _buildReplyBanner(_replyingTo!)
              : const SizedBox.shrink(),
        ),
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
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: c.surface2,
                    shape: BoxShape.circle,
                  ),
                  child: _isUploading
                      ? Padding(
                          padding: const EdgeInsets.all(12),
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
                  width: 44,
                  height: 44,
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
              // D3: text input with focus border
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  constraints: const BoxConstraints(maxHeight: 120),
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(SeeURadii.pill),
                    border: Border.all(
                      color: _focusNode.hasFocus
                          ? SeeUColors.accent.withValues(alpha: 0.4)
                          : c.line.withValues(alpha: 0.5),
                      width: 1,
                    ),
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
              // D1: animated send ↔ mic crossfade
              GestureDetector(
                onTap: _hasText
                    ? _sendMessage
                    : () => setState(() => _recording = true),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: SeeUColors.accent,
                    shape: BoxShape.circle,
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, anim) => ScaleTransition(
                      scale: anim,
                      child: FadeTransition(opacity: anim, child: child),
                    ),
                    child: Icon(
                      _hasText
                          ? PhosphorIconsFill.paperPlaneRight
                          : PhosphorIconsFill.microphone,
                      key: ValueKey(_hasText ? 'send' : 'mic'),
                      size: 20,
                      color: Colors.white,
                    ),
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

  Future<void> _confirmDeleteMessage(String messageId, {bool forAll = true}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('Удалить сообщение?'),
        content: Text(
          forAll
              ? 'Сообщение будет видно как «Сообщение удалено» для всех участников.'
              : 'Сообщение исчезнет только у вас.',
        ),
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
    final notifier = ref.read(chatMessagesProvider(widget.chatId).notifier);
    final snapshot = ref.read(chatMessagesProvider(widget.chatId)).messages;
    // Optimistic update
    if (forAll) {
      notifier.markDeletedForAll(messageId);
    } else {
      notifier.removeLocally(messageId);
    }
    try {
      final api = ref.read(apiClientProvider);
      final url = forAll
          ? ApiEndpoints.chatMessageDelete(messageId)
          : '${ApiEndpoints.chatMessageDelete(messageId)}?scope=self';
      await api.delete(url);
    } on DioException catch (e) {
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

// Widgets extracted to:
//   widgets/chat_message_bubble.dart — ChatMessageBubble, ChatSmallAvatar,
//       ChatSharedPostPreview, ChatImageAttachment, ChatIcebreakerChip,
//       ChatDateSeparator, ChatTtlCountdown
//   widgets/chat_search_sheet.dart  — ChatSearchSheet

