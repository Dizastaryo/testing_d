import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:record/record.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/models/room.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/room_provider.dart';
import '../../core/services/voice_room_service.dart';
import 'room_members_screen.dart';
import 'widgets/emoji_sticker_panel.dart';

class RoomScreen extends ConsumerStatefulWidget {
  final String roomId;
  const RoomScreen({super.key, required this.roomId});

  @override
  ConsumerState<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends ConsumerState<RoomScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;
  bool _atBottom = true;

  // ── Search ──────────────────────────────────────────────────────────────
  bool _isSearching = false;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  // ── Reactions (local-only, no backend) ──────────────────────────────────
  String? _reactionPickerMsgId;
  final Map<String, String> _myReactions = {};
  final Map<String, Map<String, int>> _allReactions = {};

  // ── Mic level monitoring (только пока пользователь в голосовом канале) ──
  final AudioRecorder _micMonitor = AudioRecorder();
  StreamSubscription<dynamic>? _micStreamSub;
  StreamSubscription<Amplitude>? _ampSub;
  final ValueNotifier<double> _myAudioLevel = ValueNotifier(0.0);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _inputController.dispose();
    _searchCtrl.dispose();
    _scrollController.dispose();
    _stopMicMonitoring();
    _micMonitor.dispose();
    _myAudioLevel.dispose();
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

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final atBottom = pos.pixels >= pos.maxScrollExtent - 50;
    if (atBottom != _atBottom) {
      if (mounted) setState(() => _atBottom = atBottom);
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
    _inputController.clear();
    setState(() => _sending = true);
    try {
      await ref.read(roomMessagesProvider(widget.roomId).notifier).send(text);
      _scrollToBottom();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showEmojiStickerPanel() {
    FocusScope.of(context).unfocus();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => EmojiStickerPanel(
        onEmojiSelected: (emoji) {
          Navigator.pop(context);
          final sel = _inputController.selection;
          final text = _inputController.text;
          final pos = sel.isValid ? sel.baseOffset : text.length;
          final newText = text.substring(0, pos) + emoji + text.substring(pos);
          _inputController.value = TextEditingValue(
            text: newText,
            selection: TextSelection.collapsed(offset: pos + emoji.length),
          );
        },
        onStickerSelected: (url) {
          Navigator.pop(context);
          _sendSticker(url);
        },
        onCreateSticker: () => Navigator.pop(context),
      ),
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
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _toggleReaction(String msgId, String emoji) {
    HapticFeedback.selectionClick();
    setState(() {
      _reactionPickerMsgId = null;
      final current = _myReactions[msgId];
      final reactions = Map<String, int>.from(_allReactions[msgId] ?? {});
      if (current == emoji) {
        _myReactions.remove(msgId);
        reactions[emoji] = ((reactions[emoji] ?? 1) - 1).clamp(0, 999);
        if ((reactions[emoji] ?? 0) == 0) reactions.remove(emoji);
      } else {
        if (current != null) {
          reactions[current] = ((reactions[current] ?? 1) - 1).clamp(0, 999);
          if ((reactions[current] ?? 0) == 0) reactions.remove(current);
        }
        _myReactions[msgId] = emoji;
        reactions[emoji] = (reactions[emoji] ?? 0) + 1;
      }
      _allReactions[msgId] = reactions;
    });
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
    final myId = ref.read(authProvider).user?.id ?? '';
    await ref.read(roomDetailProvider(widget.roomId).notifier).joinVoice(myId);
    VoiceRoomService.instance.join(widget.roomId, room.name);
    // Начинаем мониторить микрофон, если не замьючены
    if (!room.isMuted) _startMicMonitoring();
  }

  Future<void> _leaveVoice() async {
    HapticFeedback.lightImpact();
    final myId = ref.read(authProvider).user?.id ?? '';
    _stopMicMonitoring();
    await ref.read(roomDetailProvider(widget.roomId).notifier).leaveVoice(myId);
    VoiceRoomService.instance.leave();
  }

  Future<void> _leaveRoom() async {
    final c = context.seeuColors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text('Покинуть комнату?', style: TextStyle(color: c.ink, fontSize: 17)),
        content: Text('Вы выйдете из комнаты.', style: TextStyle(color: c.ink2, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Отмена', style: TextStyle(color: c.ink3)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Покинуть', style: TextStyle(color: SeeUColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  Future<void> _closeRoom() async {
    final c = context.seeuColors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text('Закрыть комнату?', style: TextStyle(color: c.ink, fontSize: 17)),
        content: Text('Все участники будут отключены.', style: TextStyle(color: c.ink2, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Отмена', style: TextStyle(color: c.ink3)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Закрыть', style: TextStyle(color: SeeUColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    VoiceRoomService.instance.leave();
    try {
      await ref.read(apiClientProvider).delete(ApiEndpoints.roomById(widget.roomId));
      ref.read(roomListProvider.notifier).load();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final detailState = ref.watch(roomDetailProvider(widget.roomId));
    final room = detailState.room;
    final myId = ref.watch(authProvider).user?.id ?? '';
    final msgsState = ref.watch(roomMessagesProvider(widget.roomId));

    // Scroll to bottom when new messages arrive — via listener, not side effect in build.
    ref.listen<RoomMessagesState>(roomMessagesProvider(widget.roomId), (prev, next) {
      final prevCount = prev?.messages.length ?? 0;
      final nextCount = next.messages.length;
      if (nextCount > prevCount) {
        _scrollToBottom();
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
        appBar: AppBar(backgroundColor: Colors.transparent),
        body: Center(child: Text('Комната не найдена', style: TextStyle(color: c.ink3))),
      );
    }

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
                        child: Container(
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: c.bg,
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
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => setState(() {
                _isSearching = false;
                _searchQuery = '';
                _searchCtrl.clear();
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(PhosphorIconsRegular.x, size: 20, color: c.ink),
              ),
            ),
          ] else ...[
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
                    '${room.participantCount} участников',
                    style: TextStyle(fontSize: 12, color: c.ink3),
                  ),
                ],
              ),
            ),
            // Members — bare
            GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => RoomMembersScreen(
                    roomId: room.id,
                    creatorId: room.creatorId,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(PhosphorIcons.users(), size: 22, color: c.ink),
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
      width: 36, height: 36,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
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
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: c.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                decoration: BoxDecoration(
                  color: c.line, borderRadius: BorderRadius.circular(2),
                ),
              ),
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
      ),
    );
  }

  // ─── Voice panel ───────────────────────────────────────────────────
  // Shows voice channel state. Users must explicitly join to speak.

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

    return Container(
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
              borderRadius: BorderRadius.circular(12),
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
              'Начните общение',
              style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, color: c.ink2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Напишите первое сообщение',
              style: TextStyle(fontSize: 13, color: c.ink3),
            ),
          ],
        ),
      );
    }

    final query = _searchQuery.trim().toLowerCase();
    final messages = query.isEmpty
        ? msgsState.messages
        : msgsState.messages
            .where((m) => m.text.toLowerCase().contains(query))
            .toList();

    return GestureDetector(
      onTap: () {
        if (_reactionPickerMsgId != null) {
          setState(() => _reactionPickerMsgId = null);
        }
      },
      behavior: HitTestBehavior.translucent,
      child: ListView.builder(
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
            showReactionPicker: _reactionPickerMsgId == msg.id,
            reactions: _allReactions[msg.id] ?? {},
            myReaction: _myReactions[msg.id],
            searchQuery: query,
            onLongPress: () => setState(() => _reactionPickerMsgId = msg.id),
            onReactionSelected: (emoji) => _toggleReaction(msg.id, emoji),
          );
        },
      ),
    );
  }

