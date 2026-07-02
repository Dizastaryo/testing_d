import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import '../../core/services/call_bg_service.dart';
import 'call_service.dart' show CallKind;
import 'group_call_service.dart';

/// Group call full-screen UI. Gallery layout + local PiP.
/// Управление: mute / speaker / camera / switch-camera / hangup.
class GroupCallScreen extends StatefulWidget {
  const GroupCallScreen({super.key});

  @override
  State<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends State<GroupCallScreen>
    with TickerProviderStateMixin {
  final _localRenderer = RTCVideoRenderer();
  Timer? _durationTicker;

  // Local PiP position
  Offset? _pipOffset;

  // Controls auto-hide
  Timer? _controlsHideTimer;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 1.0,
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _initLocal();
    GroupCallService.instance.localStream.addListener(_syncLocal);
    GroupCallService.instance.session.addListener(_onSession);
    GroupCallService.instance.isCameraOff.addListener(_syncState);
    GroupCallService.instance.session.addListener(_onSessionForTimer);
    _onSessionForTimer();
    unawaited(CallBgService.instance.setCallActive(true));
    if (Platform.isIOS) {
      final s = GroupCallService.instance.session.value;
      unawaited(CallBgService.instance.prepareCallPip(
        avatarUrl: '',
        username:  s?.chatTitle ?? '',
        kind:      (s?.kind == CallKind.voice) ? 'voice' : 'video',
      ));
    }
  }

