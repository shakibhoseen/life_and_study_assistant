import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/database/tables/daily_energy_logs_table.dart';
import 'package:life_and_study_assistant/core/database/tables/weak_topics_table.dart';
import 'package:life_and_study_assistant/core/services/ai/models/quiz_question.dart';
import 'package:life_and_study_assistant/core/services/ai/quiz_generator_service.dart';
import 'package:life_and_study_assistant/core/services/background/wifi_monitor_service.dart';
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
  });
}
