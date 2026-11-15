
import 'package:life_and_study_assistant/core/theme/ui_style_provider.dart';

/// Pins the interface style to Classic for a widget test.
///
/// Dashboard, Settings, Topics, LiveMCQ and AI Chat all paint the Acrylic
/// backdrop, whose gradient and orb controllers call `repeat()`. A widget
/// test that pumps one of those screens and then calls `pumpAndSettle` waits
/// for an animation that never ends, and fails ten minutes later with
/// "pumpAndSettle timed out" — long enough to make the whole suite look
/// hung.
///
/// Classic draws a still background and starts no ticker, so the frame
/// settles. Use it in the `overrides` of any ProviderScope that mounts one of
/// those screens:
///
/// ```dart
/// ProviderScope(
///   overrides: [
///     appDatabaseProvider.overrideWithValue(db),
///     classicUiStyle,
///   ],
///   child: const MaterialApp(home: LiveMcqScreen()),
/// )
/// ```
///
/// A test that is specifically about the Acrylic look should override the
/// style itself and drive the clock with `pump(duration)` instead.
final classicUiStyle = appUiStyleProvider.overrideWith(_ClassicUiStyle.new);

class _ClassicUiStyle extends AppUiStyleNotifier {
  @override
  AppUiStyle build() => AppUiStyle.classic;
}
