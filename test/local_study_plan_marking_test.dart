import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/services/ai/gemini_ai_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Without a key no model can be reached, so every plan here is the one the
  // phone builds. What matters is that it says so: the card calls every plan
  // an "Adaptive AI Routine", and a plan the model never saw must not pass
  // under that name.
  test('a plan built on the phone is marked as such', () async {
    final plan = await GeminiAiService.instance.generateAdaptivePlan(
      energyLevel: 'Low',
      fatigueScore: 8,
      weakTopics: const [],
      upcomingExams: const [],
    );

    expect(plan.isLocallyBuilt, isTrue);
    // Still a usable plan, not an error page.
    expect(plan.tasks, isNotEmpty);
    expect(plan.summary, isNotEmpty);
  });
}
