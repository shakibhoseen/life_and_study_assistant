import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/database/database_provider.dart';
import 'package:life_and_study_assistant/core/services/ai/models/quiz_question.dart';
import 'package:life_and_study_assistant/features/quiz/presentation/widgets/quiz_drill_modal.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets(
    'Skipping a question shows "উত্তর দেননি (স্কিপড)" rather than "ভুল উত্তর" in Practice mode',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const testQuestions = [
        QuizQuestion(
          questionText: '১. চর্যাপদের আদি কবি কে?',
          options: ['ক. লুইপা', 'খ. কাহ্নপা', 'গ. ভুসুকুপা', 'ঘ. শবরপা'],
          correctIndex: 0,
          explanation: 'লুইপা চর্যাপদের আদি কবি।',
          subject: 'বাংলা সাহিত্য',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: const MaterialApp(
            home: Scaffold(
              body: QuizDrillModal(
                subject: 'বাংলা সাহিত্য',
                topic: 'চর্যাপদ',
                customQuestions: testQuestions,
                initialMode: QuizMode.practice,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify question is displayed
      expect(find.text('১. চর্যাপদের আদি কবি কে?'), findsOneWidget);

      // Tap "জানি না — ফলাফল দেখুন"
      final skipButton = find.text('জানি না — ফলাফল দেখুন');
      expect(skipButton, findsOneWidget);
      await tester.ensureVisible(skipButton);
      await tester.pumpAndSettle();
      await tester.tap(skipButton);
      await tester.pumpAndSettle();

      // In result state, verify it shows "উত্তর দেননি (স্কিপড)" instead of "ভুল উত্তর"
      expect(find.text('প্রশ্ন 1: উত্তর দেননি (স্কিপড)'), findsOneWidget);
      expect(find.text('প্রশ্ন 1: ভুল উত্তর'), findsNothing);
      expect(find.text('⏭️ কোনো উত্তর দেননি (স্কিপ করা হয়েছে)'), findsOneWidget);
    },
  );
}
