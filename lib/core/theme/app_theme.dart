import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // Primary brand colors
  static const Color primaryLight = Color(0xFF1E3A8A); // Deep Indigo
  static const Color secondaryLight = Color(0xFF0D9488); // Teal
  static const Color bgLight = Color(0xFFF8FAFC);
  static const Color cardLight = Colors.white;
  static const Color borderLight = Color(0xFFE2E8F0);

  // OLED True Dark / Obsidian Midnight Palette
  static const Color primaryDark = Color(0xFF6366F1); // Indigo 500
  static const Color secondaryDark = Color(0xFF14B8A6); // Teal 500
  static const Color bgDark = Color(0xFF090D1A); // Midnight OLED Dark
  static const Color cardDark = Color(0xFF111827); // Obsidian Slate
  static const Color borderDark = Color(0xFF1E293B); // Muted slate border
  static const Color textDark = Color(0xFFF1F5F9); // Slate 100
  static const Color textMutedDark = Color(0xFF94A3B8); // Slate 400

  // Typography fallbacks for Bengali and Math symbols
  static const List<String> fontFallbacks = [
    'Noto Sans Bengali',
    'Roboto',
    'sans-serif',
  ];

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamilyFallback: fontFallbacks,
      scaffoldBackgroundColor: bgLight,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryLight,
        brightness: Brightness.light,
        primary: primaryLight,
        secondary: secondaryLight,
        surface: cardLight,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: bgLight,
        foregroundColor: Color(0xFF0F172A),
        titleTextStyle: TextStyle(
          color: Color(0xFF0F172A),
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardLight,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: borderLight, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cardLight,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: cardLight,
        modalBackgroundColor: cardLight,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: const DividerThemeData(color: borderLight, thickness: 1),
      tabBarTheme: const TabBarThemeData(
        labelColor: primaryLight,
        unselectedLabelColor: Color(0xFF64748B),
        indicatorColor: primaryLight,
      ),
      listTileTheme: const ListTileThemeData(
        textColor: Color(0xFF0F172A),
        iconColor: Color(0xFF0F172A),
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: cardLight,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryLight, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  /// The default OLED Ultra-Black power saver theme (Obsidian Midnight).
  static ThemeData get darkTheme {
    return _buildDarkCustomTheme(
      scaffoldBg: bgDark,
      cardBg: cardDark,
      border: borderDark,
      primary: primaryDark,
      secondary: secondaryDark,
      text: textDark,
      textMuted: textMutedDark,
      inputFill: const Color(0xFF1E293B),
      navBarBg: const Color(0xFF0C1222),
    );
  }

  /// Nature Green: Soothing forest greens with earthy tones.
  /// Perfect for nature‑loving users, low eye‑strain, calm focus.
  static ThemeData get natureGreenDarkTheme {
    return _buildDarkCustomTheme(
      scaffoldBg: const Color(0xFF0D1B1A), // deep forest
      cardBg: const Color(0xFF1A2E2C),
      border: const Color(0xFF2C4B44),
      primary: const Color(0xFF34D399), // teal‑green
      secondary: const Color(0xFF10B981), // emerald
      text: const Color(0xFFE6FFFA), // mint
      textMuted: const Color(0xFF81E6D9),
      inputFill: const Color(0xFF123530),
      navBarBg: const Color(0xFF082622),
    );
  }

  /// Ice Blue: Crisp icy cyan on a deep midnight backdrop.
  /// Gives a fresh, clean look with subtle contrast.
  static ThemeData get iceBlueDarkTheme {
    return _buildDarkCustomTheme(
      scaffoldBg: const Color(0xFF0A0F1A), // midnight blue
      cardBg: const Color(0xFF111827), // slate dark
      border: const Color(0xFF1E3A8A), // icy border
      primary: const Color(0xFF60A5FA), // ice blue
      secondary: const Color(0xFF38BDF8), // bright cyan
      text: const Color(0xFFE0F2FE), // very light blue
      textMuted: const Color(0xFF94A3B8),
      inputFill: const Color(0xFF1E293B),
      navBarBg: const Color(0xFF0F172A),
    );
  }

  /// Premium Gold: Luxurious dark with vivid gold accent.
  static ThemeData get premiumGoldDarkTheme {
    return _buildDarkCustomTheme(
      scaffoldBg: const Color(0xFF12100E),
      cardBg: const Color(0xFF1C1A17),
      border: const Color(0xFF3D3520),
      primary: const Color(0xFFFFB800),
      secondary: const Color(0xFFFF8C00),
      text: const Color(0xFFFFF8E7),
      textMuted: const Color(0xFFBFAE80),
      inputFill: const Color(0xFF25211A),
      navBarBg: const Color(0xFF0F0D0A),
    );
  }

  /// Cute Velvet Night: Soft Lavender, Pastel Rosewater & Cozy Deep Charcoal.
  /// Designed for visual delight, warmth, and zero eye fatigue.
  static ThemeData get cuteVelvetDarkTheme {
    return _buildDarkCustomTheme(
      scaffoldBg: const Color(0xFF161622),
      cardBg: const Color(0xFF202030),
      border: const Color(0xFF2E2E44),
      primary: const Color(0xFFC084FC), // Soft Lilac / Lavender
      secondary: const Color(0xFFF472B6), // Blush Rosewater
      text: const Color(0xFFF8FAFC),
      textMuted: const Color(0xFFA6ADC8),
      inputFill: const Color(0xFF252538),
      navBarBg: const Color(0xFF1B1B2A),
    );
  }

  /// Cozy Mocha: Warm Roasted Espresso, Honey Caramel Amber & Cream.
  /// Designed for a classic bookish library and coffee shop study vibe.
  static ThemeData get cozyMochaDarkTheme {
    return _buildDarkCustomTheme(
      scaffoldBg: const Color(0xFF181514),
      cardBg: const Color(0xFF24201E),
      border: const Color(0xFF38312C),
      primary: const Color(0xFFF59E0B), // Honey Amber
      secondary: const Color(0xFFFB923C), // Warm Apricot
      text: const Color(0xFFFEF3C7),
      textMuted: const Color(0xFFA8A29E),
      inputFill: const Color(0xFF2C2623),
      navBarBg: const Color(0xFF1C1816),
    );
  }

  /// Nordic Twilight: Deep Arctic Blueberry Navy & Ice Cyan.
  /// Calm, focused, and crisp night palette.
  static ThemeData get nordicTwilightDarkTheme {
    return _buildDarkCustomTheme(
      scaffoldBg: const Color(0xFF0B1329),
      cardBg: const Color(0xFF131F3F),
      border: const Color(0xFF1E305C),
      primary: const Color(0xFF38BDF8), // Ice Cyan
      secondary: const Color(0xFF818CF8), // Periwinkle Indigo
      text: const Color(0xFFF0F9FF),
      textMuted: const Color(0xFF94A3B8),
      inputFill: const Color(0xFF16244A),
      navBarBg: const Color(0xFF0F1A35),
    );
  }

  static ThemeData _buildDarkCustomTheme({
    required Color scaffoldBg,
    required Color cardBg,
    required Color border,
    required Color primary,
    required Color secondary,
    required Color text,
    required Color textMuted,
    required Color inputFill,
    required Color navBarBg,
  }) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamilyFallback: fontFallbacks,
      scaffoldBackgroundColor: scaffoldBg,
      canvasColor: scaffoldBg,
      colorScheme: ColorScheme(
        brightness: Brightness.dark,
        primary: primary,
        onPrimary: Colors.white,
        secondary: secondary,
        onSecondary: Colors.white,
        error: const Color(0xFFEF4444),
        onError: Colors.white,
        surface: cardBg,
        onSurface: text,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: scaffoldBg,
        foregroundColor: text,
        titleTextStyle: TextStyle(
          color: text,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardBg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border, width: 1),
        ),
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: text),
        bodyMedium: TextStyle(color: text),
        bodySmall: TextStyle(color: textMuted),
        titleLarge: TextStyle(color: text, fontWeight: FontWeight.bold),
        titleMedium: TextStyle(color: text, fontWeight: FontWeight.w600),
        titleSmall: TextStyle(color: textMuted),
        labelLarge: TextStyle(color: text, fontWeight: FontWeight.w600),
        labelMedium: TextStyle(color: textMuted),
        labelSmall: TextStyle(color: textMuted),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: textMuted,
        indicatorColor: primary,
      ),
      listTileTheme: ListTileThemeData(textColor: text, iconColor: text),
      popupMenuTheme: PopupMenuThemeData(
        color: cardBg,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(color: text),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: inputFill,
        labelStyle: TextStyle(color: text),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cardBg,
        modalBackgroundColor: cardBg,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cardBg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: navBarBg,
        indicatorColor: primary.withValues(alpha: 0.25),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: primary);
          }
          return IconThemeData(color: textMuted);
        }),
      ),
    );
  }
}
