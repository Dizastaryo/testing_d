import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/design/tokens.dart';
import '../decorations/decoration_item.dart';
import '../decorations/decoration_picker.dart';
import 'camera_record_button.dart';

// ── CameraMode enum (must match the one in camera_screen.dart) ──────────────
// Ре-экспортируем через typedef чтобы избежать дублирования.
// camera_bottom_panel.dart принимает _CameraBottomMode чтобы не зависеть от
// самого camera_screen.dart при компиляции виджета отдельно.

enum CameraBottomMode { photo, video, story, reel }

extension CameraBottomModeExt on CameraBottomMode {
  String get label {
    switch (this) {
      case CameraBottomMode.photo:   return 'Фото';
      case CameraBottomMode.video:   return 'Видео';
      case CameraBottomMode.story:   return 'История';
      case CameraBottomMode.reel:    return 'Рилс';
    }
  }

  bool get isVideoMode => this != CameraBottomMode.photo;

  double get maxSeconds {
    switch (this) {
      case CameraBottomMode.photo:  return 0;
      case CameraBottomMode.story:  return 15.0;
      case CameraBottomMode.video:
      case CameraBottomMode.reel:   return 60.0;
    }
  }
}

/// Нижняя область камеры:
/// - DecorationPicker (показывается/скрывается)
/// - Mode tabs (Фото / Видео / История / Рилс)
/// - Record row: [Галерея] [Кнопка съёмки] [Undo/Deco]
class CameraBottomPanel extends StatelessWidget {
  // State
  final CameraBottomMode cameraMode;
  final bool isRecording;
  final double totalPct;
  final double totalWithCurrent;
  final bool showDecorationPicker;
  final String? selectedDecorationId;
  final Set<String> savedDecorationIds;
  final Uint8List? galleryThumbnailBytes;
  final bool hasSegments;

  // Callbacks
  final ValueChanged<CameraBottomMode> onModeChanged;
  final VoidCallback onPickGallery;
  final VoidCallback onTakePicture;
  final VoidCallback onStartRecording;
  final VoidCallback onStopRecording;
  final ValueChanged<DecorationItem?> onDecorationChanged;
  final ValueChanged<String> onToggleSaveDecoration;
  final VoidCallback onToggleDecorationPicker;
  final VoidCallback onUndo;

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
    required this.onModeChanged,
    required this.onPickGallery,
    required this.onTakePicture,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onDecorationChanged,
    required this.onToggleSaveDecoration,
    required this.onToggleDecorationPicker,
    required this.onUndo,
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
                // Decoration picker (animated)
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
                              allItems: DecorationCatalog.all,
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
  final CameraBottomMode currentMode;
  final ValueChanged<CameraBottomMode> onChanged;

  const _ModeTabBar({required this.currentMode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final modes = CameraBottomMode.values;
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
  final CameraBottomMode cameraMode;
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
    final isPhotoMode = cameraMode == CameraBottomMode.photo;
    final showUndo = hasSegments || isRecording;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Story badge / REC indicator
        AnimatedOpacity(
          opacity: (isRecording && !isPhotoMode) ||
                  cameraMode == CameraBottomMode.story
              ? 1.0
              : 0.0,
          duration: const Duration(milliseconds: 220),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: isRecording && !isPhotoMode
                ? _RecordingIndicator(elapsed: totalWithCurrent)
                : cameraMode == CameraBottomMode.story
                    ? _StoryBadge()
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
              isRecording: isRecording,
              totalPct: totalPct,
              isPhotoMode: isPhotoMode,
              onTap: isPhotoMode
                  ? onTakePicture
                  : () {
                      if (isRecording) {
                        onStopRecording();
                      } else {
                        onStartRecording();
                      }
                    },
              onHoldStart: isPhotoMode ? () {} : onStartRecording,
              onHoldEnd: isPhotoMode ? () {} : onStopRecording,
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

class _StoryBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.50),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: SeeUColors.accent.withValues(alpha: 0.55),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIconsRegular.crop, color: SeeUColors.accent, size: 12),
          const SizedBox(width: 4),
          const Text(
            '9:16 · до 15 сек',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
