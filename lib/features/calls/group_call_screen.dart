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

  @override
  void initState() {
    super.initState();
    _initLocal();
    GroupCallService.instance.localStream.addListener(_syncLocal);
    GroupCallService.instance.session.addListener(_onSession);
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
        return Scaffold(
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
                right: 20,
                child: SafeArea(
                  child: _buildTopBar(sess),
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
        );
      },
    );
  }

  Widget _buildGallery(GroupCallSession sess, bool isVoice) {
    return ValueListenableBuilder<Map<String, GroupCallPeer>>(
      valueListenable: GroupCallService.instance.peers,
      builder: (_, peers, __) {
        // Incoming/outgoing pending — gradient + лейбл по центру.
        if (sess.status == GroupCallStatus.outgoingInviting ||
            sess.status == GroupCallStatus.incomingRinging) {
          return Container(
            decoration: const BoxDecoration(gradient: SeeUGradients.heroOrange),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    PhosphorIconsBold.usersThree,
                    color: Colors.white,
                    size: 80,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    sess.chatTitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    sess.status == GroupCallStatus.incomingRinging
                        ? '@${sess.inviterUsername} приглашает в звонок'
                        : 'Ждём ответа…',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        if (peers.isEmpty) {
          return Container(
            color: Colors.black,
            child: const Center(
              child: Text(
                'Ждём участников…',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ),
          );
        }
        final entries = peers.entries.toList();
        // Layout: 1 → fullscreen; 2 → row; 3-4 → 2x2 grid; >4 → wrap-grid.
        final n = entries.length;
        int cols;
        if (n == 1) {
          cols = 1;
        } else if (n == 2) {
          cols = 2; // #26: side-by-side для двух участников
        } else {
          cols = 2;
        }
        return GridView.count(
          padding: EdgeInsets.zero,
          crossAxisCount: cols,
          childAspectRatio: cols == 1 ? 9 / 16 : 3 / 4,
          children: entries.map((e) => _peerTile(e.value, isVoice)).toList(),
        );
      },
    );
  }

  Widget _peerTile(GroupCallPeer peer, bool isVoice) {
    final hasVideo = peer.remoteStream != null &&
        !isVoice &&
        peer.remoteStream!.getVideoTracks().isNotEmpty;
    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(12),
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
              child: Container(
                decoration:
                    const BoxDecoration(gradient: SeeUGradients.heroOrange),
                child: Center(
                  child: Icon(
                    isVoice
                        ? PhosphorIconsBold.microphone
                        : PhosphorIconsBold.user,
                    size: 48,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          Positioned(
            bottom: 6,
            left: 8,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                peer.username.isNotEmpty
                    ? peer.username
                    : (peer.userId.length > 8
                        ? peer.userId.substring(0, 8)
                        : peer.userId),
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
