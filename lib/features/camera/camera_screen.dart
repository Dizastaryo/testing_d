import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
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
import 'package:video_player/video_player.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/tokens.dart';
import '../post/media_prepare_screen.dart';
import 'decorations/decoration_item.dart';
import 'decorations/decoration_picker.dart';
import 'filters/filter_overlay.dart';
import 'filters/filter_state.dart';
import 'filters/frame_effect.dart';
import 'filters/overlay_effect.dart';
import 'masks/face_tracking_service.dart';
import 'masks/mask_catalog.dart';
import 'masks/mask_debug_config.dart';
import 'masks/mask_overlay.dart';
import 'widgets/camera_buttons.dart';
import 'widgets/camera_painters.dart';
import 'widgets/camera_record_button.dart';

// ─── Constants ────────────────────────────────────────────────────────────

const double _kMaxDuration = 60.0; // seconds
const Color _kAccent = SeeUColors.accent; // #FF5A3C
// BUG-15: alias на SeeUColors.glassOverlay — централизованный token.
// Сохраняем local-имя чтобы не лопатить десятки сайтов в этом файле.
const Color _kGlassBg = SeeUColors.glassOverlay;

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
  List<double> _segments = []; // completed segment durations in seconds
  MaskDescriptor? _selectedMask; // AR-маска поверх preview
  FilterState _filter = FilterState.identity; // color/grain/vignette state
  OverlayEffect? _overlayEffect; // dust/scratches, light leak, etc.
  FrameEffect? _frameEffect;    // polaroid, film strip, etc.

  // ── Украшения (объединённые фильтры + маски) ──
  bool _showDecorationPicker = false;
  String? _selectedDecorationId;
  Set<String> _savedDecorationIds = {};
  double _currentSegDur = 0.0; // live elapsed seconds for active segment

  // ── Timer state ──
  int _timerSetting = 0; // 0 | 3 | 10
  int _countdown = 0;

  // ── Settings ──
  bool _flashOn = false;
  bool _showGrid = false;

  // ── Fake music track label ──
  final String _audioTitle = 'Любимая музыка';

  // ── Gallery preview ──
  XFile? _galleryFile;
  Uint8List? _galleryBytes;
  bool _showGalleryPreview = false;

  // ── Upload state ──
  bool _isUploading = false;

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
    // Dispose the old controller BEFORE creating a new one.
    // Running two controllers simultaneously can cause the back camera to
    // output a black frame on many devices.
    final prev = _controller;
    _controller = null;
    if (mounted) setState(() => _isInitialized = false);

    if (prev != null) {
      try {
        await prev.dispose();
      } catch (e) {
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
      debugPrint(
        '_setupCamera: initialized ${camera.lensDirection.name} camera '
        'previewSize=$ps '
        '(swapped for portrait: ${ps != null ? "${ps.height}x${ps.width}" : "null"}) '
        'aspectRatio=${controller.value.aspectRatio}',
      );

      _maxZoom = await controller.getMaxZoomLevel();
      _minZoom = await controller.getMinZoomLevel();
      _currentZoom = _minZoom;

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

      // Баг 5: восстановить torch на новом контроллере после смены камеры.
      // Фронтальная камера не поддерживает вспышку — пропускаем.
      if (_flashOn && !_isFrontCamera) {
        try {
          await controller.setFlashMode(FlashMode.torch);
        } catch (_) {}
      }
    } on CameraException catch (e) {
      debugPrint('_setupCamera: CameraException: ${e.code} — ${e.description}');
      await controller.dispose();
      if (mounted) {
        setState(() {
          _errorMessage = 'Ошибка камеры: ${e.description}';
          _isSwitching = false;
        });
      } else {
        _isSwitching = false;
      }
    } catch (e) {
      debugPrint('_setupCamera: unexpected error: $e');
      await controller.dispose();
      if (mounted) {
        setState(() {
          _errorMessage = 'Ошибка инициализации камеры';
          _isSwitching = false;
        });
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
    if (_isRecording) return; // уже пишем — повторный вызов игнорируем
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
      final secs = (elapsed - _tickerStart!).inMilliseconds / 1000.0;
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

    final videoFile = await _controller?.stopVideoRecording();
    if (videoFile != null && mounted) {
      await _setGallery(videoFile);
    }
  }

  Future<void> _setGallery(XFile file) async {
    Uint8List? bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (e) {
      debugPrint('camera readAsBytes: $e');
    }
    if (!mounted) return;
    setState(() {
      _galleryFile = file;
      _galleryBytes = bytes;
      _showGalleryPreview = true;
    });
  }

  Future<void> _undoLastSegment() async {
    // Ждём остановки — _stopRecording добавляет сегмент в список,
    // поэтому await обязателен: без него undo удалит старый сегмент,
    // а новый (только что остановленный) останется.
    if (_isRecording) await _stopRecording();
    if (!mounted) return;
    if (_segments.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _segments = _segments.sublist(0, _segments.length - 1);
      // Галерея preview была открыта _stopRecording — при undo закрываем её,
      // пользователь продолжает работать с камерой.
      _showGalleryPreview = false;
      _galleryFile = null;
      _galleryBytes = null;
    });
  }

  // ── Photo capture ──────────────────────────────────────────────────────

  Future<void> _takePicture() async {
    if (_controller == null || !_isInitialized) return;
    if (_controller!.value.isTakingPicture) return;
    HapticFeedback.mediumImpact();
    try {
      final file = await _controller!.takePicture();
      // Bake AR-маску и color-filter в финальное изображение, чтобы они
      // остались на снимке а не только на preview.
      final composed = await _composeCapture(file);
      if (mounted) {
        await _setGallery(composed);
      }
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

  /// Композирует raw-фото с активным фильтром и маской.
  /// 1. Decode raw в `ui.Image`.
  /// 2. PictureRecorder + Canvas — рисует image, поверх — viewport-сайзов
  ///    vignette/grain, затем mask-painter (через `_FaceFrame.fromSize`).
  /// 3. Для color matrix используем `saveLayer + ColorFilter` — один shader pass.
  /// 4. Encode picture обратно в PNG, пишем в файл рядом с raw.
  ///
  /// Web: File I/O недоступен в браузере — для Chrome-dev возвращаем raw как
  /// есть (см. CLAUDE.md — Chrome это dev-preview, mobile это shipping).
  Future<XFile> _composeCapture(XFile raw) async {
    if (_filter.isIdentity &&
        _selectedMask == null &&
        _overlayEffect == null &&
        _frameEffect == null) {
      return raw;
    }
    if (kIsWeb) return raw; // web: dart:io недоступен — отдаём raw

    final bytes = await raw.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final w = image.width.toDouble();
    final h = image.height.toDouble();
    final size = Size(w, h);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 1. Image (с color-filter если есть).
    if (_filter.isIdentity) {
      canvas.drawImage(image, Offset.zero, Paint());
    } else {
      canvas.saveLayer(
        Rect.fromLTWH(0, 0, w, h),
        Paint()..colorFilter = ColorFilter.matrix(_filter.toMatrix()),
      );
      canvas.drawImage(image, Offset.zero, Paint());
      canvas.restore();
    }

    // 2. Vignette overlay.
    if (_filter.vignette > 0) {
      final rect = Rect.fromLTWH(0, 0, w, h);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            radius: 0.9,
            colors: [
              Colors.black.withValues(alpha: 0),
              Colors.black.withValues(alpha: _filter.vignette * 0.75),
            ],
            stops: const [0.55, 1.0],
          ).createShader(rect),
      );
    }

    // 3. Grain — пропускаем при bake (heavy на full-res и плёночный noise
    // на 4k-фотке выглядит сильнее чем в preview). Если нужно — отдельный
    // toggle «зерно в финале».

    // 4. Overlay effect (dust, light leak) — запекается с фиксированным
    // animValue = 0.6 (средняя точка анимации) через OverlayEffect.bake().
    _overlayEffect?.bake(canvas, size);

    // 5. Frame effect (polaroid, film strip…) — поверх overlay, под маской.
    _frameEffect?.bake(canvas, size);

    // 6. Mask painter — рисуется в pixel-space фотографии, _FaceFrame
    // автоматически масштабируется по size.
    if (_selectedMask != null) {
      _selectedMask!.painter().paint(canvas, size);
    }

    final picture = recorder.endRecording();
    final composedImg = await picture.toImage(w.toInt(), h.toInt());
    final pngBytes =
        await composedImg.toByteData(format: ui.ImageByteFormat.png);
    if (pngBytes == null) return raw;

    // Запись рядом с raw — тот же каталог, новое имя.
    final outPath =
        '${raw.path.replaceAll(RegExp(r'\.[^.]+$'), '')}_composed.png';
    await File(outPath).writeAsBytes(pngBytes.buffer.asUint8List());
    return XFile(outPath);
  }

  // ── Gallery picker ─────────────────────────────────────────────────────

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final file = await picker.pickMedia();
    if (file == null || !mounted) return;
    await _setGallery(file);
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
      _controller = null;
      if (mounted) setState(() => _isInitialized = false);
      if (ctrl != null) {
        ctrl.dispose();
      }
    } else if (state == AppLifecycleState.resumed) {
      // Reinitialize the camera that was active before the app went background.
      _reinitActiveCamera();
    }
  }

  /// Reinitializes the camera that was last active (front or back), without
  /// resetting [_isFrontCamera] to its default value.
  Future<void> _reinitActiveCamera() async {
    if (kIsWeb) return;
    if (_cameras.isEmpty) {
      // Camera list might have been lost; do a full reinit.
      await _initCamera();
      return;
    }
    final camera = _isFrontCamera
        ? (_getFrontCamera() ?? _cameras.first)
        : (_getBackCamera() ?? _cameras.last);
    await _setupCamera(camera);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.dispose();
    // Stop face-tracking перед disposal'ом controller'а — иначе
    // service попытается stopImageStream на уже-dispose'нутом controller'е.
    unawaited(FaceTrackingService.instance.stop());
    _controller?.dispose();
    _switchController.dispose();
    _flashPulseController.dispose();
    super.dispose();
  }

  /// Дёргается каждый раз когда юзер выбирает/снимает маску. Стартует или
  /// останавливает face-tracking. Без выбранной маски detection не нужен —
  /// сэкономим батарею.
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
      if (item == null) {
        _filter = FilterState.identity;
        _selectedMask = null;
      } else if (item.category == DecorationCategory.filter) {
        _filter = item.filterPreset!.state;
        _selectedMask = null;
      } else {
        _selectedMask = item.mask;
        _filter = FilterState.identity;
      }
    });
    _syncFaceTracking();
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Main layout: bounded camera area + solid bottom panel ──
          Column(
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // ── Camera preview ──
                    if (_errorMessage != null)
                      _buildErrorState(_errorMessage!)
                    else if (_isInitialized && _controller != null)
                      GestureDetector(
                        onScaleStart: _onScaleStart,
                        onScaleUpdate: _onScaleUpdate,
                        child: FilterOverlay(
                          state: _filter,
                          child: _buildCameraPreview(),
                        ),
                      )
                    else
                      const Center(
                        child: CircularProgressIndicator(color: Colors.white24, strokeWidth: 2),
                      ),

                    // ── AR mask overlay ──
                    MaskOverlay(descriptor: _selectedMask),

                    // ── Overlay effect (dust, light leak…) ──
                    if (_overlayEffect != null)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: EffectOverlay(effect: _overlayEffect!),
                        ),
                      ),

                    // ── Frame effect (polaroid, film strip…) ──
                    if (_frameEffect != null)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: FrameOverlay(effect: _frameEffect!),
                        ),
                      ),

                    // ── DEBUG: face tracking overlay ──
                    if (kMaskTuning && _selectedMask != null) const _FaceTrackDebugOverlay(),

                    // ── Grid overlay ──
                    if (_showGrid)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(painter: CameraGridPainter()),
                        ),
                      ),

                    // ── Gradient overlay ──
                    _buildGradientOverlay(),

                    // ── Top area: segment bar + close/music/flip row ──
                    _buildTopArea(),

                    // ── Right tools ──
                    _buildRightTools(),

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
              ),

              // ── Solid bottom controls panel ──
              _buildBottomPanel(),
            ],
          ),

          // ── Full-screen overlays (above the column layout) ──

          // DEBUG: mask adjustment sliders
          if (kMaskTuning && _selectedMask != null)
            _MaskDebugSliders(maskId: _selectedMask!.id),

          // Gallery preview
          if (_showGalleryPreview && _galleryFile != null)
            _buildGalleryPreview(),
        ],
      ),
    );
  }

  // Раньше старый flow камеры публиковал story напрямую этой функцией.
  // Заменено на MediaPrepareScreen (см. «Далее» кнопка ниже). Сохраняем
  // как утилиту для quick-upload short-circuit'а, если когда-нибудь
  // вернутся. Подавляем unused-warning.
  // ignore: unused_element
  Future<void> _uploadStory(XFile file) async {
    if (_isUploading) return;
    setState(() => _isUploading = true);
    try {
      final api = ref.read(apiClientProvider);

      // Upload file (cross-platform: read bytes, send via fromBytes).
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

      // Create story
      await api.post(
        ApiEndpoints.stories,
        data: {
          'media_url': mediaUrl,
          'media_type': 'image',
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('\u0421\u0442\u043E\u0440\u0438 \u043E\u043F\u0443\u0431\u043B\u0438\u043A\u043E\u0432\u0430\u043D\u0430!'),
            backgroundColor: Color(0xFF4CAF50),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('\u041D\u0435 \u0443\u0434\u0430\u043B\u043E\u0441\u044C \u043E\u043F\u0443\u0431\u043B\u0438\u043A\u043E\u0432\u0430\u0442\u044C: $e'),
            backgroundColor: const Color(0xFFE53935),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ── Bottom controls panel ──────────────────────────────────────────────

  Widget _buildBottomPanel() {
    return GestureDetector(
      // Свайп вверх → галерея
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) < -300) {
          _pickFromGallery();
        }
      },
      child: Container(
        color: Colors.black,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Пикер украшений (анимированно появляется/скрывается)
              AnimatedSize(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOut,
                child: _showDecorationPicker
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
                        child: DecorationPicker(
                          allItems: DecorationCatalog.all,
                          savedIds: _savedDecorationIds,
                          selectedId: _selectedDecorationId,
                          onChanged: _applyDecoration,
                          onToggleSave: (id) => setState(() {
                            if (_savedDecorationIds.contains(id)) {
                              _savedDecorationIds = _savedDecorationIds.difference({id});
                            } else {
                              _savedDecorationIds = {..._savedDecorationIds, id};
                            }
                          }),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 14),
              _buildRecordRow(),
              if (_segments.isNotEmpty && !_isRecording) ...[
                const SizedBox(height: 14),
                _buildNextButton(),
              ],
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  // ── Gallery preview ────────────────────────────────────────────────────

  bool get _galleryIsVideo {
    final path = _galleryFile?.path ?? '';
    final ext = path.split('.').last.toLowerCase();
    return ['mp4', 'mov', 'webm', 'avi', 'mkv'].contains(ext);
  }

  Widget _buildGalleryPreview() {
    final isVideo = _galleryIsVideo;
    return Positioned.fill(
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Preview: видео — VideoPlayer, фото — Image.memory
            if (isVideo && _galleryFile != null)
              _VideoGalleryPreview(file: _galleryFile!)
            else
              InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: _galleryBytes != null
                    ? Image.memory(_galleryBytes!, fit: BoxFit.contain)
                    : Container(color: Colors.black),
              ),

            // Close (X) button
            Positioned(
              top: 56,
              left: 16,
              child: GestureDetector(
                onTap: () => setState(() {
                  _showGalleryPreview = false;
                  _galleryFile = null;
                  _galleryBytes = null;
                }),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(PhosphorIconsRegular.x, color: Colors.white, size: 22),
                ),
              ),
            ),

            // "Далее" button → open MediaPrepareScreen
            Positioned(
              bottom: 48,
              right: 24,
              child: GestureDetector(
                onTap: () {
                  final file = _galleryFile!;
                  final ext = file.path.split('.').last.toLowerCase();
                  final isVideo = ['mp4', 'mov', 'webm', 'avi'].contains(ext);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MediaPrepareScreen(
                        file: file,
                        isVideo: isVideo,
                      ),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                  decoration: BoxDecoration(
                    color: _kAccent,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Text(
                    'Далее',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
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

    // `previewSize` is reported in landscape orientation (width > height).
    // In portrait mode the sensor is rotated 90°, so we swap width/height
    // when sizing the inner SizedBox.  FittedBox.cover then scales that box
    // to fill the screen exactly — no over-zoom, no black bars.
    final previewSize = controller.value.previewSize;
    if (previewSize == null) {
      return const SizedBox.expand(child: ColoredBox(color: Colors.black));
    }

    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          // Swap landscape width/height to get the portrait dimensions.
          width: previewSize.height,
          height: previewSize.width,
          child: CameraPreview(controller),
        ),
      ),
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
              // BUG-15: scrim-tokens вместо inline-hex.
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
        painter: CameraSegmentBarPainter(
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
        CameraGlassButton(
          onTap: widget.onClose ?? () => Navigator.maybePop(context),
          child: const Icon(PhosphorIconsRegular.x, color: Colors.white, size: 20),
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
                const Icon(PhosphorIconsRegular.musicNote, color: Colors.white, size: 14),
                const SizedBox(width: 6),
                CameraWaveform(),
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
          child: CameraGlassButton(
            onTap: _switchCamera,
            child: const Icon(PhosphorIconsRegular.cameraRotate, color: Colors.white, size: 20),
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
              child: CameraToolButton(
                icon: Icon(
                  _flashOn ? PhosphorIconsFill.lightning : PhosphorIconsRegular.lightning,
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
            CameraToolButton(
              icon: Icon(PhosphorIconsRegular.timer,
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
            // Grid
            CameraToolButton(
              icon: const Icon(PhosphorIconsRegular.gridFour, color: Colors.white, size: 20),
              label: 'сетка',
              active: _showGrid,
              onTap: () => setState(() => _showGrid = !_showGrid),
            ),
          ],
        ),
      ),
    );
  }

  // ── Record button row ──────────────────────────────────────────────────

  Widget _buildRecordRow() {
    final hasSegments = _segments.isNotEmpty;
    final showUndo = hasSegments || _isRecording;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Галерея (слева)
        GestureDetector(
          onTap: _pickFromGallery,
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(SeeURadii.small),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.20),
                width: 1,
              ),
            ),
            alignment: Alignment.center,
            child: const Icon(PhosphorIconsRegular.image, color: Colors.white, size: 22),
          ),
        ),

        const SizedBox(width: 32),

        // Кнопка съёмки (центр): тап → фото, удержание → видео
        CameraRecordButton(
          isRecording: _isRecording,
          totalPct: _totalPct,
          isPhotoMode: !_isRecording,
          onTap: _takePicture,
          onHoldStart: () {
            _startRecording();
          },
          onHoldEnd: _stopRecording,
        ),

        const SizedBox(width: 32),

        // Справа: отмена сегмента (при записи) или украшения
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: showUndo
              ? GestureDetector(
                  key: const ValueKey('undo'),
                  onTap: _undoLastSegment,
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.20),
                        width: 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(PhosphorIconsRegular.arrowCounterClockwise,
                        color: Colors.white, size: 22),
                  ),
                )
              : GestureDetector(
                  key: const ValueKey('deco'),
                  onTap: () => setState(
                      () => _showDecorationPicker = !_showDecorationPicker),
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: _showDecorationPicker || _selectedDecorationId != null
                          ? SeeUColors.accent.withValues(alpha: 0.18)
                          : Colors.white.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _showDecorationPicker || _selectedDecorationId != null
                            ? SeeUColors.accent
                            : Colors.white.withValues(alpha: 0.20),
                        width: 1.5,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      PhosphorIconsFill.sparkle,
                      color: _showDecorationPicker || _selectedDecorationId != null
                          ? SeeUColors.accent
                          : Colors.white,
                      size: 22,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  // ── "Далее" button ─────────────────────────────────────────────────────

  Widget _buildNextButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.mediumImpact();
          if (widget.onNext != null) {
            widget.onNext!();
          } else if (_galleryFile != null) {
            final file = _galleryFile!;
            final ext = file.path.split('.').last.toLowerCase();
            final isVideo = ['mp4', 'mov', 'webm', 'avi', 'mkv'].contains(ext);
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MediaPrepareScreen(file: file, isVideo: isVideo),
              ),
            );
          }
        },
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [SeeUColors.accentSecondary, SeeUColors.accent],
            ),
            borderRadius: BorderRadius.circular(SeeURadii.pill),
            boxShadow: [
              BoxShadow(
                color: _kAccent.withValues(alpha: 0.40),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Далее',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(width: 6),
              Icon(PhosphorIconsRegular.caretRight, color: Colors.white, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  // ── Zoom indicator ─────────────────────────────────────────────────────

  Widget _buildZoomIndicator() {
    return Positioned(
      bottom: 20,
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
            child: CameraCountdownNumber(value: _countdown),
          ),
        ),
      ),
    );
  }
}

// ─── Video preview for gallery overlay ────────────────────────────────────

class _VideoGalleryPreview extends StatefulWidget {
  final XFile file;
  const _VideoGalleryPreview({required this.file});

  @override
  State<_VideoGalleryPreview> createState() => _VideoGalleryPreviewState();
}

class _VideoGalleryPreviewState extends State<_VideoGalleryPreview> {
  VideoPlayerController? _ctrl;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _ctrl = kIsWeb
        ? VideoPlayerController.networkUrl(Uri.parse(widget.file.path))
        : VideoPlayerController.file(File(widget.file.path));
    _ctrl!
      ..setLooping(true)
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _ready = true);
          _ctrl!.play();
        }
      }).catchError((e) {
        debugPrint('_VideoGalleryPreview init error: $e');
      });
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _ctrl == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white24, strokeWidth: 2),
      );
    }
    return Center(
      child: AspectRatio(
        aspectRatio: _ctrl!.value.aspectRatio,
        child: VideoPlayer(_ctrl!),
      ),
    );
  }
}

