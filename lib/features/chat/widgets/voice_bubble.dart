import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../../core/design/design.dart';
import '../../../core/utils/format.dart';
import '../../../core/providers/chat_provider.dart';

/// Voice-message bubble — play/pause + waveform + speed control.
///
/// Speed pill is stacked directly below the play button for easy access.
/// Waveform is seekable via tap or horizontal drag.
class VoiceBubble extends ConsumerStatefulWidget {
  final String audioUrl;
  final int durationSec;
  final List<double>? waveformSamples;
  final bool isMine;
  final String? chatId;
  final String? messageId;
  final String? sentTimeLabel;
  final bool isRead;
  final bool isDelivered;

  const VoiceBubble({
    super.key,
    required this.audioUrl,
    required this.durationSec,
    this.waveformSamples,
    required this.isMine,
    this.chatId,
    this.messageId,
    this.sentTimeLabel,
    this.isRead = false,
    this.isDelivered = false,
  });

  @override
  ConsumerState<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends ConsumerState<VoiceBubble> {
  final _player = AudioPlayer();
  bool _loaded = false;
  bool _loading = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _speed = 1.0;
  static const _speedCycle = [1.0, 1.5, 2.0];
  double? _seekIndicator;

  ProviderSubscription<String?>? _queueSub;
  ProviderSubscription<String?>? _coordinatorSub;

  StreamSubscription<Duration>? _positionStreamSub;
  StreamSubscription<Duration?>? _durationStreamSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _duration = Duration(seconds: widget.durationSec);
    _positionStreamSub = _player.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _durationStreamSub = _player.durationStream.listen((d) {
      if (d != null && mounted) setState(() => _duration = d);
    });
    _playerStateSub = _player.playerStateStream.listen((s) {
      // Guard against late events firing during teardown — touching ref
      // (via _releaseCoordinatorIfMine/_triggerAutoNext) after dispose throws.
      if (_disposed || !mounted) return;
      if (s.processingState == ProcessingState.completed) {
        _player.seek(Duration.zero);
        _player.pause();
        _releaseCoordinatorIfMine();
        _triggerAutoNext();
      }
      if (mounted) setState(() {});
    });

    if (widget.chatId != null && widget.messageId != null) {
      _queueSub = ref.listenManual<String?>(
        voiceAutoPlayQueueProvider,
        (prev, next) {
          if (next != null && next == widget.messageId) {
            ref.read(voiceAutoPlayQueueProvider.notifier).state = null;
            _autoPlay();
          }
        },
      );
      _coordinatorSub = ref.listenManual<String?>(
        currentlyPlayingVoiceProvider,
        (prev, next) {
          if (next != widget.messageId && _player.playing) {
            _player.pause();
          }
        },
      );
    }
  }

  void _markListened() {
    final mid = widget.messageId;
    if (mid == null) return;
    final cur = ref.read(listenedVoiceIdsProvider);
    if (cur.contains(mid)) return;
    ref.read(listenedVoiceIdsProvider.notifier).state = {...cur, mid};
  }

  void _claimCoordinator() {
    final mid = widget.messageId;
    if (mid == null) return;
    ref.read(currentlyPlayingVoiceProvider.notifier).state = mid;
  }

  void _releaseCoordinatorIfMine() {
    final mid = widget.messageId;
    if (mid == null) return;
    final cur = ref.read(currentlyPlayingVoiceProvider);
    if (cur == mid) {
      ref.read(currentlyPlayingVoiceProvider.notifier).state = null;
    }
  }

  void _triggerAutoNext() {
    final cid = widget.chatId;
    final mid = widget.messageId;
    if (cid == null || mid == null) return;
    final messages = ref.read(chatMessagesProvider(cid)).messages;
    final idx = messages.indexWhere((m) => m.id == mid);
    if (idx < 0) return;
    final listened = ref.read(listenedVoiceIdsProvider);
    for (var i = idx + 1; i < messages.length; i++) {
      final m = messages[i];
      if (m.kind != 'voice' && m.kind != 'audio') continue;
      if (listened.contains(m.id)) continue;
      ref.read(voiceAutoPlayQueueProvider.notifier).state = m.id;
      return;
    }
  }

  Future<void> _autoPlay() async {
    await _ensureLoaded();
    if (!_player.playing) {
      _claimCoordinator();
      _markListened();
      await _player.play();
    }
  }

