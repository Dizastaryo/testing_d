import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Enums ──────────────────────────────────────────────────────────────────

enum PdfScrollDirection { vertical, horizontal }

enum PdfBackground { auto, white, dark, black }

enum PdfThemeMode { light, dark, amoled }

// ─── Model ──────────────────────────────────────────────────────────────────

class PdfReaderSettings {
  final PdfThemeMode themeMode;
  final PdfScrollDirection scrollDirection;
  final bool pageFling;
  final bool autoSpacing;
  final PdfBackground background;
  final bool keepAwake;

  const PdfReaderSettings({
    this.themeMode = PdfThemeMode.light,
    this.scrollDirection = PdfScrollDirection.vertical,
    this.pageFling = true,
    this.autoSpacing = true,
    this.background = PdfBackground.auto,
    this.keepAwake = true,
  });

  PdfReaderSettings copyWith({
    PdfThemeMode? themeMode,
    PdfScrollDirection? scrollDirection,
    bool? pageFling,
    bool? autoSpacing,
    PdfBackground? background,
    bool? keepAwake,
  }) =>
      PdfReaderSettings(
        themeMode: themeMode ?? this.themeMode,
        scrollDirection: scrollDirection ?? this.scrollDirection,
        pageFling: pageFling ?? this.pageFling,
        autoSpacing: autoSpacing ?? this.autoSpacing,
        background: background ?? this.background,
        keepAwake: keepAwake ?? this.keepAwake,
      );

  bool get isNightMode =>
      themeMode == PdfThemeMode.dark || themeMode == PdfThemeMode.amoled;

  bool get isHorizontal => scrollDirection == PdfScrollDirection.horizontal;

  /// Background color for the area around PDF pages.
  Color get backgroundColor {
    switch (background) {
      case PdfBackground.auto:
        return isNightMode ? const Color(0xFF121212) : const Color(0xFFF0F0F0);
      case PdfBackground.white:
        return const Color(0xFFF5F5F5);
      case PdfBackground.dark:
        return const Color(0xFF1A1A1A);
      case PdfBackground.black:
        return Colors.black;
    }
  }

  /// Quick presets.
  static const PdfReaderSettings day = PdfReaderSettings(
    themeMode: PdfThemeMode.light,
    scrollDirection: PdfScrollDirection.vertical,
    pageFling: true,
    autoSpacing: true,
    background: PdfBackground.auto,
  );

  static const PdfReaderSettings night = PdfReaderSettings(
    themeMode: PdfThemeMode.dark,
    scrollDirection: PdfScrollDirection.vertical,
    pageFling: true,
    autoSpacing: true,
    background: PdfBackground.auto,
  );

  static const PdfReaderSettings flipBook = PdfReaderSettings(
    themeMode: PdfThemeMode.light,
    scrollDirection: PdfScrollDirection.horizontal,
    pageFling: true,
    autoSpacing: true,
    background: PdfBackground.auto,
  );

  static const PdfReaderSettings continuous = PdfReaderSettings(
    themeMode: PdfThemeMode.light,
    scrollDirection: PdfScrollDirection.vertical,
    pageFling: false,
    autoSpacing: false,
    background: PdfBackground.auto,
  );
}

// ─── Notifier ───────────────────────────────────────────────────────────────

class PdfReaderSettingsNotifier extends StateNotifier<PdfReaderSettings> {
  static const _keyTheme = 'pdf_themeMode';
  static const _keyScroll = 'pdf_scrollDirection';
  static const _keyFling = 'pdf_pageFling';
  static const _keySpacing = 'pdf_autoSpacing';
  static const _keyBg = 'pdf_background';
  static const _keyAwake = 'pdf_keepAwake';

  PdfReaderSettingsNotifier() : super(const PdfReaderSettings()) {
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    state = PdfReaderSettings(
      themeMode: _enumAt(PdfThemeMode.values, p.getInt(_keyTheme)),
      scrollDirection:
          _enumAt(PdfScrollDirection.values, p.getInt(_keyScroll)),
      pageFling: p.getBool(_keyFling) ?? true,
      autoSpacing: p.getBool(_keySpacing) ?? true,
      background: _enumAt(PdfBackground.values, p.getInt(_keyBg)),
      keepAwake: p.getBool(_keyAwake) ?? true,
    );
  }

  T _enumAt<T extends Enum>(List<T> values, int? index) {
    if (index == null || index < 0 || index >= values.length) {
      return values.first;
    }
    return values[index];
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await Future.wait([
      p.setInt(_keyTheme, state.themeMode.index),
      p.setInt(_keyScroll, state.scrollDirection.index),
      p.setBool(_keyFling, state.pageFling),
      p.setBool(_keySpacing, state.autoSpacing),
      p.setInt(_keyBg, state.background.index),
      p.setBool(_keyAwake, state.keepAwake),
    ]);
  }

  void setTheme(PdfThemeMode v) {
    state = state.copyWith(themeMode: v);
    _save();
  }

  void setScrollDirection(PdfScrollDirection v) {
    state = state.copyWith(scrollDirection: v);
    _save();
  }

  void setPageFling(bool v) {
    state = state.copyWith(pageFling: v);
    _save();
  }

  void setAutoSpacing(bool v) {
    state = state.copyWith(autoSpacing: v);
    _save();
  }

  void setBackground(PdfBackground v) {
    state = state.copyWith(background: v);
    _save();
  }

  void setKeepAwake(bool v) {
    state = state.copyWith(keepAwake: v);
    _save();
  }

  void applyPreset(PdfReaderSettings preset) {
    state = preset;
    _save();
  }

  void reset() => applyPreset(const PdfReaderSettings());
}

// ─── Provider ───────────────────────────────────────────────────────────────

final pdfReaderSettingsProvider =
    StateNotifierProvider<PdfReaderSettingsNotifier, PdfReaderSettings>(
  (ref) => PdfReaderSettingsNotifier(),
);
