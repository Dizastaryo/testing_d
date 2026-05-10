import 'package:flutter/material.dart';

// ─── Colors ───────────────────────────────────────────────────────────────

class SeeUColors {
  SeeUColors._();

  // ── Light theme ──
  static const Color background = Color(0xFFFAF7F2);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surface2 = Color(0xFFF4EFE8);
  static const Color surfaceElevated = Color(0xFFF4EFE8); // alias for surface2

  static const Color textPrimary = Color(0xFF161310);
  static const Color textSecondary = Color(0xFF4A4540);
  static const Color textTertiary = Color(0xFF8A847C);
  static const Color textQuaternary = Color(0xFFC9C2B8);

  static const Color borderSubtle = Color(0xFFECE5DA);

  static const Color accent = Color(0xFFFF5A3C);
  static const Color accentSecondary = Color(0xFFFF8060);
  static const Color accentSoft = Color(0xFFFFE4D9);
  static const Color amber = Color(0xFFFFB547);
  static const Color plum = Color(0xFFC04CFD);
  static const Color like = Color(0xFFFF3B6B);
  static const Color success = Color(0xFF2FA84F);
  static const Color error = Color(0xFFE53935);

  // ── Dark theme ──
  static const Color darkBg = Color(0xFF0E0C0A);
  static const Color darkSurface = Color(0xFF1A1714);
  static const Color darkSurface2 = Color(0xFF221E1A);
  static const Color darkInk = Color(0xFFF5F2ED);
  static const Color darkInk2 = Color(0xFFB6AFA5);
  static const Color darkInk3 = Color(0xFF7A736A);
  static const Color darkInk4 = Color(0xFF4A443E);
  static const Color darkLine = Color(0xFF2A2520);
  static const Color darkCoralSoft = Color(0xFF3A201A);

  // Story ring gradient
  static const List<Color> storyRingColors = [
    Color(0xFFFFB547),
    Color(0xFFFF5A3C),
    Color(0xFFC04CFD),
  ];

