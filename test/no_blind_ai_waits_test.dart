import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards against a screen that waits on an AI call behind a bare spinner.
///
/// A CircularProgressIndicator with nothing beside it says only "wait". It
/// cannot say how long it has been going, whether anything is happening, or
/// how to stop, so a slow call is indistinguishable from a hung one. Every
/// screen that awaits a model must show elapsed time instead, which is what
/// AiProgressPipelineWidget is for.
void main() {
  final aiServices = [
    'GeminiAiService',
    'AiFlashcardService',
    'QuizGeneratorService',
    'QuizBatchCorrectionService',
    'RoutineParserService',
    'QuestionBankOcrService',
    'WeeklyRoutineService',
    'VoiceMistakeParserService',
  ];

  const countsItsOwnSeconds = {
    'lib/features/live_mcq/presentation/screens/live_mcq_screen.dart',
    'lib/features/live_mcq/presentation/widgets/floating_bubble_overlay.dart',
    'lib/features/chat/presentation/screens/ai_chat_screen.dart',
  };

  test('every screen that waits on a model shows how long it has waited', () {
    final offenders = <String>[];

    for (final file
        in Directory('lib/features')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();

      final callsAi = aiServices.any(source.contains);
      if (!callsAi) continue;
      if (!source.contains('CircularProgressIndicator')) continue;
      if (source.contains('AiProgressPipelineWidget')) continue;
      // These count the elapsed seconds themselves, next to the spinner,
      // because their wait is drawn inside a bubble or a chat row where the
      // full pipeline does not fit. Looking for Timer.periodic instead of
      // naming them let a countdown clock elsewhere pass for progress.
      if (countsItsOwnSeconds.contains(file.path)) continue;

      offenders.add(file.path);
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'These wait on an AI call behind a bare spinner. Use '
          'AiProgressPipelineWidget, or count the elapsed seconds:\n'
          '${offenders.join('\n')}',
    );
  });
}
