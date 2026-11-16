import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/database/database_provider.dart';
import 'package:life_and_study_assistant/core/services/reference/reference_import_service.dart';
import 'package:life_and_study_assistant/core/services/reference/reference_service.dart';
import 'package:life_and_study_assistant/features/reference/presentation/widgets/reference_import_sheet.dart';

import 'support/ui_style_override.dart';

/// Bringing a table in from outside the app.
///
/// The app's own model is the cheap one, and reading a dense conversion
/// table off a photographed page is what it is worst at. So the important
/// path is not the one that calls it — it is the one where a better model
/// elsewhere did the reading and its JSON is taken verbatim. That path must
/// work with no API key and no network at all, which is exactly what these
/// check: there is neither here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    // No API key: the external-JSON path must not need one, and the path
    // that does must say so rather than failing obscurely.
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => db.close());

  Widget host() => ProviderScope(
    overrides: [classicUiStyle, appDatabaseProvider.overrideWithValue(db)],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => ReferenceImportSheet.show(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  Future<void> openSheet(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  const pasted = '''
{
  "title": "ওজনের একক",
  "category": "পরিমাপ ও একক",
  "columns": ["একক", "সমান"],
  "rows": [
    {"cells": ["১ মণ", "৩৭.৩২ কিলোগ্রাম"]},
    {"cells": ["১ সের", "০.৯৩৩ কিলোগ্রাম"]}
  ]
}
''';

  testWidgets('pasted JSON is previewed without any model call', (
    tester,
  ) async {
    await openSheet(tester);

    await tester.enterText(find.byType(TextField), pasted);
    await tester.tap(find.text('টেবিল বানান'));
    await tester.pumpAndSettle();

    // No API key is configured in this test, so reaching the model at all
    // would have produced an error here instead of a preview.
    expect(find.text('দেখে নিন'), findsOneWidget);
    expect(find.text('ওজনের একক'), findsOneWidget);
    expect(find.textContaining('১ মণ'), findsOneWidget);
  });

  testWidgets('nothing is saved until the preview is accepted', (
    tester,
  ) async {
    await openSheet(tester);
    await tester.enterText(find.byType(TextField), pasted);
    await tester.tap(find.text('টেবিল বানান'));
    await tester.pumpAndSettle();

    // A misread digit in a conversion table is a wrong answer the user will
    // trust, so the preview is the whole point of the flow.
    expect(await ReferenceService.instance.sheets(db), isEmpty);

    await tester.tap(find.text('সংরক্ষণ'));
    await tester.pumpAndSettle();

    final sheets = await ReferenceService.instance.sheets(db);
    expect(sheets.single.title, 'ওজনের একক');
    final view = await ReferenceService.instance.view(db, sheets.single.sheetKey);
    expect(view!.rows.length, 2);
  });

  testWidgets('the prompt button puts the real prompt on the clipboard', (
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

    await openSheet(tester);
    await tester.tap(find.text('প্রম্পট কপি করুন'));
    await tester.pumpAndSettle();

    expect(copied, ReferenceImportService.externalPrompt);
    // And what it copies is something the app can actually read back.
    expect(copied, contains('"cells"'));
  });

  testWidgets('plain prose without a key is refused, not sent blindly', (
    tester,
  ) async {
    await openSheet(tester);

    await tester.enterText(find.byType(TextField), 'এক মাইল কত কিলোমিটার?');
    await tester.tap(find.text('টেবিল বানান'));
    // Not pumpAndSettle: the progress indicator spins for ever by design, so
    // settling is the one thing it can never do.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // Not JSON, so it would need the model — and with no key configured the
    // user is told that rather than left watching a spinner.
    expect(find.text('দেখে নিন'), findsNothing);
    expect(find.textContaining('API কী'), findsOneWidget);
  });
}
