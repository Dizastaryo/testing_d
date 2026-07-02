import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/design/tokens.dart';
import '../decorations/decoration_item.dart';
import '../decorations/decoration_picker.dart';
import '../presets/camera_preset.dart';
import '../presets/preset_picker_bar.dart';
import 'camera_record_button.dart';

// Unified glass constants (keep in sync with camera_top_bar.dart)
const double _kPanelBlur = 28.0;
const double _kPanelBorder = 0.09;

/// Hard recording cap for video capture.
const int kMaxVideoSeconds = 30 * 60;

/// Story max: enforced at publish time, not during capture.
const int kStoryMaxVideoSeconds = 60;

enum CameraMode { photo, video }

extension CameraModeExt on CameraMode {
  String get label {
    switch (this) {
      case CameraMode.photo: return 'ФОТО';
      case CameraMode.video: return 'ВИДЕО';
    }
  }

  bool get isVideoMode => this == CameraMode.video;

  double get maxSeconds {
    switch (this) {
      case CameraMode.photo: return 0;
      case CameraMode.video: return kMaxVideoSeconds.toDouble();
    }
  }
}

/// Нижняя область камеры — glassmorphism панель с controls.
class CameraBottomPanel extends StatelessWidget {
  final bool isRecording;
  final double totalPct;
  final double totalWithCurrent;
  final bool showDecorationPicker;
  final String? selectedDecorationId;
  final Set<String> savedDecorationIds;
  final Uint8List? galleryThumbnailBytes;
  final bool hasSegments;
  final bool showPresetPicker;
  final CameraPreset activePreset;

  final VoidCallback onPickGallery;
  final VoidCallback onTakePicture;
  final VoidCallback onRecordStart;
  final VoidCallback onRecordStop;
  final ValueChanged<DecorationItem?> onDecorationChanged;
  final ValueChanged<String> onToggleSaveDecoration;
  final VoidCallback onToggleDecorationPicker;
  final VoidCallback onTogglePresets;
  final VoidCallback onUndo;
  final ValueChanged<CameraPreset> onPresetSelected;

  const CameraBottomPanel({
    super.key,
    required this.isRecording,
    required this.totalPct,
    required this.totalWithCurrent,
    required this.showDecorationPicker,
    required this.selectedDecorationId,
    required this.savedDecorationIds,
    required this.galleryThumbnailBytes,
    required this.hasSegments,
    required this.showPresetPicker,
    required this.activePreset,
    required this.onPickGallery,
    required this.onTakePicture,
    required this.onRecordStart,
    required this.onRecordStop,
    required this.onDecorationChanged,
    required this.onToggleSaveDecoration,
    required this.onToggleDecorationPicker,
    required this.onTogglePresets,
    required this.onUndo,
    required this.onPresetSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: _kPanelBlur, sigmaY: _kPanelBlur),
          child: Container(
            decoration: BoxDecoration(
              // Glassmorphism: стеклянная панель (backdrop-blur выше по дереву)
              // + мягкий градиент + светлый бордюр сверху. Единый стиль с
              // верхней панелью, кнопками и полосами пикеров.
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.10),
                  Colors.black.withValues(alpha: 0.32),
                ],
              ),
              border: Border(
                top: BorderSide(
                  color: Colors.white.withValues(alpha: _kPanelBorder),
                  width: 0.5,
                ),
              ),
            ),
            child: GestureDetector(
              onVerticalDragEnd: (details) {
                if ((details.primaryVelocity ?? 0) < -300) onPickGallery();
              },
              behavior: HitTestBehavior.deferToChild,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Preset / Mask picker strips (animated collapse).
                      _GlassStrip(
                        visible: showPresetPicker,
                        child: PresetPickerBar(
                          activePreset: activePreset,
                          onPresetSelected: onPresetSelected,
                        ),
                      ),
                      _GlassStrip(
                        visible: showDecorationPicker,
                        child: DecorationPicker(
                          allItems: DecorationCatalog.all
                              .where((i) => i.category == DecorationCategory.mask)
                              .toList(),
                          savedIds: savedDecorationIds,
                          selectedId: selectedDecorationId,
                          onChanged: onDecorationChanged,
                          onToggleSave: onToggleSaveDecoration,
                        ),
                      ),

                      const SizedBox(height: 4),

                      // REC timer pill (hidden when not recording).
                      SizedBox(
                        height: 20,
                        child: isRecording
                            ? _RecordingIndicator(elapsed: totalWithCurrent)
                            : const SizedBox.shrink(),
                      ),

                      const SizedBox(height: 6),

                      // Record row: [Gallery] [Shutter] [Effects/Undo]
                      _RecordRow(
                        isRecording: isRecording,
                        totalPct: totalPct,
                        galleryThumbnailBytes: galleryThumbnailBytes,
                        hasSegments: hasSegments,
                        showPresetPicker: showPresetPicker,
                        presetActive: !activePreset.isNone,
                        onPickGallery: onPickGallery,
                        onTakePicture: onTakePicture,
                        onRecordStart: onRecordStart,
                        onRecordStop: onRecordStop,
                        onTogglePresets: onTogglePresets,
                        onUndo: onUndo,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
    );
  }
}

