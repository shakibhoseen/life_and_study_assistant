import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/features/dashboard/presentation/widgets/multi_track_exam_countdown_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.now();
  final todayExamDate = DateTime(now.year, now.month, now.day);
  final tomorrowExamDate = todayExamDate.add(const Duration(days: 1));

  final testExams = [
    ExamSchedule(
      id: 1,
      examDate: todayExamDate,
      examTime: '10:00 PM',
      subject: 'Bangladesh Affairs',
      title: '৪৭তম বিসিএস স্পেশাল মডেল টেস্ট ০১',
      topicsCovered: 'বাংলাদেশের নদ-নদী, প্রাচীন বাংলার ইতিহাস',
      examType: 'Model Test',
      trackName: '47th BCS',
      resourceSummary: null,
      rawReference: null,
      completedStatus: false,
      score: null,
      createdAt: now,
    ),
    ExamSchedule(
      id: 2,
      examDate: tomorrowExamDate,
      examTime: '09:00 PM',
      subject: 'Business & Management',
      title: 'পেট্রোবাংলা সহ-ব্যবস্থাপক পরীক্ষা ০২',
      topicsCovered: 'হিসাববিজ্ঞান ও সাধারণ জ্ঞান',
      examType: 'Daily',
      trackName: 'Petrobangla',
      resourceSummary: null,
      rawReference: null,
      completedStatus: false,
      score: null,
      createdAt: now,
    ),
    ExamSchedule(
      id: 3,
      examDate: todayExamDate.add(const Duration(days: 3)),
      examTime: '08:00 PM',
      subject: 'Primary Special',
      title: 'প্রাথমিক সহকারী শিক্ষক জব সল্যুশন',
      topicsCovered: 'বাংলা ব্যাকরণ ও গণিত',
      examType: 'Weekly',
      trackName: 'Primary Teacher',
      resourceSummary: null,
      rawReference: null,
      completedStatus: false,
      score: null,
      createdAt: now,
    ),
  ];

  group('MultiTrackExamCountdownCard Widget Tests', () {
    testWidgets('Renders Multi-Track header, live countdown, and track chips', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: MultiTrackExamCountdownCard(exams: testExams),
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      // 1. Verify Header exists
      expect(find.text('Multi-Track Exam Timeline'), findsOneWidget);

      // 2. Verify Track Chips exist
      expect(find.text('All Tracks (3)'), findsOneWidget);
      expect(find.text('47th BCS'), findsWidgets);
      expect(find.text('Petrobangla'), findsOneWidget);
      expect(find.text('Primary Teacher'), findsOneWidget);

      // 3. Verify Hero Exam Title & Topics
      expect(find.text('৪৭তম বিসিএস স্পেশাল মডেল টেস্ট ০১'), findsOneWidget);
      expect(
        find.text('বাংলাদেশের নদ-নদী, প্রাচীন বাংলার ইতিহাস'),
        findsOneWidget,
      );

      // 4. Verify Live Countdown Blocks
      expect(find.text('HOURS'), findsOneWidget);
      expect(find.text('MINS'), findsOneWidget);
      expect(find.text('SECS'), findsOneWidget);

      // 5. Verify Action Buttons exist
      expect(find.text('Drill Topic'), findsOneWidget);
      expect(find.text('AI Summary'), findsOneWidget);
    });

    testWidgets(
      'Tapping track filter chip updates selected track and displays hero exam for that track',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: MultiTrackExamCountdownCard(exams: testExams),
                ),
              ),
            ),
          ),
        );

        await tester.pump();

        // Tap on 'Petrobangla' track chip
        final petroChip = find.text('Petrobangla');
        expect(petroChip, findsOneWidget);
        await tester.tap(petroChip);
        await tester.pump();

        // Verify the hero exam switches to Petrobangla
        expect(
          find.text('পেট্রোবাংলা সহ-ব্যবস্থাপক পরীক্ষা ০২'),
          findsOneWidget,
        );
        expect(find.text('হিসাববিজ্ঞান ও সাধারণ জ্ঞান'), findsOneWidget);
      },
    );
  });
}