  Future<void> _ensureLoaded() async {
    if (_loaded || _loading) return;
    setState(() => _loading = true);
    try {
      await _player.setUrl(widget.audioUrl);
      if (_speed != 1.0) {
        try { await _player.setSpeed(_speed); } catch (_) {}
      }
      _loaded = true;
    } catch (_) {
      if (mounted) {
        showSeeUSnackBar(context, 'Не удалось загрузить аудио',
            icon: PhosphorIconsRegular.warning, tone: SeeUTone.danger);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle() async {
    HapticFeedback.lightImpact();
    await _ensureLoaded();
    if (_player.playing) {
      await _player.pause();
      _releaseCoordinatorIfMine();
    } else {
      _claimCoordinator();
      _markListened();
      await _player.play();
    }
  }

  Future<void> _cycleSpeed() async {
    HapticFeedback.selectionClick();
    final idx = _speedCycle.indexOf(_speed);
    final next = _speedCycle[(idx + 1) % _speedCycle.length];
    setState(() => _speed = next);
    try {
      await _player.setSpeed(next);
    } catch (_) {}
  }

  String _fmtSpeed(double s) {
    final n = s.toInt();
    return s == n.toDouble() ? '$n×' : '$s×';
  }

  @override
  void dispose() {
    _disposed = true;
    _positionStreamSub?.cancel();
    _durationStreamSub?.cancel();
    _playerStateSub?.cancel();
    _queueSub?.close();
    _coordinatorSub?.close();
    _releaseCoordinatorIfMine();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final progress = _duration.inMilliseconds == 0
        ? 0.0
        : _position.inMilliseconds / _duration.inMilliseconds;

    return VisibilityDetector(
      key: Key('vb-${widget.messageId ?? widget.audioUrl}'),
      onVisibilityChanged: (info) {
        if (_disposed || !mounted) return;
        if (info.visibleFraction == 0 && _player.playing) {
          _player.pause();
          _releaseCoordinatorIfMine();
        }
      },
      child: Container(
        constraints: const BoxConstraints(minWidth: 210, maxWidth: 300),
        padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
        decoration: BoxDecoration(
          color: widget.isMine ? c.accentSoft : c.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(widget.isMine ? 20 : 8),
            bottomRight: Radius.circular(widget.isMine ? 8 : 20),
          ),
          border: Border.all(
            color: widget.isMine
                ? SeeUColors.accent.withValues(alpha: 0.22)
                : c.line,
            width: 0.5,
          ),
          boxShadow: SeeUShadows.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Left: play button + speed pill stacked ────────────────
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildPlayButton(c),
                const SizedBox(height: 5),
                _buildSpeedPill(c),
              ],
            ),
            const SizedBox(width: 10),
            // ── Right: waveform + bottom row ──────────────────────────
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LayoutBuilder(builder: (_, cst) {
                    final w = cst.maxWidth;
                    return GestureDetector(
                      onTapUp: (details) {
                        final ratio = (details.localPosition.dx / w).clamp(0.0, 1.0);
                        _player.seek(Duration(
                            milliseconds: (_duration.inMilliseconds * ratio).round()));
                        if (mounted) setState(() => _seekIndicator = null);
                      },
                      onHorizontalDragUpdate: (details) {
                        final ratio = (details.localPosition.dx / w).clamp(0.0, 1.0);
                        if (mounted) setState(() => _seekIndicator = ratio);
                      },
                      onHorizontalDragEnd: (_) {
                        if (_seekIndicator != null) {
                          _player.seek(Duration(
                              milliseconds:
                                  (_duration.inMilliseconds * _seekIndicator!).round()));
                          if (mounted) setState(() => _seekIndicator = null);
                        }
                      },
                      child: SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: CustomPaint(
                          size: Size(w, 44),
                          painter: VoiceWavePainter(
                            samples: widget.waveformSamples ?? const [],
                            progress: _seekIndicator ?? progress,
                            colorBase: c.ink3,
                            colorPlayed: SeeUColors.accent,
                            seekIndicator: _seekIndicator,
                            showPlaybackKnob:
                                _player.playing || _position > Duration.zero,
                          ),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 3),
                  // Duration left — sent time + check right
                  Row(
                    children: [
                      Text(
                        _position > Duration.zero
                            ? formatDuration(_position)
                            : formatDuration(_duration),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: c.ink2,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const Spacer(),
                      if (widget.sentTimeLabel != null) ...[
                        Text(
                          widget.sentTimeLabel!,
                          style: TextStyle(
                            fontSize: 10,
                            color: c.ink3,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        if (widget.isMine) ...[
                          const SizedBox(width: 3),
                          Icon(
                            (widget.isRead || widget.isDelivered)
                                ? PhosphorIconsBold.checks
                                : PhosphorIconsRegular.check,
                            size: 12,
                            color: widget.isRead
                                ? SeeUColors.accent
                                : c.ink3,
                          ),
                        ],
                      ],
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

  // ── Play / pause button (44×44 circle) ────────────────────────────────────

  Widget _buildPlayButton(SeeUThemeColors c) {
    final playing = _player.playing;
    const iconColor = SeeUColors.accent;
    return GestureDetector(
      onTap: _toggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: SeeUColors.accent.withValues(alpha: playing ? 0.20 : 0.12),
        ),
        child: _loading
            ? Padding(
                padding: const EdgeInsets.all(12),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: iconColor,
                ),
              )
            : Icon(
                playing
                    ? PhosphorIcons.pause(PhosphorIconsStyle.fill)
                    : PhosphorIcons.play(PhosphorIconsStyle.fill),
                color: iconColor,
                size: 20,
              ),
      ),
    );
  }

  // ── Speed pill (44×26, stacked below play button) ─────────────────────────

  Widget _buildSpeedPill(SeeUThemeColors c) {
    final active = _speed != 1.0;
    return GestureDetector(
      onTap: _cycleSpeed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 44,
        height: 26,
        decoration: BoxDecoration(
          color: active
              ? SeeUColors.accent
              : SeeUColors.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(SeeURadii.pill),
        ),
        alignment: Alignment.center,
        child: Text(
          _fmtSpeed(_speed),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: active ? Colors.white : SeeUColors.accent,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VoiceWavePainter — статические полосы формы волны с прогрессом воспроизведения.
// Публичный класс — используется и в voice_recorder.dart (preview-режим).
// ─────────────────────────────────────────────────────────────────────────────

class VoiceWavePainter extends CustomPainter {
  final List<double> samples;
  final double progress; // 0..1 played portion
  final Color colorBase;
  final Color colorPlayed;
  final double? seekIndicator; // 0..1 drag seek position
  final bool showPlaybackKnob;

  const VoiceWavePainter({
    required this.samples,
    required this.progress,
    required this.colorBase,
    required this.colorPlayed,
    this.seekIndicator,
    this.showPlaybackKnob = false,
  });

  /// Синусоидальная форма волны для fallback (без реальных samples).
  static double _fallbackSample(int i, int n) {
    final t = i / n;
    final v = 0.25 +
        0.35 * math.sin(t * math.pi * 6.5 + 0.8) *
            math.sin(t * math.pi * 2.1) +
        0.15 * math.sin(t * math.pi * 13.0 + 1.2) +
        0.10 * math.sin(t * math.pi * 3.7 + 0.4);
    return v.clamp(0.08, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    const barW = 3.0;
    const gap = 2.0;
    final n = ((size.width + gap) / (barW + gap)).floor();
    if (n <= 0) return;
    final centerY = size.height / 2;
    final progressF = progress * n;
    final playedBars = progressF.floor();

    for (var i = 0; i < n; i++) {
      final double v;
      if (samples.isEmpty) {
        v = _fallbackSample(i, n);
      } else {
        final idx =
            ((i / n) * samples.length).floor().clamp(0, samples.length - 1);
        v = samples[idx];
      }
      final h = math.max(4.0, v * size.height * 0.90);
      final x = i * (barW + gap);

      final Color barColor;
      if (i < playedBars) {
        barColor = colorPlayed;
      } else if (i == playedBars) {
        final frac = progressF - playedBars;
        barColor = Color.lerp(colorBase, colorPlayed, frac) ?? colorBase;
      } else {
        barColor = colorBase;
      }

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(x + barW / 2, centerY), width: barW, height: h),
          const Radius.circular(2.0),
        ),
        Paint()
          ..color = barColor
          ..style = PaintingStyle.fill,
      );
    }

    // Seek drag indicator
    if (seekIndicator != null) {
      final x = (seekIndicator! * size.width).clamp(0.0, size.width);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = colorPlayed.withValues(alpha: 0.75)
          ..strokeWidth = 1.5,
      );
      canvas.drawCircle(Offset(x, centerY), 5.5, Paint()..color = colorPlayed);
    } else if (showPlaybackKnob && progress > 0) {
      final x = (progress * size.width).clamp(0.0, size.width);
      canvas.drawCircle(Offset(x, centerY), 4.0, Paint()..color = colorPlayed);
    }
  }

  @override
  bool shouldRepaint(covariant VoiceWavePainter old) =>
      old.progress != progress ||
      old.samples != samples ||
      old.colorBase != colorBase ||
      old.colorPlayed != colorPlayed ||
      old.seekIndicator != seekIndicator ||
      old.showPlaybackKnob != showPlaybackKnob;
}
