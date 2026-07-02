import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/design/design.dart';
import '../../../core/models/audio_track.dart';

/// A selected [startSec, endSec] range within a track.
class RangeSelection {
  final double startSec;
  final double endSec;
  const RangeSelection(this.startSec, this.endSec);

  double get lengthSec => (endSec - startSec).clamp(0.0, double.infinity);
}

/// Premium music range selector — a large waveform with two draggable handles
/// (in / out), live preview via just_audio, a moving playhead and time labels.
///
/// Two modes:
///  • [lockedWindowSeconds] != null → the selection width is fixed; the user
///    drags the whole window to pick *where* in the song it plays. Used when a
///    clip (video length or a photo's display time) drives the duration.
///  • [lockedWindowSeconds] == null → free in/out; both handles move
///    independently. Used when the user freely picks a segment of a track.
class WaveformRangeTrimmer extends StatefulWidget {
  final AudioTrack track;
  final double? lockedWindowSeconds;

  /// Start-only mode: a single start handle; the music plays from there to the
  /// end and loops forever (e.g. music on a photo post). End is the track end.
  final bool startOnly;

  final double initialStartSec;
  final double? initialEndSec;
  final ValueChanged<RangeSelection> onChanged;
  final double height;
  final double minSelectionSec;

  const WaveformRangeTrimmer({
    super.key,
    required this.track,
    required this.onChanged,
    this.lockedWindowSeconds,
    this.startOnly = false,
    this.initialStartSec = 0,
    this.initialEndSec,
    this.height = 76,
    this.minSelectionSec = 3,
  });

  @override
  State<WaveformRangeTrimmer> createState() => _WaveformRangeTrimmerState();
}

class _WaveformRangeTrimmerState extends State<WaveformRangeTrimmer> {
  late double _startSec;
  late double _endSec;

  // Preview player
  AudioPlayer? _player;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<PlayerState>? _stateSub;
  bool _loadedUrl = false;
  bool _playing = false;
  double _playheadSec = 0;

  double get _dur => widget.track.durationSeconds.toDouble();
  bool get _locked => widget.lockedWindowSeconds != null;
  bool get _startOnly => widget.startOnly;

  // Hit-area width for handles (#67); the visible grip inside is narrower.
  static const double _handleW = 24.0;

