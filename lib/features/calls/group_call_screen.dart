import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import 'call_buttons.dart';
import 'call_service.dart' show CallKind;
import 'group_call_service.dart';

/// Group call full-screen UI (C-7). Gallery layout: GridView с per-peer
/// remote video + local PIP в углу. Controls: mute/camera/hangup.
class GroupCallScreen extends StatefulWidget {
  const GroupCallScreen({super.key});

  @override
  State<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends State<GroupCallScreen> {
  final _localRenderer = RTCVideoRenderer();
  // #M-3: тикер для MM:SS таймера длительности звонка.
  Timer? _durationTicker;

  @override
  void initState() {
    super.initState();
    _initLocal();
    GroupCallService.instance.localStream.addListener(_syncLocal);
    GroupCallService.instance.session.addListener(_onSession);
    GroupCallService.instance.session.addListener(_onSessionForTimer); // #M-3
    _onSessionForTimer();
  }

  // #M-3: управление тикером — запускаем когда active + connectedAt, иначе гасим.
  void _onSessionForTimer() {
    final s = GroupCallService.instance.session.value;
    if (s != null &&
        s.status == GroupCallStatus.active &&
        s.connectedAt != null) {
      if (_durationTicker == null || !_durationTicker!.isActive) {
        _durationTicker = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() {});
        });
      }
    } else {
      _durationTicker?.cancel();
      _durationTicker = null;
    }
  }

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  Future<void> _initLocal() async {
    await _localRenderer.initialize();
    _localRenderer.srcObject = GroupCallService.instance.localStream.value;
    if (mounted) setState(() {});
  }

  void _syncLocal() {
    _localRenderer.srcObject = GroupCallService.instance.localStream.value;
    if (mounted) setState(() {});
  }

  void _onSession() {
    final s = GroupCallService.instance.session.value;
    if (s == null && mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    GroupCallService.instance.localStream.removeListener(_syncLocal);
    GroupCallService.instance.session.removeListener(_onSession);
    GroupCallService.instance.session.removeListener(_onSessionForTimer); // #M-3
    _durationTicker?.cancel(); // #M-3
    _localRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GroupCallSession?>(
      valueListenable: GroupCallService.instance.session,
      builder: (_, sess, __) {
        if (sess == null) return const SizedBox.shrink();
        final isVoice = sess.kind == CallKind.voice;
        return PopScope(
          canPop: true,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) GroupCallService.instance.minimized.value = true;
          },
          child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              // Gallery of remote peers.
              Positioned.fill(
                child: _buildGallery(sess, isVoice),
              ),
              // Top: chat title + status pill.
              Positioned(
                top: 50,
                left: 20,
                right: 80,
                child: SafeArea(
                  child: _buildTopBar(sess),
                ),
              ),
              // Кнопка свернуть (minimize → PiP).
              Positioned(
                top: 10,
                right: 20,
                child: SafeArea(
                  child: GestureDetector(
                    onTap: () {
                      GroupCallService.instance.minimized.value = true;
                      Navigator.of(context).maybePop();
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        PhosphorIconsRegular.arrowsInSimple,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
              // Local PIP (только для video). #15: учитываем isCameraOff.
              if (!isVoice)
                Positioned(
                  bottom: 120,
                  right: 16,
                  width: 90,
                  height: 120,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: GroupCallService.instance.isCameraOff,
                    builder: (_, cameraOff, __) => ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          border: Border.all(color: Colors.white24, width: 1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: cameraOff || _localRenderer.srcObject == null
                            ? const Center(
                                child: Icon(
                                  PhosphorIconsBold.videoCameraSlash,
                                  color: Colors.white54,
                                  size: 22,
                                ),
                              )
                            : RTCVideoView(
                                _localRenderer,
                                mirror: true,
                                objectFit: RTCVideoViewObjectFit
                                    .RTCVideoViewObjectFitCover,
                              ),
                      ),
                    ),
                  ),
                ),
              // Bottom controls.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                    child: _buildControls(sess, isVoice),
                  ),
                ),
              ),
            ],
          ),
          ),
        );
      },
    );
  }

  Widget _buildGallery(GroupCallSession sess, bool isVoice) {
    if (sess.status == GroupCallStatus.outgoingInviting) {
      return _buildOutgoingWaiting(sess, isVoice);
    }
    if (sess.status == GroupCallStatus.incomingRinging) {
      return _buildIncomingRinging(sess);
    }
    // Active state
    return ValueListenableBuilder<Map<String, GroupCallPeer>>(
      valueListenable: GroupCallService.instance.peers,
      builder: (_, peers, __) {
        if (peers.isEmpty) {
          return Container(
            color: const Color(0xFF0D0D1A),
            child: Center(
              child: Text(
                'Ждём участников…',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
              ),
            ),
          );
        }
        final entries = peers.entries.toList();
        final cols = entries.length == 1 ? 1 : 2;
        return GridView.count(
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          crossAxisCount: cols,
          childAspectRatio: cols == 1 ? 9 / 16 : 3 / 4,
          children: entries.map((e) => _peerTile(e.value, isVoice)).toList(),
        );
      },
    );
  }

  Widget _buildOutgoingWaiting(GroupCallSession sess, bool isVoice) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1C1C2E), Color(0xFF0D0D1A)],
        ),
      ),
      child: ValueListenableBuilder<List<GroupCallMember>>(
        valueListenable: GroupCallService.instance.invitedMembers,
        builder: (_, members, __) {
          final joinedCount = members
              .where((m) => m.status == GroupCallMemberStatus.joined)
              .length;
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Call type icon
              Container(
                width: 76, height: 76,
                decoration: BoxDecoration(
                  color: SeeUColors.accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: SeeUColors.accent.withValues(alpha: 0.35), width: 1.5),
                ),
                child: Icon(
                  isVoice ? PhosphorIconsBold.phone : PhosphorIconsBold.videoCamera,
                  color: SeeUColors.accent,
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                sess.chatTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Fraunces',
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                isVoice ? 'Голосовой звонок' : 'Видеозвонок',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45), fontSize: 13),
              ),
              const SizedBox(height: 40),
              if (members.isNotEmpty) ...[
                SizedBox(
                  height: 104,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    itemCount: members.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 18),
                    itemBuilder: (_, i) =>
                        _MemberStatusBubble(member: members[i]),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  joinedCount > 0
                      ? '$joinedCount из ${members.length} уже в звонке'
                      : 'Вызываем участников…',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 13,
                  ),
                ),
              ] else ...[
                Text(
                  'Вызываем участников…',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildIncomingRinging(GroupCallSession sess) {
    final isVoice = sess.kind == CallKind.voice;
    final name = sess.inviterUsername;
    final palIdx = name.isEmpty
        ? 0
        : (name.codeUnitAt(0) + name.length) %
            SeeUColors.avatarPalettes.length;
    final palette = SeeUColors.avatarPalettes[palIdx];
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1C1C2E), Color(0xFF0D0D1A)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Inviter avatar with pulsing ring
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 104, height: 104,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: SeeUColors.accent.withValues(alpha: 0.25), width: 12),
                  ),
                ),
                Container(
                  width: 84, height: 84,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: palette),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12), width: 2),
                  ),
                  child: Center(
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Text(
              '@${sess.inviterUsername}',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55), fontSize: 14),
            ),
            const SizedBox(height: 6),
            Text(
              sess.chatTitle,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                fontFamily: 'Fraunces',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12), width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isVoice
                        ? PhosphorIconsBold.phone
                        : PhosphorIconsBold.videoCamera,
                    color: Colors.white,
                    size: 13,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isVoice ? 'Голосовой звонок' : 'Видеозвонок',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _peerTile(GroupCallPeer peer, bool isVoice) {
    final hasVideo = peer.remoteStream != null &&
        !isVoice &&
        peer.remoteStream!.getVideoTracks().isNotEmpty;
    final name = peer.username.isNotEmpty
        ? peer.username
        : (peer.userId.length > 8 ? peer.userId.substring(0, 8) : peer.userId);
    final palIdx = peer.username.isEmpty
        ? 0
        : (peer.username.codeUnitAt(0) + peer.username.length) %
            SeeUColors.avatarPalettes.length;
    final palette = SeeUColors.avatarPalettes[palIdx];
    final initial = peer.username.isNotEmpty ? peer.username[0].toUpperCase() : '?';

    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          if (hasVideo)
            Positioned.fill(
              child: RTCVideoView(
                peer.renderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
            )
          else
            Positioned.fill(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64, height: 64,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: palette),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          initial,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          if (hasVideo)
            Positioned(
              bottom: 6, left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopBar(GroupCallSession sess) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(PhosphorIconsBold.usersThree,
                    color: Colors.white, size: 14),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    sess.chatTitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // #M-3: таймер длительности — показываем только в active.
                if (sess.status == GroupCallStatus.active &&
                    sess.connectedAt != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 3,
                    height: 3,
                    decoration: const BoxDecoration(
                      color: Colors.white54,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _fmtDuration(
                        DateTime.now().difference(sess.connectedAt!)),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControls(GroupCallSession sess, bool isVoice) {
    // Incoming ringing — accept/decline.
    if (sess.status == GroupCallStatus.incomingRinging) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          CallBigButton(
            icon: PhosphorIconsFill.phoneSlash,
            color: SeeUColors.error,
            onTap: GroupCallService.instance.declineGroupCall,
          ),
          CallBigButton(
            icon: PhosphorIconsFill.phone,
            color: const Color(0xFF2FA84F),
            onTap: GroupCallService.instance.acceptGroupCall,
          ),
        ],
      );
    }
    return ValueListenableBuilder<bool>(
      valueListenable: GroupCallService.instance.isMuted,
      builder: (_, muted, __) =>
          ValueListenableBuilder<bool>(
        valueListenable: GroupCallService.instance.isCameraOff,
        builder: (_, cameraOff, __) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              CallSmallButton(
                icon: muted
                    ? PhosphorIconsFill.microphoneSlash
                    : PhosphorIconsFill.microphone,
                active: muted,
                onTap: GroupCallService.instance.toggleMute,
              ),
              if (!isVoice)
                CallSmallButton(
                  icon: cameraOff
                      ? PhosphorIconsFill.videoCameraSlash
                      : PhosphorIconsFill.videoCamera,
                  active: cameraOff,
                  onTap: GroupCallService.instance.toggleCamera,
                ),
              CallBigButton(
                icon: PhosphorIconsFill.phoneSlash,
                color: SeeUColors.error,
                onTap: GroupCallService.instance.hangup,
              ),
            ],
          );
        },
      ),
    );
  }

}

