import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/widgets.dart';

/// Where on the face the model should be anchored after auto-centering.
enum MaskAnchor {
  /// Eye/nose bridge level — for sunglasses, eye masks.
  eyes,
  /// Full face center — for full-face masks.
  face,
  /// Lower face — for menpo/chin masks.
  lowerFace,
  /// Top of head — for crowns, hats. Model bottom edge sits at forehead,
  /// Z is at head center depth. Scale is relative to model WIDTH (ring diameter).
  headTop,
}

/// Per-mask 3D transform applied AFTER auto-normalization.
///
/// The native code will:
/// 1. Load the GLB and compute its bounding box.
/// 2. Center the model at origin (0,0,0).
/// 3. **Each frame**: measure real face width & nose-tip depth from AR mesh.
/// 4. Scale model so its widest axis = measured face width × [scale].
/// 5. Auto-position forward so the model sits in front of the face surface.
/// 6. Apply [anchor]-based vertical offset + fine-tuning offsets below.
///
/// Because scale and Z-position adapt to the actual face every frame,
/// masks fit both small and large faces automatically.
class MaskTransform {
  /// Width ratio relative to measured face width.
  /// 1.0 = model fills face width exactly.
  /// 1.3 = 30% wider than face (e.g. glasses reaching ears).
  final double scale;

  /// Extra offset in face-width units (measured, not fixed).
  /// X = right(+)/left(-), Y = up(+)/down(-).
  /// Z = extra forward gap ON TOP of auto-forward positioning.
  final double offsetX;
  final double offsetY;
  final double offsetZ;

  /// Rotation in degrees around each axis.
  /// X = pitch (nod), Y = yaw (shake head), Z = roll (tilt head).
  final double rotationX;
  final double rotationY;
  final double rotationZ;

  /// If true, the mask is rendered fully in front of the face mesh —
  /// no face geometry (cheeks, chin) bleeds through. Used for lower-face
  /// masks like menpo where the model must cover the skin completely.
  final bool occludeFace;

  const MaskTransform({
    this.scale = 1.0,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.offsetZ = 0.0,
    this.rotationX = 0.0,
    this.rotationY = 0.0,
    this.rotationZ = 0.0,
    this.occludeFace = false,
  });

  Map<String, dynamic> toMap() => {
        'scale': scale,
        'offsetX': offsetX,
        'offsetY': offsetY,
        'offsetZ': offsetZ,
        'rotationX': rotationX,
        'rotationY': rotationY,
        'rotationZ': rotationZ,
        'occludeFace': occludeFace,
      };
}

class MaskDescriptor {
  final String id;
  final String label;
  final String assetPath;
  final IconData previewIcon;
  final MaskAnchor anchor;
  final MaskTransform transform;

  const MaskDescriptor({
    required this.id,
    required this.label,
    required this.assetPath,
    required this.previewIcon,
    this.anchor = MaskAnchor.face,
    this.transform = const MaskTransform(),
  });

  /// Serialise to platform channel creation params.
  Map<String, dynamic> toCreationParams({bool useFrontCamera = true}) => {
        'assetPath': assetPath,
        'useFrontCamera': useFrontCamera,
        'anchor': anchor.name,
        ...transform.toMap(),
      };
}

// ─── Catalog ────────────────────────────────────────────────────────────────
//
// Native code measures the REAL face each frame (width from AR mesh vertices).
// Masks adapt to any face size automatically.
//
// For FACE masks (eyes, face, lowerFace):
//   [scale]   = ratio to face width via max bounding dimension
//   [offsetY] = vertical shift in face-width units
//   [offsetZ] = forward gap in face-width units (on top of auto-forward)
//
// For HEADWEAR (headTop):
//   [scale]   = ratio to face width via model WIDTH (ring/brim diameter)
//   Model bottom edge sits at forehead; Z at head center depth.
//   [offsetY] = cm shift up(+)/down(-) from forehead
//   [offsetZ] = cm shift forward(+)/backward(-) from head center

class MaskCatalog {
  MaskCatalog._();

