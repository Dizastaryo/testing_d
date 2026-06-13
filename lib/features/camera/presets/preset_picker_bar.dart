import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/design/tokens.dart';
import 'camera_preset.dart';
import 'camera_presets_catalog.dart';

/// Горизонтальная полоса выбора пресетов камеры.
/// Показывается над кнопкой записи при нажатии «Эффекты».
class PresetPickerBar extends StatelessWidget {
  final CameraPreset activePreset;
  final Uint8List? snapshotBytes;
  final ValueChanged<CameraPreset> onPresetSelected;

  const PresetPickerBar({
    super.key,
    required this.activePreset,
    required this.snapshotBytes,
    required this.onPresetSelected,
  });

  @override
  Widget build(BuildContext context) {
    final presets = [CameraPresetsCollection.none, ...CameraPresetsCollection.all];

    return SizedBox(
      height: 104,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: presets.length,
        itemBuilder: (context, i) {
          final preset = presets[i];
          return _PresetItem(
            preset: preset,
            isActive: preset.id == activePreset.id,
            snapshotBytes: snapshotBytes,
            onTap: () {
              HapticFeedback.selectionClick();
              onPresetSelected(preset);
            },
          );
        },
      ),
    );
  }
}

class _PresetItem extends StatelessWidget {
  final CameraPreset preset;
  final bool isActive;
  final Uint8List? snapshotBytes;
  final VoidCallback onTap;

  const _PresetItem({
    required this.preset,
    required this.isActive,
    required this.snapshotBytes,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64,
        margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Thumbnail
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              width: 64,
              height: 72,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isActive ? SeeUColors.accent : Colors.white.withValues(alpha: 0.25),
                  width: isActive ? 2.0 : 1.0,
                ),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: SeeUColors.accent.withValues(alpha: 0.45),
                          blurRadius: 8,
                          spreadRadius: 0,
                        )
                      ]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: _buildThumbnailContent(),
              ),
            ),
            const SizedBox(height: 5),
            // Label
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              style: TextStyle(
                color: isActive ? Colors.white : Colors.white60,
                fontSize: isActive ? 10.5 : 10,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 0.1,
              ),
              child: Text(
                preset.isNone ? 'Нет' : preset.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnailContent() {
    if (preset.isNone) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2C2C2E), Color(0xFF1C1C1E)],
          ),
        ),
        alignment: Alignment.center,
        child: const Text(
          '✕',
          style: TextStyle(color: Colors.white38, fontSize: 18, fontWeight: FontWeight.w300),
        ),
      );
    }

    if (snapshotBytes != null) {
      return ColorFiltered(
        colorFilter: ColorFilter.matrix(preset.filter.toMatrix()),
        child: Image.memory(
          snapshotBytes!,
          fit: BoxFit.cover,
          width: 64,
          height: 72,
          gaplessPlayback: true,
        ),
      );
    }

    // Градиентный fallback
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [preset.swatchColor, preset.swatchColor2],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        preset.emoji,
        style: const TextStyle(fontSize: 22),
      ),
    );
  }
}
