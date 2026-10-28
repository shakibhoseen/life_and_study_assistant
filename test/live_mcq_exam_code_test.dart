import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/services/ai/entity_ref.dart';
import 'package:life_and_study_assistant/features/live_mcq/presentation/providers/exam_schedule_provider.dart';
import 'package:life_and_study_assistant/features/live_mcq/presentation/screens/live_mcq_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);

  final sampleExams = [
    ExamSchedule(
      id: 25,
      examDate: todayStart.add(const Duration(days: 1)),
      examTime: '10:00 PM',
      subject: 'Bangladesh Affairs',
      title: '৪৭তম বিসিএস স্পেশাল মডেল টেস্ট ০১',
      topicsCovered: 'বাংলাদেশের সংবিধান ও মুক্তিযুদ্ধ',
      examType: 'Model Test',
      trackName: '47th BCS',
      resourceSummary: 'সংবিধানের ১ম ও ২য় ভাগ',
      rawReference: null,
      completedStatus: false,
      score: null,
      createdAt: now,
    ),
    ExamSchedule(
      id: 26,
      examDate: todayStart.add(const Duration(days: 2)),
      examTime: '09:00 PM',
      subject: 'English',
      title: 'English Literature Mastery',
      topicsCovered: 'Shakespearean Plays',
      examType: 'Subject Test',
      trackName: '47th BCS',
      resourceSummary: null,
      rawReference: null,
      completedStatus: false,
      score: null,
      createdAt: now,
    ),
  ];

  Widget createLiveMcqScreen({List<ExamSchedule>? exams}) {
    final list = exams ?? sampleExams;
    return ProviderScope(
      overrides: [
        distinctTracksStreamProvider.overrideWith(
          (ref) => Stream.value(['47th BCS']),
        ),
        filteredExamsStreamProvider.overrideWith((ref) => Stream.value(list)),
      ],
      child: const MaterialApp(home: LiveMcqScreen()),
    );
  }

  group('LiveMcqScreen Exam Code UI Tests', () {
    testWidgets('displays E-{exam.id} on each exam card near title', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(createLiveMcqScreen());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // EntityRef tag verification
      expect(EntityRef(EntityKind.exam, 25).tag, 'E-25');
      expect(EntityRef(EntityKind.exam, 26).tag, 'E-26');

      // Check tags are displayed in UI
      expect(find.text('E-25'), findsOneWidget);
      expect(find.text('E-26'), findsOneWidget);
      expect(find.text('৪৭তম বিসিএস স্পেশাল মডেল টেস্ট ০১'), findsOneWidget);
      expect(find.text('English Literature Mastery'), findsOneWidget);
    });

    testWidgets(
      'tapping E-{id} tag copies code to clipboard and shows SnackBar',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        String copiedText = '';
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (MethodCall methodCall) async {
            if (methodCall.method == 'Clipboard.setData') {
              copiedText = (methodCall.arguments as Map)['text'] as String;
              return null;
            }
            if (methodCall.method == 'Clipboard.getData') {
              return <String, dynamic>{'text': copiedText};
            }
            return null;
          },
        );

        await tester.pumpWidget(createLiveMcqScreen());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Tap on the E-25 tag
        final tagFinder = find.text('E-25');
        expect(tagFinder, findsOneWidget);
        await tester.tap(tagFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Verify copied content
        expect(copiedText, 'E-25');

        // Verify Bengali SnackBar message
        expect(
          find.text('E-25 কপি হয়েছে — AI মেন্টরে পেস্ট করে বলুন কী সমস্যা'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'three-dot popup menu contains copy ID action and copies on select',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        String copiedText = '';
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (MethodCall methodCall) async {
            if (methodCall.method == 'Clipboard.setData') {
              copiedText = (methodCall.arguments as Map)['text'] as String;
              return null;
            }
            if (methodCall.method == 'Clipboard.getData') {
              return <String, dynamic>{'text': copiedText};
            }
            return null;
          },
        );

        await tester.pumpWidget(
          createLiveMcqScreen(exams: [sampleExams.first]),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Find the popup menu button on the card
        final menuButton = find.byIcon(Icons.more_vert);
        expect(menuButton, findsOneWidget);
        await tester.tap(menuButton);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Check popup menu item exists
        final copyMenuItem = find.text('আইডি কপি (E-25)');
        expect(copyMenuItem, findsOneWidget);

        // Verify other standard menu items are preserved
        expect(find.text('Add to Calendar'), findsOneWidget);
        expect(find.text('Mark as Completed'), findsOneWidget);
        expect(find.text('Record Score'), findsOneWidget);
        expect(find.text('Delete Exam'), findsOneWidget);

        // Select copy ID menu item
        await tester.tap(copyMenuItem);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Verify copied content
        expect(copiedText, 'E-25');

        // Verify Bengali SnackBar
        expect(
          find.text('E-25 কপি হয়েছে — AI মেন্টরে পেস্ট করে বলুন কী সমস্যা'),
          findsOneWidget,
        );
      },
    );
  });
}