  static final List<MaskDescriptor> all = [
    // ── Sunglasses ────────────────────────────────────────────────────────
    MaskDescriptor(
      id: 'dark_sunglasses',
      label: 'Тёмные очки',
      assetPath: 'assets/masks/3d/dark_sunglasses.glb',
      previewIcon: PhosphorIcons.sunglasses(),
      anchor: MaskAnchor.eyes,
      transform: const MaskTransform(
        scale: 1.04,
        offsetX: 0.0,
        offsetY: 0.04,
        offsetZ: -1.0,
      ),
    ),
    MaskDescriptor(
      id: 'dior_sunglasses',
      label: 'Dior',
      assetPath: 'assets/masks/3d/dior__sunglasses.glb',
      previewIcon: PhosphorIcons.sunglasses(),
      anchor: MaskAnchor.eyes,
      transform: const MaskTransform(
        scale: 1.07,
        offsetX: 0.0,
        offsetY: 0.0,
        offsetZ: -1.12,
      ),
    ),
    MaskDescriptor(
      id: 'pink_sunglasses',
      label: 'Розовые очки',
      assetPath: 'assets/masks/3d/pink_round_sunglasses.glb',
      previewIcon: PhosphorIcons.sunglasses(),
      anchor: MaskAnchor.eyes,
      transform: const MaskTransform(
        scale: 1.22,
        offsetX: 0.0,
        offsetY: 0.06,
        offsetZ: -1.08,
        rotationX: 0.8,
      ),
    ),

    // ── Headwear ──────────────────────────────────────────────────────────
    // anchor=headTop: scale is relative to model WIDTH (ring/brim diameter).
    //   1.0 = ring matches face width exactly; 1.1 = 10% wider than face.
    // Position: model BOTTOM EDGE sits at forehead level, Z at head center.
    // offsets in CENTIMETERS: offsetY=+1 → 1cm higher; offsetZ=+1 → 1cm forward.
    // A head+hair skull occluder hides the back of every headTop mask so the
    // rear of the model is clipped at the real head silhouette (always active).
    MaskDescriptor(
      id: 'crown_of_elegance',
      label: 'Корона',
      assetPath: 'assets/masks/3d/crown_of_elegance.glb',
      previewIcon: PhosphorIcons.crown(),
      anchor: MaskAnchor.headTop,
      transform: const MaskTransform(
        scale: 1.33,
        offsetY: 1.90,
        offsetZ: 0.0,
        rotationX: 0.0,
      ),
    ),
    MaskDescriptor(
      id: 'samurai_hat',
      label: 'Самурай',
      assetPath: 'assets/masks/3d/samurai_hat.glb',
      previewIcon: PhosphorIcons.shield(),
      anchor: MaskAnchor.headTop,
      transform: const MaskTransform(
        scale: 2.60,
        offsetY: -8.0,
        offsetZ: 0.0,
        rotationX: 12.0,
      ),
    ),

    // ── Усы ───────────────────────────────────────────────────────────────
    // Зона усов = под основанием носа, над верхней губой. Начало координат
    // face-анкера — переносица, поэтому нужная высота ≈ −0.030 м:
    //   anchor lowerFace даёт базу −0.035 м (рот), а offsetY поднимает обратно
    //   к фильтруму: −0.035 + 0.03 × ширина_лица(≈0.15) ≈ −0.030 м.
    // scale 0.45 — усы примерно вполовину ширины лица (≈6–7 см), как в жизни.
    // offsetZ −0.15 — модель плоская, поэтому автовынос перед кончиком носа
    //   небольшой, и её достаточно чуть притянуть назад на кожу над губой
    //   (у очков минус куда больше: их дужки делают bbox глубоким).
    // occludeFace: true — усы всегда рисуются поверх лица. С face-окклюдером
    //   малейший уход модели «внутрь» кожи срезал бы её целиком.
    MaskDescriptor(
      id: 'mustache',
      label: 'Усы',
      assetPath: 'assets/masks/3d/mustache.glb',
      previewIcon: PhosphorIcons.smiley(),
      anchor: MaskAnchor.lowerFace,
      transform: const MaskTransform(
        scale: 0.45,
        offsetX: 0.0,
        offsetY: 0.03,
        offsetZ: -0.15,
        occludeFace: true,
      ),
    ),

    // ── Lower face / menpo masks ──────────────────────────────────────────
    // occludeFace=true — no occlusion geometry, mask renders fully in front
    // of the face so cheeks don't show through.
    MaskDescriptor(
      id: 'yoshimitsu',
      label: 'Yoshimitsu',
      assetPath: 'assets/masks/3d/yoshimitsu_menpo_mask.glb',
      previewIcon: PhosphorIcons.maskHappy(),
      anchor: MaskAnchor.lowerFace,
      transform: const MaskTransform(
        scale: 1.09,
        offsetX: 0.0,
        offsetY: -0.02,
        offsetZ: -0.64,
        occludeFace: true,
      ),
    ),
  ];
}