// ─── Member status bubble (outgoing call waiting screen) ──────────────────

class _MemberStatusBubble extends StatefulWidget {
  final GroupCallMember member;
  const _MemberStatusBubble({required this.member});

  @override
  State<_MemberStatusBubble> createState() => _MemberStatusBubbleState();
}

class _MemberStatusBubbleState extends State<_MemberStatusBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _scaleAnim;
  late Animation<double> _opacityAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.35).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOut),
    );
    _opacityAnim = Tween<double>(begin: 0.55, end: 0.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOut),
    );
    if (widget.member.status == GroupCallMemberStatus.ringing) {
      _pulseCtrl.repeat();
    }
  }

  @override
  void didUpdateWidget(_MemberStatusBubble old) {
    super.didUpdateWidget(old);
    if (widget.member.status == GroupCallMemberStatus.ringing) {
      if (!_pulseCtrl.isAnimating) _pulseCtrl.repeat();
    } else {
      _pulseCtrl.stop();
      _pulseCtrl.reset();
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    final name = m.fullName.isNotEmpty ? m.fullName : m.username;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final palIdx = name.isEmpty
        ? 0
        : (name.codeUnitAt(0) + name.length) % SeeUColors.avatarPalettes.length;
    final palette = SeeUColors.avatarPalettes[palIdx];

    final isRinging = m.status == GroupCallMemberStatus.ringing;
    final isJoined = m.status == GroupCallMemberStatus.joined;
    final isDeclined = m.status == GroupCallMemberStatus.declined;

    // Status dot icon/color
    final dotIcon = isJoined
        ? PhosphorIconsBold.check
        : isDeclined
            ? PhosphorIconsBold.x
            : PhosphorIconsBold.phone;
    final dotBg = isJoined
        ? const Color(0xFF2FA84F)
        : isDeclined
            ? Colors.white12
            : SeeUColors.accent;

    return SizedBox(
      width: 64,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // Pulsing ring (ringing state only)
              if (isRinging)
                AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (_, __) => Transform.scale(
                    scale: _scaleAnim.value,
                    child: Opacity(
                      opacity: _opacityAnim.value,
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: SeeUColors.accent,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              // Avatar circle
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: palette),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isJoined
                        ? const Color(0xFF2FA84F)
                        : isRinging
                            ? SeeUColors.accent.withValues(alpha: 0.7)
                            : Colors.white24,
                    width: isJoined || isRinging ? 2 : 1,
                  ),
                ),
                child: Opacity(
                  opacity: isDeclined ? 0.45 : 1.0,
                  child: Center(
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              // Status dot (bottom-right)
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: dotBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF0D0D1A), width: 1.5),
                  ),
                  child: Icon(dotIcon, color: Colors.white, size: 9),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            m.username.isNotEmpty ? '@${m.username}' : name,
            style: TextStyle(
              color: isDeclined
                  ? Colors.white.withValues(alpha: 0.35)
                  : Colors.white.withValues(alpha: 0.85),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
