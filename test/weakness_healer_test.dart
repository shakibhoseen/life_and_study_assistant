import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/database/database_provider.dart';
import 'package:life_and_study_assistant/core/database/tables/weak_topics_table.dart';
import 'package:life_and_study_assistant/features/quiz/presentation/providers/drill_history_provider.dart';
import 'package:life_and_study_assistant/features/settings/presentation/providers/settings_provider.dart';
import 'package:life_and_study_assistant/features/topics/presentation/providers/topics_provider.dart';
import 'package:life_and_study_assistant/features/topics/presentation/screens/topics_screen.dart';
import 'package:life_and_study_assistant/features/weakness_healer/domain/models/weakness_healing_model.dart';
import 'package:life_and_study_assistant/features/weakness_healer/presentation/widgets/weakness_healing_card.dart';
import 'package:life_and_study_assistant/features/weakness_healer/presentation/widgets/weakness_healing_drill_modal.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('Weakness Healing Engine Calculation Tests', () {
    test(
      'calculateWeaknessHealth calculates score and selects weakest topic',
      () {
        final topics = [
          WeakTopic(
            id: 1,
            subject: 'Bangla Grammar',
            topicName: 'কারক ও বিভক্তি',
            proficiencyLevel: ProficiencyLevel.weak,
            lastReviewedAt: DateTime.now().subtract(const Duration(days: 4)),
            notes: null,
            createdAt: DateTime.now(),
          ),
          WeakTopic(
            id: 2,
            subject: 'General Science',
            topicName: 'আলো ও লেন্স',
            proficiencyLevel: ProficiencyLevel.moderate,
            lastReviewedAt: DateTime.now().subtract(const Duration(days: 1)),
            notes: null,
            createdAt: DateTime.now(),
          ),
          WeakTopic(
            id: 3,
            subject: 'Mathematics',
            topicName: 'শতকরা ও লাভ-ক্ষতি',
            proficiencyLevel: ProficiencyLevel.strong,
            lastReviewedAt: DateTime.now(),
            notes: null,
            createdAt: DateTime.now(),
          ),
        ];

        final mistakes = [
          DrillQuestion(
            id: 1,
            drillRecordId: 1,
            subject: 'Bangla Grammar',
            topic: 'কারক ও বিভক্তি',
            questionText: 'তিলে তৈল হয় কোন কারক?',
            optionsJson: jsonEncode(['অপাদান', 'অধিকরণ']),
            correctIndex: 0,
            selectedIndex: 1,
            isCorrect: false,
            explanation: '',
            isMastered: false,
            attemptedAt: DateTime.now(),
          ),
        ];

        final summary = calculateWeaknessHealth(
          topics: topics,
          unmasteredMistakes: mistakes,
        );

        // 1 strong (1.0) + 1 moderate (0.5) + 1 weak (0.0) = 1.5 / 3.0 = 50.0%
        expect(summary.totalTopics, equals(3));
        expect(summary.healedCount, equals(1));
        expect(summary.moderateCount, equals(1));
        expect(summary.weakCount, equals(1));
        expect(summary.healthPercentage, equals(50.0));
        expect(summary.hasWeaknessToHeal, isTrue);

        // Primary focus must be the weak topic
        expect(summary.primaryFocusTopic?.topicName, equals('কারক ও বিভক্তি'));
        expect(summary.matchingMistakesCount, equals(1));
      },
    );

    test('calculateWeaknessHealth handles empty topics cleanly', () {
      final summary = calculateWeaknessHealth(
        topics: [],
        unmasteredMistakes: [],
      );
      expect(summary.totalTopics, equals(0));
      expect(summary.healthPercentage, equals(100.0));
      expect(summary.hasWeaknessToHeal, isFalse);
      expect(summary.primaryFocusTopic, isNull);
    });
  });

  group('Weakness Healing Card & Settings Toggle Widget Tests', () {
    testWidgets('WeaknessHealingCard renders when enabled in settings', (
      tester,
    ) async {
      final sampleTopic = WeakTopic(
        id: 1,
        subject: 'Bangla Grammar',
        topicName: 'সমাস ও প্রত্যয়',
        proficiencyLevel: ProficiencyLevel.weak,
        lastReviewedAt: null,
        notes: 'LiveMCQ test error',
        createdAt: DateTime.now(),
      );

      final enabledSettings = SettingsState(
        officeWifiSsid: 'Zavisoft',
        dinnerHour: 16,
        dinnerMinute: 0,
        geminiApiKey: '',
        lastCheckInStatus: 'Done',
        lastMealResponse: 'Yes',
        isWifiMonitoringActive: true,
        isWeaknessHealingEnabled: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            settingsNotifierProvider.overrideWith(
              () => _MockSettingsNotifier(enabledSettings),
            ),
            weakTopicsStreamProvider.overrideWith(
              (ref) => Stream.value([sampleTopic]),
            ),
            wrongQuestionsStreamProvider.overrideWith(
              (ref) => Stream.value([]),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: WeaknessHealingCard())),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('অটো-উইকনেস হিলিং'), findsOneWidget);
      expect(find.text('🎯 আজকের ফোকাস: সমাস ও প্রত্যয়'), findsOneWidget);
      expect(find.text('৩ মিনিটের হিলিং ড্রিল 🩺'), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });

    testWidgets(
      'WeaknessHealingCard hides completely when disabled in settings',
      (tester) async {
        final sampleTopic = WeakTopic(
          id: 1,
          subject: 'Bangla Grammar',
          topicName: 'সমাস ও প্রত্যয়',
          proficiencyLevel: ProficiencyLevel.weak,
          lastReviewedAt: null,
          notes: 'LiveMCQ test error',
          createdAt: DateTime.now(),
        );

        final disabledSettings = SettingsState(
          officeWifiSsid: 'Zavisoft',
          dinnerHour: 16,
          dinnerMinute: 0,
          geminiApiKey: '',
          lastCheckInStatus: 'Done',
          lastMealResponse: 'Yes',
          isWifiMonitoringActive: true,
          isWeaknessHealingEnabled: false, // Disabled
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              settingsNotifierProvider.overrideWith(
                () => _MockSettingsNotifier(disabledSettings),
              ),
              weakTopicsStreamProvider.overrideWith(
                (ref) => Stream.value([sampleTopic]),
              ),
              wrongQuestionsStreamProvider.overrideWith(
                (ref) => Stream.value([]),
              ),
            ],
            child: const MaterialApp(
              home: Scaffold(body: WeaknessHealingCard()),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Should be completely hidden
        expect(find.text('অটো-উইকনেস হিলিং'), findsNothing);
        expect(find.text('৩ মিনিটের হিলিং ড্রিল 🩺'), findsNothing);
      },
    );

    testWidgets(
      'TopicsScreen renders weak topic card and compact 3-dot without overflow on narrow width',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final longSubjectTopic = WeakTopic(
          id: 99,
          subject: 'বাংলাদেশ বিষয়াবলী ও সাম্প্রতিক ঘটনাবলী',
          topicName: 'সংবিধানের মৌলিক অধিকার ও অনুচ্ছেদ',
          proficiencyLevel: ProficiencyLevel.weak,
          lastReviewedAt: null,
          notes: 'LiveMCQ test error notes',
          createdAt: DateTime.now(),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              weakTopicsStreamProvider.overrideWith(
                (ref) => Stream.value([longSubjectTopic]),
              ),
              wrongQuestionsStreamProvider.overrideWith(
                (ref) => Stream.value([]),
              ),
            ],
            child: const MaterialApp(home: TopicsScreen()),
          ),
        );

        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 1));

        expect(find.text('সংবিধানের মৌলিক অধিকার ও অনুচ্ছেদ'), findsOneWidget);
        expect(find.text('Weak'), findsNWidgets(2)); // Filter chip + Card badge
        expect(find.byIcon(Icons.more_vert), findsWidgets);

        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'WeaknessHealingDrillModal shows 3-min timer and allows answering',
      (tester) async {
        final sampleTopic = WeakTopic(
          id: 1,
          subject: 'Bangla Grammar',
          topicName: 'সমাস',
          proficiencyLevel: ProficiencyLevel.weak,
          lastReviewedAt: null,
          notes: null,
          createdAt: DateTime.now(),
        );

        final mistake1 = DrillQuestion(
          id: 42,
          drillRecordId: 1,
          subject: 'Bangla Grammar',
          topic: 'সমাস',
          questionText: 'উপপদ তৎপুরুষ সমাস কোনটি?',
          optionsJson: jsonEncode(['পকেটমার', 'রাজপথ', 'দশ আনন', 'চাঁদমুখ']),
          correctIndex: 0,
          selectedIndex: 1,
          isCorrect: false,
          explanation:
              'যা উপপদের সাথে কৃদন্ত পদের সমাস হয় তাকে উপপদ তৎপুরুষ বলে।',
          isMastered: false,
          attemptedAt: DateTime.now(),
        );

        final mistake2 = DrillQuestion(
          id: 43,
          drillRecordId: 1,
          subject: 'Bangla Grammar',
          topic: 'সমাস',
          questionText: 'চাঁদমুখ কোন সমাস?',
          optionsJson: jsonEncode(['উপমিত', 'উপমান']),
          correctIndex: 0,
          selectedIndex: 1,
          isCorrect: false,
          explanation: 'উপমিত কর্মধারয়',
          isMastered: false,
          attemptedAt: DateTime.now(),
        );

        final mistake3 = DrillQuestion(
          id: 44,
          drillRecordId: 1,
          subject: 'Bangla Grammar',
          topic: 'সমাস',
          questionText: 'রাজপথ কোন সমাস?',
          optionsJson: jsonEncode(['তৎপুরুষ', 'বহুব্রীহি']),
          correctIndex: 0,
          selectedIndex: 1,
          isCorrect: false,
          explanation: 'ষষ্ঠী তৎপুরুষ',
          isMastered: false,
          attemptedAt: DateTime.now(),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [appDatabaseProvider.overrideWithValue(db)],
            child: MaterialApp(
              home: WeaknessHealingDrillModal(
                topic: sampleTopic,
                relatedMistakes: [mistake1, mistake2, mistake3],
              ),
            ),
          ),
        );

        // Pump frames to complete async loading without pumpAndSettle hanging on periodic timer
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('৩ মিনিটের হিলিং ড্রিল'), findsOneWidget);
        expect(find.text('উপপদ তৎপুরুষ সমাস কোনটি?'), findsOneWidget);
        expect(find.text('পূর্বের ভুল প্রশ্ন'), findsOneWidget);

        // Tap correct option A (পকেটমার)
        final optionA = find.text('পকেটমার');
        expect(optionA, findsOneWidget);
        await tester.tap(optionA);
        await tester.pump(const Duration(milliseconds: 100));

        // Explanation should be visible
        expect(find.text('ব্যাখ্যা ও মনে রাখার রুল:'), findsOneWidget);
        expect(
          find.text(
            'যা উপপদের সাথে কৃদন্ত পদের সমাস হয় তাকে উপপদ তৎপুরুষ বলে।',
          ),
          findsOneWidget,
        );

        // Tap next button to advance to question 2
        final nextBtn = find.text('পরবর্তী প্রশ্ন →');
        expect(nextBtn, findsOneWidget);
        await tester.tap(nextBtn);
        await tester.pump(const Duration(milliseconds: 100));

        // Question 2 should now be visible
        expect(find.text('চাঁদমুখ কোন সমাস?'), findsOneWidget);
      },
    );
  });
}

class _MockSettingsNotifier extends SettingsNotifier {
  final SettingsState _initial;
  _MockSettingsNotifier(this._initial);

  @override
  Future<SettingsState> build() async => _initial;
}