  Future<void> _refreshMessages() =>
      ref.read(roomMessagesProvider(widget.roomId).notifier).load();

  // ─── Input bar ───────────────────────────────────────────────────

  Widget _buildInput(SeeUThemeColors c, Room room) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(22),
      borderSide: BorderSide(color: c.line, width: 0.5),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(top: BorderSide(color: c.line, width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Emoji / sticker button
          GestureDetector(
            onTap: _showEmojiStickerPanel,
            child: Container(
              width: 38, height: 38,
              margin: const EdgeInsets.only(right: 8, bottom: 2),
              decoration: BoxDecoration(
                color: c.surface,
                shape: BoxShape.circle,
                boxShadow: SeeUShadows.sm,
              ),
              child: Icon(PhosphorIconsRegular.smiley, size: 20, color: c.ink3),
            ),
          ),
          Expanded(
            child: TextField(
              controller: _inputController,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
              style: TextStyle(fontSize: 15, color: c.ink),
              decoration: InputDecoration(
                hintText: 'Написать в чат...',
                hintStyle: TextStyle(fontSize: 15, color: c.ink3),
                filled: true,
                fillColor: c.surface,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: border,
                enabledBorder: border,
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(color: c.line, width: 1.0),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sending ? null : _sendMessage,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: SeeUColors.accent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: SeeUColors.accent.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
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
                      PhosphorIcons.paperPlaneTilt(PhosphorIconsStyle.fill),
                      size: 18, color: Colors.white,
                    ),
            ),
          ),
        ],
      ),
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
  final bool showReactionPicker;
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
    this.showReactionPicker = false,
    this.reactions = const {},
    this.myReaction,
    this.searchQuery = '',
    this.onLongPress,
    this.onReactionSelected,
  });

  static const _nameColors = [
    Color(0xFFFF5A3C), Color(0xFF5DB1FF), Color(0xFF2FA84F),
    Color(0xFFFFB547), Color(0xFFC04CFD), Color(0xFFFF3B6B),
    Color(0xFF7B61FF), Color(0xFF1AC8B8),
  ];

  static Color _senderColor(String name) {
    if (name.isEmpty) return _nameColors[0];
    return _nameColors[(name.codeUnitAt(0) + name.length) % _nameColors.length];
  }

  static List<Color> _senderPalette(String name) {
    final idx = name.isEmpty
        ? 0
        : (name.codeUnitAt(0) + name.length) % SeeUColors.avatarPalettes.length;
    return SeeUColors.avatarPalettes[idx];
  }

  Widget _buildText(String text) {
    if (searchQuery.isEmpty) {
      return Text(
        text,
        style: TextStyle(fontSize: 14, height: 1.4, color: isMe ? Colors.white : c.ink),
      );
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
          style: TextStyle(color: isMe ? Colors.white : c.ink),
        ));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + q.length),
        style: TextStyle(
          color: isMe ? Colors.white : c.ink,
          backgroundColor: Colors.yellow.withValues(alpha: 0.55),
          fontWeight: FontWeight.w700,
        ),
      ));
      start = idx + q.length;
      idx = lower.indexOf(q, start);
    }
    if (start < text.length) {
      spans.add(TextSpan(
        text: text.substring(start),
        style: TextStyle(color: isMe ? Colors.white : c.ink),
      ));
    }
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 14, height: 1.4),
        children: spans,
      ),
    );
  }

  Widget _buildBubble(String timeStr) {
    final isSticker = msg.attachedMediaType == 'sticker' &&
        msg.attachedMediaUrl != null &&
        msg.attachedMediaUrl!.isNotEmpty;

    if (isSticker) {
      return Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          CachedNetworkImage(
            imageUrl: msg.attachedMediaUrl!,
            width: 120,
            height: 120,
            fit: BoxFit.contain,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              timeStr,
              style: TextStyle(
                fontSize: 10,
                color: isMe
                    ? Colors.white.withValues(alpha: 0.65)
                    : c.ink4,
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: isMe
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFF6B4A), Color(0xFFFF4A30)],
              )
            : null,
        color: isMe ? null : c.surface,
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
          _buildText(msg.text),
          const SizedBox(height: 2),
          Text(
            timeStr,
            style: TextStyle(
              fontSize: 10,
              color: isMe
                  ? Colors.white.withValues(alpha: 0.65)
                  : c.ink4,
            ),
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
                      // Reaction picker (appears above bubble)
                      if (showReactionPicker)
                        Positioned(
                          top: -48,
                          left: isMe ? null : 0,
                          right: isMe ? 0 : null,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: c.surface2,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: SeeUShadows.md,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: kQuickReactionEmojis.map((emoji) {
                                final isSelected = myReaction == emoji;
                                return GestureDetector(
                                  onTap: () => onReactionSelected?.call(emoji),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: isSelected
                                        ? BoxDecoration(
                                            color: SeeUColors.accentSoft,
                                            shape: BoxShape.circle,
                                          )
                                        : null,
                                    child: Text(emoji, style: const TextStyle(fontSize: 22)),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
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
                                    borderRadius: BorderRadius.circular(12),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
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
        borderRadius: BorderRadius.circular(12),
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