// ─── DEBUG: on-screen face tracking values (remove after debugging) ───────

class _FaceTrackDebugOverlay extends StatefulWidget {
  const _FaceTrackDebugOverlay();

  @override
  State<_FaceTrackDebugOverlay> createState() => _FaceTrackDebugOverlayState();
}

class _FaceTrackDebugOverlayState extends State<_FaceTrackDebugOverlay> {
  late final _sub = FaceTrackingService.instance.stream.listen((_) {
    if (mounted) setState(() {});
  });

  @override
  void initState() {
    super.initState();
    _sub;
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 4,
      left: 4,
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Use the full screen size as canvas (same as Positioned.fill in MaskOverlay)
            final screen = MediaQuery.of(context).size;
            final face = maskCurrentTrackedFace;
            String text;
            final rotDeg = FaceTrackingService.instance.debugRotDeg;
            if (face == null || face.points.length < 468) {
              text = 'FALLBACK rotDeg=$rotDeg\n'
                  'face=${face == null ? "null" : "pts=${face.points.length}"}';
            } else {
              final ff = FaceFrame.fromTracked(face, screen);
              text = 'TRACKED rotDeg=$rotDeg\n'
                  'canvas=${screen.width.toInt()}x${screen.height.toInt()}\n'
                  'mesh=${face.imageWidth}x${face.imageHeight}\n'
                  'L eye=(${ff.leftEye.dx.toInt()},${ff.leftEye.dy.toInt()})\n'
                  'R eye=(${ff.rightEye.dx.toInt()},${ff.rightEye.dy.toInt()})\n'
                  'center=(${ff.center.dx.toInt()},${ff.center.dy.toInt()})\n'
                  'eyeDist=${ff.eyeDistance.toInt()}\n'
                  'faceW=${ff.faceWidth.toInt()} faceH=${ff.faceHeight.toInt()}\n'
                  'roll=${ff.rollRad.toStringAsFixed(2)}\n'
                  'yaw=${ff.yawRad.toStringAsFixed(2)}';
            }
            return Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 11,
                  fontFamily: 'monospace',
                  height: 1.3,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─── DEBUG: per-mask adjustment sliders (remove after tuning) ─────────────

class _MaskDebugSliders extends StatefulWidget {
  final String maskId;
  const _MaskDebugSliders({required this.maskId});

  @override
  State<_MaskDebugSliders> createState() => _MaskDebugSlidersState();
}

class _MaskDebugSlidersState extends State<_MaskDebugSliders> {
  MaskAdjust get _adj => MaskDebugConfig.get(widget.maskId);

  void _update(void Function(MaskAdjust a) fn) {
    setState(() {
      fn(_adj);
      MaskDebugConfig.notify();
    });
  }

  @override
  void didUpdateWidget(_MaskDebugSliders old) {
    super.didUpdateWidget(old);
    if (old.maskId != widget.maskId) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final a = _adj;
    final pad = MediaQuery.of(context).padding.top;
    return Positioned(
      left: 0,
      right: 0,
      top: pad + 50,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${widget.maskId}: dx=${a.dx.toStringAsFixed(2)} '
              'dy=${a.dy.toStringAsFixed(2)} s=${a.scale.toStringAsFixed(2)}',
              style: const TextStyle(
                color: Colors.greenAccent,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 4),
            _slider('dx', a.dx, -2.0, 2.0, (v) => _update((a) => a.dx = v)),
            _slider('dy', a.dy, -3.0, 1.0, (v) => _update((a) => a.dy = v)),
            _slider('s ', a.scale, 0.3, 3.0, (v) => _update((a) => a.scale = v)),
          ],
        ),
      ),
    );
  }

  Widget _slider(String label, double value, double min, double max,
      ValueChanged<double> onChanged) {
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                activeTrackColor: SeeUColors.accent,
                inactiveTrackColor: Colors.white30,
                thumbColor: Colors.white,
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
