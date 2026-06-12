import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ReaderTheme { light, sepia, dark }

class ReaderSettings {
  final double fontSize;
  final double lineHeight; // 1.5 = Normal, 1.9 = Wide
  final ReaderTheme theme;

  const ReaderSettings({
    this.fontSize = 16.0,
    this.lineHeight = 1.6,
    this.theme = ReaderTheme.light,
  });

  ReaderSettings copyWith({
    double? fontSize,
    double? lineHeight,
    ReaderTheme? theme,
  }) =>
      ReaderSettings(
        fontSize: fontSize ?? this.fontSize,
        lineHeight: lineHeight ?? this.lineHeight,
        theme: theme ?? this.theme,
      );

  Color backgroundColor(BuildContext context) {
    switch (theme) {
      case ReaderTheme.light:
        return Theme.of(context).scaffoldBackgroundColor;
      case ReaderTheme.sepia:
        return const Color(0xFFF5EDD3);
      case ReaderTheme.dark:
        return const Color(0xFF1A1A1A);
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
    }
  }
}

class ReaderSettingsNotifier extends StateNotifier<ReaderSettings> {
  static const _keyFontSize = 'reader_fontSize';
  static const _keyLineHeight = 'reader_lineHeight';
  static const _keyTheme = 'reader_theme';

  ReaderSettingsNotifier() : super(const ReaderSettings()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = ReaderSettings(
      fontSize: prefs.getDouble(_keyFontSize) ?? 16.0,
      lineHeight: prefs.getDouble(_keyLineHeight) ?? 1.6,
      theme: ReaderTheme.values[prefs.getInt(_keyTheme) ?? 0],
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
}

final readerSettingsProvider =
    StateNotifierProvider<ReaderSettingsNotifier, ReaderSettings>(
  (ref) => ReaderSettingsNotifier(),
);
