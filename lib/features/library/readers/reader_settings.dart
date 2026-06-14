import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ReaderTheme { light, sepia, dark, amoled }

enum ReaderFontFamily { system, serif, mono }

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
        return 'Georgia';
      case ReaderFontFamily.mono:
        return 'JetBrains Mono';
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
    state = ReaderSettings(
      fontSize: prefs.getDouble(_keyFontSize) ?? 16.0,
      lineHeight: prefs.getDouble(_keyLineHeight) ?? 1.6,
      theme: ReaderTheme.values[prefs.getInt(_keyTheme) ?? 0],
      fontFamily:
          ReaderFontFamily.values[prefs.getInt(_keyFontFamily) ?? 0],
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
}

final readerSettingsProvider =
    StateNotifierProvider<ReaderSettingsNotifier, ReaderSettings>(
  (ref) => ReaderSettingsNotifier(),
);
