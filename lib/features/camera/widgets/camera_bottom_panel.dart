import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/design/tokens.dart';
import '../decorations/decoration_item.dart';
import '../decorations/decoration_picker.dart';
import '../presets/camera_preset.dart';
import '../presets/preset_picker_bar.dart';
import 'camera_record_button.dart';

enum CameraMode { photo, sec15, sec60, min3 }

extension CameraModeExt on CameraMode {
  String get label {
    switch (this) {
      case CameraMode.photo: return 'ФОТО';
      case CameraMode.sec15: return '15 с';
      case CameraMode.sec60: return '60 с';
      case CameraMode.min3:  return '3 мин';
    }
  }

  bool get isVideoMode => this != CameraMode.photo;

  double get maxSeconds {
    switch (this) {
      case CameraMode.photo: return 0;
      case CameraMode.sec15: return 15.0;
      case CameraMode.sec60: return 60.0;
      case CameraMode.min3:  return 180.0;
    }
  }
}

/// Нижняя область камеры:
/// - DecorationPicker (показывается/скрывается)
/// - Mode tabs (ФОТО / 15 с / 60 с / 3 мин)
/// - Record row: [Галерея] [Кнопка съёмки] [Undo/Deco]
class CameraBottomPanel extends StatelessWidget {
  // State
  final CameraMode cameraMode;
  final bool isRecording;
  final double totalPct;
  final double totalWithCurrent;
  final bool showDecorationPicker;
  final String? selectedDecorationId;
  final Set<String> savedDecorationIds;
  final Uint8List? galleryThumbnailBytes;
  final bool hasSegments;

  // Preset state
  final bool showPresetPicker;
  final CameraPreset activePreset;
  final Uint8List? presetSnapshotBytes;

  // Callbacks
  final ValueChanged<CameraMode> onModeChanged;
  final VoidCallback onPickGallery;
  final VoidCallback onTakePicture;
  final VoidCallback onStartRecording;
  final VoidCallback onStopRecording;
  final ValueChanged<DecorationItem?> onDecorationChanged;
  final ValueChanged<String> onToggleSaveDecoration;
  final VoidCallback onToggleDecorationPicker;
  final VoidCallback onUndo;
  final ValueChanged<CameraPreset> onPresetSelected;

  const CameraBottomPanel({
    super.key,
    required this.cameraMode,
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
    this.presetSnapshotBytes,
    required this.onModeChanged,
    required this.onPickGallery,
    required this.onTakePicture,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onDecorationChanged,
    required this.onToggleSaveDecoration,
    required this.onToggleDecorationPicker,
    required this.onUndo,
    required this.onPresetSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: GestureDetector(
        onVerticalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) < -300) onPickGallery();
        },
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              stops: [0.0, 0.6, 1.0],
              colors: [Colors.black, Color(0xCC000000), Colors.transparent],
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Preset picker (animated)
                AnimatedSize(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOut,
                  child: showPresetPicker
                      ? AnimatedOpacity(
                          opacity: showPresetPicker ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 200),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
                            child: PresetPickerBar(
                              activePreset: activePreset,
                              snapshotBytes: presetSnapshotBytes,
                              onPresetSelected: onPresetSelected,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),

                // Mask decoration picker (animated)
                AnimatedSize(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOut,
                  child: showDecorationPicker
                      ? AnimatedOpacity(
                          opacity: showDecorationPicker ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 200),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
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
                        )
                      : const SizedBox.shrink(),
                ),

                const SizedBox(height: 10),

                // Mode tabs
                _ModeTabBar(
                  currentMode: cameraMode,
                  onChanged: onModeChanged,
                ),

                const SizedBox(height: 16),

                // Record row
                _RecordRow(
                  cameraMode: cameraMode,
                  isRecording: isRecording,
                  totalPct: totalPct,
                  totalWithCurrent: totalWithCurrent,
                  galleryThumbnailBytes: galleryThumbnailBytes,
                  hasSegments: hasSegments,
                  showDecorationPicker: showDecorationPicker,
                  selectedDecorationId: selectedDecorationId,
                  onPickGallery: onPickGallery,
                  onTakePicture: onTakePicture,
                  onStartRecording: onStartRecording,
                  onStopRecording: onStopRecording,
                  onToggleDecorationPicker: onToggleDecorationPicker,
                  onUndo: onUndo,
                ),

                const SizedBox(height: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Mode tab bar ─────────────────────────────────────────────────────────────

class _ModeTabBar extends StatelessWidget {
  final CameraMode currentMode;
  final ValueChanged<CameraMode> onChanged;

  const _ModeTabBar({required this.currentMode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final modes = CameraMode.values;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < modes.length; i++) ...[
          if (i > 0) const SizedBox(width: 24),
          _ModeTab(
            label: modes[i].label,
            active: currentMode == modes[i],
            onTap: () => onChanged(modes[i]),
          ),
        ],
      ],
    );
  }
}

