# Fluent UI guide

How every widget in this app should look. Derived from Microsoft's
Fluent 2 / Windows 11 (WinUI) design system, which is the look we are
going for.

Everything here is already expressed as code in
[`lib/core/theme/fluent_tokens.dart`](../lib/core/theme/fluent_tokens.dart).
Import it and use the tokens — do not retype the numbers.

```dart
import '../../../../core/theme/fluent_tokens.dart';
```

---

## The three rules that matter most

Fluent reads as Fluent because of these, and the app was breaking all
three on nearly every screen.

### 1. Small, consistent corner radii

| What | Token | Value |
|---|---|---|
| Buttons, inputs, chips, badges, pills, icon plates, progress bars | `FluentRadius.controlBorder` | 4 |
| Cards, list surfaces, flyouts, dialogs | `FluentRadius.cardBorder` | 8 |
| Bottom sheets, full-width hero panels | `FluentRadius.largeBorder` | 12 |

Nothing else. No 16, no 20, no 24. A fully round shape
(`BoxShape.circle`, `BorderRadius.circular(999)`) is only for avatars
and circular progress — never for a badge, pill or icon backplate.

### 2. Stroke, not glow

A card at rest is **a solid surface with a 1px border and a shadow you
can barely see**. Coloured glows are not a Fluent idiom.

```dart
// BAD — the pattern that is all over this app
boxShadow: [
  BoxShadow(
    color: Colors.indigo.withValues(alpha: 0.4),
    blurRadius: 20,
    offset: const Offset(0, 6),
  ),
],

// GOOD
border: Border.all(
  color: FluentStroke.card(Theme.of(context).brightness),
  width: FluentStroke.width,
),
boxShadow: FluentElevation.card(Theme.of(context).brightness),
```

`Card(elevation: 2)` and higher become `elevation: 0` plus the stroke.
`FluentElevation` has `card` (rest), `raised` (pressed, dropdown) and
`flyout` (popover) if you need a step up.

### 3. One accent

Accent marks **the thing you act on**. Everything else is neutral.
Colour beyond that is reserved for status meaning — green for success,
red for error, amber for warning — and should come from
`Theme.of(context).colorScheme` (`primary`, `error`, `onSurface`), not
from a hardcoded `Colors.purpleAccent`.

A card with a green icon, a purple badge, a blue button and a pink
progress bar is the thing to fix.

---

## Typography

Use the Windows 11 ramp. Emphasis comes from **weight**, not size.

| Token | Size / weight | For |
|---|---|---|
| `FluentType.caption` | 12 / regular | Secondary text, timestamps, badge labels, helper text |
| `FluentType.body` | 14 / regular | Body copy — the default reading size |
| `FluentType.bodyStrong` | 14 / w600 | List item titles, inline labels, card titles |
| `FluentType.subtitle` | 20 / w600 | Section headers |
| `FluentType.title` | 28 / w600 | Page titles |

```dart
// BAD
style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.white70)

// GOOD
style: FluentType.caption.copyWith(
  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
)
```

Sizes like 10.5, 11.5, 12.5, 14.5 are the smell. Bengali needs the
leading that `FluentType` already bakes in (`height: 1.45`) — do not
strip it.

---

## Spacing

The 4px grid, via `FluentSpacing`: `xxs` 2, `xs` 4, `s` 8, `m` 12,
`l` 16, `xl` 20, `xxl` 24.

`SizedBox(height: 14)`, `EdgeInsets.all(10)`, `SizedBox(width: 3)` all
become the nearest token. Card padding is `FluentSpacing.m` (dense) or
`FluentSpacing.l` (normal).

---

## Colour and dark mode

**Never hardcode a text colour.** `Colors.white70` on a card is
invisible in light mode; `Colors.black54` is invisible in dark. This bug
is real and has already shipped here more than once.

```dart
// BAD
color: Colors.white70
color: isDark ? Colors.white60 : Colors.black54

// GOOD
color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65)
```

The exception: text sitting on a **saturated coloured fill** you control
(a gradient hero, an accent button). There `Colors.white` is correct —
or better, `colorScheme.onPrimary`.

Also note: `Theme.of(context).primaryColor` resolves to
`colorScheme.surface` on a dark theme — the card background. It is never
what you want. Use `Theme.of(context).colorScheme.primary`.

Tinted backplates behind an icon or a selected row:
`FluentLayer.subtle(accentColour, Theme.of(context).brightness)`.

---

## Components to reach for

In `lib/core/widgets/`:

- `PremiumGlassCard` — the Fluent card. Solid layer, 1px stroke, 8px
  radius, `shadow2`. Frosts only in Acrylic style. Takes `onTap` for the
  tappable-list-row pattern.
- `PremiumIconBadge` — a rounded-square icon backplate (4px), not a
  glowing circle.
- `PremiumButton` — flat accent button, 4px radius, no gradient, darkens
  on press. `compact: true` for trailing actions in dense rows.
- `PremiumTag` — a 4px tinted badge for counts and short status words.
- `PremiumSectionHeader` — accent bar + icon + title.
- `PremiumStatTile` — icon plate, value, label.

Prefer these over hand-rolling another `Container` with a decoration.

---

## Layout safety

Keep the width constraints that are already there. A `Row` gives its
children unbounded width, so a `Text` that can grow needs `Flexible` or
`Expanded` plus `maxLines` and `TextOverflow.ellipsis`.

`Expanded` and `Flexible` **throw** inside a horizontal
`SingleChildScrollView` or `ListView`, inside a `Wrap`, or inside a
`PopupMenuItem` (Flutter lays those out under `IntrinsicWidth`). Do not
add them there.

`test/ui_overflow_test.dart` pumps widgets at 320px with 1.5x text
across three themes and all three interface styles. Run it after
restyling:

```bash
flutter test test/ui_overflow_test.dart
```

---

## Interface styles

`AppUiStyle` (in `lib/core/theme/ui_style_provider.dart`) lets the user
pick how surfaces render — `classic` (flat), `mica` (still tint),
`acrylic` (animated, frosted). Widgets normally do not need to check it;
`PremiumGlassCard` and the backdrop widgets handle it. Only read
`appUiStyleProvider` if a widget genuinely needs to drop an effect.
