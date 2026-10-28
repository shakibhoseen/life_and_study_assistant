import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:life_and_study_assistant/core/config/notification_constants.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/database/database_provider.dart';
import 'package:life_and_study_assistant/core/services/ai/gemini_ai_service.dart';
import 'package:life_and_study_assistant/core/services/ai/gemini_result_cache.dart';
import 'package:life_and_study_assistant/features/mistake_notebook/presentation/widgets/ai_mistake_explainer_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      NotificationConstants.prefGeminiApiKey: 'test_key',
      NotificationConstants.prefGeminiModel: 'gemini-flash-lite-latest',
    });
    db = AppDatabase(NativeDatabase.memory());
    await GeminiAiService.instance.init('test_key');
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertQuestion({
    int correctIndex = 0,
    int selectedIndex = 1,
    bool isCorrect = false,
    int? originalCorrectIndex,
    DateTime? correctedAt,
  }) {
    return db
        .into(db.drillQuestions)
        .insert(
          DrillQuestionsCompanion.insert(
            subject: 'Bangladesh Affairs',
            topic: 'জাতীয় প্রতীক',
            questionText: 'পতাকার অনুপাত কত?',
            optionsJson: jsonEncode(['৩:২', '৫:৩', '২:১', '৪:৩']),
            correctIndex: correctIndex,
            selectedIndex: selectedIndex,
            isCorrect: isCorrect,
            explanation: const Value('১০:৬, অর্থাৎ ৩:২।'),
            originalCorrectIndex: Value(originalCorrectIndex),
            correctedAt: Value(correctedAt),
          ),
        );
  }

  Future<DrillQuestion> fetchQuestion(int id) {
    return (db.select(
      db.drillQuestions,
    )..where((t) => t.id.equals(id))).getSingle();
  }

  Future<void> seedMistakeExplainCache({
    required int correctIndex,
    required int selectedIndex,
  }) async {
    final options = ['৩:২', '৫:৩', '২:১', '৪:৩'];
    final userAns = options[selectedIndex];
    final correctAns = options[correctIndex];
    final payload =
        'Bangladesh Affairs|জাতীয় প্রতীক|পতাকার অনুপাত কত?|${options.join(",")}|$userAns|$correctAns|১০:৬, অর্থাৎ ৩:২।';
    final cacheKey = GeminiResultCache.instance.computeKeyFromString(
      operation: 'mistake_explain',
      promptVersion: 'v2.1',
      model: 'gemini-flash-lite-latest',
      payloadText: payload,
    );
    await GeminiResultCache.instance.put(
      cacheKey,
      'মক বিশ্লেষণ: সঠিক উত্তর ৫:৩ কারণ ১০:৬ লঘিষ্ঠ করলে ৫:৩ হয়।',
    );
  }

  Future<void> seedVerificationCache({
    required int chosenIndex,
    String basis = 'recall',
    String reasoning = '১০:৬ লঘিষ্ঠ করলে ৫:৩ হয়।',
  }) async {
    const payload =
        'Bangladesh Affairs|জাতীয় প্রতীক|পতাকার অনুপাত কত?|৩:২~৫:৩~২:১~৪:৩';
    final cacheKey = GeminiResultCache.instance.computeKeyFromString(
      operation: 'mcq_independent_solve',
      promptVersion: 'v1.0',
      model: 'gemini-flash-lite-latest',
      payloadText: payload,
    );
    await GeminiResultCache.instance.put(
      cacheKey,
      jsonEncode({
        'chosen_index': chosenIndex,
        'reasoning': reasoning,
        'confidence': 0.95,
        'ambiguity': 'none',
        'basis': basis,
      }),
    );
  }

  Widget createTestWidget(DrillQuestion question) {
    return ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 1200,
            width: 800,
            child: AiMistakeExplainerSheet(question: question),
          ),
        ),
      ),
    );
  }

  group('AiMistakeExplainerSheet Verification & Correction Widget Tests', () {
    testWidgets(
      'accepting a correction updates database, regrades user, and keeps attempt history',
      (tester) async {
        final id = await insertQuestion();
        final q = await fetchQuestion(id);

        await seedMistakeExplainCache(
          correctIndex: q.correctIndex,
          selectedIndex: q.selectedIndex,
        );
        await seedVerificationCache(chosenIndex: 1);

        await tester.pumpWidget(createTestWidget(q));
        await tester.pumpAndSettle();

        // 1. Verify verify button exists and tap it
        final verifyBtn = find.text('উত্তর স্বাধীনভাবে যাচাই করুন');
        await tester.ensureVisible(verifyBtn);
        await tester.pumpAndSettle();
        expect(verifyBtn, findsOneWidget);
        await tester.tap(verifyBtn);
        await tester.pumpAndSettle();

        // 2. Proposal container should now appear
        expect(find.text('সংশোধন প্রস্তাব'), findsOneWidget);
        expect(find.text('বর্তমান উত্তর'), findsOneWidget);
        expect(find.text('প্রস্তাবিত উত্তর'), findsOneWidget);
        expect(find.text('৩:২'), findsAtLeastNWidgets(1));
        expect(find.text('৫:৩'), findsAtLeastNWidgets(1));

        // 3. Tap accept correction ("সংশোধন গ্রহণ")
        final acceptBtn = find.text('সংশোধন গ্রহণ');
        await tester.ensureVisible(acceptBtn);
        await tester.pumpAndSettle();
        expect(acceptBtn, findsOneWidget);
        await tester.tap(acceptBtn);
        await tester.pumpAndSettle();

        // 4. Verify in-memory Drift database updated accurately
        final updatedRow = await fetchQuestion(id);
        expect(updatedRow.correctIndex, 1); // Updated to 5:3
        expect(updatedRow.selectedIndex, 1); // User's attempt choice preserved!
        expect(updatedRow.isCorrect, isTrue); // Re-graded: user was right!
        expect(updatedRow.originalCorrectIndex, 0); // Snapshot preserved!
        expect(updatedRow.correctedAt, isNotNull);

        // 5. Verify UI shows success banner and revert option
        expect(find.textContaining('সংশোধন সংরক্ষিত হয়েছে'), findsOneWidget);
        expect(
          find.text('প্রশ্নটিতে পূর্বে সংশোধন প্রয়োগ করা হয়েছে'),
          findsOneWidget,
        );
        expect(find.text('পূর্বের অবস্থায় ফিরুন'), findsOneWidget);
      },
    );

    testWidgets(
      'rejecting a correction ("আগেরটাই রাখুন") dismisses proposal and does not touch database',
      (tester) async {
        final id = await insertQuestion();
        final q = await fetchQuestion(id);

        await seedMistakeExplainCache(
          correctIndex: q.correctIndex,
          selectedIndex: q.selectedIndex,
        );
        await seedVerificationCache(chosenIndex: 1);

        await tester.pumpWidget(createTestWidget(q));
        await tester.pumpAndSettle();

        // 1. Trigger verification
        final verifyBtn = find.text('উত্তর স্বাধীনভাবে যাচাই করুন');
        await tester.ensureVisible(verifyBtn);
        await tester.pumpAndSettle();
        await tester.tap(verifyBtn);
        await tester.pumpAndSettle();

        expect(find.text('সংশোধন প্রস্তাব'), findsOneWidget);

        // 2. Tap "আগেরটাই রাখুন"
        final rejectBtn = find.text('আগেরটাই রাখুন');
        await tester.ensureVisible(rejectBtn);
        await tester.pumpAndSettle();
        expect(rejectBtn, findsOneWidget);
        await tester.tap(rejectBtn);
        await tester.pumpAndSettle();

        // 3. Verify proposal box is dismissed
        expect(find.text('সংশোধন প্রস্তাব'), findsNothing);
        expect(
          find.text(
            'সংশোধন প্রস্তাব বাতিল করা হয়েছে। সংরক্ষিত উত্তরটি অপরিবর্তিত রাখা হয়েছে।',
          ),
          findsOneWidget,
        );

        // 4. Database remains completely unchanged
        final dbRow = await fetchQuestion(id);
        expect(dbRow.correctIndex, 0);
        expect(dbRow.selectedIndex, 1);
        expect(dbRow.isCorrect, isFalse);
        expect(dbRow.originalCorrectIndex, isNull);
        expect(dbRow.correctedAt, isNull);
      },
    );

    testWidgets(
      'reverting an accepted correction safely restores original correctIndex and regrades attempt',
      (tester) async {
        // Pre-insert a corrected question
        final id = await insertQuestion(
          correctIndex: 1,
          originalCorrectIndex: 0,
          correctedAt: DateTime.now(),
          selectedIndex: 1,
          isCorrect: true, // regraded when corrected
        );
        final q = await fetchQuestion(id);

        await seedMistakeExplainCache(
          correctIndex: q.correctIndex,
          selectedIndex: q.selectedIndex,
        );

        await tester.pumpWidget(createTestWidget(q));
        await tester.pumpAndSettle();

        // 1. Revert banner should be visible immediately
        expect(
          find.text('প্রশ্নটিতে পূর্বে সংশোধন প্রয়োগ করা হয়েছে'),
          findsOneWidget,
        );
        expect(find.text('মূল উত্তর ছিল'), findsOneWidget);
        expect(find.text('৩:২'), findsAtLeastNWidgets(1));

        final revertBtn = find.text('পূর্বের অবস্থায় ফিরুন');
        await tester.ensureVisible(revertBtn);
        await tester.pumpAndSettle();
        expect(revertBtn, findsOneWidget);
        await tester.tap(revertBtn);
        await tester.pumpAndSettle();

        // 2. Confirmation dialog appears
        expect(find.text('পূর্বের অবস্থায় ফিরবেন?'), findsOneWidget);
        final confirmBtn = find.text('হ্যাঁ, ফিরুন');
        expect(confirmBtn, findsOneWidget);
        await tester.tap(confirmBtn);
        await tester.pumpAndSettle();

        // 3. Database is safely restored
        final revertedRow = await fetchQuestion(id);
        expect(revertedRow.correctIndex, 0); // Restored to 0
        expect(revertedRow.selectedIndex, 1); // Attempt history preserved
        expect(revertedRow.isCorrect, isFalse); // Regraded back to false
        expect(revertedRow.originalCorrectIndex, isNull);
        expect(revertedRow.correctedAt, isNull);

        // 4. Banner is removed from UI
        expect(
          find.text('প্রশ্নটিতে পূর্বে সংশোধন প্রয়োগ করা হয়েছে'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'model agreement displays warning that it is not factual proof and highlights external limitation',
      (tester) async {
        final id = await db
            .into(db.drillQuestions)
            .insert(
              DrillQuestionsCompanion.insert(
                subject: 'Bangladesh Affairs',
                topic: 'জাতীয় প্রতীক',
                questionText: 'পতাকার অনুপাত কত?',
                optionsJson: jsonEncode(['৩:২', '৫:৩', '২:১', '৪:৩']),
                correctIndex: 0,
                selectedIndex: 1,
                isCorrect: false,
                explanation: const Value('জাতীয় প্রতীক বিষয়ক সাধারণ জ্ঞান।'),
              ),
            );
        final q = await fetchQuestion(id);

        final options = ['৩:২', '৫:৩', '২:১', '৪:৩'];
        final payload =
            'Bangladesh Affairs|জাতীয় প্রতীক|পতাকার অনুপাত কত?|${options.join(",")}|${options[1]}|${options[0]}|জাতীয় প্রতীক বিষয়ক সাধারণ জ্ঞান।';
        final explainKey = GeminiResultCache.instance.computeKeyFromString(
          operation: 'mistake_explain',
          promptVersion: 'v2.1',
          model: 'gemini-flash-lite-latest',
          payloadText: payload,
        );
        await GeminiResultCache.instance.put(explainKey, 'মক বিশ্লেষণ।');

        // Seed with agreeing answer (chosen: 0, basis: recall)
        await seedVerificationCache(
          chosenIndex: 0,
          basis: 'recall',
          reasoning: 'বিকল্প বিশ্লেষণ করে এটিই সঠিক।',
        );

        await tester.pumpWidget(createTestWidget(q));
        await tester.pumpAndSettle();

        final verifyBtn = find.text('উত্তর স্বাধীনভাবে যাচাই করুন');
        await tester.ensureVisible(verifyBtn);
        await tester.pumpAndSettle();
        await tester.tap(verifyBtn);
        await tester.pumpAndSettle();

        // 1. Headline shows agreement
        expect(find.text('স্বাধীনভাবে একই উত্তর এসেছে'), findsOneWidget);

        // 2. Factual proof limitation is explicitly visible
        expect(
          find.text(
            'মডেলের সম্মতি কোনো তথ্যগত প্রমাণ নয় (বহিঃস্থ উৎস যাচাই করা হয়নি)।',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining('External sources not checked'),
          findsOneWidget,
        );
      },
    );
  });
}
