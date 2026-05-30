import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/models/room.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/room_provider.dart';

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
  int _prevMsgCount = 0;

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
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

  Future<void> _joinVoice() async {
    HapticFeedback.mediumImpact();
    try {
      await ref.read(apiClientProvider).post(ApiEndpoints.joinRoom(widget.roomId));
      ref.read(roomDetailProvider(widget.roomId).notifier).load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  Future<void> _leaveVoice() async {
    HapticFeedback.mediumImpact();
    try {
      await ref.read(apiClientProvider).delete(ApiEndpoints.leaveRoom(widget.roomId));
      ref.read(roomDetailProvider(widget.roomId).notifier).load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
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

  Future<void> _leaveRoom() async {
    try {
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
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Комната закрыта',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: c.ink3),
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refreshMessages,
                color: SeeUColors.accent,
                child: _buildMessages(c, room, myId),
              ),
            ),
            if (room.isActive) _buildInput(c, room),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(SeeUThemeColors c, Room room, String myId) {
    final isCreator = room.creatorId == myId;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(PhosphorIcons.caretLeft(), size: 22, color: c.ink),
          ),
          // Type badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: room.isVoice
                  ? SeeUColors.accent.withValues(alpha: 0.12)
                  : c.surface2,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  room.isVoice
                      ? PhosphorIcons.microphone(PhosphorIconsStyle.fill)
                      : PhosphorIcons.chatText(PhosphorIconsStyle.fill),
                  size: 12,
                  color: room.isVoice ? SeeUColors.accent : c.ink3,
                ),
                const SizedBox(width: 4),
                Text(
                  room.isVoice ? 'Голос' : 'Текст',
                  style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600,
                    color: room.isVoice ? SeeUColors.accent : c.ink3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room.name,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${room.participantCount} участников',
                  style: TextStyle(fontSize: 11, color: c.ink3),
                ),
              ],
            ),
          ),
          if (isCreator && room.isActive)
            IconButton(
              onPressed: _closeRoom,
              icon: Icon(PhosphorIcons.xCircle(PhosphorIconsStyle.fill), size: 22, color: SeeUColors.error),
              tooltip: 'Закрыть комнату',
            )
          else if (room.isJoined && room.isActive)
            IconButton(
              onPressed: _leaveRoom,
              icon: Icon(PhosphorIcons.signOut(), size: 20, color: c.ink3),
              tooltip: 'Покинуть',
            ),
        ],
      ),
    );
  }

  // ─── Voice panel: participants with mute status ────────────────────

  Widget _buildVoicePanel(SeeUThemeColors c, Room room, String myId) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            SeeUColors.accent.withValues(alpha: 0.08),
            SeeUColors.accent.withValues(alpha: 0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: SeeUColors.accent.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Live dot
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color: SeeUColors.accent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: SeeUColors.accentSoft,
                      blurRadius: 0,
                      spreadRadius: 3,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'ГОЛОСОВОЙ ЧАТ · ${room.participantCount}',
                style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  letterSpacing: 0.6, color: SeeUColors.accent,
                ),
              ),
              const Spacer(),
              if (!room.isJoined && room.isActive)
                // Not in voice yet — show join button
                GestureDetector(
                  onTap: _joinVoice,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: SeeUColors.accent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(PhosphorIcons.microphone(PhosphorIconsStyle.fill), size: 13, color: Colors.white),
                        const SizedBox(width: 4),
                        const Text(
                          'Войти',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                )
              else if (room.isJoined && room.isActive)
                // In voice — show mute toggle + leave voice button
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () => _toggleMute(room),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _leaveVoice,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: c.surface2,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: c.line),
                        ),
                        child: Icon(PhosphorIcons.phoneDisconnect(PhosphorIconsStyle.fill), size: 14, color: SeeUColors.error),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (room.participants.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: room.participants.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (ctx, i) => _ParticipantBubble(
                  participant: room.participants[i],
                  isMe: room.participants[i].userId == myId,
                  c: c,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Messages ─────────────────────────────────────────────────────

  Widget _buildMessages(SeeUThemeColors c, Room room, String myId) {
    final msgsState = ref.watch(roomMessagesProvider(widget.roomId));

    if (msgsState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (msgsState.messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              room.isVoice
                  ? PhosphorIcons.microphone()
                  : PhosphorIcons.chatTeardropText(),
              size: 40, color: c.ink4,
            ),
            const SizedBox(height: 10),
            Text(
              'Начните общение',
              style: TextStyle(fontSize: 14, color: c.ink3),
            ),
          ],
        ),
      );
    }

    // Only auto-scroll when message count increases (new message arrived).
    final msgCount = msgsState.messages.length;
    if (msgCount > _prevMsgCount) {
      _prevMsgCount = msgCount;
      _scrollToBottom();
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
        return _MessageBubble(
          msg: msg, isMe: isMe, showSender: showSender, c: c,
        );
      },
    );
  }

  Future<void> _refreshMessages() =>
      ref.read(roomMessagesProvider(widget.roomId).notifier).load();

  // ─── Input bar ───────────────────────────────────────────────────

  Widget _buildInput(SeeUThemeColors c, Room room) {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(context).viewInsets.bottom + 12),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(top: BorderSide(color: c.line, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: c.line, width: 0.5),
              ),
              child: TextField(
                controller: _inputController,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                style: TextStyle(fontSize: 15, color: c.ink),
                decoration: InputDecoration(
                  hintText: room.isVoice ? 'Написать в чат...' : 'Сообщение...',
                  hintStyle: TextStyle(fontSize: 15, color: c.ink3),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
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
  final SeeUThemeColors c;

  const _MessageBubble({
    required this.msg, required this.isMe,
    required this.showSender, required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            const SizedBox(width: 4),
            Container(
              width: 28, height: 28,
              margin: const EdgeInsets.only(right: 6, bottom: 2),
              decoration: BoxDecoration(
                color: c.surface2,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  msg.senderName.isNotEmpty ? msg.senderName[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: c.ink2,
                  ),
                ),
              ),
            ),
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
                        color: SeeUColors.accent,
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isMe ? SeeUColors.accent : c.surface,
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
                    crossAxisAlignment: CrossAxisAlignment.end,
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
                        timeago.format(msg.createdAt, locale: 'ru'),
                        style: TextStyle(
                          fontSize: 10,
                          color: isMe ? Colors.white.withValues(alpha: 0.7) : c.ink4,
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
