import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _prefUiStyleKey = 'app_ui_style_preference';

/// How much of the Fluent-inspired surface treatment the app paints.
///
/// This is deliberately separate from [ThemeMode] and the dark colour
/// presets: those decide *which colours* are used, this decides *how the
/// surfaces are rendered* with those colours.
enum AppUiStyle {
  /// The original look: flat scaffold background, solid opaque cards,
  /// no backdrop blur and no animation. Cheapest to render, and the most
  /// readable on low-end screens.
  classic,

  /// Microsoft Mica: a single static, very subtle backdrop tint behind the
  /// content, solid cards on top. No animation, no backdrop blur — this is
  /// what Windows 11 uses for app window backgrounds.
  mica,

  /// Microsoft Acrylic: animated gradient backdrop, drifting accent orbs
  /// and translucent blurred (frosted) cards. The richest look, and the
  /// most expensive to render.
  acrylic,
}

extension AppUiStyleX on AppUiStyle {
  /// True when surfaces should be translucent and backdrop-blurred.
  bool get usesAcrylic => this == AppUiStyle.acrylic;

  /// True when any backdrop tint is painted behind the content at all.
  bool get usesBackdropTint => this != AppUiStyle.classic;

  /// True when backdrop tints and orbs animate. Off for Mica by design —
  /// Mica is a still surface — and off for Classic, which has no tint.
  bool get usesMotion => this == AppUiStyle.acrylic;

  String get label {
    switch (this) {
      case AppUiStyle.classic:
        return 'Classic';
      case AppUiStyle.mica:
        return 'Fluent Mica';
      case AppUiStyle.acrylic:
        return 'Fluent Acrylic';
    }
  }
}

class AppUiStyleNotifier extends Notifier<AppUiStyle> {
  /// Set in `main()` before `runApp` so the very first frame is already
  /// painted in the saved style instead of flashing the default one.
  static AppUiStyle? initialStyle;

  static Future<AppUiStyle> loadInitialStyle() async {
    final prefs = await SharedPreferences.getInstance();
    switch (prefs.getString(_prefUiStyleKey)) {
      case 'classic':
        return AppUiStyle.classic;
      case 'mica':
        return AppUiStyle.mica;
      case 'acrylic':
        return AppUiStyle.acrylic;
      default:
        // Keeps the look the app already shipped with for anyone who has
        // never opened the picker.
        return AppUiStyle.acrylic;
    }
  }

  @override
  AppUiStyle build() {
    if (initialStyle != null) {
      return initialStyle!;
    }
    _load();
    return AppUiStyle.acrylic;
  }

  Future<void> _load() async {
    final style = await loadInitialStyle();
    if (state != style) {
      state = style;
    }
  }

  Future<void> setStyle(AppUiStyle style) async {
    state = style;
    initialStyle = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefUiStyleKey, style.name);
  }
}

final appUiStyleProvider = NotifierProvider<AppUiStyleNotifier, AppUiStyle>(
  AppUiStyleNotifier.new,
);
