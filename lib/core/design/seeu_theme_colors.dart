import 'package:flutter/material.dart';
import 'tokens.dart';

/// Adaptive color accessor — returns correct color based on current theme.
/// Usage: `SeeUTheme.of(context).bg` or `context.seeuColors.bg`
class SeeUThemeColors {
  final Brightness brightness;

  const SeeUThemeColors._(this.brightness);

  factory SeeUThemeColors.of(BuildContext context) {
    return SeeUThemeColors._(Theme.of(context).brightness);
  }

  bool get isDark => brightness == Brightness.dark;

  // Backgrounds
  Color get bg => isDark ? SeeUColors.darkBg : SeeUColors.background;
  Color get surface => isDark ? SeeUColors.darkSurface : SeeUColors.surface;
  Color get surface2 => isDark ? SeeUColors.darkSurface2 : SeeUColors.surface2;

  // Text
  Color get ink => isDark ? SeeUColors.darkInk : SeeUColors.textPrimary;
  Color get ink2 => isDark ? SeeUColors.darkInk2 : SeeUColors.textSecondary;
  Color get ink3 => isDark ? SeeUColors.darkInk3 : SeeUColors.textTertiary;
  Color get ink4 => isDark ? SeeUColors.darkInk4 : SeeUColors.textQuaternary;

  // Borders
  Color get line => isDark ? SeeUColors.darkLine : SeeUColors.borderSubtle;

  // Accent soft
  Color get accentSoft => isDark ? SeeUColors.darkCoralSoft : SeeUColors.accentSoft;
}

/// Extension for quick access: `context.seeuColors.bg`
extension SeeUThemeExtension on BuildContext {
  SeeUThemeColors get seeuColors => SeeUThemeColors.of(this);
}
