import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/services/ai/models/parsed_routine_item.dart';
import 'package:life_and_study_assistant/features/live_mcq/presentation/widgets/routine_preview_sheet.dart';

ParsedRoutineItem item(int day, String title) => ParsedRoutineItem(
  date: DateTime(2026, 11, day),
  examTime: '10:00 PM',
  subject: 'বাংলা সাহিত্য',
  topics: const ['প্রাচীন যুগ'],
  examType: 'Daily',
  trackName: '১০০ দিনে বিসিএস',
  title: title,
);

Future<List<ParsedRoutineItem>?> openSheet(
  WidgetTester tester,
  List<ParsedRoutineItem> items,
) async {
  List<ParsedRoutineItem>? result;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await RoutinePreviewSheet.show(
              context,
              items,
              sourceLabel: 'routine.pdf',
            );
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('every parsed row is shown before anything is saved', (
    tester,
  ) async {
    await openSheet(tester, [item(2, 'পরীক্ষা – ০১'), item(4, 'পরীক্ষা – ০২')]);

    expect(find.text('পরীক্ষা – ০১'), findsOneWidget);
    expect(find.text('পরীক্ষা – ০২'), findsOneWidget);
    expect(find.textContaining('২টি যোগ করুন'), findsOneWidget);
  });

  testWidgets('cancelling returns nothing to save', (tester) async {
    List<ParsedRoutineItem>? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              captured = await RoutinePreviewSheet.show(context, [
                item(2, 'পরীক্ষা – ০১'),
              ], sourceLabel: 'routine.pdf');
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('বাতিল'));
    await tester.pumpAndSettle();

    expect(captured, isNull);
  });

  testWidgets('a wrong row can be dropped before confirming', (tester) async {
    List<ParsedRoutineItem>? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              captured = await RoutinePreviewSheet.show(context, [
                item(2, 'পরীক্ষা – ০১'),
                item(4, 'পরীক্ষা – ০২'),
              ], sourceLabel: 'routine.pdf');
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    expect(find.text('পরীক্ষা – ০১'), findsNothing);

    await tester.tap(find.textContaining('১টি যোগ করুন'));
    await tester.pumpAndSettle();

    expect(captured, hasLength(1));
    expect(captured!.single.title, 'পরীক্ষা – ০২');
  });

  testWidgets('confirming returns exactly what was shown', (tester) async {
    List<ParsedRoutineItem>? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              captured = await RoutinePreviewSheet.show(context, [
                item(2, 'পরীক্ষা – ০১'),
                item(4, 'পরীক্ষা – ০২'),
              ], sourceLabel: 'routine.pdf');
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('২টি যোগ করুন'));
    await tester.pumpAndSettle();

    expect(captured, hasLength(2));
  });

  testWidgets('dropping everything disables the confirm button', (
    tester,
  ) async {
    await openSheet(tester, [item(2, 'পরীক্ষা – ০১')]);

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(find.textContaining('সব সারি বাদ'), findsOneWidget);
  });
}
