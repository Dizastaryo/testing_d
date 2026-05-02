import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import '../../core/design/tokens.dart';

// ─── Constants ────────────────────────────────────────────────────────────

const double _kMaxDuration = 60.0; // seconds
const Color _kAccent = SeeUColors.accent; // #FF5A3C
const Color _kGlassBg = Color(0x73000000); // rgba(0,0,0,0.45)

// ─── CameraScreen ─────────────────────────────────────────────────────────

class CameraScreen extends StatefulWidget {
  final VoidCallback? onClose;
  final VoidCallback? onNext;
  final VoidCallback? onOpenMusic;

  const CameraScreen({super.key, this.onClose, this.onNext, this.onOpenMusic});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  // ── Camera state ──
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isFrontCamera = true;
  bool _isInitialized = false;
  bool _isSwitching = false;
  String? _errorMessage;

  // ── Zoom ──
  double _currentZoom = 1.0;
  double _baseZoom = 1.0;
  double _maxZoom = 1.0;
  double _minZoom = 1.0;
  bool _showZoomIndicator = false;
  String _zoomLabel = '1.0x';

  // ── Recording state ──
  bool _isRecording = false;
  List<double> _segments = []; // completed segment durations in seconds
  double _currentSegDur = 0.0; // live elapsed seconds for active segment

  // ── Timer state ──
  int _timerSetting = 0; // 0 | 3 | 10
  int _countdown = 0;

  // ── Settings ──
  bool _flashOn = false;
  double _speed = 1.0;
  String _tab = 'reel'; // photo | reel | live | duet

  // ── Fake music track label ──
  final String _audioTitle = 'Любимая музыка';

  // ── Animation controllers ──
  late AnimationController _switchController;
  late Animation<double> _switchRotation;
  late AnimationController _flashPulseController;

