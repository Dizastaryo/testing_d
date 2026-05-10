import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show NetworkAssetBundle;

import 'mask_catalog.dart' show MaskDescriptor, maskCurrentTrackedFace;

/// CustomPainter для AI-маски (PNG из бэка) — рисует image над предполагаемым
/// лицом. Если face-tracking активен — кадрируется по реальному boundingBox,
/// иначе — heuristic top-half preview'а.
///
/// Image грузится один раз и кешируется в `_imageCache` по URL. На первой
/// отрисовке без image маска не рендерится (вернётся следующий frame).
class ImageMaskPainter extends CustomPainter {
  final String url;
  ImageMaskPainter(this.url) : super(repaint: _imageCache.repaintNotifier);

  static final _imageCache = _ImageCache();

  @override
  void paint(Canvas canvas, Size size) {
    final image = _imageCache.get(url);
    if (image == null) {
      // Trigger lazy load.
      _imageCache.load(url);
      return;
    }
    // Face-frame: либо real-trackedface, либо heuristic.
    final face = maskCurrentTrackedFace;
    double cx, cy, w, h;
    if (face != null) {
      final r = face.boundingBoxRelative;
      cx = (1.0 - (r.left + r.width / 2)) * size.width;
      cy = (r.top + r.height / 2) * size.height;
      // AI-маска покрывает лицо + немного шире. 1.4× от лица — комфортный padding.
      w = r.width * size.width * 1.4;
      h = r.height * size.height * 1.4;
    } else {
      cx = size.width / 2;
      cy = size.height * 0.42;
      w = size.width * 0.65;
      h = size.height * 0.42;
    }
    final imgRatio = image.width / image.height;
    final boxRatio = w / h;
    if (imgRatio > boxRatio) {
      h = w / imgRatio;
    } else {
      w = h * imgRatio;
    }
    final dst = Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);
    final src = Rect.fromLTWH(
        0, 0, image.width.toDouble(), image.height.toDouble());
    canvas.drawImageRect(image, src, dst, Paint());
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
    if (_cache.containsKey(url)) return; // уже в работе или загружено
    _cache[url] = null;
    _fetch(url);
  }

  Future<void> _fetch(String url) async {
    try {
      final bytes = await NetworkAssetBundle(Uri.parse(url)).load(url);
      final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      _cache[url] = frame.image;
      // Notify all listening CustomPainter'ов через counter-bump.
      repaintNotifier.value = repaintNotifier.value + 1;
    } catch (_) {
      _cache.remove(url); // дать шанс retry при следующем load
    }
  }
}

/// Хелпер: создаёт `MaskDescriptor` для AI-маски — её painter рисует
/// загруженный PNG над face-frame.
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
