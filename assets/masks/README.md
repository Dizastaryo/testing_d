# Face Filter Masks — Lottie Assets

All files are Lottie JSON animations (bodymovin 5.9.0), 30 fps, transparent canvas (no background layer).

## File Reference

| File | Canvas (w×h) | Frames | Duration | Layers | Face Anchor |
|---|---|---|---|---|---|
| `bunny.json` | 1200 × 900 | 90 | 3 s | 6 | Ears top-of-head, nose on nose-tip |
| `anime_tears.json` | 1200 × 1600 | 90 | 3 s | 12 | Eyes/cheeks area (full-face portrait) |
| `gold_crown.json` | 1200 × 500 | 120 | 4 s | 13 | Forehead / crown of head |
| `flower_crown.json` | 1200 × 600 | 120 | 4 s | 4 | Forehead / crown of head |
| `butterflies.json` | 1200 × 1600 | 90 | 3 s | 6 | Left & right cheeks (full-face portrait) |

## Face Landmark Anchoring

### bunny.json — 1200 × 900
- **Landmark**: `TOP_OF_HEAD` / forehead centre
- **Placement**: align canvas bottom-centre (600, 900) to forehead centre
- Ears extend upward from the head. Left ear pivot at canvas (330, 480); right ear at (870, 480).
- Nose oval at canvas (600, 722) — align to `NOSE_TIP` landmark if adjusting.

### anime_tears.json — 1200 × 1600
- **Landmark**: `FACE_OVAL` / full-face bounding rect
- **Placement**: stretch canvas to fill the face bounding box (portrait)
- Left tears at x ≈ 340–388 (canvas coords), y ≈ 695–928
- Right tears at x ≈ 812–858, y ≈ 695–928
- In a 1200 × 1600 canvas these correspond to just below the eye corners.

### gold_crown.json — 1200 × 500
- **Landmark**: `FOREHEAD_GLABELLA` or `TOP_OF_HEAD`
- **Placement**: align canvas bottom-centre (600, 500) to hairline/top-forehead
- Crown band occupies y 320–480; spikes rise toward y 52 (centre peak).
- Offset upward by ~30 px to clear hair.

### flower_crown.json — 1200 × 600
- **Landmark**: `FOREHEAD_GLABELLA` or `TOP_OF_HEAD`
- **Placement**: same as gold crown — bottom-centre to hairline
- Sway pivot is at canvas (600, 600), i.e. the bottom edge centre.
- Centre rose sits at canvas (600, 155).

### butterflies.json — 1200 × 1600
- **Landmark**: `FACE_OVAL` / full-face bounding rect
- **Placement**: stretch canvas to fill the face bounding box
- All butterflies on left (x < 300) and right (x > 900) sides only.
- Centre corridor (x 300–900) is empty so the face shows through.

## Animation Summary

| File | Key Animations |
|---|---|
| `bunny.json` | Ear sway rotation ±4°, ear twitch at f43, nose scale pulse, sparkle scale 0→1→0 |
| `anime_tears.json` | Tear Y+83 px over 80 frames, opacity fade 0→100→0, sparkle twinkle, `st` stagger per layer |
| `gold_crown.json` | 8 sparkles staggered scale 0→1.2→0/25 f, gem glow opacity pulse 12→35→12, light rays 360°/120 f |
| `flower_crown.json` | Crown sway ±2°/60 f, falling petal pos+rot+opacity f30–90, 2 flutter leaves ±3° |
| `butterflies.json` | Wing-group rotation −25°↔+5° / 15 f cycle, body float ±15 px XY / 89 f, `st` stagger per butterfly |

## Flutter Integration Notes

```dart
// pubspec.yaml already includes:
//   assets:
//     - assets/masks/

// Add to dependencies:
//   lottie: ^3.x

import 'package:lottie/lottie.dart';

Lottie.asset(
  'assets/masks/bunny.json',
  fit: BoxFit.contain,
  repeat: true,         // all masks are designed to loop
  animate: true,
);
```

For face-aligned rendering, layer the Lottie widget over the camera preview using a `Stack`, then position/scale each mask widget to match the MediaPipe face-mesh bounding box returned from `mediapipe_face_mesh`.
