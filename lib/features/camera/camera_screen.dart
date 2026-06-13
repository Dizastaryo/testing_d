import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/tokens.dart';
import '../post/media_prepare_screen.dart';
import '../post/widgets/music_picker_sheet.dart';
import '../stories/story_editor_screen.dart';
import 'decorations/decoration_item.dart';
import 'filters/filter_overlay.dart';
import 'filters/frame_effect.dart';
import 'filters/overlay_effect.dart';
import 'presets/camera_preset.dart';
import 'presets/camera_presets_catalog.dart';
import 'masks/face_tracking_service.dart';
import 'masks/mask_catalog.dart';
import 'masks/mask_overlay.dart';
import 'widgets/camera_bottom_panel.dart';
import 'widgets/camera_gallery_preview.dart';
import 'widgets/camera_painters.dart';
import 'widgets/camera_record_button.dart';
import 'widgets/camera_right_panel.dart';
import 'widgets/camera_top_bar.dart';

// ─── Re-export CameraMode ────────────────────────────────────────────────────
export 'widgets/camera_bottom_panel.dart' show CameraMode;

// ─── Constants ────────────────────────────────────────────────────────────

const double _kMaxDuration = 60.0;
const Color _kAccent = SeeUColors.accent;

// ─── CameraScreen ─────────────────────────────────────────────────────────

class CameraScreen extends ConsumerStatefulWidget {
  final VoidCallback? onClose;
  final VoidCallback? onNext;
  final VoidCallback? onOpenMusic;

  const CameraScreen({super.key, this.onClose, this.onNext, this.onOpenMusic});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen>
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
  List<double> _segments = [];
  MaskDescriptor? _selectedMask;

  // ── Active preset ──
  CameraPreset _activePreset = CameraPresetsCollection.none;
  bool _showPresetPicker = false;
  Uint8List? _presetSnapshotBytes;

  // ── Decorations (masks only) ──
  bool _showDecorationPicker = false;
  String? _selectedDecorationId;
  Set<String> _savedDecorationIds = {};
  double _currentSegDur = 0.0;

  // ── Timer ──
  int _timerSetting = 0;
  int _countdown = 0;

  // ── Settings ──
  int _flashMode = 0; // 0=off, 1=torch, 2=auto
  bool _showGrid = false;

  // ── Camera mode ──
  CameraMode _cameraMode = CameraMode.photo;

  // ── Music ──
  AudioTrack? _selectedTrack;

  // ── Video speed ──
  static const List<double> _speedValues = [0.5, 1.0, 2.0, 3.0];
  int _speedIdx = 1;
  double get _videoSpeed => _speedValues[_speedIdx];

  // ── Beauty toggle (front camera, UI only) ──
  bool _beautyOn = false;

  // ── Gallery preview ──
  XFile? _galleryFile;
  Uint8List? _galleryBytes;
  bool _showGalleryPreview = false;
  late AnimationController _galleryPreviewController;
  late Animation<Offset> _gallerySlideAnim;
  late Animation<double> _galleryFadeAnim;
  Uint8List? _galleryThumbnailBytes;

  // ── Zoom auto-hide ──
  Timer? _zoomHideTimer;

  // ── Upload state (legacy, unused) ──
  bool _isUploading = false;

  // ── Animation controllers ──
  late AnimationController _switchController;
  late Animation<double> _switchRotation;
  late AnimationController _flashPulseController;
  late AnimationController _nextFabController;
  late AnimationController _segmentFlashCtrl;
  late AnimationController _blinkCtrl;

  // ── Ticker for segment progress ──
  Ticker? _ticker;
  Duration? _tickerStart;

  double get _effectiveMaxDuration =>
      _cameraMode.maxSeconds > 0 ? _cameraMode.maxSeconds : _kMaxDuration;