  static const LinearGradient storyGradient = LinearGradient(
    colors: storyRingColors,
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Title gradient (3-color)
  static const LinearGradient titleGradient = LinearGradient(
    colors: [
      Color(0xFFFF5A3C),
      Color(0xFFFF8060),
      Color(0xFFFFB547),
    ],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  // Signal colors (scanner)
  static const Color signalClose = Color(0xFF2FA84F);
  static const Color signalMedium = Color(0xFFFFB547);
  static const Color signalFar = Color(0xFFFF5A3C);

  // Avatar palettes
  static const List<List<Color>> avatarPalettes = [
    [Color(0xFFFF8060), Color(0xFFC04CFD)],
    [Color(0xFFFFB547), Color(0xFFFF5A3C)],
    [Color(0xFF5DB1FF), Color(0xFFC04CFD)],
    [Color(0xFF2FA84F), Color(0xFF5DB1FF)],
    [Color(0xFFFF3B6B), Color(0xFFFFB547)],
    [Color(0xFF7B61FF), Color(0xFFFF8060)],
    [Color(0xFF1AC8B8), Color(0xFF5DB1FF)],
    [Color(0xFFFFB547), Color(0xFFFF3B6B)],
    [Color(0xFFA47148), Color(0xFFFFB547)],
  ];
}

// ─── Typography ───────────────────────────────────────────────────────────

class SeeUTypography {
  SeeUTypography._();

  static const String _serifFamily = 'Fraunces';
  static const String _uiFamily = 'Inter';
  static const String _monoFamily = 'JetBrains Mono';

  static const TextStyle displayXL = TextStyle(
    fontFamily: _serifFamily,
    fontSize: 42,
    fontWeight: FontWeight.w400,
    letterSpacing: -1.5,
    color: SeeUColors.textPrimary,
  );

  static const TextStyle displayL = TextStyle(
    fontFamily: _serifFamily,
    fontSize: 32,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.5,
    color: SeeUColors.textPrimary,
  );

  static const TextStyle displayM = TextStyle(
    fontFamily: _serifFamily,
    fontSize: 28,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.3,
    color: SeeUColors.textPrimary,
  );

  static const TextStyle displayS = TextStyle(
    fontFamily: _serifFamily,
    fontSize: 22,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.2,
    color: SeeUColors.textPrimary,
  );

  static const TextStyle title = TextStyle(
    fontFamily: _uiFamily,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    color: SeeUColors.textPrimary,
  );

  static const TextStyle subtitle = TextStyle(
    fontFamily: _uiFamily,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.2,
    color: SeeUColors.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontFamily: _uiFamily,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.1,
    color: SeeUColors.textPrimary,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: _uiFamily,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    color: SeeUColors.textSecondary,
  );

  static const TextStyle micro = TextStyle(
    fontFamily: _uiFamily,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
    color: SeeUColors.textTertiary,
  );

  static const TextStyle mono = TextStyle(
    fontFamily: _monoFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: SeeUColors.textTertiary,
  );

  static const TextStyle monoLabel = TextStyle(
    fontFamily: _monoFamily,
    fontSize: 10,
    fontWeight: FontWeight.w400,
    letterSpacing: 1.0,
    color: SeeUColors.textTertiary,
  );
}

// ─── Spacing ──────────────────────────────────────────────────────────────

class SeeUSpacing {
  SeeUSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double base = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

// ─── Radii ────────────────────────────────────────────────────────────────

class SeeURadii {
  SeeURadii._();
  static const double small = 12;
  static const double medium = 18;
  static const double card = 24;
  static const double sheet = 32;
  static const double pill = 999;
}

// ─── Motion ───────────────────────────────────────────────────────────────
//
// Единые длительности и кривые. Без них переходы по приложению живут «каждый
// сам по себе». Используется в transitions, hot-таппах, story-pulse.

class SeeUMotion {
  SeeUMotion._();

  // Длительности
  static const Duration quick = Duration(milliseconds: 120);     // hot-press feedback
  static const Duration normal = Duration(milliseconds: 220);    // page-element transitions
  static const Duration slow = Duration(milliseconds: 360);      // sheets / shared-axis
  static const Duration cinematic = Duration(milliseconds: 600); // splash, hero
  static const Duration radarSweep = Duration(milliseconds: 1400); // pull-to-refresh radar
  static const Duration storyPulse = Duration(milliseconds: 2400); // unread story-ring breathing

  // Кривые
  static const Curve smooth = Curves.easeOutCubic;
  static const Curve springy = Curves.easeOutBack;
  static const Curve overshoot = Cubic(0.34, 1.56, 0.64, 1.0);
  static const Curve breathe = Curves.easeInOutSine;
}

// ─── Gradients ────────────────────────────────────────────────────────────
//
// Бренд-градиенты на оранжевом. Используются для hero-блоков, glass-cards,
// pull-to-refresh, sunset-card в рилсах.

class SeeUGradients {
  SeeUGradients._();

  // Hero — закат над городом, основной brand
  static const LinearGradient heroOrange = LinearGradient(
    colors: [
      Color(0xFFFF5A3C),
      Color(0xFFFF8060),
      Color(0xFFFFB547),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    stops: [0.0, 0.55, 1.0],
  );

  // Closer-to-pink for «like» / engagement chips
  static const LinearGradient sunsetCard = LinearGradient(
    colors: [
      Color(0xFFFF5A3C),
      Color(0xFFFF3B6B),
      Color(0xFFC04CFD),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Glass-tint поверх blur'а для bottom-sheet'ов и floating-mini-player
  static LinearGradient glassOrange({double opacity = 0.12}) => LinearGradient(
        colors: [
          SeeUColors.accent.withValues(alpha: opacity),
          SeeUColors.accent.withValues(alpha: opacity * 0.4),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  // Радиальный «радар-импульс» — центр оранжевый, края прозрачные.
  // Используется в pull-to-refresh + аватар-кольцо непрочитанной story.
  static RadialGradient radar({double innerOpacity = 0.7}) => RadialGradient(
        colors: [
          SeeUColors.accent.withValues(alpha: innerOpacity),
          SeeUColors.accent.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 1.0],
      );
}

// ─── Shadows ──────────────────────────────────────────────────────────────

class SeeUShadows {
  SeeUShadows._();

  static List<BoxShadow> get sm => [
        BoxShadow(
          color: const Color(0xFF161310).withValues(alpha: 0.06),
          offset: const Offset(0, 1),
          blurRadius: 2,
        ),
      ];

  static List<BoxShadow> get md => [
        BoxShadow(
          color: const Color(0xFF161310).withValues(alpha: 0.06),
          offset: const Offset(0, 4),
          blurRadius: 16,
        ),
        BoxShadow(
          color: const Color(0xFF161310).withValues(alpha: 0.04),
          offset: const Offset(0, 1),
          blurRadius: 2,
        ),
      ];

  static List<BoxShadow> get lg => [
        BoxShadow(
          color: const Color(0xFF161310).withValues(alpha: 0.10),
          offset: const Offset(0, 12),
          blurRadius: 32,
        ),
        BoxShadow(
          color: const Color(0xFF161310).withValues(alpha: 0.06),
          offset: const Offset(0, 2),
          blurRadius: 6,
        ),
      ];
}
