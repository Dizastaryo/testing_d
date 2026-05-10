import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/design/design.dart';

/// Voice-message bubble — обёртка вокруг play/pause-кнопки + waveform-prerender'а.
///
/// Получает [audioUrl] (full URL до ogg/m4a/webm), [durationSec] (от сервера —
/// уже probed ffprobe'ом или клиентом до отправки) и опциональный
/// [waveformSamples] (список 0..1, длиной около 48). Если samples нет —
/// рисуется ровная полоска.
class VoiceBubble extends StatefulWidget {
  final String audioUrl;
  final int durationSec;
  final List<double>? waveformSamples;
  final bool isMine;

  const VoiceBubble({
    super.key,
    required this.audioUrl,
    required this.durationSec,
    this.waveformSamples,
    required this.isMine,
  });

  @override
  State<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<VoiceBubble> {
  // Один shared плеер для всех VoiceBubble не делаем — у каждой своя
  // позиция, и чаще нужен только один играющий за раз. Если будет issue
  // с одновременным воспроизведением — добавим coordinator-провайдер.
  final _player = AudioPlayer();
  bool _loaded = false;
  bool _loading = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _duration = Duration(seconds: widget.durationSec);
    _player.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.durationStream.listen((d) {
      if (d != null && mounted) setState(() => _duration = d);
    });
    _player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) {
        // По окончанию — сбрасываем для возможности replay.
        _player.seek(Duration.zero);
        _player.pause();
      }
      if (mounted) setState(() {});
    });
  }

  Future<void> _ensureLoaded() async {
    if (_loaded || _loading) return;
    setState(() => _loading = true);
    try {
      await _player.setUrl(widget.audioUrl);
      _loaded = true;
    } catch (_) {
      // ignore — просто оставляем _loaded = false, юзер увидит
      // что прогресс не двигается; кнопка останется нажимаемой.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle() async {
    HapticFeedback.lightImpact();
    await _ensureLoaded();
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final progress =
        _duration.inMilliseconds == 0 ? 0.0 : _position.inMilliseconds / _duration.inMilliseconds;
    return Container(
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 260),
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
      decoration: BoxDecoration(
        gradient: widget.isMine ? SeeUGradients.heroOrange : null,
        color: widget.isMine ? null : c.surface2,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          // Play/pause
          GestureDetector(
            onTap: _toggle,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.isMine
                    ? Colors.white.withValues(alpha: 0.20)
                    : SeeUColors.accent.withValues(alpha: 0.10),
              ),
              child: _loading
                  ? Padding(
                      padding: const EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color:
                            widget.isMine ? Colors.white : SeeUColors.accent,
                      ),
                    )
                  : Icon(
                      _player.playing
                          ? PhosphorIcons.pause(PhosphorIconsStyle.fill)
                          : PhosphorIcons.play(PhosphorIconsStyle.fill),
                      color:
                          widget.isMine ? Colors.white : SeeUColors.accent,
                      size: 16,
                    ),
            ),
          ),
          const SizedBox(width: 10),
          // Waveform + duration
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 28,
                  child: CustomPaint(
                    painter: _StaticWavePainter(
                      samples: widget.waveformSamples ?? const [],
                      progress: progress,
                      colorBase: widget.isMine
                          ? Colors.white.withValues(alpha: 0.45)
                          : c.ink3,
                      colorPlayed: widget.isMine
                          ? Colors.white
                          : SeeUColors.accent,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _player.playing || _position > Duration.zero
                      ? _fmt(_position)
                      : _fmt(_duration),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: widget.isMine ? Colors.white70 : c.ink2,
                    fontFeatures: const [FontFeature.tabularFigures()],
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

class _StaticWavePainter extends CustomPainter {
  final List<double> samples;
  final double progress; // 0..1, played-portion
  final Color colorBase;
  final Color colorPlayed;

  _StaticWavePainter({
    required this.samples,
    required this.progress,
    required this.colorBase,
    required this.colorPlayed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const barW = 2.0;
    const gap = 2.0;
    final n = ((size.width + gap) / (barW + gap)).floor();
    final centerY = size.height / 2;
    final total = n;
    final playedBars = (progress * total).round();
    for (var i = 0; i < n; i++) {
      // Если samples длинее n — берём ближайший downsample. Если меньше —
      // зацикливаем для bar-плейсхолдера.
      double v;
      if (samples.isEmpty) {
        v = 0.4 + 0.2 * math.sin(i * 0.6);
      } else {
        final idx = ((i / n) * samples.length).floor().clamp(0, samples.length - 1);
        v = samples[idx];
      }
      final h = math.max(3.0, v * size.height * 0.95);
      final x = i * (barW + gap);
      final paint = Paint()
        ..color = i < playedBars ? colorPlayed : colorBase
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(x + barW / 2, centerY), width: barW, height: h),
          const Radius.circular(1.5),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StaticWavePainter old) =>
      old.progress != progress ||
      old.samples.length != samples.length ||
      old.colorPlayed != colorPlayed;
}
