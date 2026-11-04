import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';

const String _prefThemeModeKey = 'app_theme_mode_preference';
const String _prefDarkPresetKey = 'app_dark_theme_preset_preference';

/// Available curated aesthetic dark theme presets.
enum DarkThemePreset {
  cuteVelvet,
  cozyMocha,
  nordicTwilight,
  oledBatterySaver,
}

class DarkThemePresetNotifier extends Notifier<DarkThemePreset> {
  static DarkThemePreset? initialPreset;

  static Future<DarkThemePreset> loadInitialPreset() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefDarkPresetKey);
    switch (saved) {
      case 'cuteVelvet':
        return DarkThemePreset.cuteVelvet;
      case 'cozyMocha':
        return DarkThemePreset.cozyMocha;
      case 'nordicTwilight':
        return DarkThemePreset.nordicTwilight;
      case 'oledBatterySaver':
        return DarkThemePreset.oledBatterySaver;
      default:
        // Defaults to the soft, aesthetic Cute Velvet Night.
        return DarkThemePreset.cuteVelvet;
    }
  }

  @override
  DarkThemePreset build() {
    if (initialPreset != null) {
      return initialPreset!;
    }
    _loadPreset();
    return DarkThemePreset.cuteVelvet;
  }

  Future<void> _loadPreset() async {
    final preset = await loadInitialPreset();
    if (state != preset) {
      state = preset;
    }
  }

  Future<void> setPreset(DarkThemePreset preset) async {
    state = preset;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefDarkPresetKey, preset.name);
  }
}

final darkThemePresetProvider =
    NotifierProvider<DarkThemePresetNotifier, DarkThemePreset>(
      DarkThemePresetNotifier.new,
    );

final currentDarkThemeProvider = Provider<ThemeData>((ref) {
  final preset = ref.watch(darkThemePresetProvider);
  switch (preset) {
    case DarkThemePreset.cuteVelvet:
      return AppTheme.cuteVelvetDarkTheme;
    case DarkThemePreset.cozyMocha:
      return AppTheme.cozyMochaDarkTheme;
    case DarkThemePreset.nordicTwilight:
      return AppTheme.nordicTwilightDarkTheme;
    case DarkThemePreset.oledBatterySaver:
      return AppTheme.darkTheme;
  }
});

class ThemeModeNotifier extends Notifier<ThemeMode> {
  static ThemeMode? initialMode;

  static Future<ThemeMode> loadInitialThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString(_prefThemeModeKey);
    switch (savedMode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  @override
  ThemeMode build() {
    if (initialMode != null) {
      return initialMode!;
    }
    _loadThemeMode();
    return ThemeMode.system;
  }

  Future<void> _loadThemeMode() async {
    final mode = await loadInitialThemeMode();
    if (state != mode) {
      state = mode;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    String modeString;
    switch (mode) {
      case ThemeMode.light:
        modeString = 'light';
        break;
      case ThemeMode.dark:
        modeString = 'dark';
        break;
      case ThemeMode.system:
        modeString = 'system';
        break;
    }
    await prefs.setString(_prefThemeModeKey, modeString);
  }

  Future<void> toggleTheme() async {
    if (state == ThemeMode.dark) {
      await setThemeMode(ThemeMode.light);
    } else {
      await setThemeMode(ThemeMode.dark);
    }
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);