// ── Glass strip wrapper for pickers ──────────────────────────────────────────

class _GlassStrip extends StatelessWidget {
  final bool visible;
  final Widget child;
  const _GlassStrip({required this.visible, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedAlign(
        alignment: Alignment.topCenter,
        heightFactor: visible ? 1.0 : 0.0,
        duration: SeeUMotion.normal,
        curve: SeeUMotion.smooth,
        child: AnimatedOpacity(
          opacity: visible ? 1.0 : 0.0,
          duration: SeeUMotion.quick,
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(
                    sigmaX: _kPanelBlur, sigmaY: _kPanelBlur),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  decoration: BoxDecoration(
                    // Настоящее стекло: blur + мягкий вертикальный градиент +
                    // светлый бордюр — полоса читается как парящая карточка.
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.12),
                        Colors.black.withValues(alpha: 0.30),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.16),
                      width: 0.7,
                    ),
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Record row ───────────────────────────────────────────────────────────────

class _RecordRow extends StatelessWidget {
  final bool isRecording;
  final double totalPct;
  final Uint8List? galleryThumbnailBytes;
  final bool hasSegments;
  final bool showPresetPicker;
  final bool presetActive;
  final VoidCallback onPickGallery;
  final VoidCallback onTakePicture;
  final VoidCallback onRecordStart;
  final VoidCallback onRecordStop;
  final VoidCallback onTogglePresets;
  final VoidCallback onUndo;

  const _RecordRow({
    required this.isRecording,
    required this.totalPct,
    required this.galleryThumbnailBytes,
    required this.hasSegments,
    required this.showPresetPicker,
    required this.presetActive,
    required this.onPickGallery,
    required this.onTakePicture,
    required this.onRecordStart,
    required this.onRecordStop,
    required this.onTogglePresets,
    required this.onUndo,
  });

  @override
  Widget build(BuildContext context) {
    final showUndo = hasSegments && !isRecording;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _GalleryButton(
            thumbnailBytes: galleryThumbnailBytes,
            onTap: onPickGallery,
          ),

          CameraRecordButton(
            isRecording: isRecording,
            totalPct: totalPct,
            onTap: onTakePicture,
            onRecordStart: onRecordStart,
            onRecordStop: onRecordStop,
          ),

          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, anim) => ScaleTransition(
              scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: showUndo
                ? _UndoButton(key: const ValueKey('undo'), onTap: onUndo)
                : _EffectsButton(
                    key: const ValueKey('effects'),
                    active: showPresetPicker || presetActive,
                    onTap: onTogglePresets,
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────

class _GalleryButton extends StatefulWidget {
  final Uint8List? thumbnailBytes;
  final VoidCallback onTap;

  const _GalleryButton({required this.thumbnailBytes, required this.onTap});

  @override
  State<_GalleryButton> createState() => _GalleryButtonState();
}

class _GalleryButtonState extends State<_GalleryButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _tap;

  @override
  void initState() {
    super.initState();
    _tap = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 110),
    );
  }

  @override
  void dispose() {
    _tap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _tap.forward(),
      onTapUp: (_) {
        _tap.reverse();
        widget.onTap();
      },
      onTapCancel: () => _tap.reverse(),
      child: AnimatedBuilder(
        animation: _tap,
        builder: (_, child) => Transform.scale(
          scale: 1.0 - 0.08 * _tap.value,
          child: child,
        ),
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: widget.thumbnailBytes == null
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFFB37A), Color(0xFFC0436A)],
                  )
                : null,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.60),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: widget.thumbnailBytes != null
              ? Hero(
                  tag: 'media_prepare_preview',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12.5),
                    child: Image.memory(
                      widget.thumbnailBytes!,
                      fit: BoxFit.cover,
                      width: 50,
                      height: 50,
                    ),
                  ),
                )
              : const Center(
                  child: Icon(PhosphorIconsRegular.images,
                      color: Colors.white, size: 21),
                ),
        ),
      ),
    );
  }
}

