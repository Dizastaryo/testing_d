import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import 'call_service.dart';

/// Full-screen view активного звонка. Renderers заводятся под текущие streams,
/// меняются по подписке на ValueNotifier'ы CallService'а.
///
/// Layout: remote video на весь экран, local — pip 100×130 в правом верхнем
/// углу. Снизу контролы: mute / camera-toggle / switch-cam / end.
class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();

  @override
  void initState() {
    super.initState();
    _initRenderers();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    _localRenderer.srcObject = CallService.instance.localStream.value;
    _remoteRenderer.srcObject = CallService.instance.remoteStream.value;
    CallService.instance.localStream.addListener(_syncLocal);
    CallService.instance.remoteStream.addListener(_syncRemote);
    if (mounted) setState(() {});
  }

  void _syncLocal() {
    _localRenderer.srcObject = CallService.instance.localStream.value;
    if (mounted) setState(() {});
  }

  void _syncRemote() {
    _remoteRenderer.srcObject = CallService.instance.remoteStream.value;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    CallService.instance.localStream.removeListener(_syncLocal);
    CallService.instance.remoteStream.removeListener(_syncRemote);
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CallSession?>(
      valueListenable: CallService.instance.session,
      builder: (_, session, __) {
        if (session == null) {
          // Сессия закрыта — pop за нас.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          });
          return const SizedBox.shrink();
        }
        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              // Remote — full screen video или fallback с аватаром.
              Positioned.fill(child: _buildRemote(session)),

              // Local — pip 100×130 в правом верхнем углу.
              Positioned(
                top: 50,
                right: 20,
                width: 100,
                height: 130,
                child: _buildLocalPip(),
              ),

              // Top status bar — имя peer'а + статус.
              Positioned(
                top: 50,
                left: 20,
                child: SafeArea(
                  child: _buildPeerInfo(session),
                ),
              ),

              // Bottom controls — mute / camera / switch / end.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                    child: _buildControls(session),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRemote(CallSession s) {
    if (s.status == CallStatus.connected && _remoteRenderer.srcObject != null) {
      return RTCVideoView(
        _remoteRenderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
    }
    // Fallback — большой аватар на gradient'е (звонит/соединение/завершено).
    return Container(
      decoration: const BoxDecoration(gradient: SeeUGradients.heroOrange),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24, width: 3),
                color: Colors.white12,
              ),
              clipBehavior: Clip.antiAlias,
              child: s.peerAvatarUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: s.peerAvatarUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const Icon(
                          PhosphorIconsBold.user,
                          color: Colors.white54,
                          size: 60),
                    )
                  : const Icon(PhosphorIconsBold.user,
                      color: Colors.white54, size: 60),
            ),
            const SizedBox(height: 20),
            Text(
              s.peerUsername.isNotEmpty ? '@${s.peerUsername}' : 'Звонок',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _statusLabel(s.status),
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

  Widget _buildLocalPip() {
    return ValueListenableBuilder<bool>(
      valueListenable: CallService.instance.isCameraOff,
      builder: (_, cameraOff, __) {
        if (cameraOff || _localRenderer.srcObject == null) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white24, width: 1),
            ),
            child: const Center(
              child: Icon(PhosphorIconsBold.videoCameraSlash,
                  color: Colors.white54, size: 24),
            ),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white24, width: 1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: RTCVideoView(
              _localRenderer,
              mirror: true,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
          ),
        );
      },
    );
  }

  Widget _buildPeerInfo(CallSession s) {
    if (s.status == CallStatus.connected) {
      // На connected — peer-info сворачивается в маленький pill сверху.
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.fiber_manual_record,
                color: Colors.greenAccent, size: 10),
            const SizedBox(width: 6),
            Text(
              '@${s.peerUsername}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildControls(CallSession s) {
    return ValueListenableBuilder<bool>(
      valueListenable: CallService.instance.isMuted,
      builder: (_, muted, __) => ValueListenableBuilder<bool>(
        valueListenable: CallService.instance.isCameraOff,
        builder: (_, cameraOff, __) {
          // Для incoming-ringing — две большие кнопки accept/decline.
          if (s.status == CallStatus.incomingRinging) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _bigButton(
                  icon: PhosphorIconsFill.phoneSlash,
                  color: SeeUColors.error,
                  onTap: CallService.instance.declineIncoming,
                ),
                _bigButton(
                  icon: PhosphorIconsFill.phone,
                  color: const Color(0xFF2FA84F),
                  onTap: CallService.instance.acceptIncoming,
                ),
              ],
            );
          }
          // Connected / outgoing-ringing / connecting — controls + end.
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _smallButton(
                icon: muted
                    ? PhosphorIconsFill.microphoneSlash
                    : PhosphorIconsFill.microphone,
                active: muted,
                onTap: CallService.instance.toggleMute,
              ),
              _smallButton(
                icon: cameraOff
                    ? PhosphorIconsFill.videoCameraSlash
                    : PhosphorIconsFill.videoCamera,
                active: cameraOff,
                onTap: CallService.instance.toggleCamera,
              ),
              _smallButton(
                icon: PhosphorIconsRegular.arrowsClockwise,
                onTap: CallService.instance.switchCamera,
              ),
              _bigButton(
                icon: PhosphorIconsFill.phoneSlash,
                color: SeeUColors.error,
                onTap: CallService.instance.hangup,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _smallButton({
    required IconData icon,
    bool active = false,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active
              ? Colors.white
              : Colors.white.withValues(alpha: 0.15),
        ),
        child: Icon(
          icon,
          color: active ? Colors.black : Colors.white,
          size: 24,
        ),
      ),
    );
  }

  Widget _bigButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.4),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 30),
      ),
    );
  }

  String _statusLabel(CallStatus s) {
    switch (s) {
      case CallStatus.outgoingRinging:
        return 'Гудки…';
      case CallStatus.incomingRinging:
        return 'Входящий звонок';
      case CallStatus.connecting:
        return 'Подключение…';
      case CallStatus.connected:
        return 'В разговоре';
      case CallStatus.ended:
        return 'Звонок завершён';
      case CallStatus.idle:
        return '';
    }
  }
}
