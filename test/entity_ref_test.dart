import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/services/ai/entity_ref.dart';
import 'package:life_and_study_assistant/core/services/ai/entity_ref_resolver.dart';
import 'package:life_and_study_assistant/features/chat/domain/models/chat_action.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Entity Reference Parsing', () {
    test('a tag round-trips', () {
      expect(const EntityRef(EntityKind.question, 17).tag, 'Q-17');
      expect(
        EntityRef.tryParse('Q-17'),
        const EntityRef(EntityKind.question, 17),
      );
      expect(
        EntityRef.tryParse(' e-42 '),
        const EntityRef(EntityKind.exam, 42),
      );
    });

    test('an unknown prefix is not a tag', () {
      expect(EntityRef.tryParse('Z-3'), isNull);
      expect(EntityRef.tryParse('17'), isNull);
      expect(EntityRef.tryParse('Q-'), isNull);
    });

    test('tags are found inside a sentence', () {
      final refs = EntityRef.findAll('Q-17 আর E-42 দুটোতেই সমস্যা আছে');

      expect(refs, [
        const EntityRef(EntityKind.question, 17),
        const EntityRef(EntityKind.exam, 42),
      ]);
    });

    test('the same tag twice is listed once', () {
      expect(EntityRef.findAll('Q-7 ঠিক করো, হ্যাঁ Q-7'), hasLength(1));
    });

    test('a date is not mistaken for a tag', () {
      // Without the boundary checks "2026-11" and similar would match.
      expect(EntityRef.findAll('পরীক্ষা ২০২৬-১১-০২ তারিখে'), isEmpty);
      expect(EntityRef.findAll('abcQ-9'), isEmpty);
    });
  });

  group('Entity Reference Resolution', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.delete(db.weakTopics).go();
    });
    tearDown(() => db.close());

    test('a message with no tags resolves to nothing', () async {
      expect(await EntityRefResolver.describe(db, 'আজকে কী পড়ব?'), isNull);
    });

    test('a referenced question is spelled out', () async {
      final id = await db
          .into(db.drillQuestions)
          .insert(
            DrillQuestionsCompanion.insert(
              subject: 'Bangladesh Affairs',
              topic: 'জাতীয় প্রতীক',
              questionText: 'পতাকার অনুপাত কত?',
              optionsJson: jsonEncode(['৩:২', '১০:৬']),
              correctIndex: 1,
              selectedIndex: 1,
              isCorrect: true,
              explanation: const Value('১০:৬ = ৫:৩।'),
            ),
          );

      final described = await EntityRefResolver.describe(db, 'Q-$id ঠিক করো');

      expect(described, contains('Q-$id'));
      expect(described, contains('পতাকার অনুপাত'));
      expect(described, contains('সংরক্ষিত উত্তর: ১০:৬'));
    });

    test('a referenced exam is spelled out', () async {
      final id = await db.insertExamSchedule(
        ExamSchedulesCompanion.insert(
          examDate: DateTime(2026, 12, 1),
          examTime: const Value('09:00 PM'),
          title: 'মডেল টেস্ট ০৭',
          topicsCovered: 'সূচক',
          trackName: const Value('Weekend Batch'),
        ),
      );

      final described = await EntityRefResolver.describe(db, 'E-$id সরাও');

      expect(described, contains('মডেল টেস্ট ০৭'));
      expect(described, contains('2026-12-01'));
      expect(described, contains('Weekend Batch'));
    });

    test('a tag pointing at nothing says so instead of inventing', () async {
      final described = await EntityRefResolver.describe(db, 'Q-99999 দেখো');

      expect(described, contains('পাওয়া যায়নি'));
    });
  });

  group('Add Exam Action', () {
    test('a well-formed tag becomes a proposal', () {
      final actions = ChatAction.extractActions(
        'ঠিক আছে।\n[[ACTION:ADD_EXAM|2026-11-12|মডেল টেস্ট ০৩|বাংলা ব্যাকরণ|কারক, সমাস|১০০ দিনে বিসিএস|10:00 PM]]',
      );

      expect(actions, hasLength(1));
      final a = actions.single;
      expect(a.type, ChatActionType.addExam);
      expect(a.title, 'মডেল টেস্ট ০৩');
      expect(a.examDate, '2026-11-12');
      expect(a.examTime, '10:00 PM');
      expect(a.trackName, '১০০ দিনে বিসিএস');
      expect(a.topic, 'কারক, সমাস');
    });

    test('the trailing fields are optional', () {
      final a = ChatAction.extractActions(
        '[[ACTION:ADD_EXAM|2026-11-12|মডেল টেস্ট|গণিত]]',
      ).single;

      expect(a.examTime, isNull);
      expect(a.trackName, isNull);
    });

    test('a tag without a usable date is ignored', () {
      // Better no proposal than one scheduled on a date nobody chose.
      expect(
        ChatAction.extractActions('[[ACTION:ADD_EXAM|কাল|মডেল টেস্ট|গণিত]]'),
        isEmpty,
      );
    });

    test('action tags never reach the displayed reply', () {
      const raw =
          'রুটিনে যোগ করতে পারি।\n[[ACTION:ADD_EXAM|2026-11-12|মডেল টেস্ট|গণিত]]';

      expect(ChatAction.cleanActionTags(raw), 'রুটিনে যোগ করতে পারি।');
    });

    test('a proposal survives being stored and read back', () {
      final original = ChatAction.extractActions(
        '[[ACTION:ADD_EXAM|2026-11-12|মডেল টেস্ট ০৩|গণিত|সূচক|Batch A|09:00 PM]]',
      ).single;

      final restored = ChatAction.decodeList(ChatAction.encodeList([original]))
          .single;

      expect(restored.type, ChatActionType.addExam);
      expect(restored.examDate, '2026-11-12');
      expect(restored.trackName, 'Batch A');
    });
  });
}
