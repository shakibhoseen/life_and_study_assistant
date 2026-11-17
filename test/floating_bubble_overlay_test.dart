import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/services/reference/reference_service.dart';
import 'package:life_and_study_assistant/features/reference/presentation/widgets/detail_body.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('ReferenceService search finds formulas by query and matches details', () async {
    // 1. Seed sample math formulas
    await ReferenceService.instance.seed(
      db,
      sheets: [
        const ReferenceSheetData(
          sheetKey: 'geometry_formulas',
          title: 'জ্যামিতি ও ক্ষেত্রফল',
          category: 'গণিত সূত্র',
          subject: 'জ্যামিতি',
          note: 'বিসিএস প্রিলিমিনারি স্পেশাল',
          columns: ['চিত্র / ক্ষেত্র', 'ক্ষেত্রফল সূত্র', 'পরিসীমা'],
          rows: [
            ReferenceRowData(
              cells: ['বৃত্ত', 'πr²', '2πr'],
              note: 'r = ব্যাসার্ধ',
            ),
            ReferenceRowData(
              cells: ['সমকোণী ত্রিভুজ', '½ × ভূমি × উচ্চতা', 'a + b + c'],
              note: 'পিথাগোরাস প্রযোজ্য',
            ),
          ],
        ),
      ],
    );

    // 2. Add an SVG derivation detail to the circle formula
    final circleRows = await ReferenceService.instance.rows(db, 'geometry_formulas');
    expect(circleRows, isNotEmpty);
    final circleId = circleRows.first.id;

    const circleSvg =
        '<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">'
        '<circle cx="50" cy="50" r="40" stroke="black" stroke-width="2" fill="none"/>'
        '</svg>';
    const circleDetail =
        '### বৃত্তের ক্ষেত্রফলের উৎপত্তি\n\n'
        'বৃত্তকে অসংখ্য ক্ষুদ্র বৃত্তকলায় ভাগ করে সাজালে এটি একটি আয়তক্ষেত্রে পরিণত হয়।\n\n'
        '```svg চিত্র: বৃত্ত\n$circleSvg\n```\n';

    await ReferenceService.instance.setRowDetail(
      db,
      rowId: circleId,
      detail: circleDetail,
    );

    // 3. Search for "বৃত্ত"
    final circleHits = await ReferenceService.instance.search(db, 'বৃত্ত');
    expect(circleHits.length, 1);
    expect(circleHits.first.sheet.title, 'জ্যামিতি ও ক্ষেত্রফল');
    expect(circleHits.first.row.detail, isNotNull);
    expect(circleHits.first.row.detail, contains(circleSvg));

    // 4. Search for "পিথাগোরাস"
    final pythagorasHits = await ReferenceService.instance.search(db, 'পিথাগোরাস');
    expect(pythagorasHits.length, 1);
    expect(pythagorasHits.first.row.cellsJson, contains('সমকোণী ত্রিভুজ'));
  });

  testWidgets('DetailBody renders SVG figure and markdown text properly', (tester) async {
    const testSvg =
        '<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">'
        '<rect width="80" height="80" fill="none" stroke="black"/>'
        '</svg>';
    const testDetail =
        '### পিথাগোরাসের উপপাদ্য\n\n'
        'সমকোণী ত্রিভুজের অতিভুজের বর্গ অপর দুই বাহুর বর্গের সমষ্টির সমান: c² = a² + b²\n\n'
        '```svg চিত্র: সমকোণী ত্রিভুজ\n$testSvg\n```\n';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DetailBody(detail: testDetail),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('পিথাগোরাসের উপপাদ্য', findRichText: true), findsOneWidget);
    expect(find.textContaining('c² = a² + b²', findRichText: true), findsOneWidget);
    // Caption under figure
    expect(find.text('চিত্র: সমকোণী ত্রিভুজ'), findsOneWidget);
  });
}
