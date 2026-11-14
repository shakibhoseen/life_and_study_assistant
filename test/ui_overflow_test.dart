import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/theme/app_theme.dart';
import 'package:life_and_study_assistant/core/theme/ui_style_provider.dart';
import 'package:life_and_study_assistant/core/widgets/premium_glass_card.dart';
import 'package:life_and_study_assistant/core/widgets/premium_ui_kit.dart';
import 'package:life_and_study_assistant/features/dashboard/presentation/widgets/exam_accountability_card.dart';
import 'package:life_and_study_assistant/features/dashboard/presentation/widgets/weekly_study_goal_card.dart';
import 'package:life_and_study_assistant/features/live_mcq/presentation/providers/exam_schedule_provider.dart';
import 'package:life_and_study_assistant/features/live_mcq/presentation/widgets/exam_score_analytics_card.dart';
import 'package:life_and_study_assistant/features/live_mcq/presentation/widgets/exam_topic_checklist_widget.dart';

/// The narrowest phone the app realistically has to survive, and the text
/// scale a user with large-font accessibility settings gets.
const Size _narrowPhone = Size(320, 640);
const double _largeTextScale = 1.5;

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
    examDate: DateTime(now.year, now.month, now.day).add(
      Duration(days: dayOffset),
    ),
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

Widget _host(Widget child, {required AppUiStyle style, required ThemeData theme}) {
  return ProviderScope(
    overrides: [
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
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

class _FixedUiStyle extends AppUiStyleNotifier {
  _FixedUiStyle(this._style);
  final AppUiStyle _style;

  @override
  AppUiStyle build() => _style;
}

/// Pumps [child] and fails if Flutter reported a layout overflow.
Future<void> _expectNoOverflow(
  WidgetTester tester,
  Widget child, {
  required AppUiStyle style,
  required ThemeData theme,
}) async {
  tester.view.physicalSize = _narrowPhone;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_host(child, style: style, theme: theme));
  await tester.pump(const Duration(milliseconds: 400));

  final exception = tester.takeException();
  if (exception != null) {
    fail('Layout failed at ${_narrowPhone.width}px / '
        '${_largeTextScale}x text (${style.name}): $exception');
  }
}

void main() {
  final themes = <String, ThemeData>{
    'light': AppTheme.lightTheme,
    'cuteVelvetDark': AppTheme.cuteVelvetDarkTheme,
    'iceBlueDark': AppTheme.iceBlueDarkTheme,
  };

  final widgets = <String, Widget Function()>{
    'ExamAccountabilityCard': () => const ExamAccountabilityCard(),
    'WeeklyStudyGoalCard': () => const WeeklyStudyGoalCard(),
    'ExamScoreAnalyticsCard': () => const ExamScoreAnalyticsCard(),
    'ExamTopicChecklistWidget': () =>
        ExamTopicChecklistWidget(exam: _exam()),
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
    'PremiumGlassCard': () => const PremiumGlassCard(
      child: Text('দীর্ঘ একটি বাংলা বাক্য যা কার্ডের ভেতরে ভাঁজ হওয়া উচিত।'),
    ),
  };

  for (final styleEntry in AppUiStyle.values) {
    for (final themeEntry in themes.entries) {
      for (final widgetEntry in widgets.entries) {
        testWidgets(
          '${widgetEntry.key} lays out on a 320px screen at 1.5x text '
          '(${themeEntry.key}, ${styleEntry.name})',
          (tester) async {
            await _expectNoOverflow(
              tester,
              widgetEntry.value(),
              style: styleEntry,
              theme: themeEntry.value,
            );
          },
        );
      }
    }
  }
}
