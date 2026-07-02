import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

import '../../core/design/design.dart';
import 'services/video_trim_service.dart';
import '../camera/widgets/camera_ui_kit.dart';

/// Result returned from [VideoTrimScreen].
class VideoTrimResult {
  final double startSec;
  final double endSec;

  /// Path to the physically trimmed file (ffmpeg). Null if the cut failed —
  /// caller may then fall back to the original file + offsets.
  final String? outputPath;

  const VideoTrimResult({
    required this.startSec,
    required this.endSec,
    this.outputPath,
  });
}

/// Full-screen video trimmer: a filmstrip of frames with two draggable
/// handles, a live preview and a real ffmpeg cut on confirm.
class VideoTrimScreen extends StatefulWidget {
  final String filePath;

  /// Optional maximum selectable length (e.g. 60s when targeting a Story).
  final double? maxSelectionSec;

  const VideoTrimScreen({
    super.key,
    required this.filePath,
    this.maxSelectionSec,
  });

  @override
  State<VideoTrimScreen> createState() => _VideoTrimScreenState();
}

class _VideoTrimScreenState extends State<VideoTrimScreen> {
  VideoPlayerController? _ctrl;
  bool _ready = false;
  double _durSec = 0;

  double _startSec = 0;
  double _endSec = 0;

  final List<Uint8List?> _frames = [];
  static const int _frameCount = 12;
  static const double _handleW = 18.0;

