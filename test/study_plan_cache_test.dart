import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/services/ai/gemini_result_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reopening the app used to rebuild the day's plan from scratch — twice in
/// twenty minutes in one measured afternoon, about 1900 tokens each time.
/// What makes caching it safe is that the key follows the things the plan is
/// built from, so it is reused only while those hold.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final cache = GeminiResultCache.instance;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  String keyFor(String prompt) => cache.computeKeyFromString(
    operation: 'study_plan',
    promptVersion: 'v1.0',
    model: 'gemini-flash-latest',
    payloadText: prompt,
  );

  test('the same day, unchanged, reuses the same plan', () async {
    const prompt = 'energy: medium, fatigue: 5, exams: বাংলা সাহিত্য';
    await cache.put(keyFor(prompt), '{"summary":"আজকের প্ল্যান"}');

    final again = await cache.get(keyFor(prompt));

    expect(again, contains('আজকের প্ল্যান'));
  });

  test('logging a different energy gives a different plan', () async {
    // Without this the user could log being exhausted and still be handed
    // the plan written when they were fresh.
    await cache.put(
      keyFor('energy: high, fatigue: 2, exams: বাংলা'),
      '{"summary":"ভারী পড়া"}',
    );

    final tired = await cache.get(
      keyFor('energy: low, fatigue: 9, exams: বাংলা'),
    );

    expect(tired, isNull);
  });

  test('a new exam on the horizon gives a different plan', () async {
    await cache.put(
      keyFor('energy: medium, exams: বাংলা সাহিত্য'),
      '{"summary":"সাহিত্য"}',
    );

    final withMaths = await cache.get(
      keyFor('energy: medium, exams: বাংলা সাহিত্য, গণিত'),
    );

    expect(withMaths, isNull);
  });

  test('a plan older than its window is not reused', () async {
    const prompt = 'energy: medium, fatigue: 5';
    await cache.put(keyFor(prompt), '{"summary":"পুরোনো"}');

    // Asked for with no tolerance for age, nothing comes back.
    final stale = await cache.get(keyFor(prompt), ttl: Duration.zero);

    expect(stale, isNull);
  });
}