  // ─── Init ───────────────────────────────────────────────────────────────

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
    _nextFabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _segmentFlashCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _galleryPreviewController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _gallerySlideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _galleryPreviewController,
      curve: Curves.easeOutCubic,
    ));
    _galleryFadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _galleryPreviewController, curve: Curves.easeOut),
    );
    _blinkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      value: 1.0,
    );

    _initCamera();
  }

  // ─── Camera init ────────────────────────────────────────────────────────

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
    } catch (_) { return null; }
  }

  CameraDescription? _getBackCamera() {
    try {
      return _cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back);
    } catch (_) { return null; }
  }

  Future<void> _setupCamera(CameraDescription camera) async {
    final prev = _controller;
    _controller = null;
    if (mounted) setState(() => _isInitialized = false);

    if (prev != null) {
      try { await prev.dispose(); } catch (e) {
        debugPrint('_setupCamera: error disposing previous controller: $e');
      }
    }

    final controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await controller.initialize();
      final ps = controller.value.previewSize;
      debugPrint('_setupCamera: initialized ${camera.lensDirection.name} '
          'previewSize=$ps aspectRatio=${controller.value.aspectRatio}');

      _maxZoom = await controller.getMaxZoomLevel();
      _minZoom = await controller.getMinZoomLevel();
      _currentZoom = _minZoom;

      if (!mounted) { await controller.dispose(); return; }

      setState(() {
        _controller = controller;
        _isInitialized = true;
        _isSwitching = false;
        _errorMessage = null;
      });

      if (_flashMode > 0 && !_isFrontCamera) {
        final fm = const [FlashMode.off, FlashMode.torch, FlashMode.auto][_flashMode];
        try { await controller.setFlashMode(fm); } catch (_) {}
      }
    } on CameraException catch (e) {
      debugPrint('_setupCamera: CameraException: ${e.code} — ${e.description}');
      await controller.dispose();
      if (mounted) {
        setState(() { _errorMessage = 'Ошибка камеры: ${e.description}'; _isSwitching = false; });
      } else { _isSwitching = false; }
    } catch (e) {
      debugPrint('_setupCamera: unexpected error: $e');
      await controller.dispose();
      if (mounted) {
        setState(() { _errorMessage = 'Ошибка инициализации камеры'; _isSwitching = false; });
      } else { _isSwitching = false; }
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

  // ─── Flash ──────────────────────────────────────────────────────────────

  Future<void> _toggleFlash() async {
    if (_controller == null || !_isInitialized) return;
    HapticFeedback.selectionClick();
    _flashPulseController.forward(from: 0);
    final next = (_flashMode + 1) % 3;
    final cameraFlash = const [FlashMode.off, FlashMode.torch, FlashMode.auto][next];
    try {
      await _controller!.setFlashMode(cameraFlash);
      setState(() => _flashMode = next);
    } catch (_) {}
  }

  // ─── Recording ──────────────────────────────────────────────────────────

  double get _totalCompleted => _segments.fold(0.0, (a, b) => a + b);
  double get _totalWithCurrent => _totalCompleted + _currentSegDur;
  double get _totalPct => (_totalWithCurrent / _effectiveMaxDuration).clamp(0.0, 1.0);

  void _startRecording() {
    if (_isRecording || _countdown > 0) return;
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
    if (_isRecording) return;
    if (_controller == null || !_isInitialized) return;
    HapticFeedback.mediumImpact();
    setState(() { _isRecording = true; _currentSegDur = 0.0; });
    _nextFabController.reverse();

    _ticker?.dispose();
    _tickerStart = null;
    _ticker = createTicker((elapsed) {
      if (!mounted) return;
      _tickerStart ??= elapsed;
      final secs = (elapsed - _tickerStart!).inMilliseconds / 1000.0;
      final clamped = secs.clamp(0.0, _effectiveMaxDuration - _totalCompleted);
      setState(() => _currentSegDur = clamped);
      if (_totalCompleted + clamped >= _effectiveMaxDuration) _stopRecording();
    })..start();

    unawaited(_controller!.startVideoRecording());
  }

  Future<void> _stopRecording() async {
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

    if (_segments.isNotEmpty) {
      _nextFabController.forward();
      _segmentFlashCtrl.forward(from: 0);
    }

    final videoFile = await _controller?.stopVideoRecording();
    if (videoFile != null && mounted) await _setGallery(videoFile);
  }

  bool _isVideoPath(String path) {
    final ext = path.split('.').last.toLowerCase();
    return ['mp4', 'mov', 'webm', 'avi', 'mkv'].contains(ext);
  }

  Future<void> _setGallery(XFile file) async {
    Uint8List? bytes;
    try { bytes = await file.readAsBytes(); } catch (e) {
      debugPrint('camera readAsBytes: $e');
    }
    if (!mounted) return;

    Uint8List? thumb;
    if (_isVideoPath(file.path)) {
      if (!kIsWeb) {
        try {
          thumb = await vt.VideoThumbnail.thumbnailData(
            video: file.path,
            imageFormat: vt.ImageFormat.JPEG,
            maxWidth: 112,
            quality: 75,
          );
        } catch (e) { debugPrint('video_thumbnail: $e'); }
      }
    } else {
      thumb = bytes;
    }

    if (!mounted) return;
    setState(() {
      _galleryFile = file;
      _galleryBytes = bytes;
      _showGalleryPreview = true;
      if (thumb != null) _galleryThumbnailBytes = thumb;
    });
    _galleryPreviewController.forward(from: 0);
  }

  void _closeGalleryPreview() {
    _galleryPreviewController.reverse().then((_) {
      if (!mounted) return;
      setState(() {
        _showGalleryPreview = false;
        _galleryFile = null;
        _galleryBytes = null;
        _nextFabController.reverse();
      });
    });
  }

  Future<void> _undoLastSegment() async {
    if (_isRecording) await _stopRecording();
    if (!mounted) return;
    if (_segments.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _segments = _segments.sublist(0, _segments.length - 1);
      _showGalleryPreview = false;
      _galleryFile = null;
      _galleryBytes = null;
    });
    if (_segments.isEmpty) _nextFabController.reverse();
  }

  // ─── Photo capture ──────────────────────────────────────────────────────

  Future<void> _takePicture() async {
    if (_controller == null || !_isInitialized) return;
    if (_controller!.value.isTakingPicture) return;
    HapticFeedback.mediumImpact();
    try {
      final file = await _controller!.takePicture();
      final composed = await _composeCapture(file);
      if (mounted) await _setGallery(composed);
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

  Future<XFile> _composeCapture(XFile raw) async {
    if (_activePreset.isNone && _selectedMask == null) { return raw; }
    if (kIsWeb) { return raw; }

    final filter = _activePreset.filter;
    final bytes = await raw.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final w = image.width.toDouble();
    final h = image.height.toDouble();
    final size = Size(w, h);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    if (filter.isIdentity) {
      canvas.drawImage(image, Offset.zero, Paint());
    } else {
      canvas.saveLayer(Rect.fromLTWH(0, 0, w, h),
          Paint()..colorFilter = ColorFilter.matrix(filter.toMatrix()));
      canvas.drawImage(image, Offset.zero, Paint());
      canvas.restore();
    }

    if (filter.vignette > 0) {
      final rect = Rect.fromLTWH(0, 0, w, h);
      canvas.drawRect(rect, Paint()
        ..shader = RadialGradient(
          radius: 0.9,
          colors: [
            Colors.black.withValues(alpha: 0),
            Colors.black.withValues(alpha: filter.vignette * 0.75),
          ],
          stops: const [0.55, 1.0],
        ).createShader(rect));
    }

    if (_activePreset.hasGrain) bakeGrain(canvas, size, _activePreset.grainAmount);
    if (_activePreset.hasHalation) bakeHalation(canvas, size, _activePreset.halationAmount);

    _activePreset.overlay?.bake(canvas, size);
    _activePreset.frame?.bake(canvas, size);
    // Lottie masks are live animations and cannot be baked into a still photo.
    if (_selectedMask?.painter != null) {
      _selectedMask!.painter!().paint(canvas, size);
    }

    final picture = recorder.endRecording();
    final composedImg = await picture.toImage(w.toInt(), h.toInt());
    final pngBytes = await composedImg.toByteData(format: ui.ImageByteFormat.png);
    if (pngBytes == null) return raw;

    final outPath = '${raw.path.replaceAll(RegExp(r'\.[^.]+$'), '')}_composed.png';
    await File(outPath).writeAsBytes(pngBytes.buffer.asUint8List());
    return XFile(outPath);
  }

  // ─── Gallery picker ─────────────────────────────────────────────────────

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final file = await picker.pickMedia();
    if (file == null || !mounted) return;
    await _setGallery(file);
  }

  // ─── Music picker ───────────────────────────────────────────────────────

  void _openMusicPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MusicPickerSheet(
        onSelect: (track) {
          setState(() => _selectedTrack = track);
          Navigator.of(context).pop();
          HapticFeedback.lightImpact();
        },
      ),
    );
  }

  // ─── Zoom ──────────────────────────────────────────────────────────────

  void _onScaleStart(ScaleStartDetails d) => _baseZoom = _currentZoom;

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_controller == null) return;
    final newZoom = (_baseZoom * d.scale).clamp(_minZoom, _maxZoom);
    _currentZoom = newZoom;
    _controller!.setZoomLevel(newZoom);
    final label = '${newZoom.toStringAsFixed(1)}x';
    final shouldShow = newZoom > _minZoom;
    if (_showZoomIndicator != shouldShow || _zoomLabel != label) {
      setState(() { _showZoomIndicator = shouldShow; _zoomLabel = label; });
    }
    _zoomHideTimer?.cancel();
    if (shouldShow) {
      _zoomHideTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _showZoomIndicator = false);
      });
    }
  }

  // ─── Lifecycle ──────────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      if (_isRecording) _stopRecording();
      final ctrl = _controller;
      _controller = null;
      if (mounted) setState(() => _isInitialized = false);
      ctrl?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _reinitActiveCamera();
    }
  }

  Future<void> _reinitActiveCamera() async {
    if (kIsWeb) return;
    if (_cameras.isEmpty) { await _initCamera(); return; }
    final camera = _isFrontCamera
        ? (_getFrontCamera() ?? _cameras.first)
        : (_getBackCamera() ?? _cameras.last);
    await _setupCamera(camera);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _zoomHideTimer?.cancel();
    _ticker?.dispose();
    unawaited(FaceTrackingService.instance.stop());
    _controller?.dispose();
    _switchController.dispose();
    _flashPulseController.dispose();
    _nextFabController.dispose();
    _segmentFlashCtrl.dispose();
    _galleryPreviewController.dispose();
    _blinkCtrl.dispose();
    super.dispose();
  }

  void _syncFaceTracking() {
    if (_selectedMask != null && _isInitialized && _controller != null) {
      unawaited(FaceTrackingService.instance.start(_controller!));
    } else if (_selectedMask == null && FaceTrackingService.instance.isRunning) {
      unawaited(FaceTrackingService.instance.stop());
    }
  }

  void _applyDecoration(DecorationItem? item) {
    setState(() {
      _selectedDecorationId = item?.id;
      _selectedMask = item?.mask;
    });
    _blinkCtrl.forward(from: 0.0);
    _syncFaceTracking();
  }

  void _applyPreset(CameraPreset preset) {
    setState(() => _activePreset = preset);
    _blinkCtrl.forward(from: 0.0);
  }

  void _togglePresetPicker() {
    setState(() {
      _showPresetPicker = !_showPresetPicker;
      // Presets and mask picker must never be open simultaneously.
      if (_showPresetPicker) _showDecorationPicker = false;
    });
  }

  void _goNext({int? publishMode}) {
    HapticFeedback.mediumImpact();
    if (widget.onNext != null) {
      widget.onNext!();
    } else if (_galleryFile != null) {
      final file = _galleryFile!;
      final isVid = _isVideoPath(file.path);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MediaPrepareScreen(
            file: file,
            isVideo: isVid,
            preselectedTrack: _selectedTrack,
            initialPublishMode: publishMode,
            preloadedBytes: isVid ? null : _galleryBytes,
          ),
        ),
      );
    }
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera preview full-screen
          if (_errorMessage != null)
            _buildErrorState(_errorMessage!)
          else if (_isInitialized && _controller != null)
            GestureDetector(
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              child: FadeTransition(
                opacity: _blinkCtrl,
                child: FilterOverlay(
                  state: _activePreset.filter,
                  child: _buildCameraPreview(),
                ),
              ),
            )
          else
            const Center(
              child: CircularProgressIndicator(color: Colors.white24, strokeWidth: 2),
            ),

          // Overlays
          MaskOverlay(descriptor: _selectedMask),

          if (_activePreset.overlay != null)
            Positioned.fill(
              child: IgnorePointer(child: EffectOverlay(effect: _activePreset.overlay!)),
            ),

          if (_activePreset.frame != null)
            Positioned.fill(
              child: IgnorePointer(child: FrameOverlay(effect: _activePreset.frame!)),
            ),

          if (_showGrid)
            Positioned.fill(
              child: IgnorePointer(child: CustomPaint(painter: CameraGridPainter())),
            ),

          // Gradient scrim
          _buildGradientOverlay(),

          // ── Extracted widgets ──────────────────────────────────────────

          // Top: segment bar + controls row
          CameraTopBar(
            segments: _segments,
            currentSegDur: _currentSegDur,
            maxDuration: _effectiveMaxDuration,
            isRecording: _isRecording,
            selectedTrack: _selectedTrack,
            segmentFlashAnim: _segmentFlashCtrl,
            switchRotationAnim: _switchRotation,
            canSwitchCamera: _cameras.length >= 2 && !_isSwitching,
            onClose: widget.onClose ?? () => Navigator.maybePop(context),
            onMusicTap: _openMusicPicker,
            onSwitchCamera: _switchCamera,
            onClearTrack: () => setState(() => _selectedTrack = null),
          ),

          // Right: tool buttons
          CameraRightPanel(
            isFrontCamera: _isFrontCamera,
            flashMode: _flashMode,
            timerSetting: _timerSetting,
            showGrid: _showGrid,
            videoSpeed: _videoSpeed,
            beautyOn: _beautyOn,
            isVideoMode: _cameraMode.isVideoMode,
            presetActive: !_activePreset.isNone || _showPresetPicker,
            flashPulseAnim: _flashPulseController,
            onToggleFlash: _toggleFlash,
            onToggleTimer: () {
              HapticFeedback.selectionClick();
              setState(() {
                _timerSetting = _timerSetting == 0 ? 3 : _timerSetting == 3 ? 10 : 0;
              });
            },
            onToggleGrid: () {
              HapticFeedback.selectionClick();
              setState(() => _showGrid = !_showGrid);
            },
            onToggleSpeed: () {
              HapticFeedback.selectionClick();
              setState(() => _speedIdx = (_speedIdx + 1) % _speedValues.length);
            },
            onToggleBeauty: () {
              HapticFeedback.selectionClick();
              setState(() => _beautyOn = !_beautyOn);
            },
            onTogglePresets: _togglePresetPicker,
          ),

          // Bottom: floating mode tabs + record row
          CameraBottomPanel(
            cameraMode: _cameraMode,
            isRecording: _isRecording,
            totalPct: _totalPct,
            totalWithCurrent: _totalWithCurrent,
            showDecorationPicker: _showDecorationPicker,
            selectedDecorationId: _selectedDecorationId,
            savedDecorationIds: _savedDecorationIds,
            galleryThumbnailBytes: _galleryThumbnailBytes,
            hasSegments: _segments.isNotEmpty,
            showPresetPicker: _showPresetPicker,
            activePreset: _activePreset,
            presetSnapshotBytes: _presetSnapshotBytes,
            onModeChanged: (mode) {
              if (_cameraMode == mode) return;
              if (_isRecording) _stopRecording();
              HapticFeedback.selectionClick();
              setState(() {
                _cameraMode = mode;
                _segments = [];
                _currentSegDur = 0.0;
                _galleryFile = null;
                _galleryBytes = null;
                _showGalleryPreview = false;
                _activePreset = CameraPresetsCollection.none;
                _showPresetPicker = false;
              });
              _nextFabController.reverse();
            },
            onPickGallery: _pickFromGallery,
            onTakePicture: _takePicture,
            onStartRecording: _startRecording,
            onStopRecording: _stopRecording,
            onDecorationChanged: _applyDecoration,
            onToggleSaveDecoration: (id) => setState(() {
              if (_savedDecorationIds.contains(id)) {
                _savedDecorationIds = _savedDecorationIds.difference({id});
              } else {
                _savedDecorationIds = {..._savedDecorationIds, id};
              }
            }),
            onToggleDecorationPicker: () => setState(() {
              _showDecorationPicker = !_showDecorationPicker;
              // Presets and mask picker must never be open simultaneously.
              if (_showDecorationPicker) _showPresetPicker = false;
            }),
            onUndo: _undoLastSegment,
            onPresetSelected: _applyPreset,
          ),

          // Next FAB (appears when segments recorded)
          _buildNextFAB(),

          // Zoom pill
          _buildZoomIndicator(),

          // Camera switch fade overlay
          if (_isSwitching)
            AnimatedBuilder(
              animation: _switchController,
              builder: (_, __) => Container(
                color: Colors.black.withValues(
                    alpha: 0.3 * (1 - _switchController.value)),
              ),
            ),

          // Countdown
          if (_countdown > 0) _buildCountdownOverlay(),

          // Gallery preview full-screen
          if (_showGalleryPreview && _galleryFile != null)
            CameraGalleryPreview(
              file: _galleryFile!,
              bytes: _galleryBytes,
              selectedTrack: _selectedTrack,
              fadeAnim: _galleryFadeAnim,
              slideAnim: _gallerySlideAnim,
              onClose: _closeGalleryPreview,
              onStory: () => _goNext(publishMode: 0),
              onPost: () => _goNext(publishMode: 1),
              onEdit: _galleryBytes != null && !_isVideoPath(_galleryFile!.path)
                  ? () async {
                      if (_galleryBytes == null) return;
                      final result = await Navigator.of(context)
                          .push<StoryEditorResult>(MaterialPageRoute(
                        fullscreenDialog: true,
                        builder: (_) => StoryEditorScreen(initialBytes: _galleryBytes!),
                      ));
                      if (result == null || !mounted) return;
                      setState(() {
                        _galleryBytes = result.bytes;
                        _galleryThumbnailBytes = result.bytes;
                      });
                    }
                  : null,
            ),
        ],
      ),
    );
  }

  // ─── Error state ────────────────────────────────────────────────────────

  Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(PhosphorIconsRegular.camera, color: Colors.white54, size: 56),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 15),
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () {
                setState(() { _errorMessage = null; _isInitialized = false; });
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

  // ─── Camera preview ─────────────────────────────────────────────────────

  Widget _buildCameraPreview() {
    final controller = _controller!;
    final previewSize = controller.value.previewSize;
    if (previewSize == null) {
      return const SizedBox.expand(child: ColoredBox(color: Colors.black));
    }
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: previewSize.height,
          height: previewSize.width,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  // ─── Gradient ───────────────────────────────────────────────────────────

  Widget _buildGradientOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.0, 0.28, 0.55, 1.0],
              colors: [
                SeeUColors.mediumScrim,
                SeeUColors.transparentBlack,
                SeeUColors.transparentBlack,
                SeeUColors.darkScrim,
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Next FAB ───────────────────────────────────────────────────────────

  Widget _buildNextFAB() {
    return Positioned(
      bottom: 0,
      right: 0,
      child: SafeArea(
        top: false,
        child: AnimatedBuilder(
          animation: _nextFabController,
          builder: (_, __) {
            final t = Curves.easeOutBack.transform(_nextFabController.value);
            return Opacity(
              opacity: _nextFabController.value.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, 24 * (1 - t)),
                child: Transform.scale(
                  scale: 0.7 + 0.3 * t,
                  child: GestureDetector(
                    onTap: _goNext,
                    child: Container(
                      margin: const EdgeInsets.only(right: 20, bottom: 180),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [SeeUColors.accentSecondary, SeeUColors.accent],
                        ),
                        borderRadius: BorderRadius.circular(SeeURadii.pill),
                        boxShadow: [
                          BoxShadow(
                            color: _kAccent.withValues(alpha: 0.50),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
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
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(width: 6),
                          Icon(PhosphorIconsRegular.arrowRight,
                              color: Colors.white, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ─── Zoom indicator ─────────────────────────────────────────────────────

  Widget _buildZoomIndicator() {
    final range = _maxZoom - _minZoom;
    final fraction =
        range > 0 ? ((_currentZoom - _minZoom) / range).clamp(0.0, 1.0) : 0.0;
    const trackW = 120.0;
    const trackH = 3.0;
    const thumbD = 14.0;
    final thumbX = fraction * trackW - thumbD / 2;

    return Positioned(
      bottom: 195,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedOpacity(
          opacity: _showZoomIndicator ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: SizedBox(
            width: trackW,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.translate(
                  offset: Offset(thumbX - (trackW / 2 - thumbD / 2), 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _zoomLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: trackW,
                  height: thumbD,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        top: (thumbD - trackH) / 2, left: 0, right: 0,
                        child: Container(
                          height: trackH,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.28),
                            borderRadius: BorderRadius.circular(trackH / 2),
                          ),
                        ),
                      ),
                      Positioned(
                        top: (thumbD - trackH) / 2,
                        left: 0,
                        width: fraction * trackW,
                        child: Container(
                          height: trackH,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(trackH / 2),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        left: thumbX,
                        child: Container(
                          width: thumbD,
                          height: thumbD,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.35),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Countdown overlay ──────────────────────────────────────────────────

  Widget _buildCountdownOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.3),
          child: Center(child: CameraCountdownNumber(value: _countdown)),
        ),
      ),
    );
  }

  // ─── Legacy upload (kept, unused) ───────────────────────────────────────
  // ignore: unused_element
  Future<void> _uploadStory(XFile file) async {
    if (_isUploading) return;
    setState(() => _isUploading = true);
    try {
      final api = ref.read(apiClientProvider);
      final bytes = _galleryBytes ?? await file.readAsBytes();
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: file.name),
      });
      final uploadResp = await api.post(
        ApiEndpoints.mediaUpload,
        data: formData,
        options: Options(
          sendTimeout: const Duration(seconds: 120),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
      final mediaUrl = uploadResp.data['data']['url'] as String;
      await api.post(ApiEndpoints.stories, data: {
        'media_url': mediaUrl,
        'media_type': 'image',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Стори опубликована!'),
            backgroundColor: Color(0xFF4CAF50),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Не удалось опубликовать: $e'),
          backgroundColor: const Color(0xFFE53935),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }
}