// Glass circle button: undo last segment.
class _UndoButton extends StatefulWidget {
  final VoidCallback onTap;
  const _UndoButton({super.key, required this.onTap});

  @override
  State<_UndoButton> createState() => _UndoButtonState();
}

class _UndoButtonState extends State<_UndoButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _tap;

  @override
  void initState() {
    super.initState();
    _tap = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 110),
    );
  }

  @override
  void dispose() {
    _tap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _tap.forward(),
      onTapUp: (_) {
        _tap.reverse();
        widget.onTap();
      },
      onTapCancel: () => _tap.reverse(),
      child: AnimatedBuilder(
        animation: _tap,
        builder: (_, child) => Transform.scale(
          scale: 1.0 - 0.08 * _tap.value,
          child: child,
        ),
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.24),
              width: 0.8,
            ),
          ),
          alignment: Alignment.center,
          child: Icon(
            PhosphorIconsRegular.arrowCounterClockwise,
            color: Colors.white.withValues(alpha: 0.90),
            size: 22,
          ),
        ),
      ),
    );
  }
}

// Glass circle button: toggle effects / presets.
class _EffectsButton extends StatefulWidget {
  final bool active;
  final VoidCallback onTap;
  const _EffectsButton({super.key, required this.active, required this.onTap});

  @override
  State<_EffectsButton> createState() => _EffectsButtonState();
}

class _EffectsButtonState extends State<_EffectsButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _tap;

  @override
  void initState() {
    super.initState();
    _tap = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 110),
    );
  }

  @override
  void dispose() {
    _tap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _tap.forward(),
      onTapUp: (_) {
        _tap.reverse();
        widget.onTap();
      },
      onTapCancel: () => _tap.reverse(),
      child: AnimatedBuilder(
        animation: _tap,
        builder: (_, child) => Transform.scale(
          scale: 1.0 - 0.08 * _tap.value,
          child: child,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: widget.active
                ? SeeUColors.accent.withValues(alpha: 0.22)
                : Colors.white.withValues(alpha: 0.10),
            shape: BoxShape.circle,
            border: Border.all(
              color: widget.active
                  ? SeeUColors.accent.withValues(alpha: 0.65)
                  : Colors.white.withValues(alpha: 0.22),
              width: 0.8,
            ),
            boxShadow: widget.active
                ? [
                    BoxShadow(
                      color: SeeUColors.accent.withValues(alpha: 0.28),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: Icon(
              widget.active
                  ? PhosphorIconsFill.sparkle
                  : PhosphorIconsRegular.sparkle,
              key: ValueKey(widget.active),
              color: widget.active
                  ? SeeUColors.accent
                  : Colors.white.withValues(alpha: 0.90),
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Recording indicator ───────────────────────────────────────────────────────

class _RecordingIndicator extends StatefulWidget {
  final double elapsed;
  const _RecordingIndicator({required this.elapsed});

  @override
  State<_RecordingIndicator> createState() => _RecordingIndicatorState();
}

class _RecordingIndicatorState extends State<_RecordingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink;

  @override
  void initState() {
    super.initState();
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final secs = widget.elapsed.floor();
    final mins = secs ~/ 60;
    final rem = secs % 60;
    final timeStr = '${mins.toString().padLeft(2, '0')}:'
        '${rem.toString().padLeft(2, '0')}';
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(SeeURadii.pill),
          border: Border.all(
            color: const Color(0xFFFF3B30).withValues(alpha: 0.45),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FadeTransition(
              opacity: Tween<double>(begin: 0.30, end: 1.0).animate(_blink),
              child: Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFFFF3B30),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'REC $timeStr',
              style: const TextStyle(
                fontFamily: 'JetBrains Mono',
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
