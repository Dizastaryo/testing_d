import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:record/record.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/models/room.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/chat_provider.dart';
import '../../core/providers/realtime_provider.dart';
import '../../core/providers/room_provider.dart';
import '../../core/services/call_bg_service.dart';
import '../../core/services/voice_room_service.dart';
import '../../core/utils/format.dart';
import 'room_members_screen.dart';
import 'widgets/chat_message_bubble.dart' show ChatSmallAvatar;
import 'widgets/emoji_sticker_panel.dart';
import 'widgets/emoji_aware_controller.dart';

class RoomScreen extends ConsumerStatefulWidget {
  final String roomId;
  const RoomScreen({super.key, required this.roomId});

  @override
  ConsumerState<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends ConsumerState<RoomScreen> {
  final _inputController = EmojiAwareController();
  final _scrollController = ScrollController();
  bool _sending = false;
  bool _atBottom = true;
  bool _emojiPanelOpen = false;
  bool _hasText = false;
  int _unreadCount = 0;
  /// Сообщение, на которое отвечаем (reply-quote, паритет с чатами).
  RoomMessage? _replyTo;

  // ── Search ──────────────────────────────────────────────────────────────
  bool _isSearching = false;
  String _searchQuery = '';

  /// Русское склонение: 1 → [one], 2–4 → [few], 5+/11–14 → [many].
  String _pluralRu(int n, String one, String few, String many) {
    final mod100 = n % 100;
    final mod10 = n % 10;
    if (mod100 >= 11 && mod100 <= 14) return many;
    if (mod10 == 1) return one;
    if (mod10 >= 2 && mod10 <= 4) return few;
    return many;
  }
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;

  // ── Mic level monitoring (только пока пользователь в голосовом канале) ──
  final AudioRecorder _micMonitor = AudioRecorder();
  StreamSubscription<dynamic>? _micStreamSub;
  StreamSubscription<Amplitude>? _ampSub;
  final ValueNotifier<double> _myAudioLevel = ValueNotifier(0.0);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _inputController.addListener(_onInputChanged);
    // Регистрируем этот экран как открытый, чтобы CallListener не пушил
    // voice-panel поверх нас при смене minimized.
    VoiceRoomService.instance.currentOpenRoomId = widget.roomId;
    // Скрываем mini-overlay только если это именно наш активный голосовой канал.
    if (VoiceRoomService.instance.activeRoomId.value == widget.roomId) {
      VoiceRoomService.instance.minimized.value = false;
    }
    // Слушаем Android PiP-режим для перерисовки минимального UI.
    CallBgService.instance.pipMode.addListener(_onPipModeChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(roomMessagesProvider(widget.roomId).notifier).markRead();
      }
    });
  }

  void _onPipModeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _inputController.removeListener(_onInputChanged);
    _inputController.dispose();
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _scrollController.dispose();
    _stopMicMonitoring();
    _micMonitor.dispose();
    _myAudioLevel.dispose();
    CallBgService.instance.pipMode.removeListener(_onPipModeChanged);
    VoiceRoomService.instance.currentOpenRoomId = null;
    // Уходим со страницы — если ещё в голосовом, показываем overlay / PiP.
    if (VoiceRoomService.instance.activeRoomId.value == widget.roomId) {
      VoiceRoomService.instance.minimized.value = true;
      if (Platform.isIOS) {
        CallBgService.instance.enterPip(
          username: VoiceRoomService.instance.activeRoomName.value,
          kind: 'room',
          connectedAt: VoiceRoomService.instance.joinedAt.value,
        );
      }
    }
    super.dispose();
  }

  /// Запускает мониторинг уровня микрофона через record package (stream-режим).
  /// Amplitude нормализуется из dBFS [-50..0] → [0..1].
  Future<void> _startMicMonitoring() async {
    _stopMicMonitoring(); // закрываем предыдущий, если был
    if (!await _micMonitor.hasPermission()) return;
    try {
      final stream = await _micMonitor.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      // Читаем поток, чтобы не было backpressure — данные нам не нужны.
      _micStreamSub = stream.listen((_) {});
      _ampSub = _micMonitor
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((amp) {
        final db = amp.current;
        final normalized =
            ((db.clamp(-50.0, 0.0) + 50.0) / 50.0).clamp(0.0, 1.0);
        _myAudioLevel.value = normalized;
      });
    } catch (_) {
      // Если платформа не поддерживает PCM streaming — молча игнорируем.
    }
  }

  void _stopMicMonitoring() {
    _ampSub?.cancel();
    _ampSub = null;
    _micStreamSub?.cancel();
    _micStreamSub = null;
    _myAudioLevel.value = 0.0;
    _micMonitor.stop().ignore(); // fire-and-forget, ошибки suppressed
  }

  void _onInputChanged() {
    final hasText = _inputController.text.trim().isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final atBottom = pos.pixels >= pos.maxScrollExtent - 50;
    if (atBottom != _atBottom) {
      if (mounted) {
        setState(() {
          _atBottom = atBottom;
          if (atBottom) _unreadCount = 0;
        });
        // Докрутил вниз → фактически прочитал: синкаем с сервером, иначе
        // бейдж в списке и read-receipts отправителям висят до перезахода.
        if (atBottom) {
          ref.read(roomMessagesProvider(widget.roomId).notifier).markRead();
        }
      }
    }
    // Подгрузка истории при скролле к верху (раньше страница была одна —
    // сообщения старше первых 50 были недостижимы).
    if (pos.pixels <= 200) {
      ref.read(roomMessagesProvider(widget.roomId).notifier).loadOlder();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;
    final replyTo = _replyTo;
    _inputController.clear();
    setState(() {
      _sending = true;
      _emojiPanelOpen = false;
      _unreadCount = 0;
      _replyTo = null;
    });
    try {
      await ref.read(roomMessagesProvider(widget.roomId).notifier).send(
            text,
            replyToMessageId: replyTo?.id,
          );
      _scrollToBottom();
    } catch (_) {
      // Раньше ошибка сети тихо съедала набранный текст (поле уже очищено,
      // catch отсутствовал) — возвращаем текст и контекст ответа, сообщаем.
      if (mounted) {
        _inputController.text = text;
        setState(() => _replyTo = replyTo);
        showSeeUSnackBar(context, 'Не удалось отправить сообщение',
            tone: SeeUTone.danger);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _toggleEmojiPanel() {
    if (_emojiPanelOpen) {
      setState(() => _emojiPanelOpen = false);
    } else {
      FocusScope.of(context).unfocus();
      setState(() => _emojiPanelOpen = true);
    }
  }

  void _insertEmoji(String emoji) {
    final sel = _inputController.selection;
    final text = _inputController.text;
    final pos = sel.isValid ? sel.baseOffset : text.length;
    final newText = text.substring(0, pos) + emoji + text.substring(pos);
    _inputController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: pos + emoji.length),
    );
  }

  Future<void> _sendSticker(String url) async {
    setState(() => _sending = true);
    try {
      await ref.read(roomMessagesProvider(widget.roomId).notifier).send(
            '',
            attachedMediaUrl: url,
            attachedMediaType: 'sticker',
          );
      _scrollToBottom();
    } catch (_) {
      if (mounted) {
        showSeeUSnackBar(context, 'Не удалось отправить стикер',
            tone: SeeUTone.danger);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendGif(String url) async {
    setState(() => _sending = true);
    try {
      await ref.read(roomMessagesProvider(widget.roomId).notifier).send(
            '',
            attachedMediaUrl: url,
            attachedMediaType: 'gif',
          );
      _scrollToBottom();
    } catch (_) {
      if (mounted) {
        showSeeUSnackBar(context, 'Не удалось отправить GIF',
            tone: SeeUTone.danger);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _toggleReaction(String msgId, String emoji) {
    HapticFeedback.selectionClick();
    ref.read(roomMessagesProvider(widget.roomId).notifier).react(msgId, emoji);
  }

  // ─── Message actions (edit/delete/pin/forward) — BUGS_AUDIT #11 parity ──

  void _showMessageOptions(Room room, RoomMessage m) {
    HapticFeedback.mediumImpact();
    final myId = ref.read(authProvider).user?.id ?? '';
    final isMe = m.senderId == myId;
    final isDeleted = m.isDeletedForAll || m.kind == 'deleted';
    final c = context.seeuColors;

    showSeeUBottomSheet<void>(
      context: context,
      builder: (sheetCtx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isMe && m.senderUsername.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: Row(
                      children: [
                        Icon(PhosphorIconsRegular.user, size: 13, color: c.ink3),
                        const SizedBox(width: 6),
                        Text(
                          m.senderName.isNotEmpty
                              ? '${m.senderName} · @${m.senderUsername}'
                              : '@${m.senderUsername}',
                          style: TextStyle(
                            fontSize: 12,
                            color: c.ink3,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                if (!isDeleted)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ...['❤️', '🔥', '😂', '😮', '😢', '👍'].map(
                          (e) => GestureDetector(
                            onTap: () {
                              Navigator.of(sheetCtx).pop();
                              _toggleReaction(m.id, e);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: Text(e, style: const TextStyle(fontSize: 28)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Divider(height: 1, color: c.line),
                if (!isDeleted)
                  ListTile(
                    leading:
                        Icon(PhosphorIcons.arrowBendUpLeft(), color: c.ink),
                    title: const Text('Ответить'),
                    onTap: () {
                      Navigator.of(sheetCtx).pop();
                      setState(() => _replyTo = m);
                    },
                  ),
                if (m.text.isNotEmpty && !isDeleted)
                  ListTile(
                    leading: Icon(PhosphorIcons.copy(), color: c.ink),
                    title: const Text('Скопировать'),
                    onTap: () {
                      Navigator.of(sheetCtx).pop();
                      Clipboard.setData(ClipboardData(text: m.text));
                      showSeeUSnackBar(context, 'Скопировано',
                          duration: const Duration(seconds: 1));
                    },
                  ),
                if (!isDeleted)
                  ListTile(
                    leading: Icon(PhosphorIcons.arrowBendUpRight(), color: c.ink),
                    title: const Text('Переслать'),
                    onTap: () {
                      Navigator.of(sheetCtx).pop();
                      _showForwardPicker(m);
                    },
                  ),
                if (isMe && m.kind == 'text' && !isDeleted)
                  ListTile(
                    leading: Icon(PhosphorIcons.pencil(), color: c.ink),
                    title: const Text('Редактировать'),
                    onTap: () {
                      Navigator.of(sheetCtx).pop();
                      _showEditMessageSheet(m);
                    },
                  ),
                if (!isDeleted)
                  Builder(builder: (_) {
                    final isAlreadyPinned = room.pinnedMessage?.id == m.id;
                    return ListTile(
                      leading: Icon(PhosphorIconsBold.pushPin, color: SeeUColors.accent),
                      title: Text(isAlreadyPinned ? 'Открепить' : 'Закрепить'),
                      onTap: () {
                        Navigator.of(sheetCtx).pop();
                        _setPin(isAlreadyPinned ? null : m.id);
                      },
                    );
                  }),
                if (!isDeleted) ...[
                  Divider(height: 1, color: c.line),
                  Builder(builder: (_) {
                    final canDeleteForAll = isMe &&
                        DateTime.now().difference(m.createdAt) < const Duration(hours: 1);
                    return ListTile(
                      leading: Icon(PhosphorIcons.trash(), color: SeeUColors.danger),
                      title: Text(
                        canDeleteForAll ? 'Удалить для всех' : 'Удалить у себя',
                        style: const TextStyle(color: SeeUColors.danger),
                      ),
                      onTap: () {
                        Navigator.of(sheetCtx).pop();
                        _confirmDeleteMessage(m, forAll: canDeleteForAll);
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

  void _showEditMessageSheet(RoomMessage m) {
    final controller = TextEditingController(text: m.text);
    showSeeUBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 16,
          bottom: 20 + MediaQuery.of(sheetCtx).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Редактировать сообщение',
                style: SeeUTypography.subtitle.copyWith(color: context.seeuColors.ink)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 4,
              minLines: 1,
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () async {
                final newText = controller.text.trim();
                Navigator.of(sheetCtx).pop();
                if (newText.isEmpty || newText == m.text) return;
                try {
                  await ref
                      .read(roomMessagesProvider(widget.roomId).notifier)
                      .editMessage(m.id, newText);
                } catch (e) {
                  if (mounted) {
                    showSeeUSnackBar(context, friendlyError(e), tone: SeeUTone.danger);
                  }
                }
              },
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  gradient: SeeUGradients.heroOrange,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'Сохранить',
                  style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteMessage(RoomMessage m, {required bool forAll}) async {
    final ok = await showSeeUConfirm(
      context,
      title: forAll ? 'Удалить для всех?' : 'Удалить у себя?',
      message: forAll
          ? 'Сообщение станет видно как «Сообщение удалено» для всех участников.'
          : 'Сообщение исчезнет только у вас.',
      confirmLabel: 'Удалить',
      destructive: true,
      icon: PhosphorIconsRegular.trash,
    );
    if (!ok || !mounted) return;
    final notifier = ref.read(roomMessagesProvider(widget.roomId).notifier);
    final snapshot = ref.read(roomMessagesProvider(widget.roomId)).messages;
    if (forAll) {
      notifier.markDeletedForAll(m.id);
    } else {
      notifier.removeLocally(m.id);
    }
    try {
      final api = ref.read(apiClientProvider);
      final url = forAll
          ? ApiEndpoints.roomMessageDelete(widget.roomId, m.id)
          : '${ApiEndpoints.roomMessageDelete(widget.roomId, m.id)}?scope=self';
      await api.delete(url);
    } catch (e) {
      notifier.restoreMessages(snapshot);
      if (mounted) {
        showSeeUSnackBar(context, 'Не удалось удалить: ${friendlyError(e)}',
            tone: SeeUTone.danger);
      }
    }
  }

  Future<void> _setPin(String? messageId) async {
    HapticFeedback.mediumImpact();
    try {
      await ref
          .read(roomDetailProvider(widget.roomId).notifier)
          .setPinnedMessage(messageId);
      if (!mounted) return;
      showSeeUSnackBar(
          context, messageId == null ? 'Сообщение откреплено' : 'Сообщение закреплено',
          duration: const Duration(seconds: 1));
    } catch (e) {
      if (!mounted) return;
      showSeeUSnackBar(context, friendlyError(e), tone: SeeUTone.danger);
    }
  }

  void _showForwardPicker(RoomMessage m) {
    final c = context.seeuColors;
    final api = ref.read(apiClientProvider);
    showSeeUBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetCtx).size.height * 0.7,
          ),
          child: DefaultTabController(
            length: 2,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    'Переслать',
                    style: SeeUTypography.subtitle.copyWith(color: c.ink),
                  ),
                ),
                TabBar(
                  labelColor: SeeUColors.accent,
                  unselectedLabelColor: c.ink3,
                  indicatorColor: SeeUColors.accent,
                  tabs: const [
                    Tab(text: 'Комнаты'),
                    Tab(text: 'Чаты'),
                  ],
                ),
                Flexible(
                  child: TabBarView(
                    children: [
                      _buildRoomForwardList(sheetCtx, api, m),
                      _buildChatForwardList(sheetCtx, api, m),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRoomForwardList(BuildContext sheetCtx, ApiClient api, RoomMessage m) {
    final c = context.seeuColors;
    return FutureBuilder<List<Room>>(
      future: api.get(ApiEndpoints.rooms).then((r) {
        final list = r.data is Map
            ? (r.data['data'] as List? ?? [])
            : (r.data as List? ?? []);
        return list.map((e) => Room.fromJson(e as Map<String, dynamic>)).toList();
      }),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError || !snap.hasData || snap.data!.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Нет доступных комнат',
                style: SeeUTypography.body.copyWith(color: c.ink3)),
          );
        }
        final rooms = snap.data!;
        return ListView.builder(
          shrinkWrap: true,
          itemCount: rooms.length,
          itemBuilder: (_, i) {
            final room = rooms[i];
            return ListTile(
              leading: _forwardTargetAvatar(room.coverUrl, room.name),
              title: Text(room.name, style: SeeUTypography.body.copyWith(color: c.ink)),
              subtitle: Text('${room.participantCount} участников',
                  style: SeeUTypography.caption.copyWith(color: c.ink3)),
              onTap: () async {
                Navigator.of(sheetCtx).pop();
                await _forwardToRoom(room.id, m);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildChatForwardList(BuildContext sheetCtx, ApiClient api, RoomMessage m) {
    final c = context.seeuColors;
    return FutureBuilder<List<Chat>>(
      future: api.get(ApiEndpoints.chats).then((r) {
        final list = r.data is Map
            ? (r.data['data'] as List? ?? [])
            : (r.data as List? ?? []);
        return list.map((e) => Chat.fromJson(e as Map<String, dynamic>)).toList();
      }),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError || !snap.hasData || snap.data!.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Нет доступных чатов',
                style: SeeUTypography.body.copyWith(color: c.ink3)),
          );
        }
        final chats = snap.data!;
        return ListView.builder(
          shrinkWrap: true,
          itemCount: chats.length,
          itemBuilder: (_, i) {
            final chat = chats[i];
            final name = chat.isGroup ? chat.title : (chat.otherUser?.fullName ?? '');
            return ListTile(
              leading: ChatSmallAvatar(
                avatarUrl: chat.isGroup ? chat.coverUrl : chat.otherUser?.avatarUrl,
                isGroup: chat.isGroup,
              ),
              title: Text(name, style: SeeUTypography.body.copyWith(color: c.ink)),
              subtitle: chat.isGroup
                  ? Text('${chat.participantsCount} участников',
                      style: SeeUTypography.caption.copyWith(color: c.ink3))
                  : null,
              onTap: () async {
                Navigator.of(sheetCtx).pop();
                await _forwardToChat(chat.id, m);
              },
            );
          },
        );
      },
    );
  }

  Widget _forwardTargetAvatar(String? coverUrl, String name) {
    final hasCover = coverUrl != null && coverUrl.isNotEmpty;
    final palIdx = name.isEmpty
        ? 0
        : (name.codeUnitAt(0) + name.length) % SeeUColors.avatarPalettes.length;
    final palette = SeeUColors.avatarPalettes[palIdx];
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'R';
    return Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        gradient: hasCover ? null : LinearGradient(colors: palette),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasCover
          ? CachedNetworkImage(imageUrl: coverUrl, fit: BoxFit.cover)
          : Center(
              child: Text(initial,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
            ),
    );
  }

  Future<void> _forwardToRoom(String targetRoomId, RoomMessage m) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(roomMessagesProvider(targetRoomId).notifier).send(
            m.text,
            attachedMediaUrl: m.attachedMediaUrl?.isNotEmpty == true ? m.attachedMediaUrl : null,
            attachedMediaType:
                m.attachedMediaUrl?.isNotEmpty == true ? m.attachedMediaType : null,
            forwardedFromMessageId: m.id,
            forwardedFromSourceKind: 'room',
          );
      if (mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('Переслано')));
      }
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(const SnackBar(
          content: Text('Ошибка пересылки'),
          backgroundColor: Colors.redAccent,
        ));
      }
    }
  }

  Future<void> _forwardToChat(String chatId, RoomMessage m) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(chatMessagesProvider(chatId).notifier).sendMessage(
            m.text,
            attachedMediaUrl: m.attachedMediaUrl?.isNotEmpty == true ? m.attachedMediaUrl : null,
            attachedMediaType:
                m.attachedMediaUrl?.isNotEmpty == true ? m.attachedMediaType : null,
            forwardedFromMessageId: m.id,
            forwardedFromSourceKind: 'room',
            rethrowOnError: true,
          );
      if (mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('Переслано')));
      }
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(const SnackBar(
          content: Text('Ошибка пересылки'),
          backgroundColor: Colors.redAccent,
        ));
      }
    }
  }

  Future<void> _toggleMute(Room room) async {
    HapticFeedback.mediumImpact();
    final myId = ref.read(authProvider).user?.id ?? '';
    final newMuted = !room.isMuted;
    // Оптимистично синхронизируем мониторинг микрофона с новым состоянием мута
    if (newMuted) {
      _stopMicMonitoring();
    } else {
      _startMicMonitoring();
    }
    ref.read(roomDetailProvider(widget.roomId).notifier).setMyMute(myId, newMuted);
    try {
      await ref.read(apiClientProvider).patch(ApiEndpoints.muteRoom(room.id));
    } catch (_) {
      // Roll back on error — откатываем и мониторинг
      if (newMuted) {
        _startMicMonitoring();
      } else {
        _stopMicMonitoring();
      }
      ref.read(roomDetailProvider(widget.roomId).notifier).setMyMute(myId, room.isMuted);
    }
  }

  Future<void> _joinVoice() async {
    // #M-6: не вызываем joinVoice если уже в голосовом (защита от двойного тапа)
    final room = ref.read(roomDetailProvider(widget.roomId)).room;
    if (room == null || room.isInVoice) return;
    HapticFeedback.mediumImpact();

    // Если уже в голосовом канале ДРУГОЙ комнаты — выходим оттуда автоматически.
    final prevRoomId = VoiceRoomService.instance.activeRoomId.value;
    if (prevRoomId != null && prevRoomId != widget.roomId) {
      _stopMicMonitoring();
      try {
        await ref.read(apiClientProvider).delete(ApiEndpoints.roomVoice(prevRoomId));
      } catch (_) {}
      VoiceRoomService.instance.leave(); // очищает activeRoomId, убирает mini-overlay
    }

    final myId = ref.read(authProvider).user?.id ?? '';
    final success = await ref.read(roomDetailProvider(widget.roomId).notifier).joinVoice(myId);
    if (success) {
      VoiceRoomService.instance.join(widget.roomId, room.name);
      // Начинаем мониторить микрофон, если не замьючены
      if (!room.isMuted) _startMicMonitoring();
    }
  }

  Future<void> _leaveVoice() async {
    HapticFeedback.lightImpact();
    final myId = ref.read(authProvider).user?.id ?? '';
    _stopMicMonitoring();
    final success = await ref.read(roomDetailProvider(widget.roomId).notifier).leaveVoice(myId);
    if (success) {
      VoiceRoomService.instance.leave();
    } else {
      // API failed — rollback mic monitoring if we were unmuted
      final room = ref.read(roomDetailProvider(widget.roomId)).room;
      if (room != null && room.isInVoice && !room.isMuted) {
        _startMicMonitoring();
      }
    }
  }

  Future<void> _leaveRoom() async {
    final confirmed = await showSeeUConfirm(
      context,
      title: 'Покинуть комнату?',
      message: 'Вы выйдете из комнаты.',
      confirmLabel: 'Покинуть',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      // #M-5: явно выходим из голосового канала перед выходом из комнаты,
      // чтобы не оставаться "призраком" в голосовом списке других участников.
      final roomState = ref.read(roomDetailProvider(widget.roomId)).room;
      if (roomState?.isInVoice == true) {
        VoiceRoomService.instance.leave();
        try {
          await ref
              .read(apiClientProvider)
              .delete(ApiEndpoints.roomVoice(widget.roomId));
        } catch (_) {
          // не критично — бэкенд должен очищать при leave room
        }
      }
      await ref.read(apiClientProvider).delete(ApiEndpoints.leaveRoom(widget.roomId));
      ref.read(roomListProvider.notifier).load();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      showSeeUSnackBar(context, friendlyError(e), tone: SeeUTone.danger);
    }
  }

  Future<void> _closeRoom() async {
    final confirmed = await showSeeUConfirm(
      context,
      title: 'Закрыть комнату?',
      message: 'Все участники будут отключены.',
      confirmLabel: 'Закрыть',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    _stopMicMonitoring();
    VoiceRoomService.instance.leave();
    try {
      await ref.read(apiClientProvider).delete(ApiEndpoints.roomById(widget.roomId));
      ref.read(roomListProvider.notifier).load();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      showSeeUSnackBar(context, friendlyError(e), tone: SeeUTone.danger);
    }
  }

  Widget _buildVoicePipContent(Room room) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: SeeUColors.accent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                PhosphorIcons.microphone(PhosphorIconsStyle.fill),
                color: SeeUColors.accent,
                size: 26,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              room.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Голосовой канал',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final detailState = ref.watch(roomDetailProvider(widget.roomId));
    final room = detailState.room;
    final myId = ref.watch(authProvider).user?.id ?? '';
    final msgsState = ref.watch(roomMessagesProvider(widget.roomId));

    // Если текущего пользователя удалили из комнаты — закрываем экран.
    // Backend отправляет два события:
    //   'room.removed'         — только удалённому пользователю (payload: room_id)
    //   'room.member_removed'  — всем оставшимся (payload: room_id, user_id)
    ref.listen<AsyncValue<RealtimeEvent>>(realtimeEventsProvider, (_, next) {
      next.whenData((evt) {
        final p = evt.payload is Map<String, dynamic>
            ? evt.payload as Map<String, dynamic>
            : null;
        if (p == null || p['room_id']?.toString() != widget.roomId) return;

        // Комната закрыта создателем — останавливаем голос.
        if (evt.type == 'room.closed') {
          if (!mounted) return;
          _stopMicMonitoring();
          if (VoiceRoomService.instance.activeRoomId.value == widget.roomId) {
            VoiceRoomService.instance.leave();
          }
          return; // UI обновится через roomDetailProvider (isActive=false)
        }

        final isRemovedEvent = evt.type == 'room.removed';
        final isMemberRemovedMe = evt.type == 'room.member_removed' &&
            p['user_id']?.toString() == myId;

        if (!isRemovedEvent && !isMemberRemovedMe) return;
        if (!mounted) return;
        _stopMicMonitoring();
        VoiceRoomService.instance.leave();
        showSeeUSnackBar(context, 'Вас удалили из комнаты', tone: SeeUTone.danger);
        Navigator.of(context).pop();
      });
    });

    // Scroll to bottom when new messages arrive — via listener, not side effect in build.
    ref.listen<RoomMessagesState>(roomMessagesProvider(widget.roomId), (prev, next) {
      final prevCount = prev?.messages.length ?? 0;
      final nextCount = next.messages.length;
      if (nextCount > prevCount) {
        if (prevCount == 0 || _atBottom) {
          _scrollToBottom();
          if (prevCount > 0) {
            ref.read(roomMessagesProvider(widget.roomId).notifier).markRead();
          }
        } else {
          setState(() => _unreadCount += nextCount - prevCount);
        }
      }
    });

    if (room == null && detailState.isLoading) {
      return Scaffold(
        backgroundColor: c.bg,
        body: const SeeUMessagesSkeleton(),
      );
    }
    if (room == null) {
      return Scaffold(
        backgroundColor: c.bg,
        body: Column(
          children: [
            SeeUGlassBar(
              leading: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(PhosphorIconsRegular.caretLeft,
                      size: 22, color: c.ink),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Text('Комната не найдена',
                    style: TextStyle(color: c.ink3)),
              ),
            ),
          ],
        ),
      );
    }

    // System PiP: Android shrinks whole Activity — show minimal voice UI.
    final inVoicePip = CallBgService.instance.pipMode.value &&
        VoiceRoomService.instance.activeRoomId.value == widget.roomId;
    if (inVoicePip) return _buildVoicePipContent(room);

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(c, room, myId),
            if (room.isVoice) _buildVoicePanel(c, room, myId),
            if (!room.isActive)
              Container(
                width: double.infinity,
                color: c.surface2,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(PhosphorIcons.lockSimple(PhosphorIconsStyle.fill),
                        size: 12, color: c.ink3),
                    const SizedBox(width: 6),
                    Text(
                      'Комната закрыта',
                      style: TextStyle(fontSize: 13, color: c.ink3),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  RefreshIndicator(
                    onRefresh: _refreshMessages,
                    color: SeeUColors.accent,
                    child: _buildMessages(c, room, myId, msgsState),
                  ),
                  if (!_atBottom)
                    Positioned(
                      bottom: 12,
                      right: 16,
                      child: GestureDetector(
                        onTap: _scrollToBottom,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: c.surface,
                                shape: BoxShape.circle,
                                border: Border.all(color: c.line, width: 0.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.12),
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
                            if (_unreadCount > 0)
                              Positioned(
                                top: -6,
                                right: -6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: SeeUColors.accent,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    _unreadCount > 99
                                        ? '99+'
                                        : '$_unreadCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (room.isActive) _buildInput(c, room),
          ],
        ),
      ),
    );
  }

  void _showEditSheet(Room room) {
    showSeeUBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RoomEditSheet(
        room: room,
        onSaved: (name, desc, cover) async {
          await ref
              .read(roomDetailProvider(widget.roomId).notifier)
              .update(name: name, description: desc, coverUrl: cover);
          ref.read(roomListProvider.notifier).load();
        },
      ),
    );
  }

  Widget _buildHeader(SeeUThemeColors c, Room room, String myId) {
    final isCreator = room.creatorId == myId;
    final isAdmin = room.isAdmin || isCreator;

    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: SeeUColors.background.withValues(alpha: 0.72),
        border: Border(bottom: BorderSide(color: c.line, width: 0.5)),
      ),
      child: Row(
        children: [
          // Back — bare
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Icon(PhosphorIcons.caretLeft(PhosphorIconsStyle.bold), size: 22, color: c.ink),
            ),
          ),
          if (_isSearching) ...[
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: TextStyle(fontSize: 15, color: c.ink),
                decoration: InputDecoration(
                  hintText: 'Поиск в чате...',
                  hintStyle: TextStyle(fontSize: 15, color: c.ink3),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (v) {
                  setState(() => _searchQuery = v);
                  _searchDebounce?.cancel();
                  _searchDebounce = Timer(const Duration(milliseconds: 350), () {
                    ref.read(roomMessagesProvider(widget.roomId).notifier).search(v);
                  });
                },
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                setState(() {
                  _isSearching = false;
                  _searchQuery = '';
                  _searchCtrl.clear();
                });
                ref.read(roomMessagesProvider(widget.roomId).notifier).clearSearch();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(PhosphorIconsRegular.x, size: 20, color: c.ink),
              ),
            ),
          ] else ...[
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RoomMembersScreen(
                      roomId: room.id,
                      creatorId: room.creatorId,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    _buildRoomAvatar(c, room),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            room.name,
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.ink),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${room.participantCount} ${_pluralRu(room.participantCount, 'участник', 'участника', 'участников')}',
                            style: TextStyle(fontSize: 12, color: c.ink3),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Search — bare
            GestureDetector(
              onTap: () => setState(() => _isSearching = true),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(PhosphorIconsRegular.magnifyingGlass, size: 22, color: c.ink),
              ),
            ),
            // Overflow — bare
            GestureDetector(
              onTap: () => _showRoomMenu(c, room, isAdmin, isCreator),
              child: Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(PhosphorIcons.dotsThreeVertical(), size: 22, color: c.ink),
              ),
            ),
          ],
        ],
      ),
        ),
      ),
    );
  }

  Widget _buildRoomAvatar(SeeUThemeColors c, Room room) {
    final hasCover = room.coverUrl != null && room.coverUrl!.isNotEmpty;
    final palIdx = room.name.isEmpty
        ? 0
        : (room.name.codeUnitAt(0) + room.name.length) % SeeUColors.avatarPalettes.length;
    final palette = SeeUColors.avatarPalettes[palIdx];
    final initial = room.name.isNotEmpty ? room.name[0].toUpperCase() : 'R';

    return Container(
      width: 44, height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        gradient: hasCover ? null : LinearGradient(colors: palette),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasCover
          ? CachedNetworkImage(
              imageUrl: room.coverUrl!,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                decoration: BoxDecoration(gradient: LinearGradient(colors: palette)),
                child: Center(child: Text(initial, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700))),
              ),
              errorWidget: (_, __, ___) => Center(
                child: Text(initial, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
              ),
            )
          : Center(
              child: Text(initial, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
            ),
    );
  }

  void _showRoomMenu(SeeUThemeColors c, Room room, bool isAdmin, bool isCreator) {
    showSeeUBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isAdmin && room.isActive)
                ListTile(
                  leading: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(color: c.surface2, shape: BoxShape.circle),
                    child: Icon(PhosphorIcons.pencilSimple(), size: 18, color: c.ink),
                  ),
                  title: Text('Редактировать', style: TextStyle(fontSize: 15, color: c.ink)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showEditSheet(room);
                  },
                ),
              if (isCreator && room.isActive)
                ListTile(
                  leading: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: SeeUColors.error.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      PhosphorIcons.xCircle(PhosphorIconsStyle.fill),
                      size: 18, color: SeeUColors.error,
                    ),
                  ),
                  title: const Text('Закрыть комнату',
                      style: TextStyle(fontSize: 15, color: SeeUColors.error)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _closeRoom();
                  },
                )
              else if (!isCreator && room.isJoined)
                ListTile(
                  leading: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: SeeUColors.error.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      PhosphorIcons.signOut(PhosphorIconsStyle.fill),
                      size: 18, color: SeeUColors.error,
                    ),
                  ),
                  title: const Text('Покинуть комнату',
                      style: TextStyle(fontSize: 15, color: SeeUColors.error)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _leaveRoom();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
    );
  }

  // ─── Voice panel ───────────────────────────────────────────────────
  // Shows voice channel state. Users must explicitly join to speak.

  void _showVoiceParticipantsSheet(
      SeeUThemeColors c, List<RoomParticipant> voiceUsers,
      {bool canJoin = false}) {
    showSeeUBottomSheet<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 8,
          bottom: 20 + MediaQuery.of(ctx).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                    color: c.accentSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    PhosphorIcons.microphone(PhosphorIconsStyle.fill),
                    size: 17, color: SeeUColors.accent,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'В голосовом канале',
                  style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700,
                    color: c.ink, letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(SeeURadii.pill),
                  ),
                  child: Text(
                    '${voiceUsers.length}',
                    style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: c.ink2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (voiceUsers.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 56, height: 56,
                        decoration: BoxDecoration(
                          color: c.surface2,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          PhosphorIcons.microphone(PhosphorIconsStyle.regular),
                          size: 26, color: c.ink4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'В эфире пока никого нет',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Войдите первым и начните общение',
                        style: TextStyle(fontSize: 13, color: c.ink3),
                      ),
                      if (canJoin) ...[
                        const SizedBox(height: 16),
                        GestureDetector(
                          onTap: () {
                            Navigator.of(context).pop();
                            _joinVoice();
                          },
                          child: Container(
                            height: 44,
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            decoration: BoxDecoration(
                              color: SeeUColors.accent,
                              borderRadius: BorderRadius.circular(SeeURadii.pill),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(PhosphorIconsFill.microphone,
                                    size: 16, color: Colors.white),
                                SizedBox(width: 8),
                                Text(
                                  'Войти в эфир',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: voiceUsers.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1, color: c.line, indent: 56,
                ),
                itemBuilder: (_, i) {
                  final p = voiceUsers[i];
                  final seed = (p.fullName.isNotEmpty
                          ? p.fullName.codeUnitAt(0)
                          : 65) %
                      SeeUColors.avatarPalettes.length;
                  final pal = SeeUColors.avatarPalettes[seed];
                  final initial =
                      p.fullName.isNotEmpty ? p.fullName[0].toUpperCase() : '?';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: pal,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: p.avatarUrl != null && p.avatarUrl!.isNotEmpty
                              ? ClipOval(
                                  child: CachedNetworkImage(
                                    imageUrl: p.avatarUrl!,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => Center(
                                      child: Text(initial,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700)),
                                    ),
                                  ),
                                )
                              : Center(
                                  child: Text(initial,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700)),
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.fullName.isNotEmpty ? p.fullName : p.username,
                                style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600,
                                  color: c.ink,
                                ),
                              ),
                              Text(
                                '@${p.username}',
                                style: TextStyle(fontSize: 12, color: c.ink3),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          p.isMuted
                              ? PhosphorIcons.microphoneSlash(
                                  PhosphorIconsStyle.fill)
                              : PhosphorIcons.microphone(PhosphorIconsStyle.fill),
                          size: 18,
                          color: p.isMuted ? c.ink4 : SeeUColors.success,
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoicePanel(SeeUThemeColors c, Room room, String myId) {
    final inVoice = room.isInVoice;
    final voiceUsers = room.voiceParticipants;
    final voiceCount = room.voiceCount;

    final String subtitle;
    if (voiceCount == 0) {
      subtitle = 'Никого нет в эфире';
    } else {
      final names = voiceUsers.take(2).map((p) => p.fullName.split(' ').first).join(', ');
      subtitle = '$names · $voiceCount в голосе';
    }

    return GestureDetector(
      onTap: () => _showVoiceParticipantsSheet(
        c, voiceUsers,
        canJoin: room.isJoined && room.isActive && !inVoice,
      ),
      child: Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(SeeURadii.medium),
        border: Border.all(color: c.line, width: 0.5),
        boxShadow: SeeUShadows.sm,
      ),
      child: Row(
        children: [
          // Mic icon container
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: voiceCount > 0 ? c.accentSoft : c.surface2,
              borderRadius: BorderRadius.circular(SeeURadii.small),
            ),
            child: Icon(
              PhosphorIcons.microphone(PhosphorIconsStyle.fill),
              size: 20,
              color: voiceCount > 0 ? SeeUColors.accent : c.ink3,
            ),
          ),
          const SizedBox(width: 10),
          // Title + subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Голосовой канал',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.ink),
                ),
                if (voiceCount == 0 && room.isJoined && room.isActive && !inVoice)
                  Text(
                    'Войти первым в эфир →',
                    style: TextStyle(
                      fontSize: 12,
                      color: SeeUColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: c.ink3),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          // Avatar stack
          if (voiceUsers.isNotEmpty) ...[
            const SizedBox(width: 8),
            _VoiceAvatarStack(participants: voiceUsers, c: c),
          ],
          // Actions (only for joined & active)
          if (room.isJoined && room.isActive) ...[
            const SizedBox(width: 8),
            // Mute toggle (only when in voice)
            if (inVoice) ...[
              GestureDetector(
                onTap: () => _toggleMute(room),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: room.isMuted
                        ? c.surface2
                        : SeeUColors.success.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    room.isMuted
                        ? PhosphorIcons.microphoneSlash(PhosphorIconsStyle.fill)
                        : PhosphorIcons.microphone(PhosphorIconsStyle.fill),
                    size: 16,
                    color: room.isMuted ? c.ink3 : SeeUColors.success,
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            // Join / Leave
            GestureDetector(
              onTap: inVoice ? _leaveVoice : _joinVoice,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 42, height: 42,
                decoration: BoxDecoration(
                  gradient: inVoice ? null : SeeUGradients.heroOrange,
                  color: inVoice ? SeeUColors.error.withValues(alpha: 0.10) : null,
                  shape: BoxShape.circle,
                  border: inVoice
                      ? Border.all(color: SeeUColors.error.withValues(alpha: 0.3))
                      : null,
                  boxShadow: inVoice ? null : [
                    BoxShadow(
                      color: SeeUColors.accent.withValues(alpha: 0.30),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  inVoice ? PhosphorIconsFill.phoneSlash : PhosphorIconsFill.phone,
                  size: 18,
                  color: inVoice ? SeeUColors.error : Colors.white,
                ),
              ),
            ),
          ],
        ],
      ),
    ),
    );
  }

  // ─── Messages ─────────────────────────────────────────────────────

  Widget _buildMessages(
      SeeUThemeColors c, Room room, String myId, RoomMessagesState msgsState) {
    if (msgsState.isLoading) {
      return const SeeUMessagesSkeleton();
    }

    if (msgsState.messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(color: c.surface2, shape: BoxShape.circle),
              child: Icon(PhosphorIcons.chatTeardropText(), size: 32, color: c.ink3),
            ),
            const SizedBox(height: 14),
            Text(
              'Здесь пока пусто',
              style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, color: c.ink2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Напишите первое сообщение',
              style: TextStyle(fontSize: 13, color: c.ink3),
            ),
            const SizedBox(height: 20),
            // Animated arrow pointing toward the text input below.
            Icon(PhosphorIconsBold.arrowDown, size: 22, color: c.ink3)
                .animate(onPlay: (ctrl) => ctrl.repeat(reverse: true))
                .moveY(
                  begin: 0,
                  end: 7,
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeInOut,
                )
                .fadeIn(duration: const Duration(milliseconds: 300)),
          ],
        ),
      );
    }

    // Use server-side search results when active, otherwise show all messages.
    final messages = msgsState.searchResults ?? msgsState.messages;

    return ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        itemCount: messages.length,
        itemBuilder: (ctx, i) {
          final msg = messages[i];
          final isMe = msg.senderId == myId;
          final showSender = !isMe && (i == 0 ||
              messages[i - 1].senderId != msg.senderId);
          final showAvatar = !isMe && (i == messages.length - 1 ||
              messages[i + 1].senderId != msg.senderId);
          return _MessageBubble(
            msg: msg,
            isMe: isMe,
            showSender: showSender,
            showAvatar: showAvatar,
            c: c,
            reactions: msg.reactions,
            myReaction: msg.myReaction.isEmpty ? null : msg.myReaction,
            searchQuery: _searchQuery.trim(),
            onLongPress: () => _showMessageOptions(room, msg),
            onReactionSelected: (emoji) => _toggleReaction(msg.id, emoji),
          );
        },
      );
  }

  Future<void> _refreshMessages() =>
      ref.read(roomMessagesProvider(widget.roomId).notifier).load();

  // ─── Input bar ───────────────────────────────────────────────────

  Widget _buildInput(SeeUThemeColors c, Room room) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
    // Плашка «Ответ @username» над инпутом (reply-quote, паритет с чатами).
    if (_replyTo != null)
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
        decoration: BoxDecoration(
          color: c.accentSoft,
          borderRadius: BorderRadius.circular(SeeURadii.pill),
        ),
        child: Row(
          children: [
            Icon(PhosphorIcons.arrowBendUpLeft(),
                size: 14, color: SeeUColors.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Ответ @${_replyTo!.senderUsername}: ${_replyTo!.text.isEmpty ? 'медиа' : _replyTo!.text}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SeeUTypography.caption
                    .copyWith(color: SeeUColors.accent),
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => _replyTo = null),
              child: Icon(PhosphorIcons.x(),
                  size: 16, color: SeeUColors.accent),
            ),
          ],
        ),
      ),
    // Стеклянная оболочка (рецепт SeeUGlassInputBar): blur + тинт фона +
    // верхний hairline; внутри — плоское pill-поле (no glass-on-glass).
    ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: SeeUColors.background.withValues(alpha: 0.72),
            border: Border(top: BorderSide(color: c.line, width: 0.5)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Emoji / sticker button — плоская nested-кнопка
              Tappable.scaled(
                onTap: _toggleEmojiPanel,
                child: Container(
                  width: 44, height: 44,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: _emojiPanelOpen ? c.accentSoft : c.surface2,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.line, width: 0.5),
                  ),
                  child: Icon(
                    _emojiPanelOpen
                        ? PhosphorIconsRegular.keyboard
                        : PhosphorIconsRegular.smiley,
                    size: 20,
                    color: _emojiPanelOpen ? SeeUColors.accent : c.ink3,
                  ),
                ),
              ),
              Expanded(
                // Плоское внутреннее поле — стекло не вкладываем.
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(SeeURadii.pill),
                    border: Border.all(color: c.line, width: 0.5),
                  ),
                  child: TextField(
                    controller: _inputController,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    style: SeeUTypography.body.copyWith(color: c.ink),
                    cursorColor: SeeUColors.accent,
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: 'Написать в чат...',
                      hintStyle:
                          SeeUTypography.body.copyWith(color: c.ink3),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tappable.scaled(
                onTap: (_sending || !_hasText) ? null : _sendMessage,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: _hasText
                        ? SeeUColors.accent
                        : SeeUColors.accent.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                  child: _sending
                      ? const Center(
                          child: SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          ),
                        )
                      : Icon(
                          PhosphorIcons.paperPlaneTilt(
                              PhosphorIconsStyle.fill),
                          size: 20, color: Colors.white,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    if (_emojiPanelOpen)
      EmojiStickerPanel(
        inline: true,
        onEmojiSelected: _insertEmoji,
        onStickerSelected: (url) {
          setState(() => _emojiPanelOpen = false);
          _sendSticker(url);
        },
        onGifSelected: (url) {
          setState(() => _emojiPanelOpen = false);
          _sendGif(url);
        },
        onCreateSticker: () => setState(() => _emojiPanelOpen = false),
      ),
      ],
    );
  }
}