  void _onSessionForTimer() {
    final s = GroupCallService.instance.session.value;
    if (s != null &&
        s.status == GroupCallStatus.active &&
        s.connectedAt != null) {
      if (_durationTicker == null || !_durationTicker!.isActive) {
        _durationTicker =
            Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() {});
        });
      }
      _showControls();
    } else {
      _durationTicker?.cancel();
      _durationTicker = null;
    }
  }

  Future<void> _initLocal() async {
    await _localRenderer.initialize();
    if (!mounted) return;
    _localRenderer.srcObject = GroupCallService.instance.localStream.value;
    if (mounted) setState(() {});
  }

  void _syncLocal() {
    _localRenderer.srcObject = GroupCallService.instance.localStream.value;
    if (mounted) setState(() {});
  }

  void _syncState() {
    if (mounted) setState(() {});
  }

  void _onSession() {
    final s = GroupCallService.instance.session.value;
    if (s == null && mounted) Navigator.of(context).pop();
  }

  void _minimizeOrPip() {
    if (Platform.isAndroid) {
      unawaited(CallBgService.instance.enterPip());
    } else {
      final s = GroupCallService.instance.session.value;
      GroupCallService.instance.minimized.value = true;
      unawaited(CallBgService.instance.enterPip(
        connectedAt: s?.connectedAt,
      ));
      if (mounted) Navigator.of(context).pop();
    }
  }

  // ── Controls visibility ─────────────────────────────────────────────────

  void _scheduleHide() {
    _controlsHideTimer?.cancel();
    _controlsHideTimer = Timer(const Duration(seconds: 4), () {
      final s = GroupCallService.instance.session.value;
      if (s?.status == GroupCallStatus.active && mounted) {
        _fadeCtrl.reverse();
      }
    });
  }

  void _showControls() {
    _fadeCtrl.forward();
    _scheduleHide();
  }

  @override
  void dispose() {
    GroupCallService.instance.localStream.removeListener(_syncLocal);
    GroupCallService.instance.session.removeListener(_onSession);
    GroupCallService.instance.isCameraOff.removeListener(_syncState);
    GroupCallService.instance.session.removeListener(_onSessionForTimer);
    _durationTicker?.cancel();
    _controlsHideTimer?.cancel();
    _fadeCtrl.dispose();
    _localRenderer.dispose();
    unawaited(CallBgService.instance.setCallActive(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GroupCallSession?>(
      valueListenable: GroupCallService.instance.session,
      builder: (_, sess, __) {
        if (sess == null) return const SizedBox.shrink();
        final isVoice = sess.kind == CallKind.voice;
        final size = MediaQuery.of(context).size;
        const double pipW = 90, pipH = 120;
        final prev = _pipOffset;
        _pipOffset = Offset(
          (prev?.dx ?? (size.width - pipW - 16))
              .clamp(8.0, size.width - pipW - 8),
          (prev?.dy ?? (size.height - pipH - 150))
              .clamp(8.0, size.height - pipH - 150),
        );

        // Android PiP-режим: минимальный UI внутри PiP-окна.
        return ValueListenableBuilder<bool>(
          valueListenable: CallBgService.instance.pipMode,
          builder: (_, inPip, __) {
        if (inPip) {
          return Scaffold(
            backgroundColor: Colors.black,
            body: _buildGallery(sess, sess.kind == CallKind.voice),
          );
        }
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            final status = GroupCallService.instance.session.value?.status;
            if (status != null && status != GroupCallStatus.incomingRinging) {
              _minimizeOrPip();
            } else {
              Navigator.of(context).pop();
            }
          },
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.light,
            child: Scaffold(
              backgroundColor: Colors.black,
              body: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _showControls,
                child: Stack(
                  children: [
                    // ── Gallery of remote peers ──
                    Positioned.fill(
                      child: _buildGallery(sess, isVoice),
                    ),

                    // ── Top bar: minimize + title + timer ──
                    _buildTopBar(sess),

                    // ── Bottom controls ──
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: SafeArea(
                        top: false,
                        child: _buildControls(sess, isVoice),
                      ),
                    ),

                    // ── Local PiP — после controls, всегда поверх ──
                    if (!isVoice &&
                        sess.status != GroupCallStatus.incomingRinging)
                      _buildLocalPip(sess, size, pipW, pipH),
                  ],
                ),
              ),
            ),
          ),
        );
          }, // ValueListenableBuilder<bool> pipMode
        );
      },
    );
  }

  // ── Top bar ─────────────────────────────────────────────────────────────

  Widget _buildTopBar(GroupCallSession sess) {
    final isActive = sess.status == GroupCallStatus.active;
    Widget bar = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Minimize
          SeeUGlassCircleButton(
            blur: 22,
            onTap: _minimizeOrPip,
            icon: const Icon(PhosphorIconsRegular.arrowsInSimple,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          // Title + timer
          Expanded(child: _buildTitlePill(sess)),
        ],
      ),
    );

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: isActive
            ? FadeTransition(opacity: _fadeAnim, child: bar)
            : bar,
      ),
    );
  }

  Widget _buildTitlePill(GroupCallSession sess) {
    // Camera glass recipe: blur 22 + top-highlight → tint gradient + 0.8 border
    // so the pill reads as glass over the gallery (not a flat grey slab).
    return ClipRRect(
      borderRadius: BorderRadius.circular(SeeURadii.pill),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0.16),
                Colors.black.withValues(alpha: 0.24),
              ],
            ),
            borderRadius: BorderRadius.circular(SeeURadii.pill),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.18), width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (sess.status == GroupCallStatus.active)
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(right: 7),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: SeeUColors.success,
                  ),
                ),
              const Icon(PhosphorIconsBold.usersThree,
                  color: Colors.white70, size: 13),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  sess.chatTitle,
                  style: SeeUTypography.caption.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (sess.status == GroupCallStatus.active &&
                  sess.connectedAt != null) ...[
                const SizedBox(width: 8),
                Text(
                  _fmtDuration(
                      DateTime.now().difference(sess.connectedAt!)),
                  style: SeeUTypography.mono.copyWith(
                    color: Colors.white60,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Local PiP ────────────────────────────────────────────────────────────

  Widget _buildLocalPip(
      GroupCallSession sess, Size screen, double pipW, double pipH) {
    final offset = _pipOffset!;
    final cameraOff = GroupCallService.instance.isCameraOff.value;

    return Positioned(
      left: offset.dx,
      top: offset.dy,
      child: GestureDetector(
        onPanUpdate: (d) {
          setState(() {
            _pipOffset = Offset(
              (offset.dx + d.delta.dx).clamp(8.0, screen.width - pipW - 8),
              (offset.dy + d.delta.dy)
                  .clamp(8.0, screen.height - pipH - 150),
            );
          });
        },
        child: Container(
          width: pipW,
          height: pipH,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SeeURadii.card),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(SeeURadii.card),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (!cameraOff && _localRenderer.srcObject != null)
                  RTCVideoView(
                    _localRenderer,
                    mirror: true,
                    objectFit:
                        RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  )
                else
                  Container(
                    color: SeeUColors.darkSurface,
                    child: const Center(
                      child: Icon(
                        PhosphorIconsBold.videoCameraSlash,
                        color: Colors.white24,
                        size: 22,
                      ),
                    ),
                  ),
                // Border
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(SeeURadii.card),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                      width: 1.5,
                    ),
                  ),
                ),
                // «Вы» лейбл
                Positioned(
                  bottom: 5,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Вы',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Gallery ──────────────────────────────────────────────────────────────

  Widget _buildGallery(GroupCallSession sess, bool isVoice) {
    if (sess.status == GroupCallStatus.outgoingInviting) {
      return _buildOutgoingWaiting(sess, isVoice);
    }
    if (sess.status == GroupCallStatus.incomingRinging) {
      return _buildIncomingRinging(sess);
    }
    return ValueListenableBuilder<Map<String, GroupCallPeer>>(
      valueListenable: GroupCallService.instance.peers,
      builder: (_, peers, __) {
        if (peers.isEmpty) {
          return Container(
            color: SeeUColors.darkBg,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.07),
                    ),
                    child: const Icon(PhosphorIconsBold.usersThree,
                        color: Colors.white30, size: 28),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Ждём участников…',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        final entries = peers.entries.toList();
        final cols = entries.length == 1 ? 1 : 2;
        final ratio = cols == 1 ? 9.0 / 16.0 : 3.0 / 4.0;
        return GridView.builder(
          padding: const EdgeInsets.only(bottom: 130),
          physics: const ClampingScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            childAspectRatio: ratio,
          ),
          itemCount: entries.length,
          itemBuilder: (_, i) => _peerTile(entries[i].value, isVoice),
        );
      },
    );
  }

  Widget _buildOutgoingWaiting(GroupCallSession sess, bool isVoice) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [SeeUColors.darkSurface, SeeUColors.darkBg],
        ),
      ),
      child: ValueListenableBuilder<List<GroupCallMember>>(
        valueListenable: GroupCallService.instance.invitedMembers,
        builder: (_, members, __) {
          final joined = members
              .where((m) => m.status == GroupCallMemberStatus.joined)
              .length;
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: SeeUColors.accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: SeeUColors.accent.withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  isVoice
                      ? PhosphorIconsBold.phone
                      : PhosphorIconsBold.videoCamera,
                  color: SeeUColors.accent,
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                sess.chatTitle,
                style: SeeUTypography.displayM.copyWith(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                (isVoice ? 'ГОЛОСОВОЙ ЗВОНОК' : 'ВИДЕОЗВОНОК'),
                style: SeeUTypography.kicker
                    .copyWith(color: Colors.white.withValues(alpha: 0.5)),
              ),
              const SizedBox(height: 40),
              if (members.isNotEmpty) ...[
                SizedBox(
                  height: 104,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    itemCount: members.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(width: 18),
                    itemBuilder: (_, i) =>
                        _MemberStatusBubble(member: members[i]),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  joined > 0
                      ? '$joined из ${members.length} уже в звонке'
                      : 'Вызываем участников…',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 13,
                  ),
                ),
              ] else
                Text(
                  'Вызываем участников…',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 13,
                  ),
                ),
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
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [SeeUColors.darkSurface, SeeUColors.darkBg],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Avatar with pulsing ring
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 108,
                  height: 108,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: SeeUColors.accent.withValues(alpha: 0.2),
                      width: 14,
                    ),
                  ),
                ),
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: palette),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                      width: 2,
                    ),
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
            const SizedBox(height: 20),
            Text(
              '@${sess.inviterUsername}',
              style: SeeUTypography.caption
                  .copyWith(color: Colors.white.withValues(alpha: 0.5)),
            ),
            const SizedBox(height: 6),
            Text(
              sess.chatTitle,
              style: SeeUTypography.displayM.copyWith(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            _glassKindBadge(
              icon: isVoice
                  ? PhosphorIconsFill.phone
                  : PhosphorIconsFill.videoCamera,
              label: isVoice ? 'ГОЛОСОВОЙ ЗВОНОК' : 'ВИДЕОЗВОНОК',
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
        : (peer.userId.length > 8
            ? peer.userId.substring(0, 8)
            : peer.userId);
    final palIdx = peer.username.isEmpty
        ? 0
        : (peer.username.codeUnitAt(0) + peer.username.length) %
            SeeUColors.avatarPalettes.length;
    final palette = SeeUColors.avatarPalettes[palIdx];
    final initial =
        peer.username.isNotEmpty ? peer.username[0].toUpperCase() : '?';

    return Container(
      margin: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: SeeUColors.darkSurface2,
        borderRadius: BorderRadius.circular(SeeURadii.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          if (hasVideo)
            Positioned.fill(
              child: RTCVideoView(
                peer.renderer,
                objectFit:
                    RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
            )
          else
            Positioned.fill(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
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
              bottom: 6,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Controls ─────────────────────────────────────────────────────────────

  Widget _buildControls(GroupCallSession sess, bool isVoice) {
    if (sess.status == GroupCallStatus.incomingRinging) {
      return _buildIncomingControls(sess);
    }

    final isActive = sess.status == GroupCallStatus.active;
    final inner = _buildActiveControls(isVoice);
    return isActive
        ? FadeTransition(opacity: _fadeAnim, child: inner)
        : inner;
  }

  Widget _buildIncomingControls(GroupCallSession sess) {
    final isVoice = sess.kind == CallKind.voice;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 44),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _actionBtn(
            icon: PhosphorIconsFill.phoneSlash,
            color: SeeUColors.danger,
            label: 'Отклонить',
            onTap: GroupCallService.instance.declineGroupCall,
          ),
          _actionBtn(
            icon: isVoice
                ? PhosphorIconsFill.phone
                : PhosphorIconsFill.videoCamera,
            color: SeeUColors.success,
            label: 'Присоединиться',
            onTap: GroupCallService.instance.acceptGroupCall,
          ),
        ],
      ),
    );
  }

  /// Стеклянный kind-badge (camera glass recipe + mono eyebrow).
  Widget _glassKindBadge({required IconData icon, required String label}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(SeeURadii.pill),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0.16),
                Colors.black.withValues(alpha: 0.24),
              ],
            ),
            borderRadius: BorderRadius.circular(SeeURadii.pill),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.18), width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white70, size: 13),
              const SizedBox(width: 8),
              Text(
                label,
                style: SeeUTypography.kicker.copyWith(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () {
            HapticFeedback.mediumImpact();
            onTap();
          },
          child: Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.45),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 30),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildActiveControls(bool isVoice) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      child: ValueListenableBuilder<bool>(
        valueListenable: GroupCallService.instance.isMuted,
        builder: (_, muted, __) =>
            ValueListenableBuilder<bool>(
          valueListenable: GroupCallService.instance.isCameraOff,
          builder: (_, cameraOff, __) =>
              ValueListenableBuilder<bool>(
            valueListenable: GroupCallService.instance.isSpeakerOn,
            builder: (_, speakerOn, __) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 18),
                    decoration: BoxDecoration(
                      // Top-highlight → tint gradient so the bar reads as glass
                      // over media (not a flat grey slab).
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.16),
                          Colors.white.withValues(alpha: 0.06),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.16),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _ctrlBtn(
                          icon: muted
                              ? PhosphorIconsFill.microphoneSlash
                              : PhosphorIconsFill.microphone,
                          label: muted ? 'Включить' : 'Выключить',
                          active: muted,
                          onTap: GroupCallService.instance.toggleMute,
                        ),
                        _ctrlBtn(
                          icon: speakerOn
                              ? PhosphorIconsFill.speakerHigh
                              : PhosphorIconsFill.speakerLow,
                          label: speakerOn ? 'Гарнитура' : 'Динамик',
                          active: speakerOn,
                          onTap: GroupCallService.instance.toggleSpeaker,
                        ),
                        if (!isVoice) ...[
                          _ctrlBtn(
                            icon: cameraOff
                                ? PhosphorIconsFill.videoCameraSlash
                                : PhosphorIconsFill.videoCamera,
                            label: cameraOff
                                ? 'Вкл камеру'
                                : 'Выкл камеру',
                            active: cameraOff,
                            onTap:
                                GroupCallService.instance.toggleCamera,
                          ),
                          _ctrlBtn(
                            icon: PhosphorIconsRegular.arrowsClockwise,
                            label: 'Повернуть',
                            onTap:
                                GroupCallService.instance.switchCamera,
                          ),
                        ],
                        _endCallBtn(),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _ctrlBtn({
    required IconData icon,
    required String label,
    bool active = false,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
        _showControls();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.14),
              border: Border.all(
                color: active
                    ? Colors.transparent
                    : Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Icon(
              icon,
              color: active ? Colors.black87 : Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _endCallBtn() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        GroupCallService.instance.hangup();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: SeeUColors.danger,
              boxShadow: [
                BoxShadow(
                  color: SeeUColors.danger.withValues(alpha: 0.38),
                  blurRadius: 16,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: const Icon(
              PhosphorIconsFill.phoneSlash,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Завершить',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

// ─── Member status bubble ──────────────────────────────────────────────────

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
        : (name.codeUnitAt(0) + name.length) %
            SeeUColors.avatarPalettes.length;
    final palette = SeeUColors.avatarPalettes[palIdx];

    final isRinging = m.status == GroupCallMemberStatus.ringing;
    final isJoined = m.status == GroupCallMemberStatus.joined;
    final isDeclined = m.status == GroupCallMemberStatus.declined;

    final dotIcon = isJoined
        ? PhosphorIconsBold.check
        : isDeclined
            ? PhosphorIconsBold.x
            : PhosphorIconsBold.phone;
    final dotBg = isJoined
        ? SeeUColors.success
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
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: palette),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isJoined
                        ? SeeUColors.success
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
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: dotBg,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: SeeUColors.darkBg, width: 1.5),
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
