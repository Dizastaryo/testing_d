import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show NetworkAssetBundle;

import 'mask_catalog.dart' show MaskDescriptor, maskCurrentTrackedFace, FaceFrame;

/// CustomPainter for AI-generated PNG masks — renders image over face,
/// now tracking real landmarks with rotation and scale.
class ImageMaskPainter extends CustomPainter {
  final String url;
  ImageMaskPainter(this.url) : super(repaint: _imageCache.repaintNotifier);

  static final _imageCache = _ImageCache();

  @override
  void paint(Canvas canvas, Size size) {
    final image = _imageCache.get(url);
    if (image == null) {
      _imageCache.load(url);
      return;
    }

    final f = FaceFrame.fromSize(size);
    canvas.save();
    f.applyRotation(canvas);

    // AI mask covers face with 1.4x padding
    var w = f.faceWidth * 1.4;
    var h = f.faceHeight * 1.4;

    final imgRatio = image.width / image.height;
    final boxRatio = w / h;
    if (imgRatio > boxRatio) {
      h = w / imgRatio;
    } else {
      w = h * imgRatio;
    }

    // Apply pseudo-3D yaw compression
    w *= f.yawScale;

    final dst = Rect.fromCenter(center: f.center, width: w, height: h);
    final src =
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    canvas.drawImageRect(image, src, dst, Paint());
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ImageMaskPainter old) =>
      old.url != url || maskCurrentTrackedFace != null;
}

class _ImageCache {
  final Map<String, ui.Image?> _cache = {};
  final ValueNotifier<int> repaintNotifier = ValueNotifier<int>(0);

  ui.Image? get(String url) => _cache[url];

  void load(String url) {
    if (_cache.containsKey(url)) return;
    _cache[url] = null;
    _fetch(url);
  }

  Future<void> _fetch(String url) async {
    try {
      final bytes = await NetworkAssetBundle(Uri.parse(url)).load(url);
      final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      _cache[url] = frame.image;
      repaintNotifier.value = repaintNotifier.value + 1;
    } catch (_) {
      _cache.remove(url);
    }
  }
}

MaskDescriptor aiMaskDescriptor({
  required String id,
  required String label,
  required String imageUrl,
}) {
  return MaskDescriptor(
    id: 'ai_$id',
    label: label,
    previewIcon: Icons.auto_awesome,
    painter: () => ImageMaskPainter(imageUrl),
  );
}
