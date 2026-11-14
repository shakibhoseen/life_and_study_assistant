import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/database/database_provider.dart';
import 'package:life_and_study_assistant/core/database/tables/weak_topics_table.dart';
import 'package:life_and_study_assistant/core/theme/app_theme.dart';
import 'package:life_and_study_assistant/core/theme/ui_style_provider.dart';
import 'package:life_and_study_assistant/core/widgets/premium_glass_card.dart';
import 'package:life_and_study_assistant/core/widgets/premium_ui_kit.dart';
import 'package:life_and_study_assistant/features/dashboard/domain/next_study_action.dart';
import 'package:life_and_study_assistant/features/dashboard/presentation/widgets/exam_accountability_card.dart';
import 'package:life_and_study_assistant/features/dashboard/presentation/widgets/multi_track_exam_countdown_card.dart';
import 'package:life_and_study_assistant/features/dashboard/presentation/widgets/next_action_card.dart';
import 'package:life_and_study_assistant/features/dashboard/presentation/widgets/weekly_study_goal_card.dart';
import 'package:life_and_study_assistant/features/live_mcq/presentation/providers/exam_schedule_provider.dart';
import 'package:life_and_study_assistant/features/live_mcq/presentation/widgets/exam_score_analytics_card.dart';
import 'package:life_and_study_assistant/features/live_mcq/presentation/widgets/exam_topic_checklist_widget.dart';
import 'package:life_and_study_assistant/features/settings/presentation/widgets/study_data_cleanup_card.dart';
import 'package:life_and_study_assistant/features/settings/presentation/widgets/theme_selector_card.dart';
import 'package:life_and_study_assistant/features/settings/presentation/widgets/ui_style_selector_card.dart';
import 'package:life_and_study_assistant/features/topics/presentation/widgets/mistake_bank_and_hub_tab.dart';
import 'package:life_and_study_assistant/features/topics/presentation/widgets/topic_card.dart';
import 'package:life_and_study_assistant/features/weakness_healer/presentation/widgets/weakness_healing_card.dart';

/// The narrowest phone the app realistically has to survive, and the text
/// scale a user with large-font accessibility settings gets.
///
/// Both matter here: almost all the copy is Bengali, which sets wider than
/// Latin at the same point size, so a Row that just fits in English is
/// already over the edge in Bengali at 1.5x.
const Size _narrowPhone = Size(320, 640);
const double _largeTextScale = 1.5;

// ---------------------------------------------------------------------------
// Fixtures. Deliberately long, because a short string hides the bug.
// ---------------------------------------------------------------------------

ExamSchedule _exam({
  int id = 1,
  String title = 'সাপ্তাহিক মডেল টেস্ট — বাংলাদেশ বিষয়াবলি ও আন্তর্জাতিক',
  String subject = 'বাংলাদেশ ও আন্তর্জাতিক বিষয়াবলি',
  bool completed = false,
  double? score,
  int dayOffset = 2,
}) {
  final now = DateTime.now();
  return ExamSchedule(
    id: id,
    examDate: DateTime(
      now.year,
      now.month,
      now.day,
    ).add(Duration(days: dayOffset)),
    examTime: '09:00 PM - 10:30 PM',
    subject: subject,
    title: title,
    topicsCovered:
        'মুক্তিযুদ্ধের ইতিহাস, সংবিধান ও সংশোধনী, আন্তর্জাতিক সংস্থা, '
        'ভূগোল ও পরিবেশ, বিজ্ঞান ও প্রযুক্তি',
    examType: 'Full Model Test',
    trackName: 'BCS Preliminary Special Batch 2026',
    resourceSummary: 'প্রফেসরস বিসিএস প্রিলি ডাইজেস্ট — অধ্যায় ৩ থেকে ৭',
    rawReference: null,
    completedStatus: completed,
    score: score,
    createdAt: now,
  );
}

DrillQuestion _drillQuestion({int id = 1, bool isCorrect = false}) {
  return DrillQuestion(
    id: id,
    drillRecordId: null,
    subject: 'বাংলাদেশ ও আন্তর্জাতিক বিষয়াবলি',
    topic: 'মুক্তিযুদ্ধের ইতিহাস ও সাংবিধানিক উন্নয়ন',
    questionText:
        'বাংলাদেশের সংবিধানের কোন সংশোধনীর মাধ্যমে তত্ত্বাবধায়ক সরকার '
        'ব্যবস্থা বাতিল করা হয়েছিল?',
    optionsJson:
        '["দ্বাদশ সংশোধনী","ত্রয়োদশ সংশোধনী","পঞ্চদশ সংশোধনী","ষোড়শ সংশোধনী"]',
    correctIndex: 2,
    selectedIndex: isCorrect ? 2 : 1,
    isCorrect: isCorrect,
    explanation:
        'পঞ্চদশ সংশোধনীর (২০১১) মাধ্যমে তত্ত্বাবধায়ক সরকার ব্যবস্থা বিলুপ্ত '
        'করা হয় এবং রাষ্ট্রীয় মূলনীতি পুনঃস্থাপিত হয়।',
    isMastered: false,
    attemptedAt: DateTime.now().subtract(const Duration(days: 1)),
    originalCorrectIndex: null,
    originalExplanation: null,
    originalQuestionText: null,
    originalOptionsJson: null,
  );
}

WeakTopic _weakTopic() => WeakTopic(
  id: 1,
  subject: 'সাধারণ বিজ্ঞান ও প্রযুক্তি',
  topicName: 'আলো ও আলোকীয় যন্ত্রপাতি (Optics, Refraction & Wave Theory)',
  proficiencyLevel: ProficiencyLevel.weak,
  lastReviewedAt: DateTime.now().subtract(const Duration(days: 4)),
  notes: 'প্রতিসরণ, পূর্ণ অভ্যন্তরীণ প্রতিফলন ও লেন্সের ক্ষমতা',
  createdAt: DateTime.now(),
);

