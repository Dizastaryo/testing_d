import 'package:flutter/material.dart';

// ─── Colors ───────────────────────────────────────────────────────────────

class SeeUColors {
  SeeUColors._();

  /// Global brightness bridge. Set once per frame from the resolved Theme in
  /// the app root (main.dart builder). This lets the 40+ files that read the
  /// semantic accessors below (background / textPrimary / surface / ...)
  /// directly — with no BuildContext — become theme-aware automatically.
  /// `context.seeuColors` still works and is preferred for new code.
  static Brightness themeBrightness = Brightness.light;
  static bool get _dark => themeBrightness == Brightness.dark;

  // ── Light theme (private; exposed via the theme-aware getters below) ──
  static const Color _lightBackground = Color(0xFFFAF7F2);
  static const Color _lightSurface = Color(0xFFFFFFFF);
  static const Color _lightSurface2 = Color(0xFFF4EFE8);
  static const Color _lightTextPrimary = Color(0xFF161310);
  static const Color _lightTextSecondary = Color(0xFF4A4540);
  static const Color _lightTextTertiary = Color(0xFF8A847C);
  static const Color _lightTextQuaternary = Color(0xFFC9C2B8);
  static const Color _lightBorderSubtle = Color(0xFFECE5DA);
  static const Color _lightAccentSoft = Color(0xFFFFE4D9);

  // ── Theme-aware semantic accessors (resolve light/dark via themeBrightness) ──
  static Color get background => _dark ? darkBg : _lightBackground;
  static Color get surface => _dark ? darkSurface : _lightSurface;
  static Color get surface2 => _dark ? darkSurface2 : _lightSurface2;
  static Color get surfaceElevated => surface2; // alias
  static Color get textPrimary => _dark ? darkInk : _lightTextPrimary;
  static Color get textSecondary => _dark ? darkInk2 : _lightTextSecondary;
  static Color get textTertiary => _dark ? darkInk3 : _lightTextTertiary;
  static Color get textQuaternary => _dark ? darkInk4 : _lightTextQuaternary;
  static Color get borderSubtle => _dark ? darkLine : _lightBorderSubtle;
  static Color get accentSoft => _dark ? darkCoralSoft : _lightAccentSoft;

  // ── Brand / fixed (identical in both themes) ──
  static const Color accent = Color(0xFFFF5A3C);
  static const Color accentSecondary = Color(0xFFFF8060);
  static const Color amber = Color(0xFFFFB547);
  static const Color plum = Color(0xFFC04CFD);
  static const Color like = Color(0xFFFF3B6B);
  static const Color success = Color(0xFF2FA84F);
  static const Color error = Color(0xFFE53935);
  // Semantic aliases to migrate raw hex off-palette usages onto tokens.
  static const Color danger = Color(0xFFFF3B30); // destructive (delete/leave/block)
  static const Color live = Color(0xFFE53935); // LIVE badges / broadcast dot
  static const Color warning = Color(0xFFF57C00); // pending / внимание
  static const Color info = Color(0xFF1E88E5); // нейтрально-информационное (видео, «Хочу»)

  // Медали лидербордов (вместо raw 0xFFFFD700/C0C0C0/CD7F32 и 🥇🥈🥉).
  static const Color medalGold = Color(0xFFFFD700);
  static const Color medalSilver = Color(0xFFC0C0C0);
  static const Color medalBronze = Color(0xFFCD7F32);

  // ── Dark theme ──
  static const Color darkBg = Color(0xFF0E0C0A);
  static const Color darkSurface = Color(0xFF1A1714);
  static const Color darkSurface2 = Color(0xFF221E1A);
  static const Color darkInk = Color(0xFFF5F2ED);
  static const Color darkInk2 = Color(0xFFB6AFA5);
  static const Color darkInk3 = Color(0xFF8F877D);
  static const Color darkInk4 = Color(0xFF6B6560);
  static const Color darkLine = Color(0xFF2A2520);
  static const Color darkCoralSoft = Color(0xFF3A201A);

  // ── Overlays / scrims ──
  // BUG-15: централизованные tokens для glass/scrim-эффектов. Раньше эти
  // hex-значения дублировались в 5+ файлах (camera, post_card, mask_catalog,
  // feed, admin_users). Теперь один source-of-truth — изменение opacity
  // через design-review = 1 место.
  //
  // glassOverlay — тёмное стекло поверх camera-controls / video / images.
  static const Color glassOverlay = Color(0x73000000); // rgba(0,0,0,0.45)
  // darkScrim — лёгкая тень снизу для readable-текста поверх media.
  static const Color darkScrim = Color(0xB3000000); // rgba(0,0,0,0.70)
  // mediumScrim — средняя тень (50% opacity). Часто для action-buttons.
  static const Color mediumScrim = Color(0x80000000); // rgba(0,0,0,0.50)
  // lightScrim — slight darkening для hover/pressed states.
  static const Color lightScrim = Color(0x66000000); // rgba(0,0,0,0.40)
  // softScrim — minimal — для subtle elevation hints.
  static const Color softScrim = Color(0x99000000); // rgba(0,0,0,0.60)
  // cameraDarkOverlay — near-opaque dark glass for camera/mask overlays.
  static const Color cameraDarkOverlay = Color(0xF0181412); // rgba(24,20,18,0.94)
  // transparentBlack — отправная точка для gradient'ов scrim → transparent.
  static const Color transparentBlack = Color(0x00000000);

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

// ─── Fonts (singleton) ─────────────────────────────────────────────────────
//
// Единственный источник семейств шрифтов на всё приложение. Синглтон:
// доступ только через `AppFonts.I`. В приложении ровно ДВА шрифта —
// `sans` (Inter, весь UI/текст/метки) и `serif` (Playfair Display, заголовки).
// Оба содержат полную кириллицу, поэтому fallback не нужен. Никаких сырых
// строк с именами шрифтов в коде — только `AppFonts.I.sans` / `.serif`.

class AppFonts {
  AppFonts._();

