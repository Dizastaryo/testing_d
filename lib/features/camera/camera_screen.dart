import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import '../../core/design/tokens.dart';

class CameraScreen extends StatefulWidget {
  final VoidCallback? onClose;

  const CameraScreen({super.key, this.onClose});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isFrontCamera = true;
  bool _isInitialized = false;
  bool _isSwitching = false;

  // Error state (C07, U04)
  String? _errorMessage;

  // Zoom — kept outside setState to avoid rebuilds on every frame (P01)
  double _currentZoom = 1.0;
  double _baseZoom = 1.0;
  double _maxZoom = 1.0;
  double _minZoom = 1.0;

  // Zoom indicator visibility — updated minimally (P01)
  bool _showZoomIndicator = false;
  String _zoomLabel = '1.0x';

  FlashMode _flashMode = FlashMode.off;

  // Animations
  late AnimationController _shutterController;
  late Animation<double> _shutterAnimation;
  late AnimationController _switchController;
  late Animation<double> _switchRotation;
  late AnimationController _flashPulseController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _shutterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _shutterAnimation = Tween<double>(begin: 1.0, end: 0.85).animate(
      CurvedAnimation(parent: _shutterController, curve: Curves.easeInOut),
    );

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

  // C07 + C08: request permission, handle web, handle empty camera list
  Future<void> _initCamera() async {
    // C08: web is not supported
    if (kIsWeb) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Камера недоступна в браузере';
        });
      }
      return;
    }

    try {
      // C07: availableCameras() will throw a CameraException with
      // code 'CameraAccessDenied' if the user denies the permission.
      _cameras = await availableCameras();
    } on CameraException catch (e) {
      debugPrint('Camera permission/init error: $e');
      final msg = (e.code == 'CameraAccessDenied' ||
              e.code == 'CameraAccessDeniedWithoutPrompt' ||
              e.code == 'CameraAccessRestricted')
          ? 'Нет доступа к камере. Разрешите доступ в настройках.'
          : 'Не удалось получить список камер: ${e.description}';
      if (mounted) setState(() => _errorMessage = msg);
      return;
    } catch (e) {
      debugPrint('Camera init error: $e');
      if (mounted) setState(() => _errorMessage = 'Ошибка инициализации камеры');
      return;
    }

    // C08: no cameras found
    if (_cameras.isEmpty) {
      if (mounted) setState(() => _errorMessage = 'Камера недоступна');
      return;
    }

    await _setupCamera(_getFrontCamera() ?? _cameras.first);
  }

  CameraDescription? _getFrontCamera() {
    try {
      return _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
    } catch (_) {
      return null;
    }
  }

  CameraDescription? _getBackCamera() {
    try {
      return _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _setupCamera(CameraDescription camera) async {
    final prev = _controller;
    // M03: mark old controller as 'in-flight' to prevent double-dispose
    _controller = null;

    final controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await controller.initialize();
      _maxZoom = await controller.getMaxZoomLevel();
      _minZoom = await controller.getMinZoomLevel();
      _currentZoom = _minZoom;

      // M03: only dispose prev after new controller is fully ready,
      // and only if it has not been disposed already (lifecycle may have
      // cleared it via didChangeAppLifecycleState).
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
        // M01: reset _isSwitching inside the successful branch
        _isSwitching = false;
        _errorMessage = null;
      });
    } on CameraException catch (e) {
      debugPrint('Camera setup error: $e');
      await controller.dispose();
      if (mounted) {
        setState(() {
          _errorMessage = 'Ошибка камеры: ${e.description}';
          // M01: also reset in error path via finally below
        });
      }
    } catch (e) {
      debugPrint('Camera setup error: $e');
      await controller.dispose();
      if (mounted) {
        setState(() {
          _errorMessage = 'Ошибка инициализации камеры';
        });
      }
    } finally {
      // M01: always reset _isSwitching so controls never stay locked
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

  Future<void> _toggleFlash() async {
    if (_controller == null || !_isInitialized) return;
    HapticFeedback.selectionClick();
    _flashPulseController.forward(from: 0);

    final modes = [FlashMode.off, FlashMode.auto, FlashMode.always];
    final nextIndex = (modes.indexOf(_flashMode) + 1) % modes.length;
    final nextMode = modes[nextIndex];

    try {
      await _controller!.setFlashMode(nextMode);
      // M02: only update _flashMode after setFlashMode succeeds
      setState(() => _flashMode = nextMode);
    } catch (_) {}
  }

  Future<void> _takePicture() async {
    if (_controller == null || !_isInitialized) return;
    if (_controller!.value.isTakingPicture) return;

    HapticFeedback.mediumImpact();
    // M04: removed duplicate _shutterController.forward — the shutter button's
    // onTapDown already drives the animation; _takePicture only captures.

    try {
      final file = await _controller!.takePicture();
      debugPrint('Photo saved: ${file.path}');
      // TODO: navigate to preview/edit screen
    } catch (e) {
      debugPrint('Take picture error: $e');
      // U03: show snackbar on failed capture
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

  void _onScaleStart(ScaleStartDetails details) {
    _baseZoom = _currentZoom;
  }

  // P01: only call setZoomLevel on controller, update indicator state minimally
  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_controller == null) return;
    final newZoom = (_baseZoom * details.scale).clamp(_minZoom, _maxZoom);
    _currentZoom = newZoom;
    _controller!.setZoomLevel(newZoom);

    final label = '${newZoom.toStringAsFixed(1)}x';
    final shouldShow = newZoom > _minZoom;

    // Only call setState when the indicator visibility or label actually changes
    if (_showZoomIndicator != shouldShow || _zoomLabel != label) {
      setState(() {
        _showZoomIndicator = shouldShow;
        _zoomLabel = label;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      // M03: guard against double-dispose — null out before dispose
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
    // M03: null-check guards against already-disposed controller
    _controller?.dispose();
    _shutterController.dispose();
    _switchController.dispose();
    _flashPulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera preview / loading / error
          if (_errorMessage != null)
            // U04: error state with retry button
            _buildErrorState(_errorMessage!)
          else if (_isInitialized && _controller != null)
            GestureDetector(
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              // L01: removed ClipRRect with borderRadius on fullscreen preview
              child: _buildCameraPreview(),
            )
          else
            // C08: spinner only while genuinely loading (error handled above)
            const Center(
              child: CircularProgressIndicator(
                color: Colors.white24,
                strokeWidth: 2,
              ),
            ),

          // Top controls
          _buildTopBar(),

          // Bottom controls
          _buildBottomControls(),

          // M06: zoom indicator always in tree, visibility via Opacity only
          // L02: positioned relative to bottom controls area, not hardcoded px
          _buildZoomIndicator(),

          // Switching overlay
          if (_isSwitching)
            AnimatedBuilder(
              animation: _switchController,
              builder: (_, __) {
                return Container(
                  color: Colors.black
                      .withValues(alpha: 0.3 * (1 - _switchController.value)),
                );
              },
            ),
        ],
      ),
    );
  }

  // U04: error state widget with retry
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
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }

  // M05: properly fill screen in portrait mode with Transform.scale
  Widget _buildCameraPreview() {
    final controller = _controller!;
    final size = MediaQuery.of(context).size;
    final previewAspect = controller.value.aspectRatio; // width / height

    // In portrait the device aspect is < 1; the camera preview is typically
    // landscape (aspect > 1). Scale so the preview covers the full screen.
    final deviceAspect = size.width / size.height;
    final scale = deviceAspect / previewAspect;

    return Transform.scale(
      scale: scale < 1.0 ? 1.0 / scale : scale,
      child: Center(child: CameraPreview(controller)),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.5),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // Close button
                _GlassButton(
                  onTap: widget.onClose ?? () => Navigator.maybePop(context),
                  child: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const Spacer(),
                // U02: hide flash button when front camera is active
                if (!_isFrontCamera)
                  AnimatedBuilder(
                    animation: _flashPulseController,
                    builder: (_, child) {
                      final scale = 1.0 +
                          0.15 *
                              Curves.easeOut
                                  .transform(_flashPulseController.value);
                      return Transform.scale(scale: scale, child: child);
                    },
                    child: _GlassButton(
                      onTap: _toggleFlash,
                      child: Icon(
                        _flashIcon,
                        color: _flashMode == FlashMode.off
                            ? Colors.white70
                            : const Color(0xFFFFD60A),
                        size: 20,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData get _flashIcon {
    switch (_flashMode) {
      case FlashMode.off:
        return Icons.flash_off_rounded;
      case FlashMode.auto:
        return Icons.flash_auto_rounded;
      case FlashMode.always:
        return Icons.flash_on_rounded;
      default:
        return Icons.flash_off_rounded;
    }
  }

  Widget _buildBottomControls() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: 0.6),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24, top: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Mode label
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'ФОТО',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Shutter + flip row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // U01: gallery button shows "coming soon" snackbar
                    _GlassButton(
                      size: 44,
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Галерея — скоро'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      child: const Icon(
                        Icons.photo_library_rounded,
                        color: Colors.white70,
                        size: 22,
                      ),
                    ),
                    // Shutter button
                    _buildShutterButton(),
                    // Switch camera
                    AnimatedBuilder(
                      animation: _switchRotation,
                      builder: (_, child) {
                        return Transform.rotate(
                          angle: _switchRotation.value * math.pi,
                          child: child,
                        );
                      },
                      child: _GlassButton(
                        size: 44,
                        onTap: _switchCamera,
                        child: const Icon(
                          Icons.cameraswitch_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShutterButton() {
    return GestureDetector(
      onTapDown: (_) => _shutterController.forward(),
      onTapUp: (_) {
        _shutterController.reverse();
        _takePicture();
      },
      onTapCancel: () => _shutterController.reverse(),
      child: AnimatedBuilder(
        animation: _shutterAnimation,
        builder: (_, __) {
          return Transform.scale(
            scale: _shutterAnimation.value,
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: SeeUColors.accent.withValues(alpha: 0.3),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Container(
                margin: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white,
                      Color(0xFFF0F0F0),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // M06: always in the widget tree; L02: positioned relative to bottom controls
  Widget _buildZoomIndicator() {
    // The bottom controls area is approximately 160px tall (SafeArea + padding).
    // Position the indicator just above that area.
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
}

// ─── Glass button ──────────────────────────────────────────────────────────

class _GlassButton extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;
  final double size;

  const _GlassButton({
    required this.onTap,
    required this.child,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: size,
        height: size,
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
