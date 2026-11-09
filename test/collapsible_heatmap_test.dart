import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/widgets/collapsible_card.dart';
import 'package:life_and_study_assistant/features/dashboard/domain/dashboard_section_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The heatmap was the tallest thing on the dashboard and answered a question
/// about the last fourteen weeks, which pushed the day's actual work off the
/// first screen. Folding it away has to stick, and the folded body must not be
/// built at all — that is where the two database queries were being paid for.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the choice is remembered', () {
    test('folded away until somebody says otherwise', () async {
      SharedPreferences.setMockInitialValues({});

      expect(await DashboardSectionPrefs.heatmapExpanded(), isFalse);
      expect(DashboardSectionPrefs.heatmapExpandedByDefault, isFalse);
    });

    test('opening it is read back next launch', () async {
      SharedPreferences.setMockInitialValues({});

      await DashboardSectionPrefs.setHeatmapExpanded(true);
      expect(await DashboardSectionPrefs.heatmapExpanded(), isTrue);

      await DashboardSectionPrefs.setHeatmapExpanded(false);
      expect(await DashboardSectionPrefs.heatmapExpanded(), isFalse);
    });

    test('an already-saved choice wins over the default', () async {
      SharedPreferences.setMockInitialValues({
        DashboardSectionPrefs.heatmapExpandedKey: true,
      });

      expect(await DashboardSectionPrefs.heatmapExpanded(), isTrue);
    });
  });

  group('the card itself', () {
    Widget host({required bool expanded, ValueChanged<bool>? onToggle}) {
      return MaterialApp(
        home: Scaffold(
          body: CollapsibleCard(
            title: 'Study Activity Heatmap',
            icon: Icons.grid_on,
            iconColour: const Color(0xFF2DA44E),
            subtitle: 'শেষ ১৪ সপ্তাহের পড়ার ছক — দেখতে চাপুন',
            expanded: expanded,
            onToggle: onToggle ?? (_) {},
            child: const Text('the grid'),
          ),
        ),
      );
    }

    testWidgets('folded, the body is never built', (tester) async {
      await tester.pumpWidget(host(expanded: false));

      expect(find.text('Study Activity Heatmap'), findsOneWidget);
      // Not merely hidden: a built-but-offstage grid would still have cost the
      // queries that fill it.
      expect(find.text('the grid'), findsNothing);
      expect(find.byIcon(Icons.expand_more), findsOneWidget);
    });

    testWidgets('open, the body is there', (tester) async {
      await tester.pumpWidget(host(expanded: true));

      expect(find.text('the grid'), findsOneWidget);
      expect(find.byIcon(Icons.expand_less), findsOneWidget);
    });

    testWidgets('the header keeps its one line either way', (tester) async {
      // The section must never go missing, only quiet.
      for (final open in [true, false]) {
        await tester.pumpWidget(host(expanded: open));
        expect(
          find.text('শেষ ১৪ সপ্তাহের পড়ার ছক — দেখতে চাপুন'),
          findsOneWidget,
        );
      }
    });

    testWidgets('the whole header toggles, not just the chevron', (
      tester,
    ) async {
      final asked = <bool>[];
      await tester.pumpWidget(
        host(expanded: false, onToggle: asked.add),
      );

      await tester.tap(find.text('Study Activity Heatmap'));
      await tester.pump();

      expect(asked, [true]);
    });
  });
}
