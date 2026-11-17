import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/database/database_provider.dart';
import 'package:life_and_study_assistant/core/services/reference/reference_service.dart';
import 'package:life_and_study_assistant/features/reference/presentation/screens/reference_sheet_screen.dart';

import 'support/ui_style_override.dart';

/// A table on screen, in both of its shapes.
///
/// Two columns render as a list and three or more as a grid, and the row
/// actions were wired into the list alone. That shipped: a row added by hand
/// to the five-column tense chart could not be edited, revised or removed by
/// any means at all. These check both shapes, because the layouts diverge and
/// the thing that diverged was the only way to undo anything.
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
    db = AppDatabase(NativeDatabase.memory());
    await ReferenceService.instance.seed(db, sheets: const [narrow, wide]);
  });
  tearDown(() => db.close());

  Future<void> open(WidgetTester tester, String sheetKey) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [classicUiStyle, appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(home: ReferenceSheetScreen(sheetKey: sheetKey)),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final shape in [
    (name: 'two columns', key: 'length', cell: '১ মাইল'),
    (name: 'five columns', key: 'tense', cell: 'Present'),
  ]) {
    group(shape.name, () {
      testWidgets('shows the row', (tester) async {
        await open(tester, shape.key);
        expect(find.text(shape.cell), findsOneWidget);
      });

      testWidgets('offers the row actions without a hidden gesture', (
        tester,
      ) async {
        await open(tester, shape.key);

        // Visible control, not a long press nobody discovers.
        expect(find.byIcon(Icons.more_vert), findsOneWidget);
        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();

        expect(find.text('রিভিশনে পাঠান'), findsOneWidget);
        expect(find.text('সম্পাদনা'), findsOneWidget);
        expect(find.text('সারিটি মুছুন'), findsOneWidget);
      });

      testWidgets('a row can actually be removed', (tester) async {
        await open(tester, shape.key);

        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();
        await tester.tap(find.text('সারিটি মুছুন'));
        await tester.pumpAndSettle();

        expect(find.text(shape.cell), findsNothing);
        expect(await ReferenceService.instance.rows(db, shape.key), isEmpty);
      });

      testWidgets('a row can be sent to the review deck', (tester) async {
        await open(tester, shape.key);

        await tester.tap(find.byIcon(Icons.more_vert));
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
