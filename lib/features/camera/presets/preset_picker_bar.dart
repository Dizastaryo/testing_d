import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/design/tokens.dart';
import 'camera_preset.dart';
import 'camera_presets_catalog.dart';

/// Горизонтальная полоса выбора пресетов камеры.
/// Показывается над кнопкой записи при нажатии «Эффекты».
class PresetPickerBar extends StatelessWidget {
  final CameraPreset activePreset;
  final ValueChanged<CameraPreset> onPresetSelected;

  const PresetPickerBar({
    super.key,
    required this.activePreset,
    required this.onPresetSelected,
  });

  @override
  Widget build(BuildContext context) {
    final presets = [CameraPresetsCollection.none, ...CameraPresetsCollection.all];

    return SizedBox(
      // Компактная полоса пресетов (glassmorphism-редизайн).
      height: 78,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: presets.length,
        itemBuilder: (context, i) {
          final preset = presets[i];
          return _PresetItem(
            preset: preset,
            isActive: preset.id == activePreset.id,
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
  final VoidCallback onTap;

  const _PresetItem({
    required this.preset,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 54,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Thumbnail
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              width: 50,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
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
                borderRadius: BorderRadius.circular(13),
                child: _buildThumbnailContent(),
              ),
            ),
            const SizedBox(height: 4),
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
      // #44: unify the "none" visual with the decoration picker (prohibit icon).
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2C2C2E), Color(0xFF1C1C1E)],
          ),
        ),
        alignment: Alignment.center,
        child: Icon(PhosphorIcons.prohibit(),
            color: Colors.white38, size: 20),
      );
    }

    // #42: apply the preset's actual color grade to the swatch so the chip
    // previews the look rather than a flat gradient + emoji.
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(preset.filter.toMatrix()),
      child: Container(
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
          style: const TextStyle(fontSize: 20),
        ),
      ),
    );
  }
}
