import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/widgets/celebration_confetti.dart';
import 'package:life_and_study_assistant/features/analytics/presentation/providers/study_streak_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CelebrationConfetti Widget Tests', () {
    testWidgets('renders child widget correctly when trigger is false', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CelebrationConfetti(
              trigger: false,
              child: Text('Score: 10/10'),
            ),
          ),
        ),
      );

      expect(find.text('Score: 10/10'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is CustomPaint && w.painter is ConfettiPainter),
        findsNothing,
      );
    });

    testWidgets('animates and renders confetti CustomPaint when trigger is true', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CelebrationConfetti(
              trigger: true,
              duration: Duration(milliseconds: 1000),
              child: Text('Exam Passed!'),
            ),
          ),
        ),
      );

      expect(find.text('Exam Passed!'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is CustomPaint && w.painter is ConfettiPainter),
        findsOneWidget,
      );

      // Advance frames
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byWidgetPredicate((w) => w is CustomPaint && w.painter is ConfettiPainter),
        findsOneWidget,
      );

      // Advance past duration
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate((w) => w is CustomPaint && w.painter is ConfettiPainter),
        findsNothing,
      );
    });
  });

  group('StudyStreakProvider Tests', () {
    test('studyStreakProvider is defined and has expected type', () {
      expect(studyStreakProvider, isA<FutureProvider<int>>());
    });
  });
}
