import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/database/tables/weak_topics_table.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    // A fresh database seeds a few starter topics; these tests are about what
    // happens to rows they add themselves.
    await db.delete(db.weakTopics).go();
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> add(
    String subject,
    String topic, {
    ProficiencyLevel level = ProficiencyLevel.weak,
    String? notes,
  }) {
    return db.insertWeakTopic(
      WeakTopicsCompanion.insert(
        subject: subject,
        topicName: topic,
        proficiencyLevel: level,
        notes: Value(notes),
      ),
    );
  }

  Future<List<WeakTopic>> topicsFor(String topic) async {
    final all = await db.getAllWeakTopics();
    return all.where((t) => t.topicName.trim() == topic).toList();
  }

  group('Weak Topic Insert Dedup Tests', () {
    test('adding the same topic twice keeps one row', () async {
      final first = await add('বাংলা ব্যাকরণ', 'সমাস');
      final second = await add('বাংলা ব্যাকরণ', 'সমাস');

      expect(second, first);
      expect((await topicsFor('সমাস')).length, 1);
    });

    test('spacing and case do not create a second entry', () async {
      await add('Bangladesh Affairs', 'নদ-নদী');
      await add('  bangladesh affairs  ', '  নদ-নদী  ');

      final all = await db.getAllWeakTopics();
      expect(all.length, 1);
    });

    test(
      'a repeat insert does not overwrite the recorded proficiency',
      () async {
        // The user rated this strong; a later automated add must not quietly
        // drag it back to weak.
        await add('Mathematics', 'বৃত্ত', level: ProficiencyLevel.strong);
        await add('Mathematics', 'বৃত্ত', level: ProficiencyLevel.weak);

        final rows = await topicsFor('বৃত্ত');
        expect(rows.length, 1);
        expect(rows.single.proficiencyLevel, ProficiencyLevel.strong);
      },
    );

    test('notes from a repeat insert are merged, not lost', () async {
      await add('বাংলা ব্যাকরণ', 'সমাস', notes: 'চ্যাট থেকে যুক্ত');
      await add('বাংলা ব্যাকরণ', 'সমাস', notes: 'ভুলের খাতা থেকে');

      final row = (await topicsFor('সমাস')).single;
      expect(row.notes, contains('চ্যাট থেকে যুক্ত'));
      expect(row.notes, contains('ভুলের খাতা থেকে'));
    });

    test('the same note twice is not appended twice', () async {
      await add('বাংলা ব্যাকরণ', 'সমাস', notes: 'একই নোট');
      await add('বাংলা ব্যাকরণ', 'সমাস', notes: 'একই নোট');

      final row = (await topicsFor('সমাস')).single;
      expect('একই নোট'.allMatches(row.notes ?? '').length, 1);
    });

    test('different topics in one subject stay separate', () async {
      await add('Bangladesh Affairs', 'নদ-নদী');
      await add('Bangladesh Affairs', 'ইতিহাস ও ভূগোল');

      expect((await db.getAllWeakTopics()).length, 2);
    });
  });

  group('Existing Duplicate Cleanup Tests', () {
    test('collapses duplicates and keeps the weakest rating', () async {
      // What the real database had: the same topic twice, rated differently.
      await db
          .into(db.weakTopics)
          .insert(
            WeakTopicsCompanion.insert(
              subject: 'Bangladesh Affairs',
              topicName: 'বাংলাদেশের নদ-নদী',
              proficiencyLevel: ProficiencyLevel.moderate,
            ),
          );
      await db
          .into(db.weakTopics)
          .insert(
            WeakTopicsCompanion.insert(
              subject: 'Bangladesh Affairs',
              topicName: 'বাংলাদেশের নদ-নদী',
              proficiencyLevel: ProficiencyLevel.weak,
            ),
          );

      final removed = await db.dedupeWeakTopics();

      final all = await db.getAllWeakTopics();
      expect(removed, 1);
      expect(all.length, 1);
      expect(all.single.proficiencyLevel, ProficiencyLevel.weak);
    });

    test('keeps the most recent review date of the group', () async {
      final older = DateTime(2026, 10, 1);
      final newer = DateTime(2026, 10, 27);

      await db
          .into(db.weakTopics)
          .insert(
            WeakTopicsCompanion.insert(
              subject: 'বাংলা ব্যাকরণ',
              topicName: 'সমাস',
              proficiencyLevel: ProficiencyLevel.weak,
              lastReviewedAt: Value(older),
            ),
          );
      await db
          .into(db.weakTopics)
          .insert(
            WeakTopicsCompanion.insert(
              subject: 'বাংলা ব্যাকরণ',
              topicName: 'সমাস',
              proficiencyLevel: ProficiencyLevel.weak,
              lastReviewedAt: Value(newer),
            ),
          );

      await db.dedupeWeakTopics();

      final row = (await db.getAllWeakTopics()).single;
      expect(row.lastReviewedAt, newer);
    });

    test('a clean list is left alone', () async {
      await add('Mathematics', 'বৃত্ত');
      await add('বাংলা ব্যাকরণ', 'সমাস');

      expect(await db.dedupeWeakTopics(), 0);
      expect((await db.getAllWeakTopics()).length, 2);
    });
  });
}
