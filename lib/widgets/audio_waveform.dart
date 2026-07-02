import 'package:flutter/material.dart';

import '../core/design/tokens.dart';

/// Compact bar-chart waveform visualization.
///
/// - [waveform]: 0–100 normalized peak values in [0.0, 1.0]; null/empty = show placeholder.
/// - [progress]: playback position 0.0–1.0; bars up to this fraction are drawn in [activeColor].
/// - [height]: total widget height in logical pixels.
/// - [mini]: when true, uses a thinner bar layout suitable for list tiles and feed cards.
///
/// Falls back gracefully to placeholder bars when waveform data is absent.
class AudioWaveformPreview extends StatelessWidget {
  final List<double>? waveform;
  final double progress;
  final double height;
  final Color? activeColor;
  final Color? inactiveColor;
  final bool mini;

  const AudioWaveformPreview({
    super.key,
    required this.waveform,
    this.progress = 0.0,
    this.height = 48.0,
    this.activeColor,
    this.inactiveColor,
    this.mini = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = activeColor ?? SeeUColors.accent;
    final inactive = inactiveColor ??
        theme.colorScheme.onSurface.withValues(alpha: mini ? 0.15 : 0.22);

    final peaks = waveform;
    if (peaks == null || peaks.isEmpty) {
      // Placeholder: evenly spaced bars at 40 % height.
      return _WaveformCanvas(
        peaks: List.generate(40, (i) => 0.2 + 0.2 * ((i % 5) / 4.0)),
        progress: 0.0,
        activeColor: inactive,
        inactiveColor: inactive,
        height: height,
        mini: mini,
      );
    }

    return _WaveformCanvas(
      peaks: peaks,
      progress: progress.clamp(0.0, 1.0),
      activeColor: active,
      inactiveColor: inactive,
      height: height,
      mini: mini,
    );
  }
}

class _WaveformCanvas extends StatelessWidget {
  final List<double> peaks;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;
  final double height;
  final bool mini;

  const _WaveformCanvas({
    required this.peaks,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    required this.height,
    required this.mini,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _WaveformPainter(
          peaks: peaks,
          progress: progress,
          activeColor: activeColor,
          inactiveColor: inactiveColor,
          mini: mini,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> peaks;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;
  final bool mini;

  const _WaveformPainter({
    required this.peaks,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    required this.mini,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty || size.width <= 0 || size.height <= 0) return;

    final count = peaks.length;
    // Each bar slot = width / count. Bar itself is 55 % of slot; gap is 45 %.
    final slotW = size.width / count;
    final barW = (slotW * (mini ? 0.6 : 0.55)).clamp(1.0, mini ? 3.0 : 5.0);
    final minBarH = mini ? 2.0 : 3.0;
    final activePaint = Paint()..color = activeColor;
    final inactivePaint = Paint()..color = inactiveColor;
    final activeBar = (count * progress).floor();

    for (int i = 0; i < count; i++) {
      final x = i * slotW + (slotW - barW) / 2;
      final peak = peaks[i].clamp(0.0, 1.0);
      final barH = (size.height * peak).clamp(minBarH, size.height);
      final top = (size.height - barH) / 2;

      final paint = i < activeBar ? activePaint : inactivePaint;
      final rrect = RRect.fromLTRBR(
        x, top, x + barW, top + barH,
        Radius.circular(barW / 2),
      );
      canvas.drawRRect(rrect, paint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress ||
      old.peaks != peaks ||
      old.activeColor != activeColor ||
      old.inactiveColor != inactiveColor;
}
