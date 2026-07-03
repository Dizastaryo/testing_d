import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/design/tokens.dart';

enum ReaderTheme { light, sepia, dark, amoled }

/// Шрифт чтения. В приложении два шрифта (AppFonts): serif = Playfair,
/// sans = Inter; плюс системный по умолчанию.
enum ReaderFontFamily { system, serif, sans }

class ReaderSettings {
  final double fontSize;
  final double lineHeight;
  final ReaderTheme theme;
  final ReaderFontFamily fontFamily;

  const ReaderSettings({
    this.fontSize = 16.0,
    this.lineHeight = 1.6,
    this.theme = ReaderTheme.light,
    this.fontFamily = ReaderFontFamily.system,
  });

  ReaderSettings copyWith({
    double? fontSize,
    double? lineHeight,
    ReaderTheme? theme,
    ReaderFontFamily? fontFamily,
  }) =>
      ReaderSettings(
        fontSize: fontSize ?? this.fontSize,
        lineHeight: lineHeight ?? this.lineHeight,
        theme: theme ?? this.theme,
        fontFamily: fontFamily ?? this.fontFamily,
      );

  /// Имя шрифта для TextStyle.fontFamily (null = системный).
  String? get fontFamilyName {
    switch (fontFamily) {
      case ReaderFontFamily.system:
        return null;
      case ReaderFontFamily.serif:
        return AppFonts.I.serif;
      case ReaderFontFamily.sans:
        return AppFonts.I.sans;
    }
  }

  Color backgroundColor(BuildContext context) {
    switch (theme) {
      case ReaderTheme.light:
        return Theme.of(context).scaffoldBackgroundColor;
      case ReaderTheme.sepia:
        return const Color(0xFFF5EDD3);
      case ReaderTheme.dark:
        return const Color(0xFF1A1A1A);
      case ReaderTheme.amoled:
        return Colors.black;
    }
  }

  Color textColor(BuildContext context) {
    switch (theme) {
      case ReaderTheme.light:
        return Theme.of(context).colorScheme.onSurface;
      case ReaderTheme.sepia:
        return const Color(0xFF3D2B1A);
      case ReaderTheme.dark:
        return const Color(0xFFE0E0E0);
      case ReaderTheme.amoled:
        return Colors.white;
    }
  }

  bool get isNightMode => theme == ReaderTheme.dark || theme == ReaderTheme.amoled;

  /// Named presets for quick application.
  static const ReaderSettings comfortable = ReaderSettings(
    fontSize: 18,
    lineHeight: 1.8,
    theme: ReaderTheme.sepia,
    fontFamily: ReaderFontFamily.serif,
  );

  static const ReaderSettings night = ReaderSettings(
    fontSize: 17,
    lineHeight: 1.7,
    theme: ReaderTheme.dark,
    fontFamily: ReaderFontFamily.system,
  );

  static const ReaderSettings compact = ReaderSettings(
    fontSize: 14,
    lineHeight: 1.4,
    theme: ReaderTheme.light,
    fontFamily: ReaderFontFamily.system,
  );
}

class ReaderSettingsNotifier extends StateNotifier<ReaderSettings> {
  static const _keyFontSize = 'reader_fontSize';
  static const _keyLineHeight = 'reader_lineHeight';
  static const _keyTheme = 'reader_theme';
  static const _keyFontFamily = 'reader_fontFamily';

  ReaderSettingsNotifier() : super(const ReaderSettings()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIdx = prefs.getInt(_keyTheme) ?? 0;
    final fontIdx = prefs.getInt(_keyFontFamily) ?? 0;
    state = ReaderSettings(
      fontSize: prefs.getDouble(_keyFontSize) ?? 16.0,
      lineHeight: prefs.getDouble(_keyLineHeight) ?? 1.6,
      theme: themeIdx < ReaderTheme.values.length
          ? ReaderTheme.values[themeIdx]
          : ReaderTheme.light,
      fontFamily: fontIdx < ReaderFontFamily.values.length
          ? ReaderFontFamily.values[fontIdx]
          : ReaderFontFamily.system,
    );
  }

  Future<void> setFontSize(double v) async {
    state = state.copyWith(fontSize: v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyFontSize, v);
  }

  Future<void> setLineHeight(double v) async {
    state = state.copyWith(lineHeight: v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyLineHeight, v);
  }

  Future<void> setTheme(ReaderTheme t) async {
    state = state.copyWith(theme: t);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyTheme, t.index);
  }

  Future<void> setFontFamily(ReaderFontFamily f) async {
    state = state.copyWith(fontFamily: f);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyFontFamily, f.index);
  }

  Future<void> applyPreset(ReaderSettings preset) async {
    state = preset;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyFontSize, preset.fontSize);
    await prefs.setDouble(_keyLineHeight, preset.lineHeight);
    await prefs.setInt(_keyTheme, preset.theme.index);
    await prefs.setInt(_keyFontFamily, preset.fontFamily.index);
  }

  Future<void> reset() => applyPreset(const ReaderSettings());
}

final readerSettingsProvider =
    StateNotifierProvider<ReaderSettingsNotifier, ReaderSettings>(
  (ref) => ReaderSettingsNotifier(),
);
