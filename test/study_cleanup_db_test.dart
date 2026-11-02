import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/database/tables/weak_topics_table.dart';

/// The cleanup deletes rows, so what it decides matters more than most code.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> addTopic(String subject, String topic) => db.insertWeakTopic(
    WeakTopicsCompanion.insert(
      subject: subject,
      topicName: topic,
      proficiencyLevel: ProficiencyLevel.weak,
    ),
  );

  test('a preview changes nothing on its own', () async {
    await addTopic('Bangladesh Affairs', 'বাংলাদেশের নদ-নদী');
    final before = (await db.select(db.weakTopics).get()).length;

    final summary = await db.previewStudyCleanup();

    expect(summary.isEmpty, isFalse);
    expect((await db.select(db.weakTopics).get()).length, before);
  });

  test('applying merges the duplicate and keeps one', () async {
    await addTopic('Bangla Literature', 'মধ্যযুগ - মঙ্গলকাব্য (অন্নদামঙ্গল)');
    await addTopic('Bangla Literature', 'মধ্যযুগ (ভারতচন্দ্র রায়গুণাকর)');

    final summary = await db.previewStudyCleanup();
    await db.applyStudyCleanup(summary);

    final left = (await db.select(db.weakTopics).get())
        .where((t) => t.topicName.contains('মধ্যযুগ'))
        .toList();
    expect(left.length, 1);
    // The survivor carries the corrected subject.
    expect(left.single.subject, 'বাংলা সাহিত্য');
  });

  test('an exam title saved as its own topic is removed', () async {
    const name = 'বাংলা ১ম পত্র - নির্বাচনী পরীক্ষা ২০২৬';
    await addTopic(name, name);

    final summary = await db.previewStudyCleanup();
    await db.applyStudyCleanup(summary);

    expect(
      (await db.select(db.weakTopics).get()).where((t) => t.subject == name),
      isEmpty,
    );
  });

  test('a second run finds nothing left to do', () async {
    await addTopic('Mathematics', 'বৃত্ত ও পরিধি');

    await db.applyStudyCleanup(await db.previewStudyCleanup());
    final second = await db.previewStudyCleanup();

    // Running it twice must not keep deleting things.
    expect(second.isEmpty, isTrue);
  });

  test('genuinely different topics survive', () async {
    await addTopic('গাণিতিক যুক্তি', 'বৃত্ত ও পরিধি');
    await addTopic('গাণিতিক যুক্তি', 'সামান্তরিক ও রম্বস');
    final before = (await db.select(db.weakTopics).get()).length;

    await db.applyStudyCleanup(await db.previewStudyCleanup());

    expect((await db.select(db.weakTopics).get()).length, before);
  });
}