  static final AppFonts _instance = AppFonts._();

  /// Единственный экземпляр (singleton).
  static AppFonts get I => _instance;

  /// Основной sans — весь UI, body, kicker/eyebrow-метки.
  final String sans = 'Inter';

  /// Серифный — крупные editorial-заголовки (display*). Кириллица есть.
  final String serif = 'Playfair Display';

  /// Signature-шрифт бренда — ТОЛЬКО для wordmark названия «SeeU» (логотип).
  /// Не использовать для обычного текста.
  final String brand = 'Pacifico';
}

// ─── Typography ───────────────────────────────────────────────────────────

class SeeUTypography {
  SeeUTypography._();

  // Ровно два шрифта, оба через синглтон AppFonts.I. Mono-метки (kicker)
  // тоже идут на sans — отдельного моно-шрифта в приложении больше нет.
  static String get _serifFamily => AppFonts.I.serif;
  static String get _uiFamily => AppFonts.I.sans;
  static String get _monoFamily => AppFonts.I.sans;

  static TextStyle get displayXL => TextStyle(
    fontFamily: _serifFamily,
    fontSize: 42,
    fontWeight: FontWeight.w400,
    letterSpacing: -1.5,
    color: SeeUColors.textPrimary,
  );

  static TextStyle get displayL => TextStyle(
    fontFamily: _serifFamily,
    fontSize: 32,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.5,
    color: SeeUColors.textPrimary,
  );

  static TextStyle get displayM => TextStyle(
    fontFamily: _serifFamily,
    fontSize: 28,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.3,
    color: SeeUColors.textPrimary,
  );

  static TextStyle get displayS => TextStyle(
    fontFamily: _serifFamily,
    fontSize: 22,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.2,
    color: SeeUColors.textPrimary,
  );

  /// Самый мелкий серифный заголовок (20px) — заголовки секций, названия
  /// карточек, строк списков. Заменяет сырые `TextStyle(fontFamily:'Fraunces',
  /// fontSize:18–20)` без кириллического fallback (у которых русский текст
  /// молча терял сериф).
  static TextStyle get displayXS => TextStyle(
    fontFamily: _serifFamily,
    fontSize: 20,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.2,
    color: SeeUColors.textPrimary,
  );

  static TextStyle get title => TextStyle(
    fontFamily: _uiFamily,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    color: SeeUColors.textPrimary,
  );

  static TextStyle get subtitle => TextStyle(
    fontFamily: _uiFamily,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.2,
    color: SeeUColors.textPrimary,
  );

  static TextStyle get body => TextStyle(
    fontFamily: _uiFamily,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.1,
    color: SeeUColors.textPrimary,
  );

  static TextStyle get caption => TextStyle(
    fontFamily: _uiFamily,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    color: SeeUColors.textSecondary,
  );

  static TextStyle get micro => TextStyle(
    fontFamily: _uiFamily,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
    color: SeeUColors.textTertiary,
  );

  static TextStyle get mono => TextStyle(
    fontFamily: _monoFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: SeeUColors.textTertiary,
  );

  static TextStyle get monoLabel => TextStyle(
    fontFamily: _monoFamily,
    fontSize: 10,
    fontWeight: FontWeight.w400,
    letterSpacing: 1.0,
    color: SeeUColors.textTertiary,
  );

  /// Editorial eyebrow / kicker — small-caps mono for «рубрика · автор · время».
  /// Apply `.toUpperCase()` at the call site for the small-caps look; override
  /// `color` (e.g. accent) where needed.
  static TextStyle get kicker => TextStyle(
    fontFamily: _monoFamily,
    fontSize: 10,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.2,
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

// ─── Avatar Sizes ────────────────────────────────────────────────────────

class SeeUAvatarSizes {
  SeeUAvatarSizes._();
  static const double xl = 64;   // empty chat, profile header
  static const double lg = 52;   // chat list tile
  static const double md = 44;   // chat header, inline
  static const double sm = 36;   // small header avatar
  static const double xs = 28;   // chat bubble sender
  static const double xxs = 22;  // member list, compact
}

// ─── Touch Targets ──────────────────────────────────────────────────────

class SeeUTouchTargets {
  SeeUTouchTargets._();
  static const double button = 44;      // Apple HIG minimum
  static const double iconButton = 44;
  static const double searchBarHeight = 44;
}

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
