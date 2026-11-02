import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/widgets/ai_progress_pipeline_widget.dart';

void main() {
  group('AiProgressPipelineWidget Tests', () {
    testWidgets('renders compact text progress with timer and token badge', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AiProgressPipelineWidget(
              type: AiTaskType.text,
              isCompact: true,
              liveTokens: 420,
            ),
          ),
        ),
      );

      // Verify initial text step is displayed
      expect(find.text('কনটেক্সট ও রুটিন যাচাই করা হচ্ছে...'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.timer_outlined), findsOneWidget);

      // Verify live tokens badge
      expect(find.text('৪২০ টোকেন'), findsOneWidget);

      // Advance time by 3 seconds
      await tester.pump(const Duration(seconds: 3));

      // Step should have transitioned to thinking / structuring
      expect(find.text('উত্তরের রূপরেখা চিন্তা করছে...'), findsOneWidget);

      // Advance time by another 3 seconds (6s total)
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('রেসপন্স প্রস্তুত ও গুছিয়ে লিখছে...'), findsOneWidget);
    });

    testWidgets(
      'renders modal image OCR progress with steps and cancel button',
      (tester) async {
        bool cancelled = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AiProgressPipelineWidget(
                type: AiTaskType.image,
                isCompact: false,
                onCancel: () {
                  cancelled = true;
                },
              ),
            ),
          ),
        );

        // Initial image step
        expect(find.text('ছবি প্রস্তুত হচ্ছে...'), findsWidgets);
        expect(find.text('বাতিল করুন'), findsOneWidget);

        // Tap cancel
        await tester.tap(find.text('বাতিল করুন'));
        expect(cancelled, isTrue);

        // Reading the page starts at 4s, measured against a real call.
        await tester.pump(const Duration(seconds: 5));
        expect(find.text('পাতাটা পড়া হচ্ছে...'), findsWidgets);
      },
    );

    testWidgets('renders audio progress pipeline for voice parsing', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AiProgressPipelineWidget(
              type: AiTaskType.audio,
              isCompact: true,
            ),
          ),
        ),
      );

      // Initial audio step
      expect(find.text('অডিও প্রসেস ও নয়েজ ফিল্টার হচ্ছে...'), findsOneWidget);

      // Advance time by 3 seconds
      await tester.pump(const Duration(seconds: 3));
      expect(
        find.text('ভয়েস থেকে প্রশ্ন ও ভুল শনাক্ত হচ্ছে...'),
        findsOneWidget,
      );
    });

    testWidgets('renders drill generation progress pipeline', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AiProgressPipelineWidget(
              type: AiTaskType.drill,
              isCompact: false,
            ),
          ),
        ),
      );

      expect(
        find.text('টপিক ও দুর্বলতার ইতিহাস পর্যালোচনা হচ্ছে...'),
        findsWidgets,
      );

      await tester.pump(const Duration(seconds: 3));
      expect(find.text('হাই-ইয়েল্ড MCQ প্রশ্ন তৈরি করছে...'), findsWidgets);
    });

    testWidgets(
      'displays slow network warning after 15 seconds in modal mode',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: AiProgressPipelineWidget(
                type: AiTaskType.general,
                isCompact: false,
              ),
            ),
          ),
        );

        // Before 15 seconds, no warning
        expect(find.byIcon(Icons.wifi_tethering_error_rounded), findsNothing);

        // Fast-forward past 15 seconds
        await tester.pump(const Duration(seconds: 16));

        // Warning should now be visible
        expect(find.byIcon(Icons.wifi_tethering_error_rounded), findsOneWidget);
        expect(
          find.text(
            'ইন্টারনেট কিছুটা ধীরগতির হতে পারে, দয়া করে অপেক্ষা করুন...',
          ),
          findsOneWidget,
        );
      },
    );
  });

  testWidgets('a long wait says the model is thinking, not nearly done', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiProgressPipelineWidget(
            type: AiTaskType.image,
            isCompact: false,
          ),
        ),
      ),
    );

    // A measured page read takes about three minutes, nearly all of it
    // before the first word. Half a minute in, the screen must not be
    // claiming the result is ready.
    await tester.pump(const Duration(seconds: 30));

    expect(find.textContaining('ভেবে দেখছে'), findsWidgets);
    expect(find.textContaining('সম্পূর্ণ প্রস্তুত'), findsNothing);
  });
}
