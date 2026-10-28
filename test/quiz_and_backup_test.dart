import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/database/database_provider.dart';
import 'package:life_and_study_assistant/core/database/tables/daily_energy_logs_table.dart';
import 'package:life_and_study_assistant/core/database/tables/weak_topics_table.dart';
import 'package:life_and_study_assistant/core/services/ai/models/quiz_question.dart';
import 'package:life_and_study_assistant/core/services/ai/quiz_generator_service.dart';
import 'package:life_and_study_assistant/core/services/background/wifi_monitor_service.dart';
import 'package:life_and_study_assistant/features/quiz/presentation/widgets/quiz_drill_modal.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('Quiz Engine & Model Tests', () {
    test('QuizQuestion model serializes and deserializes correctly', () {
      const q = QuizQuestion(
        questionText: 'সন্ধি ব্যাকরণের কোন অংশে আলোচিত হয়?',
        options: ['রূপতত্ত্ব', 'ধ্বনি তত্ত্ব', 'বাক্যতত্ত্ব', 'অর্থতত্ত্ব'],
        correctIndex: 1,
        explanation:
            'সন্ধি বর্ণের সাথে বর্ণের মিলন, তাই ধ্বনিতত্ত্বে আলোচিত হয়।',
      );

      final map = q.toJson();
      expect(map['question'], equals('সন্ধি ব্যাকরণের কোন অংশে আলোচিত হয়?'));
      expect(map['options'].length, equals(4));
      expect(map['correct_index'], equals(1));

      final restored = QuizQuestion.fromJson(map);
      expect(restored.questionText, equals(q.questionText));
      expect(restored.options, equals(q.options));
      expect(restored.correctIndex, equals(1));
      expect(restored.explanation, equals(q.explanation));
    });

    test('QuizGeneratorService produces 5 valid questions offline for Bangla topic', () async {
      final questions = await QuizGeneratorService.instance.generateQuiz(
        topic: 'কারক ও বিভক্তি',
        subject: 'Bangla Grammar',
      );

      expect(questions.length, equals(5));
      for (final q in questions) {
        expect(q.questionText.isNotEmpty, isTrue);
        expect(q.options.length, equals(4));
        expect(q.correctIndex, inInclusiveRange(0, 3));
        expect(q.explanation.isNotEmpty, isTrue);
      }
    });
  });

  group('Data Backup & Restore Offline JSON Tests', () {
    test(
      'exportBackupJson exports valid JSON structure with accurate counts',
      () async {
        // 1. Insert a weak topic
        await db.insertWeakTopic(
          WeakTopicsCompanion.insert(
            subject: 'General Knowledge',
            topicName: 'Liberation War 1971',
            proficiencyLevel: ProficiencyLevel.weak,
            notes: const Value('Sector commanders revision needed'),
          ),
        );

        // 2. Insert an exam schedule
        await db.insertExamSchedule(
          ExamSchedulesCompanion.insert(
            title: 'Bangla Grammar Model Test 01',
            examDate: DateTime(2026, 11, 1),
            topicsCovered: 'কারক, সন্ধি, সমাস',
            trackName: const Value('52nd BCS 135-Day'),
            examType: const Value('Daily'),
          ),
        );

        // 3. Insert daily energy log
        await db.insertOrUpdateDailyLog(
          DailyEnergyLogsCompanion.insert(
            date: DateTime(2026, 10, 26),
            energyLevel: EnergyLevel.medium,
            officeFatigueScore: const Value(4),
            completedTasks: const Value('["Task 1"]'),
          ),
        );

        // Export
        final jsonStr = await db.exportBackupJson();
        expect(jsonStr.isNotEmpty, isTrue);

        final Map<String, dynamic> parsed = jsonDecode(jsonStr);
        expect(parsed['version'], equals(1));
        expect(parsed['exported_at'], isNotNull);

        final topics = parsed['weak_topics'] as List;
        expect(
          topics.any((t) => t['topic_name'] == 'Liberation War 1971'),
          isTrue,
        );

        final exams = parsed['exam_schedules'] as List;
        expect(
          exams.any((e) => e['title'] == 'Bangla Grammar Model Test 01'),
          isTrue,
        );

        final logs = parsed['daily_energy_logs'] as List;
        expect(logs.length, isPositive);
      },
    );

    test(
      'importBackupJson imports into a fresh database without loss',
      () async {
        final sampleBackup = jsonEncode({
          'version': 1,
          'exported_at': DateTime.now().toIso8601String(),
          'weak_topics': [
            {
              'subject': 'English',
              'topic_name': 'Subjunctive Mood',
              'proficiency_level': 'weak',
              'notes': 'Rule of suggest/insist',
            },
            {
              'subject': 'Math',
              'topic_name': 'Logarithm',
              'proficiency_level': 'strong',
              'notes': 'All formulas clear',
            },
          ],
          'exam_schedules': [
            {
              'exam_date': '2026-11-05T00:00:00.000',
              'exam_time': '10:00 PM',
              'subject': 'English Literature',
              'title': 'Elizabethan Era Test',
              'topics_covered': 'Shakespeare plays & sonnets',
              'exam_type': 'Daily',
              'track_name': 'Vocabulary Booster',
            },
          ],
          'daily_energy_logs': [
            {
              'date': '2026-10-25T00:00:00.000',
              'energy_level': 'high',
              'office_fatigue_score': 2,
              'completed_tasks': '["Read 2 chapters"]',
              'notes': 'Great productive evening',
            },
          ],
        });

        final result = await db.importBackupJson(sampleBackup);
        expect(result['weak_topics'], equals(2));
        expect(result['exam_schedules'], equals(1));
        expect(result['daily_energy_logs'], equals(1));

        final allTopics = await db.getAllWeakTopics();
        expect(allTopics.any((t) => t.topicName == 'Subjunctive Mood'), isTrue);
        expect(allTopics.any((t) => t.topicName == 'Logarithm'), isTrue);

        final allExams = await db.getUpcomingExams();
        expect(allExams.any((e) => e.title == 'Elizabethan Era Test'), isTrue);

        final todayLog = await db.getTodayLog(DateTime(2026, 10, 25));
        expect(todayLog, isNotNull);
        expect(todayLog!.energyLevel, equals(EnergyLevel.high));
        expect(todayLog.officeFatigueScore, equals(2));
      },
    );

    test(
      'importBackupJson handles duplicates safely without creating duplicates',
      () async {
        final sampleBackup = jsonEncode({
          'version': 1,
          'exported_at': DateTime.now().toIso8601String(),
          'weak_topics': [
            {
              'subject': 'Science',
              'topic_name': 'Optics & Light',
              'proficiency_level': 'weak',
            },
          ],
          'exam_schedules': [
            {
              'exam_date': '2026-11-10T00:00:00.000',
              'exam_time': '10:00 PM',
              'subject': 'General Science',
              'title': 'Optics Daily Drill',
              'topics_covered': 'Reflection & Refraction',
              'exam_type': 'Daily',
              'track_name': 'General BCS',
            },
          ],
        });

        // Import once
        await db.importBackupJson(sampleBackup);

        // Import identical data again
        final secondResult = await db.importBackupJson(sampleBackup);

        // Exam was skipped because identical; Weak topic not duplicated
        expect(secondResult['weak_topics'], equals(0));
        expect(secondResult['exam_schedules'], equals(0));

        final allTopics = await db.getAllWeakTopics();
        final opticsTopics = allTopics
            .where((t) => t.topicName == 'Optics & Light')
            .toList();
        expect(opticsTopics.length, equals(1));

        final allExams = await db.getUpcomingExams();
        final opticsExams = allExams
            .where((e) => e.title == 'Optics Daily Drill')
            .toList();
        expect(opticsExams.length, equals(1));
      },
    );

    test(
      'importBackupJson accepts code-fenced and camelCase backup JSON',
      () async {
        const backup = '''```json
{
  "weak_topics": [{"subjectName": "Math", "topicName": "Algebra"}],
  "exam_schedules": [{
    "examDate": "2026-11-12",
    "examTime": "09:00 PM",
    "subject": "Math",
    "title": "Algebra Model Test 02",
    "topics": ["সূচক", "লগারিদম"],
    "examType": "Model Test",
    "trackName": "Weekend Batch",
    "score": "87.5"
  }],
  "daily_energy_logs": [{
    "loggedAt": "2026-11-11",
    "energy_level": "high",
    "office_fatigue_score": "3",
    "completedTasks": ["Algebra revision"]
  }]
}
```''';

        final result = await db.importBackupJson(backup);
        expect(result, {
          'weak_topics': 1,
          'exam_schedules': 1,
          'daily_energy_logs': 1,
        });

        final exams = await db.select(db.examSchedules).get();
        final algebraExam = exams.singleWhere(
          (exam) => exam.title == 'Algebra Model Test 02',
        );
        // A topics array becomes a readable list, not a stringified Dart
        // list with its brackets still attached.
        expect(algebraExam.topicsCovered, 'সূচক, লগারিদম');
        expect(algebraExam.score, 87.5);
        final log = await db.getTodayLog(DateTime(2026, 11, 11));
        expect(log!.completedTasks, '["Algebra revision"]');
      },
    );
    test('a real export restores into an empty database', () async {
      // What the user actually does: copy the exported text, paste it back.
      await db.insertWeakTopic(
        WeakTopicsCompanion.insert(
          subject: 'Bangla Grammar',
          topicName: 'কারক ও বিভক্তি',
          proficiencyLevel: ProficiencyLevel.weak,
          notes: const Value('প্রায়ই ভুল হয়'),
        ),
      );
      await db.insertExamSchedule(
        ExamSchedulesCompanion.insert(
          examDate: DateTime(2026, 12, 1),
          examTime: const Value('09:00 PM'),
          subject: const Value('Mathematics'),
          title: 'Model Test 07',
          topicsCovered: 'সূচক, লগারিদম',
          trackName: const Value('Weekend Batch'),
        ),
      );

      await db
          .into(db.drillQuestions)
          .insert(
            DrillQuestionsCompanion.insert(
              subject: 'গণিত',
              topic: 'সূচক',
              questionText: '২^৩ এর মান কত?',
              optionsJson: '["৪", "৬", "৮", "১০"]',
              correctIndex: 2,
              selectedIndex: 1,
              isCorrect: false,
            ),
          );

      final exported = await db.exportBackupJson();

      final fresh = AppDatabase(NativeDatabase.memory());
      addTearDown(fresh.close);
      await fresh.delete(fresh.weakTopics).go();
      await fresh.delete(fresh.examSchedules).go();
      await fresh.delete(fresh.drillQuestions).go();

      final importRes = await fresh.importBackupJson(exported);
      expect(importRes['mistakes'], 1);

      final exams = await fresh.select(fresh.examSchedules).get();
      final restored = exams.singleWhere((e) => e.title == 'Model Test 07');
      expect(restored.topicsCovered, 'সূচক, লগারিদম');
      expect(restored.examTime, '09:00 PM');
      expect(restored.trackName, 'Weekend Batch');

      final topics = await fresh.select(fresh.weakTopics).get();
      expect(topics.any((t) => t.topicName == 'কারক ও বিভক্তি'), isTrue);

      final restoredDq = await fresh.select(fresh.drillQuestions).get();
      expect(restoredDq.length, 1);
      expect(restoredDq.first.questionText, '২^৩ এর মান কত?');
      expect(restoredDq.first.isCorrect, isFalse);
    });
  });

  group('Multi-SSID Office Wi-Fi & Transition Tests', () {
    test('parseConfiguredSsids splits comma-separated networks accurately', () {
      final list = WifiMonitorService.parseConfiguredSsids(
        'Zavisoft, SecretStar',
      );
      expect(list, equals(['Zavisoft', 'SecretStar']));

      final withQuotes = WifiMonitorService.parseConfiguredSsids(
        '"Zavisoft", "SecretStar", Office-5G',
      );
      expect(withQuotes, equals(['Zavisoft', 'SecretStar', 'Office-5G']));

      final defaultList = WifiMonitorService.parseConfiguredSsids(null);
      expect(defaultList, equals(['ZaviSoft', 'Secreat Star', 'SecretStar']));
    });

    test('isOfficeNetwork matches Zavisoft and SecretStar case-insensitively and space-insensitively', () {
      const configured = 'Zavisoft, SecretStar, Secreat Star';

      // Office Wi-Fi
      expect(
        WifiMonitorService.isOfficeNetwork('Zavisoft', configured),
        isTrue,
      );
      expect(
        WifiMonitorService.isOfficeNetwork('zavisoft', configured),
        isTrue,
      );
      expect(
        WifiMonitorService.isOfficeNetwork('ZaviSoft', configured),
        isTrue,
      );

      // Mac Hotspot (Desk)
      expect(
        WifiMonitorService.isOfficeNetwork('SecretStar', configured),
        isTrue,
      );
      expect(
        WifiMonitorService.isOfficeNetwork('secretstar', configured),
        isTrue,
      );
      expect(
        WifiMonitorService.isOfficeNetwork('Secret Star', configured),
        isTrue,
      );
      expect(
        WifiMonitorService.isOfficeNetwork('Secreat Star', configured),
        isTrue,
      );
      expect(
        WifiMonitorService.isOfficeNetwork('secreatstar', configured),
        isTrue,
      );

      // Quoted strings returned by Android Wi-Fi
      expect(
        WifiMonitorService.isOfficeNetwork('"SecretStar"', configured),
        isTrue,
      );
      expect(
        WifiMonitorService.isOfficeNetwork('"ZaviSoft"', configured),
        isTrue,
      );
      expect(
        WifiMonitorService.isOfficeNetwork('"Secreat Star"', configured),
        isTrue,
      );

      // Other Wi-Fi (Home / Coffee shop)
      expect(
        WifiMonitorService.isOfficeNetwork('Home_WiFi', configured),
        isFalse,
      );
      expect(WifiMonitorService.isOfficeNetwork(null, configured), isFalse);
      expect(WifiMonitorService.isOfficeNetwork('', configured), isFalse);
      expect(
        WifiMonitorService.isOfficeNetwork('<unknown ssid>', configured),
        isFalse,
      );
      expect(
        WifiMonitorService.isOfficeNetwork('unknown ssid', configured),
        isFalse,
      );
    });
  });

  group('Drill Performance & Mistake Bank Tests', () {
    test('Drill session and individual questions persist accurately to Drift database', () async {
      final questions = [
        DrillQuestionsCompanion.insert(
          subject: 'Bangla Grammar',
          topic: 'কারক ও বিভক্তি',
          questionText: 'পাপে বিরত হও — কোন কারকে কোন বিভক্তি?',
          optionsJson: jsonEncode([
            'অপাদানে সপ্তমী',
            'করণে সপ্তমী',
            'অধিকরণে সপ্তমী',
            'কর্তায় সপ্তমী',
          ]),
          correctIndex: 0,
          selectedIndex: 0,
          isCorrect: true,
          explanation: const Value('অপাদান কারকে ৭মী বিভক্তি।'),
        ),
        DrillQuestionsCompanion.insert(
          subject: 'Bangla Grammar',
          topic: 'কারক ও বিভক্তি',
          questionText: 'তিলে তৈল হয় — কোন কারকে কোন বিভক্তি?',
          optionsJson: jsonEncode([
            'অধিকরণে সপ্তমী',
            'অপাদানে সপ্তমী',
            'করণে সপ্তমী',
            'কর্ম কারক',
          ]),
          correctIndex: 1,
          selectedIndex: 0, // Wrong answer chosen
          isCorrect: false,
          explanation: const Value(
            'কোনো কিছু হতে উৎপন্ন বা নিঃসৃত হলে অপাদান কারক হয়।',
          ),
        ),
      ];

      final recordId = await db.recordFullDrillSession(
        subject: 'Bangla Grammar',
        topic: 'কারক ও বিভক্তি',
        totalQuestions: 2,
        correctCount: 1,
        incorrectCount: 1,
        scorePercentage: 50.0,
        questions: questions,
      );

      expect(recordId, isPositive);

      final records = await db.watchAllDrillRecords().first;
      expect(records.length, equals(1));
      expect(records.first.id, equals(recordId));
      expect(records.first.correctCount, equals(1));
      expect(records.first.incorrectCount, equals(1));
      expect(records.first.scorePercentage, equals(50.0));

      final allQuestions = await db.watchAllDrillQuestions().first;
      expect(allQuestions.length, equals(2));
      expect(allQuestions.every((q) => q.drillRecordId == recordId), isTrue);

      final wrongQuestions = await db.watchWrongDrillQuestions().first;
      expect(wrongQuestions.length, equals(1));
      expect(wrongQuestions.first.questionText, contains('তিলে তৈল হয়'));
      expect(wrongQuestions.first.isCorrect, isFalse);
      expect(wrongQuestions.first.isMastered, isFalse);
    });

    test('Marking question as mastered removes it from active mistake bank and updates stats', () async {
      final questions = [
        DrillQuestionsCompanion.insert(
          subject: 'English Literature',
          topic: 'Shakespeare',
          questionText: 'Who wrote "The Tempest"?',
          optionsJson: jsonEncode([
            'Christopher Marlowe',
            'William Shakespeare',
            'John Milton',
            'Ben Jonson',
          ]),
          correctIndex: 1,
          selectedIndex: 0, // Wrong answer chosen
          isCorrect: false,
          explanation: const Value(
            'William Shakespeare wrote The Tempest around 1610.',
          ),
        ),
      ];

      await db.recordFullDrillSession(
        subject: 'English Literature',
        topic: 'Shakespeare',
        totalQuestions: 1,
        correctCount: 0,
        incorrectCount: 1,
        scorePercentage: 0.0,
        questions: questions,
      );

      var wrong = await db.watchWrongDrillQuestions().first;
      expect(wrong.length, equals(1));
      final qId = wrong.first.id;

      var stats = await db.getDrillStats();
      expect(stats['total_drills'], equals(1));
      expect(stats['total_answered'], equals(1));
      expect(stats['total_correct'], equals(0));
      expect(stats['total_wrong'], equals(1));
      expect(stats['active_wrong_count'], equals(1));
      expect(stats['accuracy_percentage'], equals(0.0));

      // Mark as mastered
      final success = await db.markQuestionMastered(qId, true);
      expect(success, isTrue);

      // Now active wrong questions in mistake bank should be 0
      wrong = await db.watchWrongDrillQuestions().first;
      expect(wrong.length, equals(0));

      // Stats check: active_wrong_count should be 0
      stats = await db.getDrillStats();
      expect(stats['active_wrong_count'], equals(0));
      expect(stats['total_wrong'], equals(1)); // Historical wrong is kept
    });

    testWidgets(
      'QuizDrillModal shows Detailed Review and Copy button after completion',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        const testQuestions = [
          QuizQuestion(
            questionText: '১. বাংলাদেশের জাতীয় ফুল কোনটি?',
            options: ['ক. গোলাপ', 'খ. শাপলা', 'গ. পদ্ম', 'ঘ. বেলি'],
            correctIndex: 1,
            explanation: 'সাদা শাপলা বাংলাদেশের জাতীয় ফুল।',
            subject: 'বাংলাদেশ বিষয়াবলী',
          ),
        ];

        await tester.pumpWidget(
          ProviderScope(
            overrides: [appDatabaseProvider.overrideWithValue(db)],
            child: const MaterialApp(
              home: Scaffold(
                body: QuizDrillModal(
                  subject: 'বাংলাদেশ বিষয়াবলী',
                  topic: 'জাতীয় প্রতীক',
                  customQuestions: testQuestions,
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Check quiz question is displayed
        expect(find.text('১. বাংলাদেশের জাতীয় ফুল কোনটি?'), findsOneWidget);

        // Select an option ('খ. শাপলা')
        await tester.tap(find.text('খ. শাপলা'));
        await tester.pump();

        // Tap 'See Results & Summary'
        expect(find.text('See Results & Summary'), findsOneWidget);
        await tester.ensureVisible(find.text('See Results & Summary'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('See Results & Summary'));
        await tester.pumpAndSettle();

        // In results state:
        expect(find.text('দারুণ প্রস্তুতি!'), findsOneWidget);
        expect(
          find.text('📋 প্রশ্নভিত্তিক পর্যালোচনা (Detailed Review)'),
          findsOneWidget,
        );
        expect(find.text('কপি করুন'), findsOneWidget);

        // Tap 'কপি করুন'
        await tester.tap(find.text('কপি করুন'));
        await tester.pump();

        // Verify SnackBar appears
        expect(
          find.text(
            'সম্পূর্ণ কুইজ ও উত্তরপত্র ক্লিপবোর্ডে কপি হয়েছে! অন্য AI-তে পেস্ট করতে পারেন।',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'QuizDrillModal supports Real Exam mode with BCS negative marking',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final testQuestions = [
          const QuizQuestion(
            questionText: '১. বাংলাদেশের জাতীয় ফুল কোনটি?',
            options: ['ক. গোলাপ', 'খ. শাপলা', 'গ. জবা', 'ঘ. বেলি'],
            correctIndex: 1, // 'খ. শাপলা'
            explanation: 'বাংলাদেশের জাতীয় ফুল হলো সাদা শাপলা।',
          ),
          const QuizQuestion(
            questionText: '২. বাংলাদেশের জাতীয় পাখি কোনটি?',
            options: ['ক. দোয়েল', 'খ. ময়না', 'গ. কোকিল', 'ঘ. টিয়া'],
            correctIndex: 0, // 'ক. দোয়েল'
            explanation: 'বাংলাদেশের জাতীয় পাখি হলো দোয়েল।',
          ),
        ];

        await tester.pumpWidget(
          ProviderScope(
            overrides: [appDatabaseProvider.overrideWithValue(db)],
            child: MaterialApp(
              home: Scaffold(
                body: QuizDrillModal(
                  subject: 'বাংলাদেশ বিষয়াবলী',
                  topic: 'জাতীয় প্রতীক',
                  customQuestions: testQuestions,
                  initialMode: QuizMode.realExam,
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Verify Real Exam UI is active
        expect(find.text('রিয়েল এক্সাম (-০.৫০)'), findsOneWidget);
        expect(find.byIcon(Icons.timer_outlined), findsOneWidget);

        // Select question 1 correctly ('খ. শাপলা')
        await tester.tap(find.text('খ. শাপলা'));
        await tester.pumpAndSettle();

        // In Real Exam mode, explanation is NOT shown immediately
        expect(find.text('বাংলাদেশের জাতীয় ফুল হলো সাদা শাপলা।'), findsNothing);

        // Advance to question 2 using 'পরবর্তী'
        expect(find.text('পরবর্তী'), findsOneWidget);
        await tester.ensureVisible(find.text('পরবর্তী'));
        await tester.tap(find.text('পরবর্তী'));
        await tester.pumpAndSettle();

        expect(find.text('২. বাংলাদেশের জাতীয় পাখি কোনটি?'), findsOneWidget);

        // Select question 2 incorrectly ('খ. ময়না' instead of 'ক. দোয়েল')
        await tester.tap(find.text('খ. ময়না'));
        await tester.pumpAndSettle();

        // Submit the exam
        expect(find.text('সাবমিট করুন'), findsOneWidget);
        await tester.ensureVisible(find.text('সাবমিট করুন'));
        await tester.tap(find.text('সাবমিট করুন'));
        await tester.pumpAndSettle();

        // 1 correct (+1.00), 1 wrong (-0.50) => Net score = 0.50 / 2
        expect(find.text('0.50 / 2'), findsOneWidget);
        expect(find.text('অর্জিত নেট স্কোর (25%)'), findsOneWidget);
        expect(find.text('📋 প্রশ্নভিত্তিক পর্যালোচনা (Detailed Review)'), findsOneWidget);
        expect(find.text('AI ফিক্স / 🎙️ ভয়েস'), findsOneWidget);
      },
    );
  });
}
