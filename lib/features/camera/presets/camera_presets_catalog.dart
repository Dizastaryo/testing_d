import 'package:flutter/material.dart';
import '../filters/filter_state.dart';
import '../filters/frame_effect.dart';
import '../filters/overlay_effect.dart';
import 'camera_preset.dart';

/// Каталог всех 20 пресетов камеры + пресет «Нет».
class CameraPresetsCollection {
  CameraPresetsCollection._();

  static const none = CameraPreset.none;

  /// Все пресеты в порядке отображения (без none).
  static final List<CameraPreset> all = [
    ..._film,
    ..._retro,
    ..._moody,
    ..._clean,
    ..._special,
  ];

  // ── Группа 1: Плёнка / Аналог ─────────────────────────────────────────────

  static final _film = <CameraPreset>[
    const CameraPreset(
      id: 'kodak_gold',
      name: 'Kodak Gold',
      emoji: '🎞',
      swatchColor: Color(0xFFE8C96D),
      swatchColor2: Color(0xFFC8903A),
      filter: FilterState(
        warmth: 0.30,
        contrast: 0.15,
        saturation: 0.10,
        liftBlacks: 0.12,
        fadeHighlights: 0.08,
        grain: 0.35,
        halation: 0.25,
        vignette: 0.20,
      ),
      hasGrain: true,
      hasHalation: true,
      grainAmount: 0.35,
      halationAmount: 0.25,
      overlay: LightLeakEffect(style: LightLeakStyle.topOrange, intensity: 0.30),
    ),
    const CameraPreset(
      id: 'fuji_400h',
      name: 'Fuji 400H',
      emoji: '🌿',
      swatchColor: Color(0xFF9DC5A0),
      swatchColor2: Color(0xFF5A8C6A),
      filter: FilterState(
        warmth: -0.12,
        contrast: 0.05,
        saturation: 0.15,
        liftBlacks: 0.18,
        fadeHighlights: 0.14,
        grain: 0.28,
        vignette: 0.15,
      ),
      hasGrain: true,
      grainAmount: 0.28,
      frame: FilmStripFrame(filmLabel: 'FUJI 400H', frameNumber: 12),
    ),
    const CameraPreset(
      id: 'kodak_400tx',
      name: 'Kodak TX400',
      emoji: '⬛',
      swatchColor: Color(0xFF8A8A8A),
      swatchColor2: Color(0xFF2C2C2C),
      filter: FilterState(
        saturation: -0.85,
        contrast: 0.25,
        liftBlacks: 0.08,
        grain: 0.45,
        vignette: 0.30,
      ),
      hasGrain: true,
      grainAmount: 0.45,
      frame: FilmStripFrame(filmLabel: 'KODAK 400TX', frameNumber: 7),
    ),
    const CameraPreset(
      id: 'polaroid_now',
      name: 'Polaroid',
      emoji: '📸',
      swatchColor: Color(0xFFF5EDD8),
      swatchColor2: Color(0xFFD4B896),
      filter: FilterState(
        warmth: 0.15,
        brightness: 0.08,
        contrast: -0.10,
        saturation: -0.05,
        liftBlacks: 0.20,
        fadeHighlights: 0.18,
        grain: 0.20,
        vignette: 0.25,
      ),
      hasGrain: true,
      grainAmount: 0.20,
      frame: PolaroidFrame(caption: ''),
    ),
  ];

  // ── Группа 2: Ретро 90s / Y2K ─────────────────────────────────────────────

