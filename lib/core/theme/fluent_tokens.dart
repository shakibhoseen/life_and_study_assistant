import 'package:flutter/material.dart';

/// Design tokens taken from Microsoft's Fluent 2 / Windows 11 (WinUI) system.
///
/// These exist so the app stops inventing a new radius, shadow and font size
/// at every call site. Everything visual should come from here.
///
/// The three rules that make Fluent look like Fluent, and that the app was
/// breaking everywhere:
///
///  1. **Small, consistent radii.** 4px on controls, 8px on cards and
///     overlays. Not 12, 16 and 20 mixed on one screen.
///  2. **Stroke, not glow.** A card at rest is a solid surface with a 1px
///     border and a shadow you can barely see. Coloured glows are not a
///     Fluent idiom.
///  3. **One accent.** Accent marks the thing you act on. Everything else is
///     neutral, and colour beyond that is reserved for status meaning.
abstract final class FluentRadius {
  /// Controls with a backplate: buttons, inputs, chips, checkboxes.
  /// WinUI `ControlCornerRadius`.
  static const double control = 4.0;

  /// Cards, list surfaces, flyouts, dialogs. WinUI `OverlayCornerRadius`
  /// and the layer radius Fluent 2 calls out for larger components.
  static const double card = 8.0;

  /// Extra-large surfaces only: bottom sheets, full-width hero panels.
  static const double large = 12.0;

  static BorderRadius get controlBorder => BorderRadius.circular(control);
  static BorderRadius get cardBorder => BorderRadius.circular(card);
  static BorderRadius get largeBorder => BorderRadius.circular(large);
}

/// The 4px spacing grid. Pick from these instead of typing 3, 6, 7, 14.
abstract final class FluentSpacing {
  static const double xxs = 2.0;
  static const double xs = 4.0;
  static const double s = 8.0;
  static const double m = 12.0;
  static const double l = 16.0;
  static const double xl = 20.0;
  static const double xxl = 24.0;
}

/// Stroke colours for the 1px border that defines a card in Fluent.
///
/// Windows 11 uses a slightly lighter stroke than the surface in dark mode
/// and a slightly darker one in light mode, so the card edge reads without
/// a shadow doing the work.
abstract final class FluentStroke {
  static const double width = 1.0;

  static Color card(Brightness brightness) => brightness == Brightness.dark
      ? const Color(0x1AFFFFFF) // white @ 10%
      : const Color(0x14000000); // black @ 8%

  /// A stronger divider, for separating rows inside one card.
  static Color divider(Brightness brightness) => brightness == Brightness.dark
      ? const Color(0x12FFFFFF)
      : const Color(0x0F000000);

  static BorderSide side(Brightness brightness) =>
      BorderSide(color: card(brightness), width: width);
}

/// Fluent's elevation ramp. Deliberately subtle — `card` is almost invisible,
/// which is the point: depth comes from the stroke and the layer fill.
abstract final class FluentElevation {
  /// A card at rest. Fluent `shadow2`.
  static List<BoxShadow> card(Brightness brightness) {
    final a = brightness == Brightness.dark ? 0.24 : 0.07;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: a),
        blurRadius: 2,
        offset: const Offset(0, 1),
      ),
    ];
  }

  /// A raised/pressed card or a dropdown. Fluent `shadow4`.
  static List<BoxShadow> raised(Brightness brightness) {
    final a = brightness == Brightness.dark ? 0.28 : 0.10;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: a),
        blurRadius: 4,
        offset: const Offset(0, 2),
      ),
    ];
  }

  /// Flyouts and popovers. Fluent `shadow8`.
  static List<BoxShadow> flyout(Brightness brightness) {
    final a = brightness == Brightness.dark ? 0.32 : 0.12;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: a),
        blurRadius: 8,
        offset: const Offset(0, 4),
      ),
    ];
  }
}

/// The Windows 11 type ramp.
///
/// Sizes are paired with the line heights WinUI actually ships, expressed as
/// Flutter's `height` multiplier so Bengali text — which needs more leading
/// than Latin — does not collide line to line.
abstract final class FluentType {
  /// 12 / 16. Secondary and supporting text, timestamps, badges.
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    height: 1.45,
    fontWeight: FontWeight.w400,
  );

  /// 14 / 20. The default reading size for body copy.
  static const TextStyle body = TextStyle(
    fontSize: 14,
    height: 1.45,
    fontWeight: FontWeight.w400,
  );

  /// 14 / 20 semibold. A body line that needs emphasis — list item titles,
  /// inline labels. This is the workhorse Fluent uses instead of bolding
  /// body text.
  static const TextStyle bodyStrong = TextStyle(
    fontSize: 14,
    height: 1.45,
    fontWeight: FontWeight.w600,
  );

  /// 20 / 28 semibold. Card titles and section headers.
  static const TextStyle subtitle = TextStyle(
    fontSize: 20,
    height: 1.4,
    fontWeight: FontWeight.w600,
  );

  /// 28 / 36 semibold. Page titles.
  static const TextStyle title = TextStyle(
    fontSize: 28,
    height: 1.3,
    fontWeight: FontWeight.w600,
  );
}

/// Layer fills: the solid surface a card paints on top of the Mica-tinted
/// window background.
abstract final class FluentLayer {
  /// The card surface itself. In Fluent this is NOT fully opaque over Mica —
  /// it is a high-opacity neutral so a hint of the backdrop shows through.
  static Color fill(ColorScheme scheme, {double opacity = 1.0}) =>
      scheme.surface.withValues(alpha: opacity);

  /// A subtle tinted backplate behind an icon or a selected row.
  static Color subtle(Color accent, Brightness brightness) =>
      accent.withValues(alpha: brightness == Brightness.dark ? 0.16 : 0.10);
}
