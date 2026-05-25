import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../design/tokens.dart';

class AppTheme {
  AppTheme._();

  static const Color primaryBlue = SeeUColors.accent;
  static const Color likeRed = SeeUColors.like;
  static const Color secondaryText = SeeUColors.textSecondary;

  static const LinearGradient storyGradient = SeeUColors.storyGradient;

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [SeeUColors.accent, Color(0xFFC04CFD)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData get light {
    final baseTextTheme = ThemeData.light().textTheme;

    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme(
        brightness: Brightness.light,
        primary: SeeUColors.accent,
        onPrimary: Colors.white,
        secondary: Color(0xFFC04CFD),
        onSecondary: Colors.white,
        error: SeeUColors.error,
        onError: Colors.white,
        surface: SeeUColors.surface,
        onSurface: SeeUColors.textPrimary,
        surfaceContainerHighest: SeeUColors.surface2,
        surfaceContainerLowest: SeeUColors.background,
        outline: SeeUColors.borderSubtle,
        outlineVariant: SeeUColors.borderSubtle,
      ),
      scaffoldBackgroundColor: SeeUColors.background,
      // Swipe-back gesture на всех платформах (iOS-style).
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          for (final p in TargetPlatform.values)
            p: const CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: SeeUColors.background,
        foregroundColor: SeeUColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
        ),
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          color: SeeUColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
        iconTheme: const IconThemeData(color: SeeUColors.textPrimary),
      ),
      dividerTheme: const DividerThemeData(
        color: SeeUColors.borderSubtle,
        thickness: 0.5,
        space: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: SeeUColors.surface2,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide:
              const BorderSide(color: SeeUColors.accentSoft, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: SeeUColors.error, width: 1),
        ),
        hintStyle: TextStyle(
          fontFamily: 'Inter',
          color: SeeUColors.textTertiary,
          fontSize: 15,
        ),
        labelStyle: TextStyle(
          fontFamily: 'Inter',
          color: SeeUColors.textTertiary,
          fontSize: 15,
        ),
      ),
      textTheme: baseTextTheme.copyWith(
        headlineLarge: SeeUTypography.displayXL,
        headlineMedium: SeeUTypography.displayL,
        titleLarge: SeeUTypography.title,
        titleMedium: SeeUTypography.subtitle,
        titleSmall: SeeUTypography.caption,
        bodyLarge: SeeUTypography.body,
        bodyMedium: SeeUTypography.caption,
        bodySmall: SeeUTypography.micro,
        labelLarge: SeeUTypography.subtitle,
        labelSmall: SeeUTypography.micro,
      ),
    );
  }

  static ThemeData get dark {
    final baseTextTheme = ThemeData.dark().textTheme;

    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme(
        brightness: Brightness.dark,
        primary: SeeUColors.accent,
        onPrimary: Colors.white,
        secondary: Color(0xFFC04CFD),
        onSecondary: Colors.white,
        error: SeeUColors.error,
        onError: Colors.white,
        surface: SeeUColors.darkSurface,
        onSurface: SeeUColors.darkInk,
        surfaceContainerHighest: SeeUColors.darkSurface2,
        surfaceContainerLowest: SeeUColors.darkBg,
        outline: SeeUColors.darkLine,
        outlineVariant: SeeUColors.darkLine,
      ),
      scaffoldBackgroundColor: SeeUColors.darkBg,
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          for (final p in TargetPlatform.values)
            p: const CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: SeeUColors.darkBg,
        foregroundColor: SeeUColors.darkInk,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          color: SeeUColors.darkInk,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
        iconTheme: const IconThemeData(color: SeeUColors.darkInk),
      ),
      dividerTheme: const DividerThemeData(
        color: SeeUColors.darkLine,
        thickness: 0.5,
        space: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: SeeUColors.darkSurface2,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: SeeUColors.accent.withValues(alpha: 0.5), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: SeeUColors.error, width: 1),
        ),
        hintStyle: TextStyle(fontFamily: 'Inter', color: SeeUColors.darkInk3, fontSize: 15),
        labelStyle: TextStyle(fontFamily: 'Inter', color: SeeUColors.darkInk3, fontSize: 15),
      ),
      textTheme: baseTextTheme.copyWith(
        headlineLarge: SeeUTypography.displayXL.copyWith(color: SeeUColors.darkInk),
        headlineMedium: SeeUTypography.displayL.copyWith(color: SeeUColors.darkInk),
        titleLarge: SeeUTypography.title.copyWith(color: SeeUColors.darkInk),
        titleMedium: SeeUTypography.subtitle.copyWith(color: SeeUColors.darkInk),
        titleSmall: SeeUTypography.caption.copyWith(color: SeeUColors.darkInk2),
        bodyLarge: SeeUTypography.body.copyWith(color: SeeUColors.darkInk),
        bodyMedium: SeeUTypography.caption.copyWith(color: SeeUColors.darkInk2),
        bodySmall: SeeUTypography.micro.copyWith(color: SeeUColors.darkInk3),
        labelLarge: SeeUTypography.subtitle.copyWith(color: SeeUColors.darkInk),
        labelSmall: SeeUTypography.micro.copyWith(color: SeeUColors.darkInk3),
      ),
    );
  }
}