  static final _retro = <CameraPreset>[
    const CameraPreset(
      id: 'vhs_1994',
      name: 'VHS 1994',
      emoji: '📼',
      swatchColor: Color(0xFF4A3F8C),
      swatchColor2: Color(0xFF1A1060),
      filter: FilterState(
        saturation: 0.20,
        contrast: 0.15,
        warmth: -0.08,
        liftBlacks: 0.10,
        grain: 0.30,
        vignette: 0.35,
      ),
      hasGrain: true,
      grainAmount: 0.30,
      overlay: VHSEffect(),
    ),
    const CameraPreset(
      id: 'disposable_90s',
      name: 'Одноразовый',
      emoji: '🟧',
      swatchColor: Color(0xFFE8A055),
      swatchColor2: Color(0xFFB86A20),
      filter: FilterState(
        warmth: 0.22,
        contrast: 0.20,
        saturation: 0.12,
        liftBlacks: 0.15,
        grain: 0.50,
        vignette: 0.40,
        halation: 0.15,
      ),
      hasGrain: true,
      hasHalation: true,
      grainAmount: 0.50,
      halationAmount: 0.15,
      frame: DisposableCameraFrame(),
    ),
    const CameraPreset(
      id: 'y2k_chrome',
      name: 'Y2K Chrome',
      emoji: '💿',
      swatchColor: Color(0xFFB0C8E8),
      swatchColor2: Color(0xFF6080C0),
      filter: FilterState(
        warmth: -0.20,
        contrast: 0.30,
        saturation: 0.35,
        brightness: 0.05,
        vignette: 0.15,
      ),
      overlay: LightLeakEffect(style: LightLeakStyle.topCool, intensity: 0.40),
    ),
    const CameraPreset(
      id: 'lofi_cam',
      name: 'Lo-Fi',
      emoji: '🔲',
      swatchColor: Color(0xFF7A6A5A),
      swatchColor2: Color(0xFF3A2A1A),
      filter: FilterState(
        saturation: -0.30,
        contrast: 0.18,
        warmth: 0.18,
        liftBlacks: 0.22,
        fadeHighlights: 0.16,
        grain: 0.60,
        vignette: 0.45,
        halation: 0.10,
      ),
      hasGrain: true,
      hasHalation: true,
      grainAmount: 0.60,
      halationAmount: 0.10,
    ),
  ];

  // ── Группа 3: Moody / Cinematic ────────────────────────────────────────────

  static final _moody = <CameraPreset>[
    const CameraPreset(
      id: 'teal_orange',
      name: 'Teal & Orange',
      emoji: '🎬',
      swatchColor: Color(0xFF1E7A78),
      swatchColor2: Color(0xFFD45A20),
      filter: FilterState(
        contrast: 0.22,
        saturation: 0.15,
        warmth: 0.12,
        vignette: 0.30,
        liftBlacks: 0.05,
        fadeHighlights: 0.10,
      ),
    ),
    const CameraPreset(
      id: 'noir',
      name: 'Нуар',
      emoji: '🌑',
      swatchColor: Color(0xFF404040),
      swatchColor2: Color(0xFF101010),
      filter: FilterState(
        saturation: -1.0,
        contrast: 0.40,
        brightness: -0.05,
        vignette: 0.55,
        grain: 0.25,
      ),
      hasGrain: true,
      grainAmount: 0.25,
      overlay: DustScratchesEffect(intensity: 0.45),
    ),
    const CameraPreset(
      id: 'dusk',
      name: 'Закат',
      emoji: '🌅',
      swatchColor: Color(0xFFFF7040),
      swatchColor2: Color(0xFF8B2060),
      filter: FilterState(
        warmth: 0.35,
        contrast: 0.20,
        saturation: 0.25,
        fadeHighlights: 0.12,
        vignette: 0.20,
        halation: 0.30,
      ),
      hasHalation: true,
      halationAmount: 0.30,
      overlay: LightLeakEffect(style: LightLeakStyle.bottomWarm, intensity: 0.45),
    ),
    const CameraPreset(
      id: 'fog',
      name: 'Туман',
      emoji: '🌫',
      swatchColor: Color(0xFFB8C8D8),
      swatchColor2: Color(0xFF607080),
      filter: FilterState(
        brightness: 0.08,
        contrast: -0.15,
        saturation: -0.20,
        warmth: -0.10,
        fadeHighlights: 0.25,
        liftBlacks: 0.28,
        vignette: 0.10,
      ),
    ),
  ];

  // ── Группа 4: Clean / Bright ───────────────────────────────────────────────

