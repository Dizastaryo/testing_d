import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
import 'widgets/emoji_sticker_panel.dart';
import 'widgets/voice_recorder.dart';
import '../sticker/sticker_creator_screen.dart';
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
  // Round video message (Telegram-style): double-tap mic → switch to camera mode,
  // long-press camera icon → record circular video message.
  bool _videoMsgMode = false;
  bool _recordingVideoMsg = false;
  int _recordingSeconds = 0;
  Timer? _recordingTimer;
  CameraController? _videoCamController;
  ReplyPreview? _replyingTo;
  String? _editingMessageId;
  // Оригинальный текст редактируемого сообщения — показывается в edit-банере,
  // чтобы юзер видел что редактирует, а не что уже напечатал.
  String _editingOriginalText = '';
  // CHAT-3.1: scroll-to-search-result + flash highlight. Timer сбрасывает
  // подсветку через 2 сек.
  String? _flashMessageId;
  Timer? _flashTimer;
  // CHAT-11: TTL для следующего сообщения. null/0 = вечно. После send'а
  // сбрасывается обратно в null чтобы случайно не пометить весь чат
  // disappearing'ом (per-message UX, не chat-wide).
  int? _ttlSeconds;

  int _messageCount = 0;
  bool _atBottom = true;
  bool _sendError = false;
  String _failedText = '';

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onTextChanged);
    _focusNode.addListener(() {
      if (mounted) setState(() {});
    });
    _itemPositionsListener.itemPositions.addListener(_onScrollPositionsChanged);
    // Прокрутка вниз происходит через ref.listen когда грузятся первые сообщения.
    // Вызов здесь бесполезен — контроллер ещё не прикреплён (список не отрендерен).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(chatMessagesProvider(widget.chatId).notifier).markRead();
      }
    });
  }

  @override
  void dispose() {
    _itemPositionsListener.itemPositions
        .removeListener(_onScrollPositionsChanged);
    _flashTimer?.cancel();
    _recordingTimer?.cancel();
    _videoCamController?.dispose();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onScrollPositionsChanged() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty || _messageCount == 0) return;
    final indices = positions.map((p) => p.index);
    final minVisible = indices.reduce((a, b) => a < b ? a : b);
    final maxVisible = indices.reduce((a, b) => a > b ? a : b);
    // With reverse=true, index 0 = newest message. atBottom when index 0 is visible.
    final atBottom = minVisible == 0;
    if (atBottom != _atBottom) {
      if (mounted) setState(() => _atBottom = atBottom);
    }
    if (maxVisible >= _messageCount - 2) {
      ref
          .read(chatMessagesProvider(widget.chatId).notifier)
          .loadOlderMessages();
    }
  }

  /// Throttle typing pings: server can fan out at most once every 2s.
  /// We send on first keystroke after idle, then suppress until the timer
  /// expires or the field clears.
  DateTime _lastTypingSentAt = DateTime.fromMillisecondsSinceEpoch(0);

  void _onTextChanged() {
    final hasText = _textController.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
    if (hasText) {
      final now = DateTime.now();
      if (now.difference(_lastTypingSentAt) > const Duration(seconds: 2)) {
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
    final messages = ref.read(chatMessagesProvider(widget.chatId)).messages;
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
  // Кнопка звонка для group-чата в хедере.
  Widget _groupCallHeaderButton(SeeUThemeColors c, Chat chat, CallKind kind) {
    final isVoice = kind == CallKind.voice;
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        final me = ref.read(authProvider).user;
        if (me == null) return;
        GroupCallService.instance.startGroupCall(
          chatId: widget.chatId,
          chatTitle: chat.title,
          myId: me.id,
          myUsername: me.username,
          kind: kind,
        );
      },
      child: SizedBox(
        width: 44, height: 44,
        child: Icon(
          isVoice ? PhosphorIconsRegular.phone : PhosphorIconsRegular.videoCamera,
          size: 22, color: c.ink,
        ),
      ),
    );
  }

  // #39: DRY-хелпер для кнопок звонка в хедере direct-чата.
  Widget _callHeaderButton(SeeUThemeColors c, dynamic peer, CallKind kind) {
    final isVoice = kind == CallKind.voice;
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        CallService.instance.startCall(
          peerId: peer.id,
          peerUsername: peer.username,
          peerAvatarUrl: peer.avatarUrl ?? '',
          kind: kind,
        );
      },
      child: SizedBox(
        width: 44,
        height: 44,
        child: Icon(
          isVoice ? PhosphorIconsRegular.phone : PhosphorIconsRegular.videoCamera,
          size: 22,
          color: c.ink,
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
          isOrganizer
              ? 'Отменить сбор?'
              : isSbor
                  ? 'Выйти из сбора?'
                  : 'Выйти из группы?',
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
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Нет', style: TextStyle(color: c.ink3))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isOrganizer ? 'Отменить сбор' : 'Выйти',
                style: const TextStyle(color: Colors.red)),
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
        _focusNode.unfocus();
        context.go('/chat');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  void _showSearchSheet() {
    _focusNode.unfocus();
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

    // Режим редактирования: отправляем PATCH вместо нового сообщения.
    if (_editingMessageId != null) {
      final editId = _editingMessageId!;
      setState(() {
        _editingMessageId = null;
        _editingOriginalText = '';
      });
      _textController.clear();
      try {
        await ref
            .read(chatMessagesProvider(widget.chatId).notifier)
            .editMessage(editId, text);
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Не удалось изменить сообщение'),
          backgroundColor: Colors.redAccent,
        ));
      }
      return;
    }

    final reply = _replyingTo;
    // CHAT-11: TTL prok'ается + сбрасывается после send'а (per-message, не
    // chat-wide). Если юзер хочет каждое сообщение с TTL — нужно tap'ать
    // ⏱ перед каждым отправлением. Чтобы не было «забыл выключить»
    // ситуаций когда disappearing включается случайно для всего чата.
    final ttl = _ttlSeconds ?? 0;
    if (overrideText == null) {
      _textController.clear();
    }
    if (mounted && _sendError) setState(() => _sendError = false);
    try {
      await ref
          .read(chatMessagesProvider(widget.chatId).notifier)
          .sendMessage(text, replyTo: reply, expiresInSeconds: ttl,
              rethrowOnError: true);
      if (mounted) {
        setState(() {
          if (reply != null) _replyingTo = null;
          _ttlSeconds = null;
          _failedText = '';
        });
      }
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      // Restore text so user can retry without retyping.
      if (overrideText == null && _textController.text.isEmpty) {
        _textController.text = text;
        _textController.selection = TextSelection.collapsed(
            offset: _textController.text.length);
      }
      setState(() {
        _sendError = true;
        _failedText = text;
      });
    }
  }

  /// Bottom-sheet выбора TTL (CHAT-11). Опции: off / 1h / 24h / 7d.
  void _showTtlPicker() {
    HapticFeedback.selectionClick();
    _focusNode.unfocus();
    final c = context.seeuColors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        Widget option(String label, int? seconds, IconData icon) {
          final isSelected = _ttlSeconds == seconds;
          return ListTile(
            leading: Icon(icon, color: isSelected ? SeeUColors.accent : c.ink),
            title: Text(label,
                style: SeeUTypography.subtitle.copyWith(
                  color: isSelected ? SeeUColors.accent : c.ink,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
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
                      Icon(PhosphorIcons.timer(), color: SeeUColors.accent),
                      const SizedBox(width: 8),
                      Text('Исчезающее сообщение', style: SeeUTypography.title),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                option('Вечно (выключить)', null, PhosphorIcons.infinity()),
                option('1 час', 3600, PhosphorIcons.timer()),
                option('24 часа', 86400, PhosphorIcons.calendarBlank()),
                option('7 дней', 604800, PhosphorIcons.calendarX()),
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
    return '$secondsс';
  }

  /// Opens the emoji + sticker panel as a bottom sheet.
  void _showEmojiStickerPanel() {
    _focusNode.unfocus();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => EmojiStickerPanel(
        onEmojiSelected: (emoji) {
          Navigator.pop(context);
          final sel = _textController.selection;
          final text = _textController.text;
          final pos = sel.isValid ? sel.baseOffset : text.length;
          final newText = text.substring(0, pos) + emoji + text.substring(pos);
          _textController.value = TextEditingValue(
            text: newText,
            selection: TextSelection.collapsed(offset: pos + emoji.length),
          );
        },
        onStickerSelected: (url) {
          Navigator.pop(context);
          _sendSticker(url);
        },
        onCreateSticker: () {
          Navigator.pop(context);
          _openStickerCreator();
        },
      ),
    );
  }

  Future<void> _sendSticker(String url) async {
    HapticFeedback.lightImpact();
    final reply = _replyingTo;
    try {
      await ref.read(chatMessagesProvider(widget.chatId).notifier).sendMessage(
            '',
            attachedMediaUrl: url,
            attachedMediaType: 'sticker',
            replyTo: reply,
            rethrowOnError: true,
          );
      if (mounted) {
        setState(() => _replyingTo = null);
        _scrollToBottom();
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось отправить стикер'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _openStickerCreator() async {
    final result = await Navigator.push<StickerCreatorResult>(
      context,
      MaterialPageRoute(builder: (_) => const StickerCreatorScreen()),
    );
    if (result != null && mounted) {
      _sendSticker(result.url);
    }
  }

  /// Take photo with camera → upload → send as image message.
  Future<void> _attachFromCamera() async {
    if (_isUploading) return;
    HapticFeedback.selectionClick();
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1920,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    setState(() => _isUploading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final api = ref.read(apiClientProvider);
      final bytes = await picked.readAsBytes();
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: picked.name),
      });
      final upload = await api.post(ApiEndpoints.mediaUpload, data: formData);
      final url = upload.data['data']['url'] as String;
      final reply = _replyingTo;
      await ref.read(chatMessagesProvider(widget.chatId).notifier).sendMessage(
            '',
            attachedMediaUrl: url,
            attachedMediaType: 'image',
            replyTo: reply,
          );
      if (reply != null && mounted) setState(() => _replyingTo = null);
      _scrollToBottom();
    } on DioException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Не удалось: ${apiErrorMessage(e)}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Не удалось: ${friendlyError(e)}')));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
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
      final upload = await api.post(ApiEndpoints.mediaUpload, data: formData);
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

  /// Показывает меню выбора вложения: 8 опций в 4-column grid.
  void _showAttachMenu() {
    if (_isUploading) return;
    _focusNode.unfocus();
    final c = context.seeuColors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        void snackSoon() {
          Navigator.pop(ctx);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Скоро')),
          );
        }

        Widget opt(String label, IconData icon, List<Color> colors, VoidCallback onTap) {
          return GestureDetector(
            onTap: onTap,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: colors,
                    ),
                    boxShadow: SeeUShadows.sm,
                  ),
                  child: Icon(icon, color: Colors.white, size: 25),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: c.ink2,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return Container(
          padding: EdgeInsets.only(
            left: 16, right: 16, top: 0,
            bottom: 16 + MediaQuery.of(ctx).padding.bottom,
          ),
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(SeeURadii.sheet)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: c.line, borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 16),
                child: Text(
                  'Прикрепить',
                  style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w600, color: c.ink,
                  ),
                ),
              ),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 4,
                mainAxisSpacing: 18,
                crossAxisSpacing: 8,
                childAspectRatio: 0.85,
                children: [
                  opt('Камера', PhosphorIconsRegular.camera,
                      const [Color(0xFFFF5A3C), Color(0xFFFF3B6B)],
                      () { Navigator.pop(ctx); _attachFromCamera(); }),
                  opt('Фото', PhosphorIconsRegular.image,
                      const [Color(0xFFC04CFD), Color(0xFF5DB1FF)],
                      () { Navigator.pop(ctx); _attachImage(); }),
                  opt('Видео', PhosphorIconsRegular.videoCamera,
                      const [Color(0xFF5DB1FF), Color(0xFF1AC8B8)],
                      () { Navigator.pop(ctx); _attachFile(); }),
                  opt('Файл', PhosphorIconsRegular.paperclip,
                      const [Color(0xFF2FA84F), Color(0xFF5DB1FF)],
                      () { Navigator.pop(ctx); _attachFile(); }),
                  opt('Геолокация', PhosphorIconsRegular.mapPin,
                      const [Color(0xFFFF8060), Color(0xFFFFB547)],
                      snackSoon),
                  opt('Контакт', PhosphorIconsRegular.userCircle,
                      const [Color(0xFF7B61FF), Color(0xFFC04CFD)],
                      snackSoon),
                  opt('Сбор', PhosphorIconsRegular.usersThree,
                      const [Color(0xFFFFB547), Color(0xFFFF5A3C)],
                      snackSoon),
                  opt('Аудио', PhosphorIconsRegular.microphone,
                      const [Color(0xFF1AC8B8), Color(0xFF5DB1FF)],
                      () { Navigator.pop(ctx); _attachFile(); }),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// Выбор файла через FilePicker → upload → send.
  Future<void> _attachFile() async {
    if (_isUploading) return;
    HapticFeedback.selectionClick();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'jpg', 'jpeg', 'png', 'gif', 'webp',
        'mp4', 'mov', 'webm',
        'mp3', 'm4a', 'wav', 'aac', 'ogg',
      ],
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final file = result.files.first;
    final ext = (file.extension ?? '').toLowerCase();
    final isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext);
    final isVideo = ['mp4', 'mov', 'webm'].contains(ext);
    final isAudio = ['mp3', 'm4a', 'wav', 'aac', 'ogg'].contains(ext);
    if (!isImage && !isVideo && !isAudio) return;
    final mediaType = isImage ? 'image' : isVideo ? 'video' : 'audio';

    setState(() => _isUploading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final api = ref.read(apiClientProvider);
      final FormData formData;
      if (kIsWeb || file.bytes != null) {
        formData = FormData.fromMap({
          'file': MultipartFile.fromBytes(file.bytes!, filename: file.name),
        });
      } else {
        formData = FormData.fromMap({
          'file': await MultipartFile.fromFile(file.path!, filename: file.name),
        });
      }
      final upload = await api.post(ApiEndpoints.mediaUpload, data: formData);
      final url = upload.data['data']['url'] as String;
      final reply = _replyingTo;
      await ref.read(chatMessagesProvider(widget.chatId).notifier).sendMessage(
            '',
            attachedMediaUrl: url,
            attachedMediaType: mediaType,
            replyTo: reply,
          );
      if (reply != null && mounted) setState(() => _replyingTo = null);
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
      final FormData formData;
      if (kIsWeb) {
        // На вебе record возвращает blob URL — прямая загрузка через fromFile
        // невозможна. Показываем ошибку.
        messenger.showSnackBar(const SnackBar(
          content: Text('Голосовые сообщения пока недоступны в веб-версии'),
        ));
        return;
      } else {
        final filename = filePath.split('/').last;
        // Явно указываем audio/mp4 (m4a контейнер) чтобы бэкенд
        // корректно определил тип без fallback на extension.
        formData = FormData.fromMap({
          'file': await MultipartFile.fromFile(
            filePath,
            filename: filename,
            contentType: MediaType('audio', 'mp4'),
          ),
        });
      }
      final upload = await api.post(ApiEndpoints.mediaUpload, data: formData);
      final url = upload.data['data']['url'] as String;

      final reply = _replyingTo;
      await ref.read(chatMessagesProvider(widget.chatId).notifier).sendMessage(
            '',
            attachedMediaUrl: url,
            attachedMediaType: 'audio',
            mediaDurationSeconds: durationSec,
            waveform: samples,
            replyTo: reply,
            rethrowOnError: true,
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
    'Эмоции': [
      '😀', '😂', '🤣', '😅', '😍', '🥰', '😘', '😎', '🤩', '🥳',
      '😭', '😡', '🤔', '🥺', '😱', '🤗', '😏', '🙃', '😴', '🤫',
    ],
    'Сердечки': [
      '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '💔', '💖',
      '💕', '💞', '❣️', '❤️‍🔥', '💯', '✨', '🫶', '💝',
    ],
    'Жесты': [
      '👍', '👎', '👏', '🙌', '🙏', '💪', '🤝', '👌', '✌️', '🤘',
      '🫶', '🤜', '🤛', '👊', '✊', '🤙', '🤞', '🫵',
    ],
    'Прочее': [
      '🔥', '🎉', '🚀', '⭐', '⚡', '💀', '👀', '🎯', '🏆', '🎁',
      '🌈', '😤', '🤯', '🫡', '😬', '🥴', '🤡', '👾',
    ],
  };

  void _showExpandedEmojiPicker(String messageId) {
    _focusNode.unfocus();
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
    HapticFeedback.selectionClick();
    ref
        .read(chatMessagesProvider(widget.chatId).notifier)
        .toggleReaction(messageId, emoji);
  }

  void _onMessageLongPress(String messageId) {
    HapticFeedback.mediumImpact();
    _focusNode.unfocus();
    final messages = ref.read(chatMessagesProvider(widget.chatId)).messages;
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
    // For group chats otherUser is null — use senderUsername from the message.
    final replyUsername = m.isMe
        ? (me?.username ?? '')
        : (m.senderUsername.isNotEmpty
            ? m.senderUsername
            : (chat?.otherUser?.username ?? ''));

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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                            child:
                                Text(e, style: const TextStyle(fontSize: 28)),
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
                if (!m.isDeletedForAll && m.kind != 'deleted')
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
                    leading: Icon(PhosphorIcons.copy(), color: c.ink),
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
                // Переслать сообщение в другой чат
                ListTile(
                  leading: Icon(PhosphorIcons.arrowBendUpRight(), color: c.ink),
                  title: const Text('Переслать'),
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    _showForwardPicker(m);
                  },
                ),
                // Редактировать — только своё текстовое сообщение
                if (m.isMe && m.kind == 'text' && !m.isDeletedForAll)
                  ListTile(
                    leading: Icon(PhosphorIcons.pencil(), color: c.ink),
                    title: const Text('Редактировать'),
                    onTap: () {
                      Navigator.of(sheetCtx).pop();
                      setState(() {
                        _editingMessageId = m.id;
                        _editingOriginalText = m.text;
                        _replyingTo = null;
                      });
                      _textController.text = m.text;
                      _textController.selection = TextSelection.collapsed(
                        offset: m.text.length,
                      );
                      _focusNode.requestFocus();
                    },
                  ),
                // Закрепить / Открепить — для всех; backend сам отдаст 403,
                // если в group-чате не админ.
                Builder(builder: (_) {
                  final isAlreadyPinned = chat?.pinnedMessage?.id == m.id;
                  return ListTile(
                    leading: Icon(PhosphorIconsBold.pushPin,
                        color: SeeUColors.accent),
                    title: Text(isAlreadyPinned ? 'Открепить' : 'Закрепить'),
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
                        DateTime.now().difference(m.createdAt) <
                            const Duration(hours: 1);
                    return ListTile(
                      leading: Icon(PhosphorIcons.trash(), color: Colors.red),
                      title: Text(
                        canDeleteForAll ? 'Удалить для всех' : 'Удалить у себя',
                        style: const TextStyle(color: Colors.red),
                      ),
                      onTap: () {
                        Navigator.of(sheetCtx).pop();
                        _confirmDeleteMessage(messageId,
                            forAll: canDeleteForAll);
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
    _messageCount = msgState.messages.length;

    // Scroll to bottom on new messages; mark read while chat is open.
    ref.listen<ChatMessagesState>(chatMessagesProvider(widget.chatId),
        (prev, next) {
      _messageCount = next.messages.length;
      // Show SnackBar when loading older messages fails.
      if (next.loadOlderFailed && prev?.loadOlderFailed != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось загрузить старые сообщения')),
        );
      }
      // Ignore pagination loads — don't jump to bottom when loading older msgs.
      if (prev?.isLoadingOlder == true && !next.isLoadingOlder) return;
      final prevCount = prev?.messages.length ?? 0;
      final nextCount = next.messages.length;
      if (nextCount > prevCount) {
        _scrollToBottom(animate: prevCount > 0);
        // Mark read when new messages arrive while chat is open.
        if (prevCount > 0) {
          ref.read(chatMessagesProvider(widget.chatId).notifier).markRead();
        }
      }
    });

    final c = context.seeuColors;
    return GestureDetector(
      onTap: () {},
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
          child: Stack(
            children: [
              Column(
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
                                _focusNode.unfocus();
                                if (context.canPop()) {
                                  context.pop();
                                } else {
                                  context.go('/chat');
                                }
                              },
                              child: Icon(
                                  PhosphorIconsRegular.caretLeft,
                                  color: c.ink,
                                  size: 22,
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
                                    ? () => context
                                        .push('/chat/${widget.chatId}/members')
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
                                                : (otherUser?.fullName ??
                                                    'Чат'),
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
                                                  typingProvider(
                                                      widget.chatId));
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
                                                  typingProvider(
                                                      widget.chatId));
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
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      label.startsWith('@')
                                                          ? label
                                                          : 'печатает',
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                        color:
                                                            SeeUColors.accent,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    const TypingDots(
                                                        color:
                                                            SeeUColors.accent,
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
                            // Для direct: 📞 + 📹 в хедере (всего 3 иконки: поиск+звонок+видео)
                            if (otherUser != null) ...[
                              _callHeaderButton(c, otherUser, CallKind.voice),
                              _callHeaderButton(c, otherUser, CallKind.video),
                            ],
                            // Для группы: звонок + видео прямо в хедере (как у direct)
                            if (chat?.isGroup == true) ...[
                              _groupCallHeaderButton(c, chat!, CallKind.voice),
                              _groupCallHeaderButton(c, chat!, CallKind.video),
                            ],
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
                    ? const SeeUMessagesSkeleton()
                    : msgState.error != null
                        ? _buildLoadErrorState(msgState.error!)
                        : msgState.messages.isEmpty
                        ? _buildEmptyChat(otherUser)
                        : Stack(
                            children: [
                              Column(
                                children: [
                                  if (msgState.isLoadingOlder)
                                    const LinearProgressIndicator(
                                      color: SeeUColors.accent,
                                      backgroundColor: Colors.transparent,
                                    ),
                                  Expanded(
                                    child: _buildMessageList(msgState.messages,
                                        myId, otherUser, chat),
                                  ),
                                ],
                              ),
                              // Scroll-to-bottom FAB: shown when scrolled up.
                              if (!_atBottom)
                                Positioned(
                                  bottom: 12,
                                  right: 16,
                                  child: GestureDetector(
                                    onTap: () => _scrollToBottom(),
                                    child: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: c.surface,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: c.line, width: 0.5),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.12),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Icon(
                                        PhosphorIconsRegular.arrowDown,
                                        size: 20,
                                        color: c.ink,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
              ),
              // Input bar
              _buildInputBar(),
                ], // Column children
              ), // Column
              // Round video message overlay
              if (_recordingVideoMsg) _buildRoundVideoOverlay(),
            ], // Stack children
          ), // Stack
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
                  onTap: () => _sendMessage('Мы были рядом сегодня! \u{1F4CD}'),
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

  Widget _buildMessageList(List<ChatMessage> messages, String myId,
      dynamic otherUser, Chat? currentChat) {
    // #30: вместо List<Widget> (O(N) allocation per rebuild) строим плоский
    // список дескрипторов: String = разделитель даты, ChatMessage = сообщение.
    // Виджеты создаются лениво в itemBuilder только для видимых элементов.
    final items = <Object>[];
    final groups = <String, List<ChatMessage>>{};
    for (final msg in messages) {
      // Используем local time — иначе в UTC+N группировка по дням неверна.
      final key = _dateKey(msg.createdAt.toLocal());
      groups.putIfAbsent(key, () => []).add(msg);
    }
    for (final entry in groups.entries) {
      items.add(_formatDateLabel(entry.value.first.createdAt)); // separator
      items.addAll(entry.value);
    }

    return ScrollablePositionedList.builder(
      itemScrollController: _itemScrollController,
      itemPositionsListener: _itemPositionsListener,
      // #22: с reverse=true, EdgeInsets.top — это визуальный низ (под newest msg).
      // Когда FAB виден (!_atBottom), нижние сообщения перекрываются — даём 60px.
      padding: EdgeInsets.fromLTRB(16, _atBottom ? 8 : 60, 16, 8),
      physics: const BouncingScrollPhysics(),
      // reverse=true: index 0 рендерится в нижней части viewport'а
      // (newest message внизу — как в любом мессенджере).
      reverse: true,
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[items.length - 1 - index]; // reverse mapping
        if (item is String) return ChatDateSeparator(label: item);

        final msg = item as ChatMessage;
        final isMine = msg.senderId == myId;
        final rawIdx = items.length - 1 - index;
        // showTail: следующий элемент — разделитель или другой отправитель
        final nextIdx = rawIdx + 1;
        final showTail = nextIdx >= items.length ||
            items[nextIdx] is String ||
            (items[nextIdx] as ChatMessage).senderId != msg.senderId;

        // CHAT-3.1: wrapper с animated bg для flash-highlight на scroll-to.
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
            senderName: isMine
                ? null
                : msg.senderName.isNotEmpty
                    ? msg.senderName
                    : null,
            senderAvatarUrl: isMine
                ? null
                : (currentChat?.isGroup == true
                    ? msg.senderAvatarUrl
                    : otherUser?.avatarUrl),
            reaction: msg.myReaction.isEmpty ? null : msg.myReaction,
            allReactions: msg.reactions,
            onLongPress: () => _onMessageLongPress(msg.id),
            onDoubleTap: () => _onReactionSelected(msg.id, '❤️'),
            onReactionSelected: (emoji) => _onReactionSelected(msg.id, emoji),
          ),
        );
        // E1: swipe right → reply
        return SwipeToReply(
          onReply: () {
            final me = ref.read(authProvider).user;
            final username = isMine
                ? (me?.username ?? '')
                : (msg.senderUsername.isNotEmpty
                    ? msg.senderUsername
                    : (currentChat?.otherUser?.username ?? ''));
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
        );
      },
    );
  }

  // ─── Round video message (Telegram-style) ──────────────────────────────────

  String _fmtRecordingTime(int sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _startVideoRecording() async {
    if (_recordingVideoMsg) return;
    HapticFeedback.mediumImpact();
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final ctrl = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: true,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await ctrl.initialize();
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      _videoCamController = ctrl;
      setState(() {
        _recordingVideoMsg = true;
        _recordingSeconds = 0;
      });
      await ctrl.startVideoRecording();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _recordingSeconds++);
        if (_recordingSeconds >= 60) _stopVideoRecording(); // max 60s
      });
    } catch (_) {
      _videoCamController?.dispose();
      _videoCamController = null;
      if (mounted) setState(() => _recordingVideoMsg = false);
    }
  }

  Future<void> _stopVideoRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    final ctrl = _videoCamController;
    _videoCamController = null;
    if (mounted) setState(() => _recordingVideoMsg = false);
    if (ctrl == null) return;
    try {
      if (ctrl.value.isRecordingVideo) {
        final file = await ctrl.stopVideoRecording();
        ctrl.dispose();
        if (_recordingSeconds < 1) return; // too short — discard
        await _uploadAndSendVideoMsg(file.path);
      } else {
        ctrl.dispose();
      }
    } catch (_) {
      ctrl.dispose();
    }
  }

  Future<void> _uploadAndSendVideoMsg(String filePath) async {
    if (_isUploading) return;
    setState(() => _isUploading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final api = ref.read(apiClientProvider);
      final filename = filePath.split('/').last;
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          filePath,
          filename: filename,
          contentType: MediaType('video', 'mp4'),
        ),
      });
      final upload = await api.post(ApiEndpoints.mediaUpload, data: formData);
      final url = upload.data['data']['url'] as String;
      final reply = _replyingTo;
      await ref.read(chatMessagesProvider(widget.chatId).notifier).sendMessage(
            '',
            attachedMediaUrl: url,
            attachedMediaType: 'video',
            replyTo: reply,
          );
      if (reply != null && mounted) setState(() => _replyingTo = null);
      _scrollToBottom();
    } on DioException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Не удалось: ${apiErrorMessage(e)}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Не удалось: ${friendlyError(e)}')));
    } finally {
      // Clean up temp file
      try { File(filePath).deleteSync(); } catch (_) {}
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Widget _buildRoundVideoOverlay() {
    final ctrl = _videoCamController;
    final initialized = ctrl?.value.isInitialized == true;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.88),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Recording timer
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF3B3B),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _fmtRecordingTime(_recordingSeconds),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              // Circular camera preview with progress ring
              Stack(
                alignment: Alignment.center,
                children: [
                  // Progress ring (max 60s)
                  SizedBox(
                    width: 276,
                    height: 276,
                    child: CircularProgressIndicator(
                      value: _recordingSeconds / 60.0,
                      strokeWidth: 4,
                      backgroundColor: Colors.white.withValues(alpha: 0.15),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF5A3C)),
                    ),
                  ),
                  // Circle camera preview
                  Container(
                    width: 260,
                    height: 260,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                        width: 2,
                      ),
                    ),
                    child: ClipOval(
                      child: initialized
                          ? CameraPreview(ctrl!)
                          : Container(
                              color: const Color(0xFF1A1A1A),
                              child: const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white54,
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 36),
              // Hint
              Text(
                'Отпустите для отправки',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Макс. 60 секунд',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
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
        // Send error banner
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: _sendError
              ? _buildSendErrorBanner(c)
              : const SizedBox.shrink(),
        ),
        // Edit banner
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: _editingMessageId != null
              ? _buildEditBanner(c)
              : const SizedBox.shrink(),
        ),
        // D2: reply banner — instant (no animation delay)
        if (_replyingTo != null) _buildReplyBanner(_replyingTo!),
        Container(
          decoration: BoxDecoration(
            color: c.bg,
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
                  // Attach button: opens menu → photo from gallery or file.
                  GestureDetector(
                    onTap: _isUploading ? null : _showAttachMenu,
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: _isUploading
                          ? Padding(
                              padding: const EdgeInsets.all(10),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: c.ink2,
                              ),
                            )
                          : Icon(
                              PhosphorIcons.plus(PhosphorIconsStyle.bold),
                              size: 22,
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
                      width: 40,
                      height: 40,
                      decoration: _ttlSeconds != null ? BoxDecoration(
                        color: SeeUColors.accent.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ) : null,
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
                  // iMessage-style field: emoji left, send/camera right inside
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      constraints: const BoxConstraints(maxHeight: 120),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(SeeURadii.pill),
                        border: Border.all(
                          color: _focusNode.hasFocus
                              ? SeeUColors.accent.withValues(alpha: 0.4)
                              : c.line,
                          width: 0.5,
                        ),
                        boxShadow: SeeUShadows.sm,
                      ),
                      child: TextField(
                        controller: _textController,
                        focusNode: _focusNode,
                        maxLines: null,
                        textCapitalization: TextCapitalization.sentences,
                        style: SeeUTypography.body.copyWith(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: _editingMessageId != null
                              ? 'Редактировать сообщение'
                              : 'Сообщение…',
                          hintStyle: SeeUTypography.body.copyWith(
                            fontSize: 14,
                            color: c.ink3,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.only(
                            left: 4,
                            right: 4,
                            top: 9,
                            bottom: 9,
                          ),
                          // Emoji/smiley icon — LEFT inside field
                          prefixIcon: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _showEmojiStickerPanel,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              child: Icon(
                                PhosphorIconsRegular.smiley,
                                size: 20,
                                color: c.ink2,
                              ),
                            ),
                          ),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 36,
                          ),
                          // Send button — only when typing
                          suffixIcon: _hasText
                              ? GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _sendMessage,
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: Container(
                                      width: 30,
                                      height: 30,
                                      decoration: const BoxDecoration(
                                        color: SeeUColors.accent,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        PhosphorIconsFill.arrowUp,
                                        size: 15,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                )
                              : null,
                          suffixIconConstraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 36,
                          ),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  // External mic / video-msg button — only when not typing
                  if (!_hasText) ...[
                    const SizedBox(width: 4),
                    if (_videoMsgMode)
                      // Camera icon: long-press → record round video, double-tap → back to mic
                      GestureDetector(
                        onDoubleTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _videoMsgMode = false);
                        },
                        onLongPressStart: (_) => _startVideoRecording(),
                        onLongPressEnd: (_) => _stopVideoRecording(),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: SeeUColors.accent.withValues(alpha: 0.12),
                          ),
                          child: Icon(
                            PhosphorIconsRegular.videoCamera,
                            size: 22,
                            color: SeeUColors.accent,
                          ),
                        ),
                      )
                    else
                      // Mic icon: tap → voice record, double-tap → switch to video mode
                      GestureDetector(
                        onTap: () => setState(() => _recording = true),
                        onDoubleTap: () {
                          HapticFeedback.mediumImpact();
                          setState(() => _videoMsgMode = true);
                        },
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: Icon(
                            PhosphorIconsRegular.microphone,
                            size: 22,
                            color: c.ink2,
                          ),
                        ),
                      ),
                  ],
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
      onTap: () => _scrollToMessage(pinned.id),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(
            bottom: BorderSide(color: c.line, width: 0.5),
          ),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left accent strip
              Container(
                width: 3,
                decoration: BoxDecoration(
                  color: SeeUColors.accent,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(2),
                    bottomRight: Radius.circular(2),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(PhosphorIconsBold.pushPin,
                              size: 12, color: SeeUColors.accent),
                          const SizedBox(width: 4),
                          Text(
                            'Закреплённое',
                            style: const TextStyle(
                              color: SeeUColors.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        pinned.shortLabel(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.ink2, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ),
              // Caret-down to dismiss
              GestureDetector(
                onTap: () => _confirmUnpin(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(
                    PhosphorIconsRegular.caretDown,
                    size: 18,
                    color: c.ink3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadErrorState(String error) {
    final c = context.seeuColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIconsRegular.cloudSlash, size: 52, color: c.ink3),
            const SizedBox(height: 16),
            Text(
              'Не удалось загрузить сообщения',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.ink),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              error,
              style: TextStyle(fontSize: 12, color: c.ink3),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => ref.invalidate(chatMessagesProvider(widget.chatId)),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                decoration: BoxDecoration(
                  color: SeeUColors.accent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Повторить',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSendErrorBanner(SeeUThemeColors c) {
    return Container(
      color: SeeUColors.error.withValues(alpha: 0.10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(PhosphorIconsRegular.warningCircle, size: 16, color: SeeUColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Не удалось отправить',
              style: TextStyle(fontSize: 13, color: SeeUColors.error),
            ),
          ),
          GestureDetector(
            onTap: () => _sendMessage(_failedText),
            child: Text(
              'Повторить',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: SeeUColors.error,
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => setState(() {
              _sendError = false;
              _failedText = '';
            }),
            child: Icon(PhosphorIconsRegular.x, size: 16, color: SeeUColors.error),
          ),
        ],
      ),
    );
  }

  Widget _buildEditBanner(SeeUThemeColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line, width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: SeeUColors.accent,
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
                  'Редактирование',
                  style: const TextStyle(
                    color: SeeUColors.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  _editingOriginalText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.ink2, fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _editingMessageId = null;
                _editingOriginalText = '';
              });
              _textController.clear();
            },
            icon: Icon(PhosphorIcons.x(), size: 18, color: c.ink3),
            tooltip: 'Отменить редактирование',
          ),
        ],
      ),
    );
  }

  void _showForwardPicker(ChatMessage m) {
    _focusNode.unfocus();
    final c = context.seeuColors;
    final api = ref.read(apiClientProvider);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: c.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Переслать в чат',
                  style: SeeUTypography.subtitle.copyWith(color: c.ink),
                ),
              ),
              Flexible(
                child: FutureBuilder<List<Chat>>(
                  future: api.get(ApiEndpoints.chats).then((r) {
                    final list = r.data is Map
                        ? (r.data['data'] as List? ?? [])
                        : (r.data as List? ?? []);
                    return list
                        .map((e) => Chat.fromJson(e as Map<String, dynamic>))
                        .toList();
                  }),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snap.hasError || !snap.hasData) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('Не удалось загрузить чаты',
                            style: SeeUTypography.body.copyWith(color: c.ink3)),
                      );
                    }
                    final chats = snap.data!;
                    return ListView.builder(
                      shrinkWrap: true,
                      itemCount: chats.length,
                      itemBuilder: (_, i) {
                        final chat = chats[i];
                        final name = chat.isGroup
                            ? chat.title
                            : (chat.otherUser?.fullName ?? '');
                        return ListTile(
                          leading: ChatSmallAvatar(
                            avatarUrl: chat.isGroup
                                ? chat.coverUrl
                                : chat.otherUser?.avatarUrl,
                            isGroup: chat.isGroup,
                          ),
                          title: Text(name,
                              style: SeeUTypography.body.copyWith(color: c.ink)),
                          subtitle: chat.isGroup
                              ? Text('${chat.participantsCount} участников',
                                  style: SeeUTypography.caption
                                      .copyWith(color: c.ink3))
                              : null,
                          onTap: () async {
                            Navigator.of(sheetCtx).pop();
                            final messenger = ScaffoldMessenger.of(context);
                            final forwardText = m.text.isNotEmpty
                                ? m.text
                                : '';
                            // Имя оригинального отправителя для баннера
                            final originSender = m.isMe
                                ? (ref.read(authProvider).user?.username ?? '')
                                : (m.senderUsername.isNotEmpty
                                    ? m.senderUsername
                                    : m.senderName);
                            try {
                              await ref
                                  .read(chatMessagesProvider(chat.id).notifier)
                                  .sendMessage(
                                    forwardText,
                                    attachedMediaUrl: m.attachedMediaUrl
                                            .isNotEmpty
                                        ? m.attachedMediaUrl
                                        : null,
                                    attachedMediaType: m.attachedMediaUrl
                                            .isNotEmpty
                                        ? m.attachedMediaType
                                        : null,
                                    forwardedFromMessageId: m.id,
                                    forwardedFromSender: originSender,
                                  );
                              if (mounted) {
                                messenger.showSnackBar(
                                  const SnackBar(content: Text('Переслано')),
                                );
                              }
                            } catch (_) {
                              if (mounted) {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('Ошибка пересылки'),
                                    backgroundColor: Colors.redAccent,
                                  ),
                                );
                              }
                            }
                          },
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteMessage(String messageId,
      {bool forAll = true}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: Text(forAll ? 'Удалить для всех?' : 'Удалить у себя?'),
        content: Text(
          forAll
              ? 'Сообщение станет видно как «Сообщение удалено» для всех участников.'
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
      messenger.showSnackBar(
          SnackBar(content: Text('Не удалось удалить: ${apiErrorMessage(e)}')));
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