  @override
  void initState() {
    super.initState();
    final d = _dur;
    _startSec = widget.initialStartSec.clamp(0.0, d > 0 ? d : 0.0);
    if (_startOnly) {
      _endSec = d > 0 ? d : _startSec; // plays from start to end, then loops
    } else if (_locked) {
      final win = widget.lockedWindowSeconds!.clamp(0.0, d > 0 ? d : double.infinity);
      _endSec = (_startSec + win).clamp(0.0, d > 0 ? d : _startSec + win);
      // If the window pushed past the end, pull the start back.
      if (d > 0 && _endSec >= d) {
        _endSec = d;
        _startSec = (d - win).clamp(0.0, d);
      }
    } else {
      _endSec = (widget.initialEndSec ?? (d > 0 ? d : _startSec + 15))
          .clamp(_startSec + widget.minSelectionSec, d > 0 ? d : double.infinity);
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _stateSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  void _emit() => widget.onChanged(RangeSelection(_startSec, _endSec));

  // ── Preview ────────────────────────────────────────────────────────────

  Future<void> _togglePreview() async {
    if (_playing) {
      await _stopPreview();
      return;
    }
    final url = widget.track.playbackUrl;
    if (url.isEmpty) return;

    _player ??= AudioPlayer();
    _stateSub ??= _player!.playerStateStream.listen((s) {
      if (!mounted) return;
      if (s.processingState == ProcessingState.completed) _stopPreview();
    });
    _posSub ??= _player!.positionStream.listen((pos) {
      if (!mounted) return;
      final secs = pos.inMilliseconds / 1000.0;
      if (_playing && secs >= _endSec) {
        if (_startOnly) {
          // Loop back to the chosen start (infinite playback preview).
          _player?.seek(Duration(milliseconds: (_startSec * 1000).round()));
          return;
        }
        _stopPreview();
        return;
      }
      setState(() => _playheadSec = secs);
    });

    try {
      if (!_loadedUrl) {
        await _player!.setUrl(url);
        _loadedUrl = true;
      }
      await _player!.seek(Duration(milliseconds: (_startSec * 1000).round()));
      await _player!.play();
      if (mounted) setState(() => _playing = true);
    } catch (_) {
      if (mounted) setState(() => _playing = false);
    }
  }

  Future<void> _stopPreview() async {
    await _player?.pause();
    if (mounted) {
      setState(() {
        _playing = false;
        _playheadSec = _startSec;
      });
    }
  }

  // ── Drag handlers ──────────────────────────────────────────────────────

  void _onBodyDrag(double dxSec) {
    if (_startOnly) {
      _onLeftHandle(dxSec);
      return;
    }
    setState(() {
      final len = _endSec - _startSec;
      var ns = _startSec + dxSec;
      ns = ns.clamp(0.0, (_dur > 0 ? _dur : (ns + len)) - len);
      _startSec = ns;
      _endSec = ns + len;
    });
    _emit();
  }

  void _onLeftHandle(double dxSec) {
    setState(() {
      final maxStart = _startOnly
          ? (_dur - widget.minSelectionSec).clamp(0.0, _dur)
          : _endSec - widget.minSelectionSec;
      _startSec = (_startSec + dxSec).clamp(0.0, maxStart);
      if (_startOnly) _endSec = _dur;
    });
    _emit();
  }

  void _onRightHandle(double dxSec) {
    setState(() {
      var ne = (_endSec + dxSec).clamp(
          _startSec + widget.minSelectionSec, _dur > 0 ? _dur : _endSec + dxSec);
      _endSec = ne;
    });
    _emit();
  }

  // ── Build ──────────────────────────────────────────────────────────────

  String _fmt(double s) {
    final m = (s ~/ 60);
    final sec = (s % 60).floor();
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    if (_dur <= 0) {
      return Container(
        height: widget.height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(SeeURadii.medium),
        ),
        child: Text('Длительность трека неизвестна',
            style: SeeUTypography.caption.copyWith(color: c.ink3)),
      );
    }

    return Column(
      children: [
        SizedBox(
          height: widget.height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              double secToX(double s) => (s / _dur) * w;
              double dxToSec(double dx) => (dx / w) * _dur;

              final selLeft = secToX(_startSec);
              final selRight = secToX(_endSec);
              final selW = math.max(selRight - selLeft, _handleW * 2);
              final playheadX = secToX(_playheadSec.clamp(_startSec, _endSec));

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // Full-track waveform background
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _RangeWaveformPainter(
                        peaks: widget.track.waveformData,
                        startFrac: _startSec / _dur,
                        endFrac: _endSec / _dur,
                        accent: SeeUColors.accent,
                        dim: c.ink3.withValues(alpha: 0.28),
                      ),
                    ),
                  ),

                  // Dim veil outside the selection (left & right)
                  Positioned(
                    left: 0, top: 0, bottom: 0, width: selLeft,
                    child: _veil(c),
                  ),
                  Positioned(
                    left: selRight, right: 0, top: 0, bottom: 0,
                    child: _veil(c),
                  ),

                  // Selection window (draggable body)
                  Positioned(
                    left: selLeft,
                    width: selW,
                    top: 0,
                    bottom: 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragStart: (_) {
                        if (_playing) _stopPreview();
                        HapticFeedback.selectionClick();
                      },
                      onHorizontalDragUpdate: (d) =>
                          _onBodyDrag(dxToSec(d.delta.dx)),
                      child: Container(
                        decoration: BoxDecoration(
                          color: c.accentSoft.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: SeeUColors.accent,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Playhead — #68: white core + dark edge so it reads on any
                  // waveform brightness.
                  if (_playing)
                    Positioned(
                      left: playheadX - 1.25,
                      top: -3,
                      bottom: -3,
                      child: IgnorePointer(
                        child: Container(
                          width: 2.5,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: SeeUShadows.md,
                          ),
                        ),
                      ),
                    ),

                  // Left handle (free mode only)
                  if (!_locked)
                    Positioned(
                      left: selLeft - _handleW / 2,
                      top: 0, bottom: 0,
                      width: _handleW,
                      child: _Handle(
                        onDrag: (dx) {
                          if (_playing) _stopPreview();
                          _onLeftHandle(dxToSec(dx));
                        },
                      ),
                    ),
                  // Right handle (free mode only — not in start-only loop)
                  if (!_locked && !_startOnly)
                    Positioned(
                      left: selRight - _handleW / 2,
                      top: 0, bottom: 0,
                      width: _handleW,
                      child: _Handle(
                        onDrag: (dx) {
                          if (_playing) _stopPreview();
                          _onRightHandle(dxToSec(dx));
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 10),

        // Controls row: preview + time labels
        Row(
          children: [
            _PreviewButton(playing: _playing, onTap: _togglePreview),
            const SizedBox(width: 12),
            Expanded(
              child: _startOnly
                  ? Row(
                      children: [
                        Text('С ${_fmt(_startSec)}',
                            style: SeeUTypography.mono.copyWith(
                                fontSize: 11,
                                color: SeeUColors.accent,
                                fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Icon(PhosphorIconsRegular.repeat,
                            size: 13, color: c.ink3),
                        const SizedBox(width: 4),
                        Text('играет по кругу',
                            style: SeeUTypography.micro.copyWith(color: c.ink3)),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_fmt(_startSec),
                            style: SeeUTypography.mono.copyWith(
                                fontSize: 11,
                                color: SeeUColors.accent,
                                fontWeight: FontWeight.w700)),
                        // #71/#69: center pill — shows playhead time while
                        // previewing, otherwise the selection length.
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 2),
                          decoration: BoxDecoration(
                            color: c.accentSoft,
                            borderRadius: BorderRadius.circular(SeeURadii.pill),
                          ),
                          child: Text(
                            _playing
                                ? _fmt(_playheadSec)
                                : '${(_endSec - _startSec).round()} сек',
                            style: SeeUTypography.mono.copyWith(
                                fontSize: 11,
                                color: SeeUColors.accent,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(_fmt(_endSec),
                            style: SeeUTypography.mono.copyWith(
                                fontSize: 11,
                                color: SeeUColors.accent,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
            ),
          ],
        ),
      ],
    );
  }

  // #66: stronger mask over the unselected range for clearer separation.
  Widget _veil(SeeUThemeColors c) => IgnorePointer(
        child: Container(color: c.bg.withValues(alpha: 0.58)),
      );
}

// ── Handle ───────────────────────────────────────────────────────────────────

class _Handle extends StatelessWidget {
  final ValueChanged<double> onDrag;
  const _Handle({required this.onDrag});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) => HapticFeedback.selectionClick(),
      onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
      child: Center(
        child: Container(
          width: 16,
          decoration: BoxDecoration(
            color: SeeUColors.accent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: SeeUShadows.sm,
          ),
          alignment: Alignment.center,
          child: Container(
            width: 3,
            height: 22,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Preview button ───────────────────────────────────────────────────────────

class _PreviewButton extends StatelessWidget {
  final bool playing;
  final VoidCallback onTap;
  const _PreviewButton({required this.playing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: c.accentSoft,
          shape: BoxShape.circle,
          border: Border.all(
            color: SeeUColors.accent.withValues(alpha: 0.5),
          ),
        ),
        child: Icon(
          playing ? PhosphorIconsFill.pause : PhosphorIconsFill.play,
          color: SeeUColors.accent,
          size: 18,
        ),
      ),
    );
  }
}

// ── Waveform painter (two-tone by selection) ─────────────────────────────────

class _RangeWaveformPainter extends CustomPainter {
  final List<double>? peaks;
  final double startFrac;
  final double endFrac;
  final Color accent;
  final Color dim;

  const _RangeWaveformPainter({
    required this.peaks,
    required this.startFrac,
    required this.endFrac,
    required this.accent,
    required this.dim,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final data = (peaks != null && peaks!.isNotEmpty)
        ? peaks!
        : List<double>.generate(64, (i) {
            // #65: deterministic pseudo-random amplitude per bar — organic,
            // not an obvious repeating sine.
            final h = ((i * 2654435761) & 0x7fffffff) / 0x7fffffff;
            final h2 = (((i * 40503) ^ 0x5bd1e995) & 0x7fffffff) / 0x7fffffff;
            return (0.22 + 0.7 * (0.4 * h + 0.6 * h2)).clamp(0.12, 1.0);
          });
    final count = data.length;
    final slotW = size.width / count;
    final barW = (slotW * 0.55).clamp(1.5, 5.0);
    final minH = 3.0;

    // #72: faint vertical gridlines (every ~1/8) for a pro, beat-grid feel.
    final gridPaint = Paint()..color = dim.withValues(alpha: 0.10);
    for (int g = 1; g < 8; g++) {
      final x = size.width * g / 8;
      canvas.drawRect(Rect.fromLTWH(x, 0, 1, size.height), gridPaint);
    }

    for (int i = 0; i < count; i++) {
      final frac = (i + 0.5) / count;
      final inSel = frac >= startFrac && frac <= endFrac;
      final x = i * slotW + (slotW - barW) / 2;
      final peak = data[i].clamp(0.0, 1.0);
      final h = (size.height * peak).clamp(minH, size.height);
      final top = (size.height - h) / 2;
      final paint = Paint()..color = inSel ? accent : dim;
      canvas.drawRRect(
        RRect.fromLTRBR(x, top, x + barW, top + h, Radius.circular(barW / 2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_RangeWaveformPainter old) =>
      old.startFrac != startFrac ||
      old.endFrac != endFrac ||
      old.peaks != peaks;
}
