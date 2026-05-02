import 'dart:math' as math;
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
  double _currentZoom = 1.0;
  double _baseZoom = 1.0;
  double _maxZoom = 1.0;
  double _minZoom = 1.0;
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

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;
      await _setupCamera(_getFrontCamera() ?? _cameras.first);
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
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

      await prev?.dispose();

      if (!mounted) {
        controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _isInitialized = true;
        _isSwitching = false;
      });
    } catch (e) {
      debugPrint('Camera setup error: $e');
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
    _flashMode = modes[nextIndex];

    try {
      await _controller!.setFlashMode(_flashMode);
      setState(() {});
    } catch (_) {}
  }

  Future<void> _takePicture() async {
    if (_controller == null || !_isInitialized) return;
    if (_controller!.value.isTakingPicture) return;

    HapticFeedback.mediumImpact();
    _shutterController.forward().then((_) => _shutterController.reverse());

    try {
      final file = await _controller!.takePicture();
      debugPrint('Photo saved: ${file.path}');
      // TODO: navigate to preview/edit screen
    } catch (e) {
      debugPrint('Take picture error: $e');
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    _baseZoom = _currentZoom;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_controller == null) return;
    final newZoom = (_baseZoom * details.scale).clamp(_minZoom, _maxZoom);
    _currentZoom = newZoom;
    _controller!.setZoomLevel(newZoom);
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
      _controller = null;
      setState(() => _isInitialized = false);
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
          // Camera preview
          if (_isInitialized && _controller != null)
            GestureDetector(
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: _buildCameraPreview(),
              ),
            )
          else
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

          // Zoom indicator
          if (_currentZoom > _minZoom) _buildZoomIndicator(),

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

  Widget _buildCameraPreview() {
    final controller = _controller!;
    final size = MediaQuery.of(context).size;

    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: size.width,
        height: size.width / controller.value.aspectRatio,
        child: CameraPreview(controller),
      ),
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
                // Flash toggle
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
                    // Gallery placeholder
                    _GlassButton(
                      size: 44,
                      onTap: () {},
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

  Widget _buildZoomIndicator() {
    return Positioned(
      bottom: 180,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedOpacity(
          opacity: _currentZoom > _minZoom ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '${_currentZoom.toStringAsFixed(1)}x',
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
