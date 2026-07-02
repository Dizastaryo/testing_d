import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App theme mode. Defaults to light; the user's choice is persisted across
/// launches in SharedPreferences. SeeUColors semantic colors + SeeUTypography
/// are theme-aware (resolve via SeeUColors.themeBrightness, bridged from the
/// active Theme in main.dart), so screens reading them directly adapt.
class ThemeNotifier extends StateNotifier<ThemeMode> {
  static const _prefsKey = 'theme_mode';

  ThemeNotifier() : super(ThemeMode.light) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    switch (prefs.getString(_prefsKey)) {
      case 'dark':
        state = ThemeMode.dark;
      case 'system':
        state = ThemeMode.system;
      case 'light':
        state = ThemeMode.light;
      // null / unknown → keep the default (light)
    }
  }

  Future<void> _persist(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.name);
  }

  void setLight() => setThemeMode(ThemeMode.light);
  void setDark() => setThemeMode(ThemeMode.dark);
  void setSystem() => setThemeMode(ThemeMode.system);

  void setThemeMode(ThemeMode mode) {
    state = mode;
    _persist(mode);
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) {
  return ThemeNotifier();
});
