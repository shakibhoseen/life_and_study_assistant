import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/theme/app_theme.dart';
import 'package:life_and_study_assistant/features/settings/presentation/widgets/theme_selector_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Aesthetic Theme Presets Definition Tests', () {
    test(
      'Cute Velvet Dark Theme has soft lavender and cozy charcoal palette',
      () {
        final theme = AppTheme.cuteVelvetDarkTheme;
        expect(theme.brightness, Brightness.dark);
        expect(theme.scaffoldBackgroundColor, const Color(0xFF161622));
        expect(theme.cardTheme.color, const Color(0xFF202030));
        expect(theme.colorScheme.primary, const Color(0xFFC084FC));
        expect(theme.colorScheme.secondary, const Color(0xFFF472B6));
      },
    );

    test(
      'Cozy Mocha Dark Theme has warm espresso and caramel amber palette',
      () {
        final theme = AppTheme.cozyMochaDarkTheme;
        expect(theme.brightness, Brightness.dark);
        expect(theme.scaffoldBackgroundColor, const Color(0xFF181514));
        expect(theme.cardTheme.color, const Color(0xFF24201E));
        expect(theme.colorScheme.primary, const Color(0xFFF59E0B));
      },
    );

    test('Nordic Twilight Theme has deep blueberry and ice cyan palette', () {
      final theme = AppTheme.nordicTwilightDarkTheme;
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, const Color(0xFF0B1329));
      expect(theme.cardTheme.color, const Color(0xFF131F3F));
      expect(theme.colorScheme.primary, const Color(0xFF38BDF8));
    });

    test('OLED Ultra Black Theme maintains backwards compatibility', () {
      final theme = AppTheme.darkTheme;
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, const Color(0xFF090D1A));
      expect(theme.cardTheme.color, const Color(0xFF111827));
    });
  });

  group('ThemeSelectorCard & Preset Switching Widget Tests', () {
    testWidgets(
      'renders all theme options and switches to Cute Velvet on tap',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(child: ThemeSelectorCard()),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Check all options are rendered
        expect(find.text('System Default'), findsOneWidget);
        expect(find.text('Clean Light Mode ☀️'), findsOneWidget);
        expect(find.text('Cute Velvet Night 🌸💜 (কউট ডার্ক)'), findsOneWidget);
        expect(
          find.text('Cozy Mocha & Espresso ☕🤎 (ক্যাফে স্টাডি)'),
          findsOneWidget,
        );
        expect(
          find.text('Nordic Twilight 🌌❄️ (নর্ডিক মিডনাইট)'),
          findsOneWidget,
        );
        expect(
          find.text('OLED Battery Saver 🔋⚡ (আল্ট্রা ব্ল্যাক)'),
          findsOneWidget,
        );

        // Tap Cute Velvet Night
        await tester.tap(find.text('Cute Velvet Night 🌸💜 (কউট ডার্ক)'));
        await tester.pumpAndSettle();

        // Tap Cozy Mocha
        await tester.tap(
          find.text('Cozy Mocha & Espresso ☕🤎 (ক্যাফে স্টাডি)'),
        );
        await tester.pumpAndSettle();

        // Tap OLED Battery Saver
        await tester.tap(find.text('OLED Battery Saver 🔋⚡ (আল্ট্রা ব্ল্যাক)'));
        await tester.pumpAndSettle();
      },
    );
  });
}
