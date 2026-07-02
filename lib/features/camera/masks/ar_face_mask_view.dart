import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'mask_catalog.dart';

/// Handle for triggering actions on a live [ARFaceMaskView] from outside —
/// e.g. capturing a still frame (camera feed + 3D mask composited natively).
class ARFaceMaskController {
  MethodChannel? _channel;

  void _attach(MethodChannel channel) => _channel = channel;
  void _detach(MethodChannel channel) {
    if (identical(_channel, channel)) _channel = null;
  }

  bool get isReady => _channel != null;

  /// Capture the current AR frame (camera + mask) as JPEG bytes.
  /// Returns null if the native view isn't ready or capture failed.
  Future<Uint8List?> captureSnapshot() async {
    final channel = _channel;
    if (channel == null) return null;
    try {
      return await channel.invokeMethod<Uint8List>('captureSnapshot');
    } catch (e) {
      debugPrint('[ARFaceMask] captureSnapshot failed: $e');
      return null;
    }
  }
}

/// Native AR face mask view using ARKit (iOS) / ARCore (Android).
///
/// Loads a .glb 3D model, auto-normalizes it (bounding-box center + scale to
/// face width), then applies [MaskAnchor]-based positioning and per-mask
/// [MaskTransform] fine-tuning. The model follows head rotation in full 360
/// degrees with occlusion (parts behind the head are hidden).
class ARFaceMaskView extends StatefulWidget {
  final MaskDescriptor mask;

  /// Called when the AR session encounters an error.
  final ValueChanged<String>? onError;

  /// Whether to use the front camera (default: true).
  final bool useFrontCamera;

  /// Optional handle for capturing snapshots of the live AR scene.
  final ARFaceMaskController? controller;

  const ARFaceMaskView({
    super.key,
    required this.mask,
    this.onError,
    this.useFrontCamera = true,
    this.controller,
  });

  @override
  State<ARFaceMaskView> createState() => _ARFaceMaskViewState();
}

class _ARFaceMaskViewState extends State<ARFaceMaskView> {
  MethodChannel? _channel;
  bool _ready = false;
  String? _error;

  @override
  void didUpdateWidget(ARFaceMaskView old) {
    super.didUpdateWidget(old);
    if (old.mask.id != widget.mask.id) {
      _channel?.invokeMethod('loadMask', widget.mask.toCreationParams(
        useFrontCamera: widget.useFrontCamera,
      ));
    }
  }

  void _onPlatformViewCreated(int viewId) {
    final channel = MethodChannel('seeu/ar_face_mask_$viewId');
    _channel = channel;
    channel.setMethodCallHandler(_handleMethodCall);
    widget.controller?._attach(channel);
  }

  @override
  void dispose() {
    if (_channel != null) widget.controller?._detach(_channel!);
    super.dispose();
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onReady':
        if (mounted) setState(() => _ready = true);
      case 'onError':
        final msg = call.arguments as String? ?? 'Unknown AR error';
        debugPrint('[ARFaceMask] Error: $msg');
        widget.onError?.call(msg);
        if (mounted) setState(() => _error = msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const Center(
        child: Text('AR masks not supported on web',
            style: TextStyle(color: Colors.white54)),
      );
    }

    final creationParams = widget.mask.toCreationParams(
      useFrontCamera: widget.useFrontCamera,
    );

    Widget? platformView;

    if (Platform.isIOS) {
      platformView = UiKitView(
        viewType: 'seeu/ar_face_mask',
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
      );
    } else if (Platform.isAndroid) {
      platformView = AndroidView(
        viewType: 'seeu/ar_face_mask',
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
      );
    }

    if (platformView == null) {
      return const Center(
        child: Text('AR masks not supported on this platform',
            style: TextStyle(color: Colors.white54)),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        platformView,
        // Loading indicator while AR initializes
        if (!_ready && _error == null)
          const Center(
            child: CircularProgressIndicator(
              color: Colors.white24,
              strokeWidth: 2,
            ),
          ),
        // Error overlay
        if (_error != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ),
          ),
      ],
    );
  }
}
