import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import '../../core/services/call_bg_service.dart';
import '../../widgets/speaking_rings.dart';
import 'call_service.dart';

/// Full-screen экран звонка.
///
/// Фичи:
/// - Видеозвонок: remote на весь экран, local — маленький PiP.
/// - Tap по PiP → swap (local ↔ remote становятся main/pip).
/// - Drag PiP в любой угол.
/// - Контролы автоматически скрываются через 4 с (показываются по тапу).
/// - Glassmorphism controls bar с подписями.
/// - Красивый incoming-call layout.
/// - Reconnecting banner.
class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with TickerProviderStateMixin {
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  Timer? _durationTicker;

  // true = local video is main, remote is PiP
  bool _swapped = false;

  // Draggable PiP position; set lazily from screen size
  Offset? _pipOffset;

  // Auto-hide controls
  Timer? _controlsHideTimer;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  // Pulse rings during ringing states
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 1.0,
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _initRenderers();
    CallService.instance.session.addListener(_onSessionChanged);
    CallService.instance.isCameraOff.addListener(_syncState);
    _onSessionChanged();
    _scheduleHide();
    unawaited(CallBgService.instance.setCallActive(true));
    // iOS: регистрируем lifecycle-наблюдатели чтобы PiP автозапускался при
    // уходе в фон (как с полного экрана, так и после minimize).
    if (Platform.isIOS) {
      final s = CallService.instance.session.value;
      unawaited(CallBgService.instance.prepareCallPip(
        avatarUrl: s?.peerAvatarUrl ?? '',
        username:  s?.peerUsername  ?? '',
        kind:      (s?.kind == CallKind.voice) ? 'voice' : 'video',
      ));
    }
  }

  void _onSessionChanged() {
    final s = CallService.instance.session.value;
    if (s == null) {
      _durationTicker?.cancel();
      _durationTicker = null;
      _pulseCtrl.stop();
      return;
    }
    if (s.status == CallStatus.connected) {
      _showControls(); // сбрасываем hide-таймер при каждом connected-событии
      _pulseCtrl.stop();
      _pulseCtrl.value = 0;
      if (_durationTicker == null || !_durationTicker!.isActive) {
        _durationTicker =
            Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() {});
        });
      }
    } else {
      _durationTicker?.cancel();
      _durationTicker = null;
    }
    // Start pulse rings during ringing
    if (s.status == CallStatus.incomingRinging ||
        s.status == CallStatus.outgoingRinging) {
      if (!_pulseCtrl.isAnimating) _pulseCtrl.repeat();
    } else if (s.status != CallStatus.connected) {
      _pulseCtrl.stop();
      _pulseCtrl.value = 0;
    }
    if (mounted) setState(() {});
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

  void _syncState() {
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

  // ── Controls visibility ─────────────────────────────────────────────────

  void _scheduleHide() {
    _controlsHideTimer?.cancel();
    _controlsHideTimer = Timer(const Duration(seconds: 4), () {
      final s = CallService.instance.session.value;
      if (s?.status == CallStatus.connected && mounted) {
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
    _durationTicker?.cancel();
    _controlsHideTimer?.cancel();
    _fadeCtrl.dispose();
    _pulseCtrl.dispose();
    CallService.instance.session.removeListener(_onSessionChanged);
    CallService.instance.isCameraOff.removeListener(_syncState);
    CallService.instance.localStream.removeListener(_syncLocal);
    CallService.instance.remoteStream.removeListener(_syncRemote);
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    unawaited(CallBgService.instance.setCallActive(false));
    super.dispose();
  }

  // ── PiP ─────────────────────────────────────────────────────────────────

  /// Android: Activity входит в PiP-режим (окно остаётся, маршрут не меняется).
  /// iOS: запускаем нативный AVPictureInPicture немедленно (floating over app),
  /// закрываем полноэкранный маршрут. Один нативный PiP работает и внутри и снаружи.
  void _minimizeOrPip() {
    if (Platform.isAndroid) {
      unawaited(CallBgService.instance.enterPip());
    } else {
      final s = CallService.instance.session.value;
      CallService.instance.minimized.value = true;
      unawaited(CallBgService.instance.enterPip(
        connectedAt: s?.connectedAt,
      ));
      if (mounted) Navigator.of(context).pop();
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CallSession?>(
      valueListenable: CallService.instance.session,
      builder: (_, session, __) {
        if (session == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).pop();
          });
          return const SizedBox.shrink();
        }

        // Android PiP-режим: минимальный UI — только видео/аватар, без управления.
        return ValueListenableBuilder<bool>(
          valueListenable: CallBgService.instance.pipMode,
          builder: (_, inPip, __) {
            if (inPip) {
              final isVoicePip = session.kind == CallKind.voice;
              return Scaffold(
                backgroundColor: Colors.black,
                body: isVoicePip
                    ? _buildAvatarBg(session)
                    : _buildMainView(session, false),
              );
            }

        final isVoice = session.kind == CallKind.voice;
        final size = MediaQuery.of(context).size;
        // Clamp PiP on every build — prevents going off-screen after rotation.
        const double pipW = 110, pipH = 148;
        final prev = _pipOffset;
        _pipOffset = Offset(
          (prev?.dx ?? (size.width - pipW - 20))
              .clamp(8.0, size.width - pipW - 8),
          (prev?.dy ?? 80.0).clamp(8.0, size.height - pipH - 8),
        );

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            final status = CallService.instance.session.value?.status;
            if (status != null &&
                status != CallStatus.incomingRinging &&
                status != CallStatus.ended &&
                status != CallStatus.idle) {
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
                    // ── Main video / avatar background ──
                    Positioned.fill(
                      child: _buildMainView(session, isVoice),
                    ),

                    // ── Draggable PiP ──
                    if (!isVoice &&
                        session.status != CallStatus.incomingRinging)
                      _buildPip(session, size),

                    // ── Reconnecting banner ──
                    if (session.status == CallStatus.reconnecting)
                      _buildReconnectBanner(),

                    // ── Top bar: minimize + timer ──
                    _buildTopBar(session),

                    // ── Bottom controls ──
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: SafeArea(
                        top: false,
                        child: _buildControls(session),
                      ),
                    ),
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

  // ── Main view ───────────────────────────────────────────────────────────

  Widget _buildMainView(CallSession s, bool isVoice) {
    if (isVoice) return _buildAvatarBg(s);
    final cameraOff = CallService.instance.isCameraOff.value;
    if (s.status == CallStatus.connected) {
      // Swapped: local full-screen (only if camera is on)
      if (_swapped && _localRenderer.srcObject != null && !cameraOff) {
        return RTCVideoView(
          _localRenderer,
          mirror: true,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        );
      }
      // Default: remote full-screen
      if (!_swapped && _remoteRenderer.srcObject != null) {
        return RTCVideoView(
          _remoteRenderer,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        );
      }
    }
    // During outgoing ringing — show local camera preview as main (if not swapped)
    // so the user can see themselves before the call connects.
    if (!_swapped &&
        s.status == CallStatus.outgoingRinging &&
        _localRenderer.srcObject != null &&
        !cameraOff) {
      return RTCVideoView(
        _localRenderer,
        mirror: true,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
    }
    return _buildAvatarBg(s);
  }

  Widget _buildAvatarBg(CallSession s) {
    final isConnected = s.status == CallStatus.connected ||
        s.status == CallStatus.reconnecting;
    final isRinging = s.status == CallStatus.incomingRinging ||
        s.status == CallStatus.outgoingRinging;
    final avatarSize = isConnected ? 170.0 : 148.0;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1C1C2E), Color(0xFF0A0A14)],
        ),
      ),
      child: Stack(
        children: [
          // Subtle accent glow
          Positioned(
            top: -120,
            left: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    SeeUColors.accent.withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Avatar: pulse rings (ringing) or speaking rings (connected)
                SizedBox(
                  width: avatarSize + 100,
                  height: avatarSize + 100,
                  child: Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      if (isRinging) ...[
                        _pulseRingWidget(0.0, avatarSize),
                        _pulseRingWidget(0.5, avatarSize),
                      ],
                      if (isConnected)
                        ValueListenableBuilder<double>(
                          valueListenable:
                              CallService.instance.remoteAudioLevel,
                          builder: (_, level, child) => SpeakingRings(
                            audioLevel: level,
                            size: avatarSize,
                            color: SeeUColors.accent,
                            child: child!,
                          ),
                          child: _avatarCircle(s, avatarSize),
                        )
                      else
                        _avatarCircle(s, avatarSize),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  s.peerUsername.isNotEmpty ? '@${s.peerUsername}' : 'Звонок',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 10),
                if (s.status != CallStatus.incomingRinging &&
                    s.status != CallStatus.connected &&
                    s.status != CallStatus.reconnecting)
                  _statusChip(s),
                if (isConnected) ...[
                  const SizedBox(height: 14),
                  _buildMicPill(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarCircle(CallSession s, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24, width: 2.5),
        color: Colors.white10,
      ),
      clipBehavior: Clip.antiAlias,
      child: s.peerAvatarUrl.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: s.peerAvatarUrl,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Icon(
                PhosphorIconsBold.user,
                color: Colors.white38,
                size: size * 0.38,
              ),
            )
          : Icon(
              PhosphorIconsBold.user,
              color: Colors.white38,
              size: size * 0.38,
            ),
    );
  }

  Widget _pulseRingWidget(double offset, double baseSize) {
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (_, __) {
        final t = (_pulseCtrl.value + offset) % 1.0;
        final scale = 1.0 + t * 0.65;
        final opacity = (1.0 - t).clamp(0.0, 1.0) * 0.35;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: baseSize,
            height: baseSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: SeeUColors.accent.withValues(alpha: opacity),
                width: 2.5,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMicPill() {
    return ValueListenableBuilder<bool>(
      valueListenable: CallService.instance.isMuted,
      builder: (_, muted, __) => ValueListenableBuilder<double>(
        valueListenable: CallService.instance.localAudioLevel,
        builder: (_, level, __) {
          final isSpeaking = !muted && level > 0.05;
          final Color pillColor;
          final IconData icon;
          final String label;
          if (muted) {
            pillColor = const Color(0xFFFF3B30);
            icon = PhosphorIconsFill.microphoneSlash;
            label = 'Микрофон выключен';
          } else if (isSpeaking) {
            pillColor = const Color(0xFF2FA84F);
            icon = PhosphorIconsFill.microphone;
            label = 'Говорите…';
          } else {
            pillColor = Colors.white.withValues(alpha: 0.15);
            icon = PhosphorIconsFill.microphone;
            label = 'Тихо';
          }
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: pillColor,
              borderRadius: BorderRadius.circular(99),
              boxShadow: isSpeaking
                  ? [
                      BoxShadow(
                        color: const Color(0xFF2FA84F)
                            .withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 12),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _statusChip(CallSession s) {
    final label = _statusLabel(s);
    if (label.isEmpty) return const SizedBox.shrink();
    final noAnswer = s.status == CallStatus.outgoingRinging &&
        s.peerResponseSeen == false;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
      decoration: BoxDecoration(
        color: noAnswer
            ? SeeUColors.accent.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: noAnswer
              ? SeeUColors.accent.withValues(alpha: 0.4)
              : Colors.white12,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: noAnswer
              ? SeeUColors.accent
              : Colors.white.withValues(alpha: 0.75),
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  // ── Draggable PiP ───────────────────────────────────────────────────────

  Widget _buildPip(CallSession s, Size screen) {
    const pipW = 110.0;
    const pipH = 148.0;
    final offset = _pipOffset!;

    // What goes in PiP: opposite of main
    final pipIsLocal = !_swapped;
    final renderer = pipIsLocal ? _localRenderer : _remoteRenderer;
    // Local PiP: show camera preview even before connected (outgoing state).
    // Remote PiP: only when actually connected (stream carries data).
    final hasVideo = renderer.srcObject != null &&
        (pipIsLocal || s.status == CallStatus.connected);
    final cameraOff =
        pipIsLocal && CallService.instance.isCameraOff.value;

    return Positioned(
      left: offset.dx,
      top: offset.dy,
      child: GestureDetector(
        // Tap = swap main ↔ PiP
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _swapped = !_swapped);
          _showControls();
        },
        // Drag = reposition
        onPanUpdate: (d) {
          setState(() {
            _pipOffset = Offset(
              (offset.dx + d.delta.dx).clamp(8.0, screen.width - pipW - 8),
              (offset.dy + d.delta.dy).clamp(8.0, screen.height - pipH - 8),
            );
          });
        },
        child: ValueListenableBuilder<double>(
          valueListenable: CallService.instance.localAudioLevel,
          builder: (_, level, __) {
            final speaking = pipIsLocal && level > 0.08;
            return Container(
              width: pipW,
              height: pipH,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.55),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Video or placeholder
                    if (hasVideo && !cameraOff)
                      RTCVideoView(
                        renderer,
                        mirror: pipIsLocal,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      )
                    else
                      Container(
                        color: const Color(0xFF1A1A2E),
                        child: const Center(
                          child: Icon(
                            PhosphorIconsBold.videoCameraSlash,
                            color: Colors.white24,
                            size: 26,
                          ),
                        ),
                      ),

                    // Speaking border overlay
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: speaking
                              ? const Color(0xFF2FA84F).withValues(
                                  alpha: (0.4 + level).clamp(0.0, 1.0))
                              : Colors.white.withValues(alpha: 0.2),
                          width: speaking ? 2.5 : 1.5,
                        ),
                      ),
                    ),

                    // Swap hint icon (bottom-right)
                    Positioned(
                      bottom: 7,
                      right: 7,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          PhosphorIconsRegular.arrowsCounterClockwise,
                          color: Colors.white60,
                          size: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Top bar ─────────────────────────────────────────────────────────────

  Widget _buildTopBar(CallSession s) {
    final isLive = s.status == CallStatus.connected ||
        s.status == CallStatus.reconnecting;
    final showFade = isLive;

    Widget bar = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Minimize — top-left (avoids conflict with PiP top-right)
          _glassButton(
            icon: PhosphorIconsRegular.arrowsInSimple,
            onTap: _minimizeOrPip,
          ),
          const Spacer(),
          // Timer pill — center when connected
          if (isLive) _timerPill(s),
          const Spacer(),
          const SizedBox(width: 44), // balance for minimize btn
        ],
      ),
    );

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: showFade
            ? FadeTransition(opacity: _fadeAnim, child: bar)
            : bar,
      ),
    );
  }

  Widget _glassButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.15),
              border:
                  Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }

  Widget _timerPill(CallSession s) {
    final connectedAt = s.connectedAt;
    final dur = connectedAt != null
        ? DateTime.now().difference(connectedAt)
        : Duration.zero;

    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(99),
            border:
                Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF2FA84F),
                ),
              ),
              const SizedBox(width: 7),
              Text(
                '@${s.peerUsername}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _fmtDuration(dur),
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Reconnecting banner ──────────────────────────────────────────────────

  Widget _buildReconnectBanner() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9500)
                      .withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Восстановление связи…',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Controls ─────────────────────────────────────────────────────────────

  Widget _buildControls(CallSession s) {
    if (s.status == CallStatus.ended) return const SizedBox.shrink();

    if (s.status == CallStatus.incomingRinging) {
      return _buildIncomingLayout(s);
    }

    final isLive = s.status == CallStatus.connected ||
        s.status == CallStatus.reconnecting;

    final inner = _buildActiveControls(s);
    return isLive
        ? FadeTransition(opacity: _fadeAnim, child: inner)
        : inner;
  }

  // ── Incoming call layout ─────────────────────────────────────────────────

  Widget _buildIncomingLayout(CallSession s) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 44),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Kind badge
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  s.kind == CallKind.voice
                      ? PhosphorIconsFill.phone
                      : PhosphorIconsFill.videoCamera,
                  color: Colors.white54,
                  size: 13,
                ),
                const SizedBox(width: 7),
                Text(
                  s.kind == CallKind.voice
                      ? 'Голосовой вызов'
                      : 'Видеовызов',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 36),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _actionBtn(
                icon: PhosphorIconsFill.phoneSlash,
                color: const Color(0xFFFF3B30),
                label: 'Отклонить',
                onTap: CallService.instance.declineIncoming,
              ),
              _actionBtn(
                icon: s.kind == CallKind.voice
                    ? PhosphorIconsFill.phone
                    : PhosphorIconsFill.videoCamera,
                color: const Color(0xFF2FA84F),
                label: 'Принять',
                onTap: CallService.instance.acceptIncoming,
              ),
            ],
          ),
        ],
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
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ── Active controls (connected / connecting / outgoing) ───────────────────

  Widget _buildActiveControls(CallSession s) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      child: ValueListenableBuilder<bool>(
        valueListenable: CallService.instance.isMuted,
        builder: (_, muted, __) =>
            ValueListenableBuilder<bool>(
          valueListenable: CallService.instance.isCameraOff,
          builder: (_, cameraOff, __) =>
              ValueListenableBuilder<bool>(
            valueListenable: CallService.instance.isSpeakerOn,
            builder: (_, speakerOn, __) {
              final isVoice = s.kind == CallKind.voice;
              return ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: BackdropFilter(
                  filter:
                      ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 18),
                    decoration: BoxDecoration(
                      color: Colors.white
                          .withValues(alpha: 0.1),
                      borderRadius:
                          BorderRadius.circular(30),
                      border: Border.all(
                        color: Colors.white
                            .withValues(alpha: 0.1),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceEvenly,
                      children: [
                        _ctrlBtn(
                          icon: muted
                              ? PhosphorIconsFill
                                  .microphoneSlash
                              : PhosphorIconsFill.microphone,
                          label:
                              muted ? 'Включить' : 'Выключить',
                          active: muted,
                          onTap:
                              CallService.instance.toggleMute,
                        ),
                        _ctrlBtn(
                          icon: speakerOn
                              ? PhosphorIconsFill.speakerHigh
                              : PhosphorIconsFill.speakerLow,
                          label: speakerOn
                              ? 'Гарнитура'
                              : 'Динамик',
                          active: speakerOn,
                          onTap: CallService
                              .instance.toggleSpeaker,
                        ),
                        if (!isVoice) ...[
                          _ctrlBtn(
                            icon: cameraOff
                                ? PhosphorIconsFill
                                    .videoCameraSlash
                                : PhosphorIconsFill.videoCamera,
                            label: cameraOff
                                ? 'Вкл камеру'
                                : 'Выкл камеру',
                            active: cameraOff,
                            onTap: CallService
                                .instance.toggleCamera,
                          ),
                          _ctrlBtn(
                            icon: PhosphorIconsRegular
                                .arrowsClockwise,
                            label: 'Перевернуть',
                            onTap: CallService
                                .instance.switchCamera,
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
        CallService.instance.hangup();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFF3B30),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF3B30)
                      .withValues(alpha: 0.38),
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

  String _statusLabel(CallSession s) {
    switch (s.status) {
      case CallStatus.outgoingRinging:
        return s.peerResponseSeen == false
            ? 'Не отвечает…'
            : 'Соединение…';
      case CallStatus.incomingRinging:
        return 'Входящий звонок';
      case CallStatus.connecting:
        return 'Подключение…';
      case CallStatus.connected:
        return 'В разговоре';
      case CallStatus.reconnecting:
        return 'Восстановление…';
      case CallStatus.ended:
        return 'Звонок завершён';
      case CallStatus.idle:
        return '';
    }
  }
}
