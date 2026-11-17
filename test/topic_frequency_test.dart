import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';

/// How often a topic has actually been asked.
///
/// The question-bank OCR has always read the source exam off the page and
/// always shown it on the review card, then dropped it on the way to the
/// database. So "high-yield" could only ever be a guess, when it was sitting
/// in the scan all along.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> add({
    required String topic,
    String? exam,
    String question = '',
  }) async {
    await db
        .into(db.drillQuestions)
        .insert(
          DrillQuestionsCompanion.insert(
            subject: 'বাংলা',
            topic: topic,
            questionText: question.isEmpty
                ? 'প্রশ্ন ${DateTime.now().microsecondsSinceEpoch}'
                : question,
            optionsJson: '["ক","খ"]',
            correctIndex: 0,
            selectedIndex: 0,
            isCorrect: true,
            sourceExam: Value(exam),
          ),
        );
  }

  test('ranks by how many different papers a topic turned up in', () async {
    await add(topic: 'কারক', exam: '৪৫তম বিসিএস');
    await add(topic: 'কারক', exam: '৪৩তম বিসিএস');
    await add(topic: 'কারক', exam: '৪১তম বিসিএস');
    await add(topic: 'সমাস', exam: '৪৫তম বিসিএস');

    final ranked = await db.getTopicFrequency();

    expect(ranked.first.topic, 'কারক');
    expect(ranked.first.exams.length, 3);
    expect(ranked.first.exams, contains('৪৩তম বিসিএস'));
    expect(ranked[1].topic, 'সমাস');
  });

  test('scanning one paper twice does not promote its topics', () async {
    // Four questions, one paper. A topic from three different papers must
    // still rank above it.
    for (var i = 0; i < 4; i++) {
      await add(topic: 'সমাস', exam: '৪৫তম বিসিএস');
    }
    await add(topic: 'কারক', exam: '৪৫তম বিসিএস');
    await add(topic: 'কারক', exam: '৪৩তম বিসিএস');
    await add(topic: 'কারক', exam: '৪১তম বিসিএস');

    final ranked = await db.getTopicFrequency();
    expect(ranked.first.topic, 'কারক');
    expect(ranked[1].questions, 4);
  });

  test('a question with no source exam is not counted', () async {
    await add(topic: 'কারক');
    await add(topic: 'কারক', exam: '  ');

    expect(await db.getTopicFrequency(), isEmpty);
  });

  test('nothing imported yet is empty, not a zero-filled list', () async {
    expect(await db.getTopicFrequency(), isEmpty);
  });

  test('the limit is respected', () async {
    for (var i = 0; i < 12; i++) {
      await add(topic: 'টপিক $i', exam: '৪৫তম বিসিএস');
    }

    expect((await db.getTopicFrequency(limit: 5)).length, 5);
  });

  test('ties keep a stable order between builds', () async {
    await add(topic: 'খ টপিক', exam: '৪৫তম বিসিএস');
    await add(topic: 'ক টপিক', exam: '৪৫তম বিসিএস');

    final first = await db.getTopicFrequency();
    final second = await db.getTopicFrequency();
    expect(first.map((t) => t.topic), second.map((t) => t.topic));
  });

  test('the source exam survives a round trip', () async {
    await add(topic: 'কারক', exam: '৪৫তম বিসিএস', question: 'প্রশ্নটি');

    final row = (await db.select(db.drillQuestions).get()).single;
    expect(row.sourceExam, '৪৫তম বিসিএস');
  });
}
