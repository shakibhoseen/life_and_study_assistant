import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/database/database_provider.dart';
import 'package:life_and_study_assistant/core/services/reference/reference_service.dart';
import 'package:life_and_study_assistant/features/reference/presentation/screens/reference_sheet_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/ui_style_override.dart';

/// A table on screen, in both of its shapes.
///
/// Two columns render as a list and three or more as a grid, and the row
/// actions were wired into the list alone. That shipped: a row added by hand
/// to the five-column tense chart could not be edited, revised or removed by
/// any means at all. These check both shapes, because the layouts diverge and
/// the thing that diverged was the only way to undo anything.
///
/// The way in is a long press on the row, in both shapes. A visible control
/// was tried and taken out again: this is a single-user app and its user
/// knows the gesture, so a button on every line was clutter — and in the
/// grid it cost a whole column of a table that already scrolls sideways.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  const narrow = ReferenceSheetData(
    sheetKey: 'length',
    title: 'দৈর্ঘ্য',
    category: 'পরিমাপ ও একক',
    subject: '',
    note: '',
    columns: ['একক', 'সমান'],
    rows: [ReferenceRowData(cells: ['১ মাইল', '১.৬১ কিলোমিটার'])],
  );

  const wide = ReferenceSheetData(
    sheetKey: 'tense',
    title: 'Tense',
    category: 'বাংলা ও ইংরেজির নিয়ম',
    subject: '',
    note: '',
    columns: ['Tense', 'Indefinite', 'Continuous', 'Perfect', 'Perfect Cont.'],
    rows: [
      ReferenceRowData(
        cells: ['Present', 'V1', 'am + V-ing', 'have + V3', 'have been'],
      ),
    ],
  );

  setUp(() async {
    // The drill sheet reads its remembered size from preferences before it
    // loads any questions, so without this it never gets past loading.
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    await ReferenceService.instance.seed(db, sheets: const [narrow, wide]);
  });
  tearDown(() => db.close());

  Future<void> open(
    WidgetTester tester,
    String sheetKey, {
    Size size = const Size(1000, 1600),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [classicUiStyle, appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(home: ReferenceSheetScreen(sheetKey: sheetKey)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a table big enough offers a drill, and it opens', (
    tester,
  ) async {
    await ReferenceService.instance.seed(
      db,
      sheets: const [
        ReferenceSheetData(
          sheetKey: 'units',
          title: 'দৈর্ঘ্য',
          category: 'পরিমাপ ও একক',
          subject: 'গাণিতিক যুক্তি',
          note: '',
          columns: ['একক', 'সমান'],
          rows: [
            ReferenceRowData(cells: ['১ মাইল', '১.৬১ কিলোমিটার']),
            ReferenceRowData(cells: ['১ গজ', '৩ ফুট']),
            ReferenceRowData(cells: ['১ ইঞ্চি', '২.৫৪ সেন্টিমিটার']),
            ReferenceRowData(cells: ['১ হাত', '১৮ ইঞ্চি']),
          ],
        ),
      ],
    );

    // Taller than the default: the drill modal is a full-height sheet and
    // a short surface overflows widgets that have nothing to do with this.
    await open(tester, 'units', size: const Size(1000, 2400));

    await tester.tap(find.text('এই টেবিল থেকে পরীক্ষা'));
    // Not pumpAndSettle: the drill sheet runs a repeating animation, so
    // settling is the one thing it never does.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // A real question built from the table, with its wrong options taken
    // from the table's own other rows.
    expect(find.textContaining('= কত?'), findsOneWidget);
  });

  testWidgets('a table too small to ask about offers no drill', (
    tester,
  ) async {
    // Two rows cannot make three plausible wrong answers, and a drill
    // button that opens an empty drill is worse than no button.
    await open(tester, 'length');

    expect(find.text('এই টেবিল থেকে পরীক্ষা'), findsNothing);
    expect(find.text('সারি যোগ'), findsOneWidget);
  });

  // A tall surface throughout: the derivation sheet is nearly full height,
  // and on the default 1600 its buttons fall off the bottom.
  group('the derivation behind a rule', () {
    /// The sheet is taller than any surface, so its buttons have to be
    /// scrolled to before they can be tapped.
    Future<void> tapIn(WidgetTester tester, String label) async {
      final target = find.text(label);
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    testWidgets('tapping a row opens it, in both layouts', (tester) async {
      for (final key in ['length', 'tense']) {
        await open(tester, key, size: const Size(1000, 2600));
        await tester.tap(
          find.text(key == 'length' ? '১ মাইল' : 'Present'),
        );
        await tester.pumpAndSettle();

        // Nothing written yet, so it opens straight into the editor rather
        // than a dead end with an empty box.
        expect(find.text('প্রম্পট কপি করুন'), findsOneWidget);
        await tapIn(tester, 'বাতিল');
      }
    });

    testWidgets('what is written is kept and shown as markdown', (
      tester,
    ) async {
      await open(tester, 'length', size: const Size(1000, 2600));
      await tester.tap(find.text('১ মাইল'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField),
        '## কোথা থেকে\n\n১ গজ = ৩ ফুট ধরে হিসাব।',
      );
      await tester.tap(find.text('সংরক্ষণ'));
      await tester.pumpAndSettle();

      final rows = await ReferenceService.instance.rows(db, 'length');
      expect(rows.single.detail, contains('কোথা থেকে'));
      // Editing a bundled row claims it, or the next content update would
      // replace the row and take the explanation with it.
      expect(rows.single.isCustom, isTrue);

      // Reopening reads rather than edits.
      await tester.tap(find.text('১ মাইল'));
      await tester.pumpAndSettle();
      expect(find.text('সম্পাদনা'), findsOneWidget);
      expect(find.text('প্রম্পট কপি করুন'), findsNothing);
    });

    testWidgets('the copied prompt carries the row and the table', (
      tester,
    ) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await open(tester, 'length', size: const Size(1000, 2600));
      await tester.tap(find.text('১ মাইল'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('প্রম্পট কপি করুন'));
      await tester.pumpAndSettle();

      // Without the row in it the prompt is useless, and without the ban on
      // LaTeX the answer comes back unreadable.
      expect(copied, contains('১ মাইল'));
      expect(copied, contains('দৈর্ঘ্য'));
      expect(copied, contains('LaTeX'));
    });

    testWidgets('clearing it removes the detail rather than storing blank', (
      tester,
    ) async {
      await open(tester, 'length', size: const Size(1000, 2600));
      await tester.tap(find.text('১ মাইল'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'কিছু একটা');
      await tester.tap(find.text('সংরক্ষণ'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('১ মাইল'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('সম্পাদনা'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('সংরক্ষণ'));
      await tester.pumpAndSettle();

      final rows = await ReferenceService.instance.rows(db, 'length');
      expect(rows.single.detail, isNull);
    });
  });

  for (final shape in [
    (name: 'two columns', key: 'length', cell: '১ মাইল'),
    (name: 'five columns', key: 'tense', cell: 'Present'),
  ]) {
    group(shape.name, () {
      testWidgets('shows the row', (tester) async {
        await open(tester, shape.key);
        expect(find.text(shape.cell), findsOneWidget);
      });

      testWidgets('a long press offers the row actions', (tester) async {
        await open(tester, shape.key);

        await tester.longPress(find.text(shape.cell));
        await tester.pumpAndSettle();

        expect(find.text('রিভিশনে পাঠান'), findsOneWidget);
        expect(find.text('সম্পাদনা'), findsOneWidget);
        expect(find.text('সারিটি মুছুন'), findsOneWidget);
      });

      testWidgets('a row can actually be removed', (tester) async {
        await open(tester, shape.key);

        await tester.longPress(find.text(shape.cell));
        await tester.pumpAndSettle();
        await tester.tap(find.text('সারিটি মুছুন'));
        await tester.pumpAndSettle();

        expect(find.text(shape.cell), findsNothing);
        expect(await ReferenceService.instance.rows(db, shape.key), isEmpty);
      });

      testWidgets('a row can be sent to the review deck', (tester) async {
        await open(tester, shape.key);

        await tester.longPress(find.text(shape.cell));
        await tester.pumpAndSettle();
        await tester.tap(find.text('রিভিশনে পাঠান'));
        await tester.pumpAndSettle();

        // The database seeds review items of its own on create, so this
        // looks for the one the tap added rather than expecting only it.
        final due = await db.select(db.spacedReviewItems).get();
        expect(due.map((d) => d.title), contains(shape.cell));
      });
    });
  }
}