class _ModeTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ModeTab({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            style: TextStyle(
              color: active ? Colors.white : Colors.white54,
              fontSize: active ? 14.5 : 13,
              fontWeight: active ? FontWeight.w800 : FontWeight.w500,
              letterSpacing: active ? 0.2 : 0,
            ),
            child: Text(label),
          ),
          const SizedBox(height: 3),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            height: 2.5,
            width: active ? 20 : 0,
            decoration: BoxDecoration(
              color: SeeUColors.accent,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Record row ───────────────────────────────────────────────────────────────

class _RecordRow extends StatelessWidget {
  final CameraMode cameraMode;
  final bool isRecording;
  final double totalPct;
  final double totalWithCurrent;
  final Uint8List? galleryThumbnailBytes;
  final bool hasSegments;
  final bool showDecorationPicker;
  final String? selectedDecorationId;
  final VoidCallback onPickGallery;
  final VoidCallback onTakePicture;
  final VoidCallback onStartRecording;
  final VoidCallback onStopRecording;
  final VoidCallback onToggleDecorationPicker;
  final VoidCallback onUndo;

  const _RecordRow({
    required this.cameraMode,
    required this.isRecording,
    required this.totalPct,
    required this.totalWithCurrent,
    required this.galleryThumbnailBytes,
    required this.hasSegments,
    required this.showDecorationPicker,
    required this.selectedDecorationId,
    required this.onPickGallery,
    required this.onTakePicture,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onToggleDecorationPicker,
    required this.onUndo,
  });

  @override
  Widget build(BuildContext context) {
    final isPhotoMode = !cameraMode.isVideoMode;
    final showUndo = hasSegments || isRecording;
    final captureState = isPhotoMode
        ? CaptureButtonState.photoReady
        : isRecording
            ? CaptureButtonState.recording
            : CaptureButtonState.videoReady;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // REC indicator
        AnimatedOpacity(
          opacity: isRecording && !isPhotoMode ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 220),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: isRecording && !isPhotoMode
                ? _RecordingIndicator(elapsed: totalWithCurrent)
                : const SizedBox.shrink(),
          ),
        ),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Gallery button
            _GalleryButton(
              thumbnailBytes: galleryThumbnailBytes,
              onTap: onPickGallery,
            ),

            const SizedBox(width: 28),

            // Record / Shutter
            CameraRecordButton(
              state: captureState,
              totalPct: totalPct,
              onTap: isPhotoMode
                  ? onTakePicture
                  : isRecording
                      ? onStopRecording
                      : onStartRecording,
            ),

            const SizedBox(width: 28),

            // Undo or Decoration toggle
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) => ScaleTransition(
                scale: anim,
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: showUndo
                  ? _UndoButton(key: const ValueKey('undo'), onTap: onUndo)
                  : _DecoButton(
                      key: const ValueKey('deco'),
                      active: showDecorationPicker || selectedDecorationId != null,
                      onTap: onToggleDecorationPicker,
                    ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Helper widgets ───────────────────────────────────────────────────────────

class _GalleryButton extends StatelessWidget {
  final Uint8List? thumbnailBytes;
  final VoidCallback onTap;

  const _GalleryButton({required this.thumbnailBytes, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(
                alpha: thumbnailBytes != null ? 0.55 : 0.28),
            width: thumbnailBytes != null ? 2.0 : 1.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10.5),
          child: thumbnailBytes != null
              ? Image.memory(
                  thumbnailBytes!,
                  fit: BoxFit.cover,
                  width: 56,
                  height: 56,
                )
              : Container(
                  color: Colors.white.withValues(alpha: 0.12),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(PhosphorIconsRegular.images,
                          color: Colors.white, size: 22),
                      const SizedBox(height: 2),
                      Icon(PhosphorIconsRegular.arrowUp,
                          color: Colors.white.withValues(alpha: 0.45), size: 10),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _UndoButton extends StatelessWidget {
  final VoidCallback onTap;
  const _UndoButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.28),
            width: 1.5,
          ),
        ),
        alignment: Alignment.center,
        child: const Icon(PhosphorIconsRegular.arrowCounterClockwise,
            color: Colors.white, size: 24),
      ),
    );
  }
}

class _DecoButton extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  const _DecoButton({super.key, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: active
              ? SeeUColors.accent.withValues(alpha: 0.20)
              : Colors.white.withValues(alpha: 0.12),
          shape: BoxShape.circle,
          border: Border.all(
            color: active
                ? SeeUColors.accent
                : Colors.white.withValues(alpha: 0.28),
            width: 1.5,
          ),
        ),
        alignment: Alignment.center,
        child: Icon(
          active ? PhosphorIconsFill.smileySticker : PhosphorIconsRegular.smileySticker,
          color: active ? SeeUColors.accent : Colors.white,
          size: 26,
        ),
      ),
    );
  }
}

class _RecordingIndicator extends StatelessWidget {
  final double elapsed;
  const _RecordingIndicator({required this.elapsed});

  @override
  Widget build(BuildContext context) {
    final secs = elapsed.floor();
    final mins = secs ~/ 60;
    final rem = secs % 60;
    final timeStr = '${mins.toString().padLeft(2, '0')}:'
        '${rem.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: Color(0xFFFF3B30),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            'REC $timeStr',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