  // ── Ticker for segment progress ──
  Ticker? _ticker;
  Duration? _tickerStart;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _switchController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _switchRotation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _switchController, curve: Curves.easeInOutCubic),
    );

    _flashPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _initCamera();
  }

  // ── Camera init ────────────────────────────────────────────────────────

  Future<void> _initCamera() async {
    if (kIsWeb) {
      if (mounted) setState(() => _errorMessage = 'Камера недоступна в браузере');
      return;
    }

    try {
      _cameras = await availableCameras();
    } on CameraException catch (e) {
      final msg = (e.code == 'CameraAccessDenied' ||
              e.code == 'CameraAccessDeniedWithoutPrompt' ||
              e.code == 'CameraAccessRestricted')
          ? 'Нет доступа к камере. Разрешите доступ в настройках.'
          : 'Не удалось получить список камер: ${e.description}';
      if (mounted) setState(() => _errorMessage = msg);
      return;
    } catch (_) {
      if (mounted) setState(() => _errorMessage = 'Ошибка инициализации камеры');
      return;
    }

    if (_cameras.isEmpty) {
      if (mounted) setState(() => _errorMessage = 'Камера недоступна');
      return;
    }

    await _setupCamera(_getFrontCamera() ?? _cameras.first);
  }

  CameraDescription? _getFrontCamera() {
    try {
      return _cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front);
    } catch (_) {
      return null;
    }
  }

  CameraDescription? _getBackCamera() {
    try {
      return _cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back);
    } catch (_) {
      return null;
    }
  }

  Future<void> _setupCamera(CameraDescription camera) async {
    final prev = _controller;
    _controller = null;

    final controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await controller.initialize();
      _maxZoom = await controller.getMaxZoomLevel();
      _minZoom = await controller.getMinZoomLevel();
      _currentZoom = _minZoom;

      if (prev != null && prev.value.isInitialized) {
        await prev.dispose();
      }

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _isInitialized = true;
        _isSwitching = false;
        _errorMessage = null;
      });
    } on CameraException catch (e) {
      await controller.dispose();
      if (mounted) setState(() => _errorMessage = 'Ошибка камеры: ${e.description}');
    } catch (_) {
      await controller.dispose();
      if (mounted) setState(() => _errorMessage = 'Ошибка инициализации камеры');
    } finally {
      if (mounted && _isSwitching) {
        setState(() => _isSwitching = false);
      } else {
        _isSwitching = false;
      }
    }
  }

  Future<void> _switchCamera() async {
    if (_isSwitching || _cameras.length < 2) return;
    HapticFeedback.lightImpact();
    setState(() => _isSwitching = true);
    _switchController.forward(from: 0);
    _isFrontCamera = !_isFrontCamera;
    final camera = _isFrontCamera
        ? (_getFrontCamera() ?? _cameras.first)
        : (_getBackCamera() ?? _cameras.last);
    await _setupCamera(camera);
  }

  // ── Flash ──────────────────────────────────────────────────────────────

  Future<void> _toggleFlash() async {
    if (_controller == null || !_isInitialized) return;
    HapticFeedback.selectionClick();
    _flashPulseController.forward(from: 0);
    final next = !_flashOn;
    try {
      await _controller!.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      setState(() => _flashOn = next);
    } catch (_) {}
  }

  // ── Recording ──────────────────────────────────────────────────────────

  double get _totalCompleted => _segments.fold(0.0, (a, b) => a + b);
  double get _totalWithCurrent => _totalCompleted + _currentSegDur;
  double get _totalPct => (_totalWithCurrent / _kMaxDuration).clamp(0.0, 1.0);

  void _startRecording() {
    if (_timerSetting > 0) {
      _startCountdown();
    } else {
      _beginSegment();
    }
  }

  void _startCountdown() {
    setState(() => _countdown = _timerSetting);
    _runCountdown(_timerSetting);
  }

  void _runCountdown(int n) {
    if (!mounted) return;
    if (n <= 0) {
      setState(() => _countdown = 0);
      _beginSegment();
      return;
    }
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() => _countdown = n - 1);
      _runCountdown(n - 1);
    });
  }

  void _beginSegment() {
    if (_controller == null || !_isInitialized) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _isRecording = true;
      _currentSegDur = 0.0;
    });

    _ticker?.dispose();
    _tickerStart = null;
    _ticker = createTicker((elapsed) {
      if (!mounted) return;
      _tickerStart ??= elapsed;
      final secs = (elapsed - _tickerStart!).inMilliseconds / 1000.0 * _speed;
      final clamped = secs.clamp(0.0, _kMaxDuration - _totalCompleted);
      setState(() => _currentSegDur = clamped);
      if (_totalCompleted + clamped >= _kMaxDuration) {
        _stopRecording();
      }
    })
      ..start();

    // Also start actual video recording on controller (best-effort)
    unawaited(_controller!.startVideoRecording());
  }

  void _stopRecording() {
    if (!_isRecording) return;
    HapticFeedback.mediumImpact();
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;

    final dur = _currentSegDur;
    setState(() {
      _isRecording = false;
      if (dur > 0.1) _segments = [..._segments, dur];
      _currentSegDur = 0.0;
    });

    unawaited(_controller?.stopVideoRecording());
  }

  void _toggleRecord() {
    if (_isRecording) {
      _stopRecording();
    } else {
      _startRecording();
    }
  }

  void _undoLastSegment() {
    if (_isRecording) _stopRecording();
    if (_segments.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _segments = _segments.sublist(0, _segments.length - 1));
  }

  // ── Photo capture ──────────────────────────────────────────────────────

  Future<void> _takePicture() async {
    if (_controller == null || !_isInitialized) return;
    if (_controller!.value.isTakingPicture) return;
    HapticFeedback.mediumImpact();
    try {
      final file = await _controller!.takePicture();
      debugPrint('Photo saved: ${file.path}');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось сделать фото. Попробуйте ещё раз.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // ── Zoom ──────────────────────────────────────────────────────────────

  void _onScaleStart(ScaleStartDetails d) => _baseZoom = _currentZoom;

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_controller == null) return;
    final newZoom = (_baseZoom * d.scale).clamp(_minZoom, _maxZoom);
    _currentZoom = newZoom;
    _controller!.setZoomLevel(newZoom);
    final label = '${newZoom.toStringAsFixed(1)}x';
    final shouldShow = newZoom > _minZoom;
    if (_showZoomIndicator != shouldShow || _zoomLabel != label) {
      setState(() {
        _showZoomIndicator = shouldShow;
        _zoomLabel = label;
      });
    }
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      if (_isRecording) _stopRecording();
      final ctrl = _controller;
      if (ctrl != null && ctrl.value.isInitialized) {
        _controller = null;
        ctrl.dispose();
      }
      if (mounted) setState(() => _isInitialized = false);
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.dispose();
    _controller?.dispose();
    _switchController.dispose();
    _flashPulseController.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Camera preview ──
          if (_errorMessage != null)
            _buildErrorState(_errorMessage!)
          else if (_isInitialized && _controller != null)
            GestureDetector(
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              child: _buildCameraPreview(),
            )
          else
            const Center(
              child: CircularProgressIndicator(color: Colors.white24, strokeWidth: 2),
            ),

          // ── Gradient overlay ──
          _buildGradientOverlay(),

          // ── Top area: segment bar + close/music/flip row ──
          _buildTopArea(),

          // ── Right tools ──
          _buildRightTools(),

          // ── Left speed pills (reel mode) ──
          if (_tab == 'reel') _buildSpeedPills(),

          // ── Record button row ──
          _buildRecordRow(),

          // ── Mode tabs ──
          _buildModeTabs(),

          // ── "Далее" button ──
          if (_segments.isNotEmpty && !_isRecording)
            _buildNextButton(),

          // ── Zoom indicator ──
          _buildZoomIndicator(),

          // ── Camera switching overlay ──
          if (_isSwitching)
            AnimatedBuilder(
              animation: _switchController,
              builder: (_, __) => Container(
                color: Colors.black
                    .withValues(alpha: 0.3 * (1 - _switchController.value)),
              ),
            ),

          // ── Countdown overlay ──
          if (_countdown > 0) _buildCountdownOverlay(),
        ],
      ),
    );
  }

  // ── Error state ────────────────────────────────────────────────────────

  Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.camera_alt_outlined, color: Colors.white54, size: 56),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 15),
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () {
                setState(() {
                  _errorMessage = null;
                  _isInitialized = false;
                });
                _initCamera();
              },
              style: TextButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.15),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(SeeURadii.pill)),
              ),
              child: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Camera preview ─────────────────────────────────────────────────────

  Widget _buildCameraPreview() {
    final controller = _controller!;
    final size = MediaQuery.of(context).size;
    final previewAspect = controller.value.aspectRatio;
    final deviceAspect = size.width / size.height;
    final scale = deviceAspect / previewAspect;

    return Transform.scale(
      scale: scale < 1.0 ? 1.0 / scale : scale,
      child: Center(child: CameraPreview(controller)),
    );
  }

  // ── Gradient overlay ───────────────────────────────────────────────────

  Widget _buildGradientOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.0, 0.30, 0.60, 1.0],
              colors: [
                Color(0x80000000),
                Color(0x00000000),
                Color(0x00000000),
                Color(0xB3000000),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Top area ───────────────────────────────────────────────────────────

  Widget _buildTopArea() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSegmentBar(),
              const SizedBox(height: 12),
              _buildTopRow(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Segment progress bar ───────────────────────────────────────────────

  Widget _buildSegmentBar() {
    return SizedBox(
      height: 4,
      child: CustomPaint(
        painter: _SegmentBarPainter(
          segments: _segments,
          currentSegDur: _currentSegDur,
          maxDuration: _kMaxDuration,
          isRecording: _isRecording,
          accentColor: _kAccent,
        ),
      ),
    );
  }

  // ── Top row: close | music | flip ─────────────────────────────────────

  Widget _buildTopRow() {
    return Row(
      children: [
        // Close
        _GlassButton(
          onTap: widget.onClose ?? () => Navigator.maybePop(context),
          child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
        ),

        const Spacer(),

        // Audio strip
        GestureDetector(
          onTap: widget.onOpenMusic ?? () {},
          child: Container(
            constraints: const BoxConstraints(maxWidth: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _kGlassBg,
              borderRadius: BorderRadius.circular(SeeURadii.pill),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.music_note_rounded, color: Colors.white, size: 14),
                const SizedBox(width: 6),
                _WaveformWidget(),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _audioTitle,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const Spacer(),

        // Flip camera
        AnimatedBuilder(
          animation: _switchRotation,
          builder: (_, child) => Transform.rotate(
            angle: _switchRotation.value * math.pi,
            child: child,
          ),
          child: _GlassButton(
            onTap: _switchCamera,
            child: const Icon(Icons.cameraswitch_rounded, color: Colors.white, size: 20),
          ),
        ),
      ],
    );
  }

  // ── Right tools ────────────────────────────────────────────────────────

  Widget _buildRightTools() {
    final timerLabel = _timerSetting == 0
        ? 'таймер'
        : '$_timerSetting\u0441';

    return Positioned(
      right: 12,
      top: 110,
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Flash
            AnimatedBuilder(
              animation: _flashPulseController,
              builder: (_, child) {
                final scale = 1.0 +
                    0.15 * Curves.easeOut.transform(_flashPulseController.value);
                return Transform.scale(scale: scale, child: child);
              },
              child: _ToolButton(
                icon: Icon(
                  _flashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                  color: _flashOn ? SeeUColors.textPrimary : Colors.white,
                  size: 20,
                ),
                label: _flashOn ? 'вкл' : 'выкл',
                active: _flashOn,
                onTap: _isFrontCamera ? null : _toggleFlash,
              ),
            ),
            const SizedBox(height: 12),
            // Timer
            _ToolButton(
              icon: Icon(Icons.timer_rounded,
                  color: _timerSetting > 0 ? SeeUColors.textPrimary : Colors.white,
                  size: 20),
              label: timerLabel,
              active: _timerSetting > 0,
              onTap: () {
                setState(() {
                  _timerSetting = _timerSetting == 0
                      ? 3
                      : _timerSetting == 3
                          ? 10
                          : 0;
                });
              },
            ),
            const SizedBox(height: 12),
            // Effects
            _ToolButton(
              icon: const Icon(Icons.auto_fix_high_rounded,
                  color: Colors.white, size: 20),
              label: 'эффекты',
              onTap: () {},
            ),
            const SizedBox(height: 12),
            // Filter
            _ToolButton(
              icon: const Icon(Icons.filter_rounded, color: Colors.white, size: 20),
              label: 'фильтр',
              onTap: () {},
            ),
            const SizedBox(height: 12),
            // Grid
            _ToolButton(
              icon: const Icon(Icons.grid_on_rounded, color: Colors.white, size: 20),
              label: 'сетка',
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }

  // ── Speed pills ────────────────────────────────────────────────────────

  Widget _buildSpeedPills() {
    const speeds = [0.3, 0.5, 1.0, 2.0, 3.0];
    return Positioned(
      left: 14,
      top: 110,
      child: SafeArea(
        bottom: false,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: _kGlassBg,
            borderRadius: BorderRadius.circular(SeeURadii.pill),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: speeds.map((s) {
              final selected = _speed == s;
              final label = s == s.truncateToDouble()
                  ? '${s.toInt()}x'
                  : '${s}x';
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _speed = s);
                },
                child: Container(
                  width: 38,
                  height: 32,
                  margin: const EdgeInsets.symmetric(vertical: 1),
                  decoration: BoxDecoration(
                    color: selected ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(SeeURadii.pill),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected ? SeeUColors.textPrimary : Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  // ── Record button row ──────────────────────────────────────────────────

  Widget _buildRecordRow() {
    final hasSegments = _segments.isNotEmpty;

    return Positioned(
      bottom: 130,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Gallery button
          GestureDetector(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Галерея — скоро'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(SeeURadii.small),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.15),
                  width: 1,
                ),
              ),
              alignment: Alignment.center,
              child: const Text(
                'Галерея',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),

          const SizedBox(width: 32),

          // Big record button
          _RecordButton(
            isRecording: _isRecording,
            totalPct: _totalPct,
            isPhotoMode: _tab == 'photo',
            onPress: _tab == 'photo' ? _takePicture : _toggleRecord,
          ),

          const SizedBox(width: 32),

          // Undo button
          GestureDetector(
            onTap: hasSegments || _isRecording ? _undoLastSegment : null,
            child: AnimatedOpacity(
              opacity: hasSegments || _isRecording ? 1.0 : 0.3,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                    width: 1,
                  ),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.undo_rounded, color: Colors.white, size: 22),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Mode tabs ──────────────────────────────────────────────────────────

  Widget _buildModeTabs() {
    const tabs = [
      ('photo', 'Фото'),
      ('reel', 'Reel'),
      ('live', 'LIVE'),
      ('duet', 'Дуэт'),
    ];

    return Positioned(
      bottom: 78,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: tabs.map((entry) {
          final (key, label) = entry;
          final selected = _tab == key;
          return GestureDetector(
            onTap: () {
              if (_isRecording) _stopRecording();
              setState(() => _tab = key);
            },
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.white.withValues(alpha: 0.55),
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  AnimatedOpacity(
                    opacity: selected ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 150),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: _kAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── "Далее" button ─────────────────────────────────────────────────────

  Widget _buildNextButton() {
    return Positioned(
      right: 14,
      bottom: 200,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.mediumImpact();
          widget.onNext?.call();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [SeeUColors.accentSecondary, SeeUColors.accent],
            ),
            borderRadius: BorderRadius.circular(SeeURadii.pill),
            boxShadow: [
              BoxShadow(
                color: _kAccent.withValues(alpha: 0.45),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Далее',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, color: Colors.white, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ── Zoom indicator ─────────────────────────────────────────────────────

  Widget _buildZoomIndicator() {
    return Positioned(
      bottom: 160,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedOpacity(
          opacity: _showZoomIndicator ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              _zoomLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Countdown overlay ──────────────────────────────────────────────────

  Widget _buildCountdownOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.3),
          child: Center(
            child: _CountdownNumber(value: _countdown),
          ),
        ),
      ),
    );
  }
}

// ─── Segment bar painter ───────────────────────────────────────────────────

class _SegmentBarPainter extends CustomPainter {
  final List<double> segments;
  final double currentSegDur;
  final double maxDuration;
  final bool isRecording;
  final Color accentColor;

  const _SegmentBarPainter({
    required this.segments,
    required this.currentSegDur,
    required this.maxDuration,
    required this.isRecording,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(3),
    );
    canvas.drawRRect(rrect, trackPaint);

    double offsetX = 0;
    const gap = 2.0;

    // Draw completed (white) segments
    final whitePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    for (int i = 0; i < segments.length; i++) {
      final w = (segments[i] / maxDuration) * size.width;
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(offsetX, 0, w - gap, size.height),
        const Radius.circular(2),
      );
      canvas.drawRRect(r, whitePaint);
      offsetX += w;
    }

    // Draw current (red) segment
    if (isRecording && currentSegDur > 0) {
      final w = (currentSegDur / maxDuration) * size.width;
      final redPaint = Paint()
        ..color = accentColor
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      final redPaintSolid = Paint()
        ..color = accentColor
        ..style = PaintingStyle.fill;

      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(offsetX, 0, w, size.height),
        const Radius.circular(2),
      );
      canvas.drawRRect(r, redPaint);
      canvas.drawRRect(r, redPaintSolid);
    }
  }

  @override
  bool shouldRepaint(_SegmentBarPainter old) =>
      old.segments != segments ||
      old.currentSegDur != currentSegDur ||
      old.isRecording != isRecording;
}

// ─── Record button ─────────────────────────────────────────────────────────

class _RecordButton extends StatefulWidget {
  final bool isRecording;
  final double totalPct; // 0.0 – 1.0
  final bool isPhotoMode;
  final VoidCallback onPress;

  const _RecordButton({
    required this.isRecording,
    required this.totalPct,
    required this.isPhotoMode,
    required this.onPress,
  });

  @override
  State<_RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<_RecordButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    if (widget.isRecording) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_RecordButton old) {
    super.didUpdateWidget(old);
    if (widget.isRecording && !old.isRecording) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isRecording && old.isRecording) {
      _pulseController.stop();
      _pulseController.animateTo(0);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double btnSize = 96;
    const double whiteRingSize = 78;
    const double innerPhotoSize = 64;
    const double innerRecordSize = 30;

    final isRecording = widget.isRecording && !widget.isPhotoMode;
    final innerSize = isRecording ? innerRecordSize : innerPhotoSize;
    final innerRadius = isRecording ? 8.0 : innerPhotoSize / 2;

    return GestureDetector(
      onTap: widget.onPress,
      child: SizedBox(
        width: btnSize,
        height: btnSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Outer pulsing glow ring when recording
            if (isRecording)
              AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, __) => Transform.scale(
                  scale: _pulseAnim.value,
                  child: Container(
                    width: btnSize,
                    height: btnSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFFFF8060).withValues(alpha: 0.30),
                          const Color(0xFFFF5A3C).withValues(alpha: 0.12),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.6, 1.0],
                      ),
                    ),
                  ),
                ),
              ),

            // Progress ring + tick marks via CustomPaint
            CustomPaint(
              size: const Size(btnSize, btnSize),
              painter: _RingPainterV3(
                totalPct: widget.isPhotoMode ? 0.0 : widget.totalPct,
                ringRadius: 46.0,
                isRecording: isRecording,
              ),
            ),

            // White border ring (3px, 78x78)
            Container(
              width: whiteRingSize,
              height: whiteRingSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
              ),
            ),

            // Inner gradient shape — morphs circle ↔ rounded-square
            AnimatedContainer(
              duration: const Duration(milliseconds: 320),
              curve: const Cubic(0.34, 1.56, 0.64, 1.0), // spring-like
              width: innerSize,
              height: innerSize,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFFF8060),
                    Color(0xFFFF5A3C),
                    Color(0xFFFF3B6B),
                  ],
                ),
                borderRadius: BorderRadius.circular(innerRadius),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF5A3C).withValues(alpha: 0.55),
                    blurRadius: 22,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Align(
                alignment: const Alignment(-0.3, -0.55),
                child: Container(
                  width: innerSize * 0.38,
                  height: innerSize * 0.14,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainterV3 extends CustomPainter {
  final double totalPct;
  final double ringRadius;
  final bool isRecording;

  const _RingPainterV3({
    required this.totalPct,
    required this.ringRadius,
    required this.isRecording,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Track ring (faint white)
    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, ringRadius, trackPaint);

    // 60 tick marks around the ring
    const int tickCount = 60;
    for (int i = 0; i < tickCount; i++) {
      final angle = (i / tickCount) * 2 * math.pi - math.pi / 2;
      final isMajor = i % 5 == 0;
      final tickLen = isMajor ? 6.0 : 3.5;
      final tickWidth = isMajor ? 1.8 : 1.0;
      final tickOpacity = isMajor ? 0.55 : 0.28;

      final outerR = ringRadius + 6;
      final innerR = outerR - tickLen;
      final cosA = math.cos(angle);
      final sinA = math.sin(angle);

      final tickPaint = Paint()
        ..color = Colors.white.withValues(alpha: tickOpacity)
        ..strokeWidth = tickWidth
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      canvas.drawLine(
        Offset(center.dx + innerR * cosA, center.dy + innerR * sinA),
        Offset(center.dx + outerR * cosA, center.dy + outerR * sinA),
        tickPaint,
      );
    }

    if (totalPct <= 0) return;

    // Gradient progress arc
    const startAngle = -math.pi / 2;
    final sweepAngle = 2 * math.pi * totalPct;
    final rect = Rect.fromCircle(center: center, radius: ringRadius);

    final gradientColors = const [
      Color(0xFFFFB547), // amber
      Color(0xFFFF5A3C), // coral
      Color(0xFFFF3B6B), // rose
    ];
    final sweepGradient = SweepGradient(
      startAngle: startAngle,
      endAngle: startAngle + sweepAngle,
      colors: gradientColors,
      tileMode: TileMode.clamp,
    );

    final progressPaint = Paint()
      ..shader = sweepGradient.createShader(rect)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Glow pass
    final glowPaint = Paint()
      ..shader = sweepGradient.createShader(rect)
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    canvas.drawArc(rect, startAngle, sweepAngle, false, glowPaint);
    canvas.drawArc(rect, startAngle, sweepAngle, false, progressPaint);
  }

  @override
  bool shouldRepaint(_RingPainterV3 old) =>
      old.totalPct != totalPct || old.isRecording != isRecording;
}

// ─── Countdown number ──────────────────────────────────────────────────────

class _CountdownNumber extends StatefulWidget {
  final int value;
  const _CountdownNumber({required this.value});

  @override
  State<_CountdownNumber> createState() => _CountdownNumberState();
}

class _CountdownNumberState extends State<_CountdownNumber>
    with SingleTickerProviderStateMixin {
  late AnimationController _ac;
  late Animation<double> _scale;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _scale = Tween<double>(begin: 0.6, end: 1.0)
        .animate(CurvedAnimation(parent: _ac, curve: Curves.easeOut));
    _opacity = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _ac, curve: Curves.easeOut));
    _ac.forward();
  }

  @override
  void didUpdateWidget(_CountdownNumber old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _ac.forward(from: 0);
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ac,
      builder: (_, __) => Opacity(
        opacity: _opacity.value,
        child: Transform.scale(
          scale: _scale.value,
          child: Text(
            '${widget.value}',
            style: const TextStyle(
              fontFamily: 'Georgia',
              fontSize: 140,
              color: Colors.white,
              fontWeight: FontWeight.w400,
              shadows: [
                Shadow(
                  color: Color(0x80000000),
                  blurRadius: 32,
                  offset: Offset(0, 8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Waveform widget ───────────────────────────────────────────────────────

class _WaveformWidget extends StatefulWidget {
  @override
  State<_WaveformWidget> createState() => _WaveformWidgetState();
}

class _WaveformWidgetState extends State<_WaveformWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ac;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ac,
      builder: (_, __) {
        final t = _ac.value;
        final heights = [
          4.0 + 6.0 * math.sin(t * math.pi),
          4.0 + 6.0 * math.sin(t * math.pi + 1.2),
          4.0 + 6.0 * math.sin(t * math.pi + 2.4),
        ];
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(3, (i) {
            return Container(
              width: 2,
              height: heights[i],
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(1),
              ),
            );
          }),
        );
      },
    );
  }
}

// ─── Tool button ───────────────────────────────────────────────────────────

class _ToolButton extends StatelessWidget {
  final Widget icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    this.active = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: active ? Colors.white : const Color(0x66000000),
              borderRadius: BorderRadius.circular(SeeURadii.small),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 1,
              ),
            ),
            child: Center(child: icon),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              shadows: [
                Shadow(
                  color: Color(0x99000000),
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Glass button ──────────────────────────────────────────────────────────

class _GlassButton extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;

  const _GlassButton({
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.2),
            width: 0.5,
          ),
        ),
        child: Center(child: child),
      ),
    );
  }
}
