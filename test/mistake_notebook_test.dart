import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/database/database_provider.dart';
import 'package:life_and_study_assistant/features/mistake_notebook/domain/models/mistake_folder.dart';
import 'package:life_and_study_assistant/features/mistake_notebook/presentation/screens/mistake_notebook_screen.dart';
import 'package:life_and_study_assistant/features/mistake_notebook/presentation/widgets/nightly_review_modal.dart';
import 'package:life_and_study_assistant/features/quiz/presentation/providers/drill_history_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('Mistake Notebook Models & Grouping Tests', () {
    test('detectMistakeSource identifies source correctly', () {
      final voiceQuestion = DrillQuestion(
        id: 1,
        drillRecordId: 1,
        subject: 'Bangla Grammar',
        topic: 'কারক ও বিভক্তি',
        questionText: 'তিলে তৈল হয় কোন কারক?',
        optionsJson: jsonEncode(['অপাদান', 'অধিকরণ', 'করণ', 'কর্ম']),
        correctIndex: 0,
        selectedIndex: 1,
        isCorrect: false,
        explanation:
            '[উৎস: LiveMCQ 🎙️] যা থেকে উৎপন্ন বা বিচ্যুত হয় তা অপাদান কারক।',
        isMastered: false,
        attemptedAt: DateTime.now(),
      );

      final bookScanQuestion = DrillQuestion(
        id: 2,
        drillRecordId: 2,
        subject: 'General Science',
        topic: 'বই স্ক্যান: আলো ও লেন্স',
        questionText: 'অপটিক্যাল ফাইবার কোন নীতিতে কাজ করে?',
        optionsJson: jsonEncode([
          'প্রতিসরণ',
          'পূর্ণ অভ্যন্তরীণ প্রতিফলন',
          'বিচ্ছুরণ',
          'ব্যতিচার',
        ]),
        correctIndex: 1,
        selectedIndex: 0,
        isCorrect: false,
        explanation: 'আলোর পূর্ণ অভ্যন্তরীণ প্রতিফলন নীতি ব্যবহার করা হয়।',
        isMastered: false,
        attemptedAt: DateTime.now(),
      );

      final modelTestQuestion = DrillQuestion(
        id: 3,
        drillRecordId: 3,
        subject: 'Bangladesh Affairs',
        topic: 'মুক্তিযুদ্ধ ও সংবিধান',
        questionText: 'বাংলাদেশের সংবিধান কত তারিখে গৃহীত হয়?',
        optionsJson: jsonEncode([
          '১৬ ডিসেম্বর ১৯৭২',
          '৪ নভেম্বর ১৯৭২',
          '২৬ মার্চ ১৯৭২',
          '১০ জানুয়ারি ১৯৭২',
        ]),
        correctIndex: 1,
        selectedIndex: 0,
        isCorrect: false,
        explanation:
            '৪ নভেম্বর ১৯৭২ সংবিধান গৃহীত হয় এবং ১৬ ডিসেম্বর কার্যকর হয়।',
        isMastered: true,
        attemptedAt: DateTime.now(),
      );

      expect(
        detectMistakeSource(voiceQuestion),
        equals(MistakeSource.liveMcqVoice),
      );
      expect(
        detectMistakeSource(bookScanQuestion),
        equals(MistakeSource.bookScan),
      );
      expect(
        detectMistakeSource(modelTestQuestion),
        equals(MistakeSource.modelTest),
      );
    });

    test('groupMistakesIntoFolders accurately groups questions into subject folders', () {
      final questions = [
        DrillQuestion(
          id: 1,
          drillRecordId: 1,
          subject: 'Bangla Grammar',
          topic: 'সমাস',
          questionText: 'সিংহাসন কোন সমাস?',
          optionsJson: jsonEncode([
            'মধ্যপদলোপী কর্মধারয়',
            'দ্বন্দ্ব',
            'তৎপুরুষ',
            'বহুব্রীহি',
          ]),
          correctIndex: 0,
          selectedIndex: 1,
          isCorrect: false,
          explanation: '',
          isMastered: false,
          attemptedAt: DateTime.now(),
        ),
        DrillQuestion(
          id: 2,
          drillRecordId: 1,
          subject: 'বাংলা ব্যাকরণ',
          topic: 'সন্ধি',
          questionText: 'বিদ্যালয়',
          optionsJson: jsonEncode(['বিদ্যা+আলয়', 'বিদ্যা+লয়']),
          correctIndex: 0,
          selectedIndex: 1,
          isCorrect: false,
          explanation: '',
          isMastered: true,
          attemptedAt: DateTime.now(),
        ),
        DrillQuestion(
          id: 3,
          drillRecordId: 2,
          subject: 'Petrobangla Mechanical',
          topic: 'Thermodynamics',
          questionText: 'Carnot engine efficiency',
          optionsJson: jsonEncode(['1 - T2/T1', 'T2/T1']),
          correctIndex: 0,
          selectedIndex: 1,
          isCorrect: false,
          explanation: '',
          isMastered: false,
          attemptedAt: DateTime.now(),
        ),
      ];

      final folders = groupMistakesIntoFolders(questions);

      expect(folders.length, equals(2)); // Bangla and Petrobangla

      final banglaFolder = folders.firstWhere((f) => f.id == 'bangla');
      expect(banglaFolder.totalCount, equals(2));
      expect(banglaFolder.pendingCount, equals(1));
      expect(banglaFolder.masteredCount, equals(1));
      expect(banglaFolder.masteryRate, equals(50.0));

      final petroFolder = folders.firstWhere(
        (f) => f.id.contains('petrobangla'),
      );
      expect(petroFolder.totalCount, equals(1));
      expect(petroFolder.pendingCount, equals(1));
      expect(petroFolder.masteredCount, equals(0));
    });
  });

  group('Mistake Database Queries & Persistence Tests', () {
    test('watchAllMistakeQuestions returns all errors and markQuestionMastered updates status', () async {
      await db
          .into(db.drillQuestions)
          .insert(
            DrillQuestionsCompanion.insert(
              subject: 'English',
              topic: 'Subject-Verb Agreement',
              questionText: 'Neither of the boys ___ present.',
              optionsJson: jsonEncode(['was', 'were', 'are', 'have']),
              correctIndex: 0,
              selectedIndex: 1,
              isCorrect: false,
              explanation: const drift.Value('Neither of takes singular verb.'),
              isMastered: const drift.Value(false),
            ),
          );

      await db
          .into(db.drillQuestions)
          .insert(
            DrillQuestionsCompanion.insert(
              subject: 'Mathematics',
              topic: 'শতকরা',
              questionText: '১০ টাকার ২০% কত?',
              optionsJson: jsonEncode(['২', '৩', '৪', '৫']),
              correctIndex: 0,
              selectedIndex: 0,
              isCorrect: true, // Correct question, not a mistake
              explanation: const drift.Value(''),
              isMastered: const drift.Value(false),
            ),
          );

      final initialMistakes = await db.watchAllMistakeQuestions().first;
      expect(initialMistakes.length, equals(1));
      expect(initialMistakes.first.subject, equals('English'));
      expect(initialMistakes.first.isMastered, isFalse);

      // Mark mastered
      final success = await db.markQuestionMastered(
        initialMistakes.first.id,
        true,
      );
      expect(success, isTrue);

      final updatedMistakes = await db.watchAllMistakeQuestions().first;
      expect(updatedMistakes.length, equals(1));
      expect(updatedMistakes.first.isMastered, isTrue);

      // Unmastered stream should now be empty
      final wrongOnly = await db.watchWrongDrillQuestions().first;
      expect(wrongOnly.isEmpty, isTrue);
    });
  });

  group('Mistake Notebook Widget Tests', () {
    testWidgets(
      'Renders MistakeNotebookScreen with stats, folders, and cards',
      (tester) async {
        final sampleList = [
          DrillQuestion(
            id: 1,
            drillRecordId: 1,
            subject: 'Bangla',
            topic: 'কারক ও বিভক্তি',
            questionText: 'তিলে তৈল হয় কোন কারক?',
            optionsJson: jsonEncode(['অপাদান', 'অধিকরণ', 'করণ', 'কর্ম']),
            correctIndex: 0,
            selectedIndex: 1,
            isCorrect: false,
            explanation: 'অপাদান কারকের নিয়ম',
            isMastered: false,
            attemptedAt: DateTime.now(),
          ),
          DrillQuestion(
            id: 2,
            drillRecordId: 2,
            subject: 'English',
            topic: 'Vocabulary',
            questionText: 'What is the synonym of Benevolent?',
            optionsJson: jsonEncode(['Kind', 'Cruel', 'Harsh', 'Greedy']),
            correctIndex: 0,
            selectedIndex: 1,
            isCorrect: false,
            explanation: 'Benevolent means kind.',
            isMastered: true,
            attemptedAt: DateTime.now(),
          ),
        ];

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              allMistakesStreamProvider.overrideWith(
                (ref) => Stream.value(sampleList),
              ),
            ],
            child: const MaterialApp(home: MistakeNotebookScreen()),
          ),
        );

        await tester.pumpAndSettle();

        // Verify screen title
        expect(find.text('স্মার্ট মিস্টেক নোটবুক'), findsOneWidget);

        // Verify stats overview
        expect(find.text('মোট ভুল'), findsOneWidget);
        expect(find.text('2 টি'), findsOneWidget); // 2 total
        expect(find.text('1 টি'), findsNWidgets(2)); // 1 pending, 1 mastered
        expect(find.text('50% সলভড'), findsOneWidget);

        // Verify subject folder chips
        expect(find.text('সকল ভুল'), findsOneWidget);
        expect(find.text('বাংলা ভাষা ও সাহিত্য'), findsOneWidget);
        expect(find.text('English Language & Lit'), findsOneWidget);

        // Verify mistake question is rendered
        expect(find.text('তিলে তৈল হয় কোন কারক?'), findsOneWidget);
      },
    );

    testWidgets(
      'NightlyReviewModal allows revealing answer and marking mastered',
      (tester) async {
        final sampleQuestions = [
          DrillQuestion(
            id: 101,
            drillRecordId: 1,
            subject: 'Bangla Grammar',
            topic: 'সমাস',
            questionText: 'চাঁদমুখ কোন সমাস?',
            optionsJson: jsonEncode([
              'উপমিত কর্মধারয়',
              'উপমান কর্মধারয়',
              'রূপক কর্মধারয়',
              'তৎপুরুষ',
            ]),
            correctIndex: 0,
            selectedIndex: 1,
            isCorrect: false,
            explanation: 'মুখ চাঁদের ন্যায় = চাঁদমুখ (উপমিত কর্মধারয়)।',
            isMastered: false,
            attemptedAt: DateTime.now(),
          ),
        ];

        await tester.pumpWidget(
          ProviderScope(
            overrides: [appDatabaseProvider.overrideWithValue(db)],
            child: MaterialApp(
              home: NightlyReviewModal(questions: sampleQuestions),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Top title and card index
        expect(find.text('রাতের ৫ মিনিটের রিভিশন'), findsOneWidget);
        expect(find.text('কার্ড 1 / 1'), findsOneWidget);
        expect(find.text('চাঁদমুখ কোন সমাস?'), findsOneWidget);

        // Tap to reveal answer
        final revealBtn = find.text('ট্যাপ করে সঠিক উত্তর ও ব্যাখ্যা দেখুন');
        expect(revealBtn, findsOneWidget);
        await tester.tap(revealBtn);
        await tester.pumpAndSettle();

        // Answer revealed
        expect(find.text('ব্যাখ্যা ও রুল:'), findsOneWidget);
        expect(
          find.text('মুখ চাঁদের ন্যায় = চাঁদমুখ (উপমিত কর্মধারয়)।'),
          findsOneWidget,
        );

        // Tap Mastered button
        final masteredBtn = find.text('আয়ত্তে এসেছে!');
        expect(masteredBtn, findsOneWidget);
        await tester.tap(masteredBtn);
        await tester.pumpAndSettle();

        // Completion screen shown
        expect(find.text('দারুণ কাজ! আজকের রিভিশন শেষ! 🎉'), findsOneWidget);
        expect(find.text('Mistake Notebook এ ফিরে যান'), findsOneWidget);
      },
    );
  });
}
