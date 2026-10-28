import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide Column;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/database/database_provider.dart';
import 'package:life_and_study_assistant/core/services/ai/models/question_bank_extract_result.dart';
import 'package:life_and_study_assistant/core/services/ai/models/quiz_question.dart';
import 'package:life_and_study_assistant/core/services/ai/question_bank_ocr_service.dart';
import 'package:life_and_study_assistant/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:life_and_study_assistant/features/live_mcq/presentation/providers/exam_schedule_provider.dart';
import 'package:life_and_study_assistant/features/live_mcq/presentation/screens/live_mcq_screen.dart';
import 'package:life_and_study_assistant/features/quiz/presentation/widgets/question_bank_scanner_modal.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('QuestionBankExtractResult Model Tests', () {
    test('serializes and deserializes cleanly with questions and options', () {
      const q = QuizQuestion(
        questionText: '১. "সূর্য" শব্দের সমার্থক শব্দ কোনটি?',
        options: ['ক. সুধাকর', 'খ. তপন', 'গ. শশাঙ্ক', 'ঘ. বিধু'],
        correctIndex: 1,
        explanation: 'তপন সূর্যের সমার্থক।',
        subject: 'বাংলা ব্যাকরণ',
      );

      final result = QuestionBankExtractResult(
        title: 'বিগত বছরের সমার্থক শব্দ প্রশ্ন ব্যাংক',
        subject: 'বাংলা ব্যাকরণ',
        questions: const [q],
        rawReference: 'Page: question_p1.jpg',
        hasSeparateAnswerKey: true,
      );

      final jsonMap = result.toJson();
      expect(jsonMap['title'], 'বিগত বছরের সমার্থক শব্দ প্রশ্ন ব্যাংক');
      expect(jsonMap['subject'], 'বাংলা ব্যাকরণ');
      expect(jsonMap['has_separate_answer_key'], isTrue);
      expect(jsonMap['questions'], isList);

      final deserialized = QuestionBankExtractResult.fromJson(
        jsonMap,
        rawRef: 'Page: question_p1.jpg',
        hasSeparateAnswerKey: true,
      );

      expect(deserialized.title, result.title);
      expect(deserialized.subject, result.subject);
      expect(deserialized.questions.length, 1);
      expect(deserialized.questions.first.questionText, q.questionText);
      expect(deserialized.questions.first.correctIndex, 1);
      expect(deserialized.hasSeparateAnswerKey, isTrue);
    });

    test('QuizQuestion copyWith updates correctIndex without altering other fields', () {
      const q = QuizQuestion(
        questionText: 'পাপে বিরত হও—কোন কারকে কোন বিভক্তি?',
        options: [
          'ক. করণে ৭মী',
          'খ. অপাদানে ৭মী',
          'গ. কর্মে ৭মী',
          'ঘ. অধিকরণে ৭মী',
        ],
        correctIndex: 0,
        explanation: 'অপাদান কারক।',
      );

      final updated = q.copyWith(correctIndex: 1);
      expect(updated.correctIndex, 1);
      expect(updated.questionText, q.questionText);
      expect(updated.options, q.options);
      expect(updated.explanation, q.explanation);
    });
  });

  group('QuestionBankOcrService Offline Fallback Tests', () {
    test(
      'extractQuestionBank returns offline fallback when no API key is present',
      () async {
        final tempFile = File('${Directory.systemTemp.path}/test_qb_page.jpg');
        await tempFile.writeAsBytes([
          0xFF,
          0xD8,
          0xFF,
          0xE0,
          0x00,
          0x10,
          0x4A,
          0x46,
        ]);

        try {
          final result = await QuestionBankOcrService.instance
              .extractQuestionBank(
                questionImage: tempFile,
                subjectHint: 'বাংলা ব্যাকরণ',
              );

          expect(result.questions, isNotEmpty);
          expect(result.subject, 'বাংলা ব্যাকরণ');
          expect(result.questions.first.options.length, 4);
        } finally {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        }
      },
    );
  });

  group('QuestionBankScannerModal Widget Tests', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.delete(db.examSchedules).go();
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets('renders input state with camera/gallery prompts and chips', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: const MaterialApp(
            home: Scaffold(body: QuestionBankScannerModal()),
          ),
        ),
      );

      await tester.pump();

      // Check header
      expect(find.text('প্রশ্ন ব্যাংক স্ক্যানার ও কুইজ তৈরি'), findsOneWidget);
      expect(
        find.text('বই বা প্রশ্ন ব্যাংকের পাতার ছবি দিয়ে পরীক্ষা দিন'),
        findsOneWidget,
      );

      // Check image upload cards
      expect(find.text('১. প্রশ্ন পাতার ছবি (আবশ্যক)'), findsOneWidget);
      expect(find.text('২. উত্তরপত্রের ছবি (ঐচ্ছিক)'), findsOneWidget);

      // Check Scan button is rendered
      expect(
        find.text('⚡ প্রশ্ন ব্যাংক স্ক্যান করুন (Extract MCQs)'),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });

    test('allows saving extracted question bank into exam_schedules', () async {
      // Simulate a question bank extract result
      final tempFile = File(
        '${Directory.systemTemp.path}/test_qb_page_save.jpg',
      );
      await tempFile.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0]);

      try {
        final res = await QuestionBankOcrService.instance.extractQuestionBank(
          questionImage: tempFile,
          subjectHint: 'বাংলা ব্যাকরণ',
        );

        expect(res.questions.length, greaterThanOrEqualTo(2));

        // Insert directly using database companion to test persistence and retrieval
        final questionsJson = jsonEncode(
          res.questions.map((q) => q.toJson()).toList(),
        );
        await db.insertExamSchedulesDeduplicated([
          ExamSchedulesCompanion.insert(
            examDate: DateTime.now(),
            title: 'বাংলা ব্যাকরণ প্রশ্ন ব্যাংক (কারক ও বিভক্তি)',
            subject: const Value('বাংলা ব্যাকরণ'),
            topicsCovered: 'কারক ও বিভক্তি',
            trackName: const Value('Self Test'),
            resourceSummary: Value(questionsJson),
            rawReference: const Value('Question Bank OCR (3 MCQs)'),
          ),
        ]);

        final saved = await db.select(db.examSchedules).get();
        expect(saved.length, 1);
        expect(
          saved.first.title,
          'বাংলা ব্যাকরণ প্রশ্ন ব্যাংক (কারক ও বিভক্তি)',
        );
        expect(saved.first.trackName, 'Self Test');

        // Confirm questions round-trip from resourceSummary
        final decodedList = jsonDecode(saved.first.resourceSummary!) as List;
        final loadedQuestions = decodedList
            .map((e) => QuizQuestion.fromJson(e as Map<String, dynamic>))
            .toList();
        expect(loadedQuestions.length, res.questions.length);
        expect(
          loadedQuestions.first.questionText,
          res.questions.first.questionText,
        );
        expect(loadedQuestions.first.options.length, 4);
      } finally {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }
    });

    testWidgets(
      'DashboardScreen renders Test Paper quick action pill and opens scanner',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          ProviderScope(
            overrides: [appDatabaseProvider.overrideWithValue(db)],
            child: const MaterialApp(home: DashboardScreen()),
          ),
        );

        await tester.pump();

        // Check Test Paper pill is rendered alongside Voice Mistake and Mistake Book
        expect(find.text('Voice Mistake'), findsOneWidget);
        expect(find.text('Mistake Book'), findsOneWidget);
        expect(find.text('Test Paper'), findsOneWidget);

        // Tap on 'Test Paper'
        await tester.tap(find.text('Test Paper'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Verify QuestionBankScannerModal is opened
        expect(
          find.text('প্রশ্ন ব্যাংক স্ক্যানার ও কুইজ তৈরি'),
          findsOneWidget,
        );

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 100));
      },
    );

    testWidgets(
      'QuestionBankScannerModal opens in review mode when preloaded with initialQuestions',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        const sampleQuestions = [
          QuizQuestion(
            questionText: '১. "সূর্য" শব্দের সমার্থক শব্দ কোনটি?',
            options: ['ক. সুধাকর', 'খ. তপন', 'গ. শশাঙ্ক', 'ঘ. বিধু'],
            correctIndex: 1,
            explanation: 'তপন সূর্যের সমার্থক।',
            subject: 'বাংলা ব্যাকরণ',
          ),
          QuizQuestion(
            questionText: '২. "অরণ্য" শব্দের সমার্থক শব্দ কোনটি?',
            options: ['ক. বন', 'খ. গিরি', 'গ. শৈল', 'ঘ. অবনী'],
            correctIndex: 0,
            explanation: 'অরণ্য মানে বন।',
            subject: 'বাংলা ব্যাকরণ',
          ),
        ];

        await tester.pumpWidget(
          ProviderScope(
            overrides: [appDatabaseProvider.overrideWithValue(db)],
            child: const MaterialApp(
              home: Scaffold(
                body: QuestionBankScannerModal(
                  initialQuestions: sampleQuestions,
                  initialTitle: 'টেস্ট পেপার সমার্থক শব্দ',
                  initialSubject: 'বাংলা ব্যাকরণ',
                  existingExamId: 99,
                ),
              ),
            ),
          ),
        );

        await tester.pump();

        // Should be directly in review mode
        expect(
          find.text('টেস্ট পেপার প্রশ্নমালা ও AI ফ্যাক্ট-চেক'),
          findsOneWidget,
        );
        expect(find.text('২টি প্রশ্ন'), findsOneWidget);
        expect(
          find.text('১. "সূর্য" শব্দের সমার্থক শব্দ কোনটি?'),
          findsOneWidget,
        );
        expect(
          find.text(
            '২. "অরণ্য" শব্দের সমার্থক শব্দ কোনটি?',
            skipOffstage: false,
          ),
          findsOneWidget,
        );
        expect(find.text('⚡ সব প্রশ্ন AI দিয়ে যাচাই করুন'), findsOneWidget);
        expect(find.text('সব কপি'), findsOneWidget);
        expect(find.text('AI ফিক্স'), findsOneWidget);
        expect(find.text('💾 আপডেট করুন'), findsOneWidget);

        // Search keyword filters question list
        await tester.enterText(
          find.widgetWithText(TextField, 'প্রশ্ন খুঁজুন...'),
          'অরণ্য',
        );
        await tester.pump();

        expect(
          find.text('১. "সূর্য" শব্দের সমার্থক শব্দ কোনটি?'),
          findsNothing,
        );
        expect(
          find.text('২. "অরণ্য" শব্দের সমার্থক শব্দ কোনটি?'),
          findsOneWidget,
        );

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 100));
      },
    );

    testWidgets(
      'LiveMcqScreen renders formatted Test Paper card summary instead of raw JSON',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        const sampleQuestions = [
          QuizQuestion(
            questionText: '১. "অপরিচিতা" গল্পের কথকের নাম কী?',
            options: ['ক. অনুপম', 'খ. হরিশ', 'গ. বিনুদা', 'ঘ. শম্ভুনাথ'],
            correctIndex: 0,
            explanation: 'অনুপম মূল চরিত্র ও কথক।',
            subject: 'বাংলা ১ম পত্র',
          ),
          QuizQuestion(
            questionText: '২. কল্যাণীর বাবার নাম কী?',
            options: ['ক. মামা', 'খ. শম্ভুনাথ সেন', 'গ. হরিশ', 'ঘ. গজানন'],
            correctIndex: 1,
            explanation: 'কল্যাণীর বাবা শম্ভুনাথ সেন।',
            subject: 'বাংলা ১ম পত্র',
          ),
        ];
        final jsonQuestions = jsonEncode(
          sampleQuestions.map((q) => q.toJson()).toList(),
        );

        final testPaperExam = ExamSchedule(
          id: 54,
          examDate: DateTime.now().add(const Duration(days: 1)),
          examTime: '10:00 PM',
          subject: 'বাংলা ১ম পত্র',
          title: 'বাংলা ১ম পত্র - নির্বাচনী পরীক্ষা ২০২৩',
          topicsCovered: 'বাংলা ১ম পত্র - নির্বাচনী পরীক্ষা ২০২৩',
          examType: 'Self Test',
          trackName: 'Self Test',
          resourceSummary: jsonQuestions,
          rawReference: 'Question Bank OCR (2 MCQs)',
          completedStatus: false,
          score: null,
          createdAt: DateTime.now(),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              distinctTracksStreamProvider.overrideWith(
                (ref) => Stream.value(['Self Test']),
              ),
              filteredExamsStreamProvider.overrideWith(
                (ref) => Stream.value([testPaperExam]),
              ),
            ],
            child: const MaterialApp(home: LiveMcqScreen()),
          ),
        );

        await tester.pumpAndSettle();

        // Verify that the raw JSON string is NOT shown on the card!
        expect(find.text(jsonQuestions), findsNothing);

        // Verify clean Test Paper card summary is rendered
        expect(find.text('টেস্ট পেপার প্রশ্নমালা (২টি MCQ)'), findsOneWidget);
        expect(
          find.text('১ম প্রশ্ন: ১. "অপরিচিতা" গল্পের কথকের নাম কী?'),
          findsOneWidget,
        );
        expect(find.text('সম্পাদনা'), findsOneWidget);
        expect(find.text('কপি'), findsOneWidget);
        expect(find.text('AI ফিক্স'), findsOneWidget);
        expect(find.text('প্রশ্ন দেখুন'), findsOneWidget);

        // Tap 'প্রশ্ন দেখুন' to expand
        await tester.tap(find.text('প্রশ্ন দেখুন'));
        await tester.pump();

        // Check expanded state with individual questions and options
        expect(find.text('সংক্ষেপ'), findsOneWidget);
        expect(find.text('১. "অপরিচিতা" গল্পের কথকের নাম কী?'), findsOneWidget);
        expect(find.text('২. কল্যাণীর বাবার নাম কী?'), findsOneWidget);
        expect(find.text('ক. অনুপম'), findsOneWidget);
        expect(find.text('খ. শম্ভুনাথ সেন'), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 100));
      },
    );
  });
}
