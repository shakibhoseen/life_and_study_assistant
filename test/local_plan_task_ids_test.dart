import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/services/ai/gemini_ai_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// With no API key the plan is built locally — and that plan is not cached, so
/// it is rebuilt from scratch every time the dashboard asks for it. Its task
/// ids used to come from DateTime.now(), which meant the same task had a new
/// id on every build and a task ticked off could never be found again.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // No key: generateAdaptivePlan falls through to the local planner.
    SharedPreferences.setMockInitialValues({});
  });

  test('the same local plan gives the same task ids twice', () async {
    final first = await GeminiAiService.instance.generateAdaptivePlan(
      energyLevel: 'low',
      fatigueScore: 8,
      weakTopics: const [],
      upcomingExams: const [],
    );
    final second = await GeminiAiService.instance.generateAdaptivePlan(
      energyLevel: 'low',
      fatigueScore: 8,
      weakTopics: const [],
      upcomingExams: const [],
    );

    expect(first.isLocallyBuilt, isTrue);
    expect(first.tasks, isNotEmpty);
    expect(
      first.tasks.map((t) => t.id).toList(),
      second.tasks.map((t) => t.id).toList(),
    );
  });

  test('no task id is minted from the clock', () async {
    final plan = await GeminiAiService.instance.generateAdaptivePlan(
      energyLevel: 'high',
      fatigueScore: 2,
      weakTopics: const [],
      upcomingExams: const [],
    );

    for (final task in plan.tasks) {
      // A thirteen-digit run is a millisecondsSinceEpoch stamp, and a stamp in
      // an id is the bug itself.
      expect(
        RegExp(r'\d{13}').hasMatch(task.id),
        isFalse,
        reason: 'id ${task.id} looks like a timestamp',
      );
    }
  });

  test('the branches do not collide with each other', () async {
    final low = await GeminiAiService.instance.generateAdaptivePlan(
      energyLevel: 'low',
      fatigueScore: 8,
      weakTopics: const [],
      upcomingExams: const [],
    );
    final high = await GeminiAiService.instance.generateAdaptivePlan(
      energyLevel: 'high',
      fatigueScore: 2,
      weakTopics: const [],
      upcomingExams: const [],
    );

    // Ticking the low-energy task off must not tick a high-energy one off on
    // a day the energy log changes.
    expect(
      low.tasks.map((t) => t.id).toSet().intersection(
        high.tasks.map((t) => t.id).toSet(),
      ),
      isEmpty,
    );
  });
}
