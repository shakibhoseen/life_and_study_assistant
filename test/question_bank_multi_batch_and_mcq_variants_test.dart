import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/services/ai/models/quiz_question.dart';
import 'package:life_and_study_assistant/core/services/ai/question_text_parser.dart';
import 'package:life_and_study_assistant/features/quiz/domain/merge_scanned_pages.dart';
import 'package:life_and_study_assistant/features/quiz/presentation/widgets/question_bank_scanner_modal.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MCQ Generation & Format Parsing Tests (Multi-way)', () {
    test('parses Bengali MCQs with answers and explanations cleanly', () {
      const bengaliInput = '''
১. কোনটি মেঘনা নদীর প্রধান উপনদী?
ক) গোমতী
খ) করতোয়া
গ) কপোতাক্ষ
ঘ) ধলেশ্বরী
উত্তর: ক
ব্যাখ্যা: মেঘনা নদীর প্রধান উপনদীগুলোর মধ্যে গোমতী অন্যতম।

২. বাংলাদেশের সংবিধানের অভিভাবক ও ব্যাখ্যাকারক কে?
ক) প্রধান বিচারপতি
খ) বাংলাদেশ সুপ্রিম কোর্ট
গ) জাতীয় সংসদ
ঘ) মহামান্য রাষ্ট্রপতি
উত্তর: খ
ব্যাখ্যা: গণপ্রজাতন্ত্রী বাংলাদেশের সংবিধানের অভিভাবক ও ব্যাখ্যাকারক হলো সুপ্রিম কোর্ট।
''';

      final result = QuestionTextParser.tryParseLocal(bengaliInput);
      expect(result, isNotNull);
      expect(result!.questions.length, 2);

      final q1 = result.questions[0];
      expect(q1.questionText, contains('মেঘনা'));
      expect(q1.options.length, 4);
      expect(q1.options[0], contains('গোমতী'));
      expect(q1.correctIndex, 0);
      expect(q1.hasAnswer, isTrue);
      expect(q1.explanation, contains('উপনদীগুলোর মধ্যে গোমতী'));

      final q2 = result.questions[1];
      expect(q2.questionText, contains('সংবিধানের অভিভাবক'));
      expect(q2.correctIndex, 1);
      expect(q2.hasAnswer, isTrue);
      expect(q2.explanation, contains('সুপ্রিম কোর্ট'));
    });

    test('parses English MCQs with Ans: and Explanation:', () {
      const englishInput = '''
1. What is the powerhouse of the cell?
A) Nucleus
B) Ribosome
C) Mitochondria
D) Cytoplasm
Ans: C
Explanation: Mitochondria generates most of the chemical energy needed by the cell.

2. Which protocol is used for secure communication over the Internet?
A) HTTP
B) HTTPS
C) FTP
D) SMTP
Answer: B
Explanation: HTTPS encrypts communication between the browser and the web server.
''';

      final result = QuestionTextParser.tryParseLocal(englishInput);
      expect(result, isNotNull);
      expect(result!.questions.length, 2);

      final q1 = result.questions[0];
      expect(q1.questionText, contains('powerhouse of the cell'));
      expect(q1.correctIndex, 2); // C -> index 2
      expect(q1.hasAnswer, isTrue);
      expect(q1.explanation, contains('chemical energy'));

      final q2 = result.questions[1];
      expect(q2.questionText, contains('secure communication'));
      expect(q2.correctIndex, 1); // B -> index 1
      expect(q2.hasAnswer, isTrue);
    });

    test('parses MCQs without answers and marks them with correctIndex = -1', () {
      const inputWithoutAnswers = '''
১. প্রথম প্রোগ্রামিং ভাষার নাম কী?
ক) ফোরট্রান
খ) প্যাস্কেল
গ) সি
ঘ) পাইথন

২. র‍্যাম (RAM) কোন ধরনের মেমোরি?
ক) স্থায়ী
খ) অস্থায়ী
গ) সেকেন্ডারি
ঘ) অপটিক্যাল
''';

      final result = QuestionTextParser.tryParseLocal(inputWithoutAnswers);
      expect(result, isNotNull);
      expect(result!.questions.length, 2);

      for (final q in result.questions) {
        expect(q.correctIndex, -1);
        expect(q.hasAnswer, isFalse);
        expect(q.answerSource, AnswerSource.guess);
        expect(q.needsReview, isTrue);
      }
    });
  });

  group('Multi-batch MCQ Addition & Merge Scenarios', () {
    test('Scenario 1: Adding a second batch of brand new MCQs appends smoothly', () {
      final batch1 = [
        QuizQuestion(
          questionText: '১. মুজিবনগর সরকার কবে শপথ গ্রহণ করে?',
          options: const ['ক) ১০ এপ্রিল ১৯৭১', 'খ) ১৭ এপ্রিল ১৯৭১', 'গ) ৭ মার্চ ১৯৭১', 'ঘ) ২৫ মার্চ ১৯৭১'],
          correctIndex: 1,
          explanation: '১৯৭১ সালের ১৭ এপ্রিল মেহেরপুরের বৈদ্যনাথতলায় মুজিবনগর সরকার শপথ নেয়।',
          subject: 'বাংলাদেশ বিষয়াবলী',
        ),
      ];

      final batch2 = [
        QuizQuestion(
          questionText: '২. মুক্তিযুদ্ধকালে বাংলাদেশকে কয়টি সেক্টরে ভাগ করা হয়েছিল?',
          options: const ['ক) ৮টি', 'খ) ৯টি', 'গ) ১১টি', 'ঘ) ৬৪টি'],
          correctIndex: 2,
          explanation: 'সারাদেশকে ১১টি প্রশাসনিক ও সামরিক সেক্টরে বিভক্ত করা হয়।',
          subject: 'বাংলাদেশ বিষয়াবলী',
        ),
      ];

      final merge = mergeScannedPage(existing: batch1, fromPage: batch2);
      expect(merge.questions.length, 2);
      expect(merge.added, 1);
      expect(merge.duplicates, 0);
      expect(merge.questions[0].questionText, contains('মুজিবনগর'));
      expect(merge.questions[1].questionText, contains('মুক্তিযুদ্ধকালে'));
    });

    test('Scenario 2: Adding duplicate questions drops duplicates without crashing or doubling', () {
      final batch1 = [
        QuizQuestion(
          questionText: '১. জাতিসংঘের বর্তমান মহাসচিব কে?',
          options: const ['ক) বান কি মুন', 'খ) আন্তোনিও গুতেরেস', 'গ) কফি আনান', 'ঘ) বুত্রোস ঘালি'],
          correctIndex: 1,
          explanation: '',
          subject: 'আন্তর্জাতিক বিষয়াবলী',
        ),
      ];

      // Second paste repeats the exact same question
      final batch2 = [
        QuizQuestion(
          questionText: '১. জাতিসংঘের বর্তমান মহাসচিব কে?',
          options: const ['ক) বান কি মুন', 'খ) আন্তোনিও গুতেরেস', 'গ) কফি আনান', 'ঘ) বুত্রোস ঘালি'],
          correctIndex: 1,
          explanation: '',
          subject: 'আন্তর্জাতিক বিষয়াবলী',
        ),
        QuizQuestion(
          questionText: '২. ন্যাটো (NATO)-এর সদর দপ্তর কোথায়?',
          options: const ['ক) জেনেভা', 'খ) ব্রাসেলস', 'গ) ওয়াশিংটন', 'ঘ) লন্ডন'],
          correctIndex: 1,
          explanation: 'বেলজিয়ামের ব্রাসেলসে ন্যাটোর সদর দপ্তর অবস্থিত।',
          subject: 'আন্তর্জাতিক বিষয়াবলী',
        ),
      ];

      final merge = mergeScannedPage(existing: batch1, fromPage: batch2);
      expect(merge.questions.length, 2); // 1 from batch 1 + 1 new from batch 2
      expect(merge.added, 1);
      expect(merge.duplicates, 1);
      expect(merge.questions[1].questionText, contains('ন্যাটো'));
    });

    test('Scenario 3: Enriching unanswered question when the same question is re-added with answer', () {
      // First batch had no answer (correctIndex = -1)
      final batch1Unanswered = [
        QuizQuestion(
          questionText: '১. এসডিজি (SDG)-এর লক্ষ্যমাত্রা কয়টি?',
          options: const ['ক) ৮টি', 'খ) ১৫টি', 'গ) ১৭টি', 'ঘ) ২১টি'],
          correctIndex: -1,
          explanation: '',
          subject: 'আন্তর্জাতিক',
          answerSource: AnswerSource.guess,
        ),
      ];
      expect(batch1Unanswered.first.hasAnswer, isFalse);

      // Second batch provides the verified answer and explanation
      final batch2WithAnswer = [
        QuizQuestion(
          questionText: '১. এসডিজি (SDG)-এর লক্ষ্যমাত্রা কয়টি?',
          options: const ['ক) ৮টি', 'খ) ১৫টি', 'গ) ১৭টি', 'ঘ) ২১টি'],
          correctIndex: 2,
          explanation: 'টেকসই উন্নয়ন লক্ষ্যমাত্রা (SDG) এর ১৭টি লক্ষ্য রয়েছে।',
          subject: 'আন্তর্জাতিক',
          answerSource: AnswerSource.answerKey,
        ),
      ];

      final merge = mergeScannedPage(existing: batch1Unanswered, fromPage: batch2WithAnswer);
      expect(merge.questions.length, 1); // deduplicated
      expect(merge.duplicates, 1);

      // The existing question was enriched with the newly provided answer!
      final enriched = merge.questions.first;
      expect(enriched.correctIndex, 2);
      expect(enriched.hasAnswer, isTrue);
      expect(enriched.explanation, contains('১৭টি লক্ষ্য রয়েছে'));
      expect(enriched.answerSource, AnswerSource.answerKey);
    });

    test('Scenario 4: Textbook answer key mapping on multi-batch questions', () {
      final questions = [
        QuizQuestion(
          questionText: '১. বাংলা গদ্যের জনক কে?',
          options: const ['ক) বঙ্কিমচন্দ্র', 'খ) ঈশ্বরচন্দ্র বিদ্যাসাগর', 'গ) রবীন্দ্রনাথ', 'ঘ) প্রমথ চৌধুরী'],
          correctIndex: -1,
          explanation: '',
          subject: 'বাংলা',
        ),
        QuizQuestion(
          questionText: '২. "গীতাঞ্জলি" কাব্যগ্রন্থ কত সালে প্রকাশিত হয়?',
          options: const ['ক) ১৯১০', 'খ) ১৯১৩', 'গ) ১৯১২', 'ঘ) ১৯০৫'],
          correctIndex: -1,
          explanation: '',
          subject: 'বাংলা',
        ),
        QuizQuestion(
          questionText: '৩. কাজী নজরুল ইসলামের জন্মস্থান কোথায়?',
          options: const ['ক) চুরুলিয়া', 'খ) শিলাইদহ', 'গ) কুষ্টিয়া', 'ঘ) ঢাকা'],
          correctIndex: -1,
          explanation: '',
          subject: 'বাংলা',
        ),
      ];

      // Parse textbook answer key: ১. খ, ২. ক, ৩. ক
      final keyMap = QuestionTextParser.parseAnswerKey('১. খ, ২. ক, ৩. ক');
      expect(keyMap.length, 3);
      expect(keyMap[0], 1); // Q1 -> খ (index 1)
      expect(keyMap[1], 0); // Q2 -> ক (index 0)
      expect(keyMap[2], 0); // Q3 -> ক (index 0)

      // Apply key to questions
      final updated = <QuizQuestion>[];
      for (int i = 0; i < questions.length; i++) {
        final optIdx = keyMap[i];
        if (optIdx != null) {
          updated.add(questions[i].copyWith(
            correctIndex: optIdx,
            answerSource: AnswerSource.answerKey,
          ));
        } else {
          updated.add(questions[i]);
        }
      }

      expect(updated[0].correctIndex, 1);
      expect(updated[0].hasAnswer, isTrue);
      expect(updated[1].correctIndex, 0);
      expect(updated[1].hasAnswer, isTrue);
      expect(updated[2].correctIndex, 0);
      expect(updated[2].hasAnswer, isTrue);
    });
  });

  group('Widget Integration: Multi-batch Paste in QuestionBankScannerModal', () {
    testWidgets('Review screen shows "+ আরও পেস্ট" button and opens add sheet', (tester) async {
      final initialQuestions = [
        QuizQuestion(
          questionText: '১. পদ্মা সেতুর দৈর্ঘ্য কত?',
          options: const ['ক) ৬.১৫ কিমি', 'খ) ৪.৮ কিমি', 'গ) ৭.২ কিমি', 'ঘ) ৫.৫ কিমি'],
          correctIndex: 0,
          explanation: 'মূল সেতুর দৈর্ঘ্য ৬.১৫ কিলোমিটার।',
          subject: 'সাধারণ জ্ঞান',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: QuestionBankScannerModal(
                initialQuestions: initialQuestions,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check that 1 question is currently displayed
      expect(find.text('১টি প্রশ্ন'), findsOneWidget);
      expect(find.text('১. পদ্মা সেতুর দৈর্ঘ্য কত?'), findsOneWidget);

      // Verify that the "+ আরও পেস্ট" button is visible in the top action row
      expect(find.text('+ আরও পেস্ট'), findsOneWidget);

      // Tap "+ আরও পেস্ট"
      await tester.tap(find.text('+ আরও পেস্ট'));
      await tester.pumpAndSettle();

      // Verify bottom sheet opened
      expect(find.text('আরও প্রশ্ন যোগ করুন (পেস্ট)'), findsOneWidget);
      expect(find.text('প্রশ্নে যুক্ত করুন (+ Merge)'), findsOneWidget);

      // Close bottom sheet using the last close button (in sheet)
      await tester.tap(find.byIcon(Icons.close).last);
      await tester.pumpAndSettle();
    });

    testWidgets('Unanswered questions show amber warning and manual option tap sets answer', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final unansweredQuestion = [
        QuizQuestion(
          questionText: '১. বাংলাদেশের একমাত্র প্রবাল দ্বীপ কোনটি?',
          options: const ['ক) সেন্টমার্টিন', 'খ) মহেশখালী', 'গ) কুতুবদিয়া', 'ঘ) সন্দ্বীপ'],
          correctIndex: -1, // No answer!
          explanation: '',
          subject: 'ভূগোল',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: QuestionBankScannerModal(
                initialQuestions: unansweredQuestion,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check unanswered amber banner and badge
      // Check unanswered amber banner
      expect(find.textContaining('প্রশ্নের কোনো উত্তর বা ব্যাখ্যা নেই'), findsOneWidget);

      expect(find.text('১. বাংলাদেশের একমাত্র প্রবাল দ্বীপ কোনটি?'), findsOneWidget);
      expect(find.textContaining('উত্তর নির্বাচিত নেই'), findsOneWidget);

      // Tap option 'ক) সেন্টমার্টিন'
      await tester.tap(find.text('ক) সেন্টমার্টিন'));
      await tester.pumpAndSettle();

      // Tapping marks it as selected!
      expect(find.text('চিহ্নিত উত্তর'), findsOneWidget);
    });

    testWidgets('Review screen allows pasting additional questions and merges into current quiz', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final initialQuestions = [
        QuizQuestion(
          questionText: '১. বাংলাদেশের জাতীয় খেলা কোনটি?',
          options: const ['ক) ফুটবল', 'খ) হা-ডু-ডু', 'গ) ক্রিকেট', 'ঘ) কাবাডি'],
          correctIndex: 3,
          explanation: 'বাংলাদেশের জাতীয় খেলা কাবাডি বা হা-ডু-ডু।',
          subject: 'বাংলাদেশ বিষয়াবলী',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: QuestionBankScannerModal(
                initialQuestions: initialQuestions,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('১টি প্রশ্ন'), findsOneWidget);
      expect(find.text('১. বাংলাদেশের জাতীয় খেলা কোনটি?'), findsOneWidget);

      // Tap '+ আরও পেস্ট'
      await tester.tap(find.text('+ আরও পেস্ট'));
      await tester.pumpAndSettle();

      // Enter a new question into the bottom sheet text field
      const additionalMcqText = '''
২. জাতীয় কবি কাজী নজরুল ইসলামের সমাধিস্থল কোথায়?
ক) ধানমন্ডি
খ) ঢাকা বিশ্ববিদ্যালয় মসজিদ প্রাঙ্গণ
গ) মিরপুর বুদ্ধিজীবী কবরস্থান
ঘ) বাংলা একাডেমি
উত্তর: খ
ব্যাখ্যা: ঢাকা বিশ্ববিদ্যালয় কেন্দ্রীয় মসজিদ প্রাঙ্গণে কবিকে সমাহিত করা হয়।
''';

      // Find the TextField in the bottom sheet and enter text
      final bottomSheetTextField = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(TextField),
      );
      expect(bottomSheetTextField, findsOneWidget);
      await tester.enterText(bottomSheetTextField, additionalMcqText);
      await tester.pumpAndSettle();

      // Tap 'প্রশ্নে যুক্ত করুন (+ Merge)'
      await tester.tap(find.text('প্রশ্নে যুক্ত করুন (+ Merge)'));
      await tester.pumpAndSettle();

      // Verify that the total question count has updated to 2!
      expect(find.text('২টি প্রশ্ন'), findsOneWidget);
      // Verify both questions exist in the quiz!
      expect(find.text('১. বাংলাদেশের জাতীয় খেলা কোনটি?'), findsOneWidget);
      expect(find.text('২. জাতীয় কবি কাজী নজরুল ইসলামের সমাধিস্থল কোথায়?'), findsOneWidget);
    });
  });
}