  static final _clean = <CameraPreset>[
    const CameraPreset(
      id: 'bright_air',
      name: 'Воздух',
      emoji: '☁️',
      swatchColor: Color(0xFFD8EAF8),
      swatchColor2: Color(0xFF90B8E0),
      filter: FilterState(
        brightness: 0.12,
        contrast: -0.08,
        saturation: -0.10,
        warmth: -0.05,
        fadeHighlights: 0.10,
        liftBlacks: 0.08,
      ),
    ),
    const CameraPreset(
      id: 'golden_hour',
      name: 'Золотой час',
      emoji: '✨',
      swatchColor: Color(0xFFFFD080),
      swatchColor2: Color(0xFFFF9030),
      filter: FilterState(
        warmth: 0.28,
        brightness: 0.08,
        contrast: 0.10,
        saturation: 0.20,
        fadeHighlights: 0.08,
        vignette: 0.12,
        halation: 0.20,
      ),
      hasHalation: true,
      halationAmount: 0.20,
    ),
    const CameraPreset(
      id: 'vivid',
      name: 'Сочный',
      emoji: '🌈',
      swatchColor: Color(0xFF40C060),
      swatchColor2: Color(0xFF4080E0),
      filter: FilterState(
        saturation: 0.45,
        contrast: 0.20,
        brightness: 0.04,
        vignette: 0.10,
      ),
    ),
    const CameraPreset(
      id: 'minimal',
      name: 'Minimal',
      emoji: '⬜',
      swatchColor: Color(0xFFF0F0F0),
      swatchColor2: Color(0xFFD0D0D0),
      filter: FilterState(
        brightness: 0.10,
        contrast: -0.05,
        saturation: -0.15,
        fadeHighlights: 0.05,
      ),
    ),
  ];

  // ── Группа 5: Спецэффекты ─────────────────────────────────────────────────

  static final _special = <CameraPreset>[
    const CameraPreset(
      id: 'scrapbook',
      name: 'Скрапбук',
      emoji: '📋',
      swatchColor: Color(0xFFE8D8B0),
      swatchColor2: Color(0xFFC0A068),
      filter: FilterState(
        warmth: 0.18,
        saturation: -0.10,
        contrast: 0.05,
        liftBlacks: 0.12,
        fadeHighlights: 0.10,
        grain: 0.22,
        vignette: 0.18,
      ),
      hasGrain: true,
      grainAmount: 0.22,
      frame: ScrapbookFrame(),
      overlay: PaperTextureEffect(),
    ),
    const CameraPreset(
      id: 'dust_punk',
      name: 'Dust Punk',
      emoji: '🏜',
      swatchColor: Color(0xFFD4A050),
      swatchColor2: Color(0xFF804010),
      filter: FilterState(
        warmth: 0.25,
        contrast: 0.28,
        saturation: 0.08,
        liftBlacks: 0.10,
        grain: 0.55,
        vignette: 0.50,
        halation: 0.12,
      ),
      hasGrain: true,
      hasHalation: true,
      grainAmount: 0.55,
      halationAmount: 0.12,
      overlay: DustScratchesEffect(intensity: 0.70),
    ),
    const CameraPreset(
      id: 'light_leak_warm',
      name: 'Засветка',
      emoji: '💡',
      swatchColor: Color(0xFFFF9840),
      swatchColor2: Color(0xFFFF5090),
      filter: FilterState(
        warmth: 0.20,
        brightness: 0.06,
        contrast: 0.10,
        saturation: 0.12,
        fadeHighlights: 0.08,
        grain: 0.18,
        halation: 0.22,
        vignette: 0.15,
      ),
      hasGrain: true,
      hasHalation: true,
      grainAmount: 0.18,
      halationAmount: 0.22,
      overlay: LightLeakEffect(style: LightLeakStyle.topOrange, intensity: 0.60),
    ),
    const CameraPreset(
      id: 'tape_diary',
      name: 'Дневник',
      emoji: '📓',
      swatchColor: Color(0xFFF0E8C8),
      swatchColor2: Color(0xFFB8A870),
      filter: FilterState(
        warmth: 0.12,
        saturation: -0.08,
        contrast: -0.05,
        liftBlacks: 0.15,
        fadeHighlights: 0.20,
        grain: 0.30,
        vignette: 0.22,
      ),
      hasGrain: true,
      grainAmount: 0.30,
      frame: TapeEffect(),
      overlay: PaperTextureEffect(),
    ),
  ];
}