  bool _exporting = false;
  bool _playing = false;
  Timer? _playGuard;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final ctrl = VideoPlayerController.file(File(widget.filePath));
    _ctrl = ctrl;
    try {
      await ctrl.initialize();
      _durSec = ctrl.value.duration.inMilliseconds / 1000.0;
      _startSec = 0;
      _endSec = widget.maxSelectionSec != null
          ? widget.maxSelectionSec!.clamp(0.0, _durSec)
          : _durSec;
      if (mounted) setState(() => _ready = true);
      _extractFrames();
    } catch (e) {
      debugPrint('VideoTrimScreen init: $e');
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _extractFrames() async {
    for (int i = 0; i < _frameCount; i++) {
      _frames.add(null);
    }
    if (mounted) setState(() {});
    for (int i = 0; i < _frameCount; i++) {
      final t = (_durSec * 1000 * (i / (_frameCount - 1))).round();
      try {
        final data = await vt.VideoThumbnail.thumbnailData(
          video: widget.filePath,
          imageFormat: vt.ImageFormat.JPEG,
          timeMs: t,
          maxWidth: 120,
          quality: 50,
        );
        if (!mounted) return;
        setState(() => _frames[i] = data);
      } catch (_) {/* leave placeholder */}
    }
  }

  @override
  void dispose() {
    _playGuard?.cancel();
    _ctrl?.dispose();
    super.dispose();
  }

  double get _maxLen => widget.maxSelectionSec ?? _durSec;

  Future<void> _seekTo(double sec) async {
    final ctrl = _ctrl;
    if (ctrl == null || !_ready) return;
    await ctrl.seekTo(Duration(milliseconds: (sec * 1000).round()));
  }

  void _onLeftHandle(double dxSec) {
    setState(() {
      var ns = (_startSec + dxSec).clamp(0.0, _endSec - 1.0);
      // Respect max length.
      if (_endSec - ns > _maxLen) ns = _endSec - _maxLen;
      _startSec = ns;
    });
    _seekTo(_startSec);
  }

  void _onRightHandle(double dxSec) {
    setState(() {
      var ne = (_endSec + dxSec).clamp(_startSec + 1.0, _durSec);
      if (ne - _startSec > _maxLen) ne = _startSec + _maxLen;
      _endSec = ne;
    });
    _seekTo(_endSec);
  }

  Future<void> _togglePlay() async {
    final ctrl = _ctrl;
    if (ctrl == null || !_ready) return;
    if (_playing) {
      await ctrl.pause();
      _playGuard?.cancel();
      if (mounted) setState(() => _playing = false);
      return;
    }
    await _seekTo(_startSec);
    await ctrl.play();
    if (mounted) setState(() => _playing = true);
    // Stop at the out-point.
    _playGuard?.cancel();
    _playGuard = Timer.periodic(const Duration(milliseconds: 120), (_) async {
      if (!mounted) return;
      final pos = ctrl.value.position.inMilliseconds / 1000.0;
      if (pos >= _endSec) {
        await ctrl.pause();
        await _seekTo(_startSec);
        _playGuard?.cancel();
        if (mounted) setState(() => _playing = false);
      }
    });
  }

  Future<void> _confirm() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    HapticFeedback.mediumImpact();
    await _ctrl?.pause();
    _playGuard?.cancel();

    // If the whole video is selected, skip the cut entirely.
    final full = _startSec <= 0.05 && _endSec >= _durSec - 0.05;
    String? outPath;
    if (!full) {
      outPath = await VideoTrimService.trim(
        inputPath: widget.filePath,
        startSec: _startSec,
        endSec: _endSec,
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop(VideoTrimResult(
      startSec: _startSec,
      endSec: _endSec,
      outputPath: outPath,
    ));
  }

  String _fmt(double s) {
    final m = s ~/ 60;
    final sec = (s % 60).floor();
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: !_ready
            ? const Center(child: BrandedLoader(label: 'Готовим видео…'))
            : Column(
                children: [
                  _topBar(),
                  Expanded(child: _preview()),
                  _filmstrip(),
                  _labels(),
                  const SizedBox(height: 16),
                ],
              ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
      child: Row(
        children: [
          SeeUGlassCircleButton(
            icon: const Icon(PhosphorIconsRegular.x,
                color: Colors.white, size: 20),
            size: 40,
            onTap: _exporting ? null : () => Navigator.of(context).pop(),
          ),
          const Spacer(),
          Column(
            children: [
              Text('ОБРЕЗКА',
                  style: SeeUTypography.kicker
                      .copyWith(color: SeeUColors.accent)),
              const SizedBox(height: 2),
              Text('Видео',
                  style: SeeUTypography.displayS
                      .copyWith(color: Colors.white, fontSize: 20)),
            ],
          ),
          const Spacer(),
          _exporting
              ? const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: SeeUColors.accent, strokeWidth: 2),
                  ),
                )
              : GestureDetector(
                  onTap: _confirm,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [SeeUColors.accentSecondary, SeeUColors.accent],
                      ),
                      borderRadius: BorderRadius.circular(SeeURadii.pill),
                    ),
                    child: const Text('Готово',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800)),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _preview() {
    final ctrl = _ctrl!;
    return GestureDetector(
      onTap: _togglePlay,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: ctrl.value.aspectRatio,
              child: VideoPlayer(ctrl),
            ),
          ),
          if (!_playing)
            ClipOval(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.14),
                        Colors.black.withValues(alpha: 0.28),
                      ],
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                      width: 0.8,
                    ),
                  ),
                  child: const Icon(PhosphorIconsFill.play,
                      color: Colors.white, size: 26),
                ),
              ),
            ),
          // #78: in/out timecodes overlaid on the preview.
          Positioned(
            bottom: 12,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(SeeURadii.pill),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(SeeURadii.pill),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    '${_fmt(_startSec)} – ${_fmt(_endSec)}',
                    style: SeeUTypography.mono.copyWith(
                        color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filmstrip() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: SizedBox(
        height: 56,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            double secToX(double s) => _durSec > 0 ? (s / _durSec) * w : 0;
            double dxToSec(double dx) => _durSec > 0 ? (dx / w) * _durSec : 0;
            final selLeft = secToX(_startSec);
            final selRight = secToX(_endSec);

            return Stack(
              clipBehavior: Clip.none,
              children: [
                // Filmstrip frames
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    children: List.generate(_frameCount, (i) {
                      final data = i < _frames.length ? _frames[i] : null;
                      return Expanded(
                        child: data != null
                            ? Image.memory(data, height: 56, fit: BoxFit.cover)
                            // #73: shimmer-ish placeholder while frames extract.
                            : Container(
                                height: 56,
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      SeeUColors.darkSurface,
                                      SeeUColors.darkSurface2,
                                    ],
                                  ),
                                ),
                                child: Center(
                                  child: Icon(PhosphorIconsRegular.filmStrip,
                                      color: Colors.white.withValues(alpha: 0.12),
                                      size: 16),
                                ),
                              ),
                      );
                    }),
                  ),
                ),
                // Dim veils outside selection
                Positioned(
                  left: 0, top: 0, bottom: 0, width: selLeft,
                  child: _veil(),
                ),
                Positioned(
                  left: selRight, right: 0, top: 0, bottom: 0,
                  child: _veil(),
                ),
                // Selection border — #74: fully closed box (all four sides).
                Positioned(
                  left: selLeft,
                  width: (selRight - selLeft).clamp(_handleW * 2, w),
                  top: 0, bottom: 0,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: SeeUColors.accent, width: 2.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                // Left handle
                Positioned(
                  left: selLeft - _handleW / 2,
                  top: 0, bottom: 0, width: _handleW,
                  child: _TrimHandle(
                    left: true,
                    onDrag: (dx) {
                      HapticFeedback.selectionClick();
                      _onLeftHandle(dxToSec(dx));
                    },
                  ),
                ),
                // Right handle
                Positioned(
                  left: selRight - _handleW / 2,
                  top: 0, bottom: 0, width: _handleW,
                  child: _TrimHandle(
                    left: false,
                    onDrag: (dx) {
                      HapticFeedback.selectionClick();
                      _onRightHandle(dxToSec(dx));
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _veil() => IgnorePointer(
        child: Container(color: SeeUColors.softScrim),
      );

  Widget _labels() {
    final len = (_endSec - _startSec).clamp(0.0, _durSec);
    final maxHint = widget.maxSelectionSec != null
        ? ' / макс ${widget.maxSelectionSec!.round()}с'
        : '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(_fmt(_startSec),
              style: SeeUTypography.mono.copyWith(
                  color: SeeUColors.accent, fontWeight: FontWeight.w700)),
          Text('${len.round()} сек$maxHint',
              style: SeeUTypography.mono.copyWith(color: Colors.white54)),
          Text(_fmt(_endSec),
              style: SeeUTypography.mono.copyWith(
                  color: SeeUColors.accent, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _TrimHandle extends StatelessWidget {
  final bool left;
  final ValueChanged<double> onDrag;
  const _TrimHandle({required this.left, required this.onDrag});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
      child: Center(
        child: Container(
          width: 18,
          decoration: BoxDecoration(
            color: SeeUColors.accent,
            borderRadius: BorderRadius.horizontal(
              left: Radius.circular(left ? 8 : 0),
              right: Radius.circular(left ? 0 : 8),
            ),
          ),
          alignment: Alignment.center,
          child: Icon(
            left ? PhosphorIconsBold.caretLeft : PhosphorIconsBold.caretRight,
            color: Colors.white,
            size: 14,
          ),
        ),
      ),
    );
  }
}