const _nextAction = NextStudyAction(
  kind: StudyActionKind.mistakeDrill,
  title: 'মিস্টেক ব্যাংক থেকে ১২টি ভুল প্রশ্নের রিভিশন ড্রিল',
  why: 'গতকালের লাইভ পরীক্ষায় এই অধ্যায়গুলোতেই সবচেয়ে বেশি ভুল হয়েছে',
  minutes: 15,
  count: 12,
);

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

class _FixedUiStyle extends AppUiStyleNotifier {
  _FixedUiStyle(this._style);
  final AppUiStyle _style;

  @override
  AppUiStyle build() => _style;
}

/// Pumps [child] at phone width with large text and fails if Flutter
/// reported a layout overflow.
Future<void> _expectNoOverflow(
  WidgetTester tester,
  Widget Function() build, {
  required AppUiStyle style,
  required ThemeData theme,
}) async {
  SharedPreferences.setMockInitialValues({});

  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);

  tester.view.physicalSize = _narrowPhone;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        appUiStyleProvider.overrideWith(() => _FixedUiStyle(style)),
        allExamsStreamProvider.overrideWith(
          (ref) => Stream.value([
            _exam(),
            _exam(id: 2, completed: true, score: 142.5, dayOffset: -3),
            _exam(id: 3, dayOffset: 0),
          ]),
        ),
      ],
      child: MaterialApp(
        theme: theme,
        home: MediaQuery(
          data: const MediaQueryData(
            size: _narrowPhone,
            textScaler: TextScaler.linear(_largeTextScale),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: build(),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  // Long enough for streams to deliver and for entrance animations to settle,
  // without pumpAndSettle, which never returns on the cards that animate
  // continuously.
  await tester.pump(const Duration(milliseconds: 600));

  final exception = tester.takeException();
  if (exception != null) {
    fail(
      'Layout failed at ${_narrowPhone.width}px / ${_largeTextScale}x text '
      '(${style.name}): $exception',
    );
  }
}

void main() {
  final themes = <String, ThemeData>{
    'light': AppTheme.lightTheme,
    'cuteVelvetDark': AppTheme.cuteVelvetDarkTheme,
    'iceBlueDark': AppTheme.iceBlueDarkTheme,
  };

  final widgets = <String, Widget Function()>{
    // Dashboard
    'ExamAccountabilityCard': () => const ExamAccountabilityCard(),
    'WeeklyStudyGoalCard': () => const WeeklyStudyGoalCard(),
    'NextActionCard': () =>
        NextActionCard(action: _nextAction, onStart: () {}, streakDays: 12),
    'MultiTrackExamCountdownCard': () => MultiTrackExamCountdownCard(
      exams: [_exam(), _exam(id: 2, dayOffset: 9)],
    ),

    // Live MCQ
    'ExamScoreAnalyticsCard': () => const ExamScoreAnalyticsCard(),
    'ExamTopicChecklistWidget': () => ExamTopicChecklistWidget(exam: _exam()),

    // Topics / mistake bank — the Drill Performance Summary lives in here.
    'MistakeBankAndHubTab': () => MistakeBankAndHubTab(
      wrongQuestions: [
        _drillQuestion(),
        _drillQuestion(id: 2),
        _drillQuestion(id: 3),
      ],
      onStartMistakeBankDrill: (_) {},
    ),
    'MistakeBankAndHubTab (empty)': () => MistakeBankAndHubTab(
      wrongQuestions: const [],
      onStartMistakeBankDrill: (_) {},
    ),
    'TopicCard': () => TopicCard(topic: _weakTopic()),

    // Weakness healer
    'WeaknessHealingCard': () => const WeaknessHealingCard(),

    // Settings
    'ThemeSelectorCard': () => const ThemeSelectorCard(),
    'UiStyleSelectorCard': () => const UiStyleSelectorCard(),
    'StudyDataCleanupCard': () => const StudyDataCleanupCard(),

    // Shared kit
    'PremiumSectionHeader': () => const PremiumSectionHeader(
      icon: Icons.star,
      label: 'আজকের পড়ার লক্ষ্য ও অগ্রগতি রিপোর্ট',
      subtitle: 'গত সাত দিনের গড় স্কোর ও দুর্বল অধ্যায়ের তালিকা',
    ),
    'PremiumStatTile': () => const PremiumStatTile(
      icon: Icons.local_fire_department,
      value: '1,284',
      label: 'মোট অনুশীলন করা প্রশ্ন',
    ),
    'PremiumTag': () => const PremiumTag(
      label: 'সর্বোচ্চ অগ্রাধিকার',
      icon: Icons.priority_high,
    ),
    'PremiumGlassCard': () => const PremiumGlassCard(
      child: Text('দীর্ঘ একটি বাংলা বাক্য যা কার্ডের ভেতরে ভাঁজ হওয়া উচিত।'),
    ),
  };

  for (final style in AppUiStyle.values) {
    for (final themeEntry in themes.entries) {
      for (final widgetEntry in widgets.entries) {
        testWidgets(
          '${widgetEntry.key} lays out on a 320px screen at 1.5x text '
          '(${themeEntry.key}, ${style.name})',
          (tester) async {
            await _expectNoOverflow(
              tester,
              widgetEntry.value,
              style: style,
              theme: themeEntry.value,
            );
          },
        );
      }
    }
  }
}
