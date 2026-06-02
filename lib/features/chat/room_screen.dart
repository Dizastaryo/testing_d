import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/models/room.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/room_provider.dart';
import 'room_members_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
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

  Future<void> _toggleMute(Room room) async {
    HapticFeedback.mediumImpact();
    final myId = ref.read(authProvider).user?.id ?? '';
    ref.read(roomDetailProvider(widget.roomId).notifier).setMyMute(myId, !room.isMuted);
    try {
      await ref.read(apiClientProvider).patch(ApiEndpoints.muteRoom(room.id));
    } catch (_) {
      // Roll back on error
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
  }

  Future<void> _leaveVoice() async {
    HapticFeedback.lightImpact();
    final myId = ref.read(authProvider).user?.id ?? '';
    await ref.read(roomDetailProvider(widget.roomId).notifier).leaveVoice(myId);
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
        body: const Center(child: CircularProgressIndicator()),
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
          // Circle back button
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
          // Room avatar (cover or gradient initials)
          _buildRoomAvatar(c, room),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room.name,
                  style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700,
                    fontFamily: 'Fraunces', color: c.ink,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${room.participantCount} участников',
                  style: TextStyle(fontSize: 11, color: c.ink3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Members button
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => RoomMembersScreen(
                  roomId: room.id,
                  creatorId: room.creatorId,
                ),
              ),
            ),
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: c.surface,
                shape: BoxShape.circle,
                boxShadow: SeeUShadows.sm,
              ),
              child: Icon(PhosphorIcons.users(), size: 18, color: c.ink),
            ),
          ),
          const SizedBox(width: 8),
          // Overflow menu
          GestureDetector(
            onTap: () => _showRoomMenu(c, room, isAdmin, isCreator),
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: c.surface,
                shape: BoxShape.circle,
                boxShadow: SeeUShadows.sm,
              ),
              child: Icon(PhosphorIcons.dotsThreeVertical(), size: 18, color: c.ink),
            ),
          ),
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
        shape: BoxShape.circle,
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

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            SeeUColors.accent.withValues(alpha: inVoice ? 0.10 : 0.05),
            SeeUColors.accent.withValues(alpha: 0.02),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: SeeUColors.accent.withValues(alpha: inVoice ? 0.3 : 0.15),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              // Pulse dot — orange when any user in voice, grey when empty
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color: voiceCount > 0 ? SeeUColors.accent : c.ink4,
                  shape: BoxShape.circle,
                  boxShadow: voiceCount > 0
                      ? [BoxShadow(color: SeeUColors.accentSoft, blurRadius: 0, spreadRadius: 3)]
                      : null,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                voiceCount > 0
                    ? 'ГОЛОСОВОЙ · $voiceCount'
                    : 'ГОЛОСОВОЙ',
                style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: voiceCount > 0 ? SeeUColors.accent : c.ink3,
                ),
              ),
              const Spacer(),
              if (room.isJoined && room.isActive) ...[
                // Mute button (only visible when in voice)
                if (inVoice)
                  GestureDetector(
                    onTap: () => _toggleMute(room),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: room.isMuted ? c.surface2 : SeeUColors.accent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            room.isMuted
                                ? PhosphorIcons.microphoneSlash(PhosphorIconsStyle.fill)
                                : PhosphorIcons.microphone(PhosphorIconsStyle.fill),
                            size: 13,
                            color: room.isMuted ? c.ink3 : Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            room.isMuted ? 'Выкл.' : 'Вкл.',
                            style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600,
                              color: room.isMuted ? c.ink3 : Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                // Join / Leave voice button
                GestureDetector(
                  onTap: inVoice ? _leaveVoice : _joinVoice,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: inVoice
                          ? SeeUColors.error.withValues(alpha: 0.12)
                          : SeeUColors.accent,
                      borderRadius: BorderRadius.circular(999),
                      border: inVoice
                          ? Border.all(color: SeeUColors.error.withValues(alpha: 0.4))
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          inVoice
                              ? PhosphorIconsFill.phoneSlash
                              : PhosphorIconsFill.phone,
                          size: 13,
                          color: inVoice ? SeeUColors.error : Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          inVoice ? 'Выйти' : 'Войти',
                          style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600,
                            color: inVoice ? SeeUColors.error : Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          // Participants in voice (only shown if anyone is in voice)
          if (voiceUsers.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: voiceUsers.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (ctx, i) => _ParticipantBubble(
                  participant: voiceUsers[i],
                  isMe: voiceUsers[i].userId == myId,
                  c: c,
                ),
              ),
            ),
          ] else if (!inVoice && room.isJoined) ...[
            // #M-7: подсказку показываем только участникам (не гостям)
            const SizedBox(height: 8),
            Text(
              'Нажми «Войти», чтобы подключиться к голосовому',
              style: TextStyle(fontSize: 12, color: c.ink3),
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
      return const Center(child: CircularProgressIndicator());
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

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      itemCount: msgsState.messages.length,
      itemBuilder: (ctx, i) {
        final msg = msgsState.messages[i];
        final isMe = msg.senderId == myId;
        final showSender = !isMe && (i == 0 ||
            msgsState.messages[i - 1].senderId != msg.senderId);
        // Show avatar only on last message of a cluster (tail)
        final showAvatar = !isMe && (i == msgsState.messages.length - 1 ||
            msgsState.messages[i + 1].senderId != msg.senderId);
        return _MessageBubble(
          msg: msg, isMe: isMe, showSender: showSender,
          showAvatar: showAvatar, c: c,
        );
      },
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

// ─── Participant bubble (voice panel) ─────────────────────────────

class _ParticipantBubble extends StatelessWidget {
  final RoomParticipant participant;
  final bool isMe;
  final SeeUThemeColors c;

  const _ParticipantBubble({
    required this.participant, required this.isMe, required this.c,
  });

  @override
  Widget build(BuildContext context) {
    final seed = (participant.fullName.isNotEmpty
        ? participant.fullName.codeUnitAt(0) + participant.fullName.length
        : 0) %
        SeeUColors.avatarPalettes.length;
    final pal = SeeUColors.avatarPalettes[seed];
    final initial = participant.fullName.isNotEmpty ? participant.fullName[0].toUpperCase() : '?';

    return SizedBox(
      width: 52,
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: pal),
                  shape: BoxShape.circle,
                  border: isMe
                      ? Border.all(color: SeeUColors.accent, width: 2)
                      : null,
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18),
                  ),
                ),
              ),
              // Mute indicator
              Positioned(
                right: 0, bottom: 0,
                child: Container(
                  width: 16, height: 16,
                  decoration: BoxDecoration(
                    color: participant.isMuted ? c.surface2 : SeeUColors.success,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.bg, width: 2),
                  ),
                  child: Icon(
                    participant.isMuted
                        ? PhosphorIcons.microphoneSlash(PhosphorIconsStyle.fill)
                        : PhosphorIcons.microphone(PhosphorIconsStyle.fill),
                    size: 7,
                    color: participant.isMuted ? c.ink3 : Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isMe ? 'Вы' : participant.fullName.split(' ').first,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: c.ink2),
            maxLines: 1, overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
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

  const _MessageBubble({
    required this.msg,
    required this.isMe,
    required this.showSender,
    required this.showAvatar,
    required this.c,
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

  @override
  Widget build(BuildContext context) {
    final localTime = msg.createdAt.toLocal();
    final timeStr =
        '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
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
              // Placeholder to keep bubble alignment when avatar is hidden
              const SizedBox(width: 34), // 28 container + 6 margin
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
                Container(
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
                      Text(
                        msg.text,
                        style: TextStyle(
                          fontSize: 14, height: 1.4,
                          color: isMe ? Colors.white : c.ink,
                        ),
                      ),
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
                ),
              ],
            ),
          ),
        ],
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