// ─── Voice avatar stack ───────────────────────────────────────────

class _VoiceAvatarStack extends StatelessWidget {
  final List<RoomParticipant> participants;
  final SeeUThemeColors c;
  const _VoiceAvatarStack({required this.participants, required this.c});

  @override
  Widget build(BuildContext context) {
    const double size = 22;
    const double overlap = 8;
    final shown = participants.take(3).toList();
    final extra = participants.length - shown.length;
    final itemCount = shown.length + (extra > 0 ? 1 : 0);
    final totalWidth = size + (itemCount - 1) * (size - overlap);

    return SizedBox(
      width: totalWidth,
      height: size,
      child: Stack(
        children: [
          ...shown.asMap().entries.map((e) {
            final idx = e.key;
            final p = e.value;
            final seed = (p.fullName.isNotEmpty
                    ? p.fullName.codeUnitAt(0) + p.fullName.length
                    : 0) %
                SeeUColors.avatarPalettes.length;
            final pal = SeeUColors.avatarPalettes[seed];
            final initial = p.fullName.isNotEmpty ? p.fullName[0].toUpperCase() : '?';
            return Positioned(
              left: idx * (size - overlap),
              child: Container(
                width: size, height: size,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: pal),
                  shape: BoxShape.circle,
                  border: Border.all(color: c.surface, width: 1.5),
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            );
          }),
          if (extra > 0)
            Positioned(
              left: shown.length * (size - overlap),
              child: Container(
                width: size, height: size,
                decoration: BoxDecoration(
                  color: c.surface2,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.surface, width: 1.5),
                ),
                child: Center(
                  child: Text(
                    '+$extra',
                    style: TextStyle(
                      color: c.ink3, fontSize: 8, fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Message bubble ───────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final RoomMessage msg;
  final bool isMe;
  final bool showSender;
  final bool showAvatar;
  final SeeUThemeColors c;
  final Map<String, int> reactions;
  final String? myReaction;
  final String searchQuery;
  final VoidCallback? onLongPress;
  final ValueChanged<String>? onReactionSelected;

  const _MessageBubble({
    required this.msg,
    required this.isMe,
    required this.showSender,
    required this.showAvatar,
    required this.c,
    this.reactions = const {},
    this.myReaction,
    this.searchQuery = '',
    this.onLongPress,
    this.onReactionSelected,
  });

  static Color _senderColor(String name) {
    if (name.isEmpty) return SeeUColors.avatarPalettes[0][0];
    final idx =
        (name.codeUnitAt(0) + name.length) % SeeUColors.avatarPalettes.length;
    return SeeUColors.avatarPalettes[idx][0];
  }

  static List<Color> _senderPalette(String name) {
    final idx = name.isEmpty
        ? 0
        : (name.codeUnitAt(0) + name.length) % SeeUColors.avatarPalettes.length;
    return SeeUColors.avatarPalettes[idx];
  }

  Widget _buildText(String text) {
    if (searchQuery.isEmpty) {
      return _buildMixedText(text);
    }
    final lower = text.toLowerCase();
    final q = searchQuery.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;
    int idx = lower.indexOf(q, start);
    while (idx != -1) {
      if (idx > start) {
        spans.add(TextSpan(
          text: text.substring(start, idx),
          style: TextStyle(color: c.ink),
        ));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + q.length),
        style: TextStyle(
          color: c.ink,
          backgroundColor: c.accentSoft,
          fontWeight: FontWeight.w700,
        ),
      ));
      start = idx + q.length;
      idx = lower.indexOf(q, start);
    }
    if (start < text.length) {
      spans.add(TextSpan(
        text: text.substring(start),
        style: TextStyle(color: c.ink),
      ));
    }
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 14, height: 1.4),
        children: spans,
      ),
    );
  }

  static final _emojiRegex = RegExp(
    r'[\u{1F300}-\u{1FAFF}][\u{1F3FB}-\u{1F3FF}]?(?:\u{200D}[\u{1F300}-\u{1FAFF}][\u{1F3FB}-\u{1F3FF}]?)*'
    r'|[\u{2600}-\u{27BF}]\u{FE0F}?'
    r'|[\u{1F1E0}-\u{1F1FF}][\u{1F1E0}-\u{1F1FF}]'
    r'|[\u{1F000}-\u{1F02F}]|[\u{1F0A0}-\u{1F0FF}]',
    unicode: true,
  );

  Widget _buildMixedText(String text) {
    final textColor = c.ink;
    if (text.runes.every((r) => r < 0x2194)) {
      return Text(text, style: TextStyle(fontSize: 14, height: 1.4, color: textColor));
    }
    final spans = <InlineSpan>[];
    int cursor = 0;
    for (final m in _emojiRegex.allMatches(text)) {
      if (m.start > cursor) {
        spans.add(TextSpan(
          text: text.substring(cursor, m.start),
          style: TextStyle(fontSize: 14, color: textColor, height: 1.4),
        ));
      }
      spans.add(TextSpan(
        text: m.group(0),
        style: TextStyle(fontSize: 18, height: 1.3, color: textColor),
      ));
      cursor = m.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(
        text: text.substring(cursor),
        style: TextStyle(fontSize: 14, color: textColor, height: 1.4),
      ));
    }
    if (spans.length == 1 && (spans.first as TextSpan).style?.fontSize == 14) {
      return Text(text, style: TextStyle(fontSize: 14, height: 1.4, color: textColor));
    }
    return RichText(text: TextSpan(children: spans), overflow: TextOverflow.clip);
  }

  Widget _buildBubble(String timeStr) {
    if (msg.isDeletedForAll || msg.kind == 'deleted') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isMe ? c.accentSoft : c.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIconsRegular.prohibit, size: 14, color: c.ink3),
            const SizedBox(width: 6),
            Text(
              'Сообщение удалено',
              style: TextStyle(fontSize: 13, color: c.ink3, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      );
    }

    final isSticker = msg.attachedMediaType == 'sticker' &&
        msg.attachedMediaUrl != null &&
        msg.attachedMediaUrl!.isNotEmpty;
    final isGif = msg.attachedMediaType == 'gif' &&
        msg.attachedMediaUrl != null &&
        msg.attachedMediaUrl!.isNotEmpty;

    final forwardBanner = msg.forwardedFromSender.isNotEmpty
        ? Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(PhosphorIconsRegular.arrowBendUpRight,
                    size: 11, color: SeeUColors.accent),
                const SizedBox(width: 4),
                Text(
                  'Переслано от @${msg.forwardedFromSender}',
                  style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: SeeUColors.accent,
                  ),
                ),
              ],
            ),
          )
        : null;

    if (isSticker || isGif) {
      return Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (forwardBanner != null) forwardBanner,
          CachedNetworkImage(
            imageUrl: msg.attachedMediaUrl!,
            width: 120,
            height: 120,
            fit: BoxFit.contain,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 10,
                    color: c.ink4,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  _ReadReceiptIcon(isRead: msg.isRead, isDelivered: msg.isDelivered, c: c),
                ],
              ],
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        // Плоский accentSoft вместо hero-градиента: акцент как акцент.
        color: isMe ? c.accentSoft : c.surface,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isMe ? 16 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (forwardBanner != null) forwardBanner,
          // Quoted-блок ответа (reply-quote, паритет с чатами).
          if (msg.replyTo != null)
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: c.surface2.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
                border: Border(
                  left: BorderSide(color: SeeUColors.accent, width: 2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '@${msg.replyTo!.senderUsername}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: SeeUColors.accent,
                    ),
                  ),
                  Text(
                    msg.replyTo!.text.isEmpty
                        ? 'медиа'
                        : msg.replyTo!.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: c.ink2),
                  ),
                ],
              ),
            ),
          _buildText(msg.text),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                timeStr,
                style: TextStyle(
                  fontSize: 10,
                  color: c.ink4,
                ),
              ),
              if (isMe) ...[
                const SizedBox(width: 4),
                _ReadReceiptIcon(isRead: msg.isRead, isDelivered: msg.isDelivered, c: c),
              ],
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localTime = msg.createdAt.toLocal();
    final timeStr =
        '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';

    return GestureDetector(
      onLongPress: onLongPress,
      child: Padding(
        padding: EdgeInsets.only(bottom: reactions.isNotEmpty ? 20 : 4),
        child: Row(
          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMe) ...[
              const SizedBox(width: 4),
              if (showAvatar)
                Container(
                  width: 28, height: 28,
                  margin: const EdgeInsets.only(right: 6, bottom: 2),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: _senderPalette(msg.senderName)),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      msg.senderName.isNotEmpty ? msg.senderName[0].toUpperCase() : '?',
                      style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white,
                      ),
                    ),
                  ),
                )
              else
                const SizedBox(width: 34),
            ],
            Flexible(
              child: Column(
                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (showSender && !isMe)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 2),
                      child: Text(
                        msg.senderName,
                        style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600,
                          color: _senderColor(msg.senderName),
                        ),
                      ),
                    ),
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _buildBubble(timeStr),
                      // Reaction pills (below bubble)
                      if (reactions.isNotEmpty)
                        Positioned(
                          bottom: -18,
                          left: isMe ? null : 4,
                          right: isMe ? 4 : null,
                          child: Wrap(
                            spacing: 4,
                            children: reactions.entries.map((e) {
                              final isMine = myReaction == e.key;
                              return GestureDetector(
                                onTap: () => onReactionSelected?.call(e.key),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isMine ? SeeUColors.accentSoft : c.surface,
                                    borderRadius: BorderRadius.circular(SeeURadii.small),
                                    boxShadow: SeeUShadows.sm,
                                    border: isMine
                                        ? Border.all(color: SeeUColors.accent, width: 0.8)
                                        : null,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(e.key, style: const TextStyle(fontSize: 13)),
                                      if (e.value > 1) ...[
                                        const SizedBox(width: 3),
                                        Text('${e.value}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: c.ink2,
                                              fontWeight: FontWeight.w600,
                                            )),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Read-receipt галочки: прочитано → accent (двойная); доставлено →
/// приглушённая двойная; отправлено → одиночная. Портировано 1-в-1 из
/// chat_message_bubble.dart's _ReadReceiptIcon (BUGS_AUDIT #11 parity).
class _ReadReceiptIcon extends StatelessWidget {
  final bool isRead;
  final bool isDelivered;
  final SeeUThemeColors c;
  const _ReadReceiptIcon({
    required this.isRead,
    required this.isDelivered,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Icon(
      (isRead || isDelivered) ? PhosphorIconsBold.checks : PhosphorIconsRegular.check,
      size: 14,
      color: isRead
          ? SeeUColors.accent
          : isDelivered
              ? c.ink4
              : c.ink3,
    );
  }
}

// ─── Room edit sheet ──────────────────────────────────────────────

class _RoomEditSheet extends ConsumerStatefulWidget {
  final Room room;
  final Future<void> Function(String name, String description, String coverUrl) onSaved;

  const _RoomEditSheet({required this.room, required this.onSaved});

  @override
  ConsumerState<_RoomEditSheet> createState() => _RoomEditSheetState();
}

class _RoomEditSheetState extends ConsumerState<_RoomEditSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  XFile? _pickedCoverImage;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.room.name);
    _descCtrl = TextEditingController(text: widget.room.description ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickCoverImage() async {
    HapticFeedback.selectionClick();
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1080,
      maxHeight: 1080,
      imageQuality: 85,
    );
    if (file != null && mounted) setState(() => _pickedCoverImage = file);
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      // Upload new cover if a local image was picked
      String coverUrl = widget.room.coverUrl ?? '';
      if (_pickedCoverImage != null) {
        final api = ref.read(apiClientProvider);
        final formData = FormData.fromMap({
          'file': await MultipartFile.fromFile(
            _pickedCoverImage!.path,
            filename: _pickedCoverImage!.name,
          ),
        });
        final up = await api.post(ApiEndpoints.mediaUpload, data: formData);
        final upData = up.data is Map ? up.data : {};
        coverUrl = (upData['data']?['url'] ?? upData['url'] ?? coverUrl) as String;
      }
      await widget.onSaved(name, _descCtrl.text.trim(), coverUrl);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        showSeeUSnackBar(context, friendlyError(e), tone: SeeUTone.danger);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: c.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: c.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Редактировать комнату',
                style: SeeUTypography.title.copyWith(color: c.ink),
              ),
              const SizedBox(height: 20),
              _label('Название', c),
              const SizedBox(height: 6),
              _buildField(
                controller: _nameCtrl,
                hint: 'Название комнаты',
                c: c,
              ),
              const SizedBox(height: 16),
              _label('Описание', c),
              const SizedBox(height: 6),
              _buildField(
                controller: _descCtrl,
                hint: 'Необязательно',
                maxLines: 3,
                c: c,
              ),
              const SizedBox(height: 16),
              _label('Обложка', c),
              const SizedBox(height: 6),
              _buildCoverPicker(c),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: _saving ? null : _save,
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: SeeUGradients.heroOrange,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Text(
                          'Сохранить',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCoverPicker(SeeUThemeColors c) {
    final existingUrl = widget.room.coverUrl;
    final hasPicked = _pickedCoverImage != null;
    final hasExisting = existingUrl != null && existingUrl.isNotEmpty;

    return GestureDetector(
      onTap: _pickCoverImage,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 130,
        decoration: BoxDecoration(
          color: (hasPicked || hasExisting)
              ? Colors.transparent
              : SeeUColors.accent.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: (hasPicked || hasExisting)
                ? SeeUColors.accent
                : SeeUColors.accent.withValues(alpha: 0.22),
            width: (hasPicked || hasExisting) ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: hasPicked
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(File(_pickedCoverImage!.path), fit: BoxFit.cover),
                  Positioned(
                    top: 8, right: 8,
                    child: GestureDetector(
                      onTap: () => setState(() => _pickedCoverImage = null),
                      child: Container(
                        width: 28, height: 28,
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(PhosphorIconsBold.x, size: 13, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              )
            : hasExisting
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: existingUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: c.surface2),
                        errorWidget: (_, __, ___) => Container(color: c.surface2),
                      ),
                      // Overlay hint to tap and change
                      Positioned.fill(
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.30),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(PhosphorIcons.pencilSimple(), size: 22, color: Colors.white),
                              const SizedBox(height: 4),
                              const Text(
                                'Изменить обложку',
                                style: TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: SeeUColors.accent.withValues(alpha: 0.10),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          PhosphorIcons.image(PhosphorIconsStyle.duotone),
                          size: 20, color: SeeUColors.accent,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Добавить обложку',
                        style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600,
                          color: SeeUColors.accent,
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _label(String text, SeeUThemeColors c) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: c.ink2,
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
    required SeeUThemeColors c,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(SeeURadii.small),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: TextStyle(fontSize: 14, color: c.ink),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: c.ink3),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: InputBorder.none,
        ),
      ),
    );
  }
}
