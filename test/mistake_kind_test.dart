import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/data/mistake_kind.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';

/// Why a question was got wrong, rather than which topic it was in.
///
/// The app could already say "শতকরায় দুর্বল". It could not say "আমি হিসাবে
/// ভুল করি", which is the one that changes what somebody does tomorrow. What
/// these check is mostly restraint: that a handful of tags is reported as a
/// handful rather than as the truth about a person.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TaggedMistake m(MistakeKind? kind, [String topic = 'শতকরা']) =>
      TaggedMistake(kind: kind, topic: topic);

  group('the taxonomy', () {
    test('every kind has a label and a remedy', () {
      for (final kind in MistakeKind.values) {
        expect(kind.label.trim(), isNotEmpty, reason: kind.name);
        expect(kind.remedy.trim(), isNotEmpty, reason: kind.name);
      }
    });

    test('no two kinds share a remedy', () {
      // The whole basis of the list: two kinds that lead to the same action
      // should have been one kind.
      final remedies = MistakeKind.values.map((k) => k.remedy).toList();
      expect(remedies.toSet().length, remedies.length);
    });

    test('a name round-trips, and an unknown one reads as untagged', () {
      for (final kind in MistakeKind.values) {
        expect(mistakeKindFromName(kind.name), kind);
      }
      // A kind written by a later build must not throw on this one.
      expect(mistakeKindFromName('somethingElse'), isNull);
      expect(mistakeKindFromName(null), isNull);
      expect(mistakeKindFromName(''), isNull);
    });
  });

  group('summarising', () {
    test('counts the kinds, commonest first', () {
      final pattern = summariseMistakes([
        m(MistakeKind.calculation),
        m(MistakeKind.calculation),
        m(MistakeKind.calculation),
        m(MistakeKind.trap),
        m(MistakeKind.forgot),
        m(MistakeKind.forgot),
      ]);

      expect(pattern.byKind.first.key, MistakeKind.calculation);
      expect(pattern.byKind.first.value, 3);
      expect(pattern.byKind[1].key, MistakeKind.forgot);
      expect(pattern.dominant, MistakeKind.calculation);
      expect(pattern.tagged, 6);
    });

    test('untagged mistakes are counted apart, never as a kind', () {
      final pattern = summariseMistakes([
        m(MistakeKind.trap),
        m(null),
        m(null),
      ]);

      expect(pattern.tagged, 1);
      expect(pattern.untagged, 2);
      expect(pattern.dominantShare, 1.0);
    });

    test('a thin sample says it is thin', () {
      // Four tagged mistakes can make any kind look like half a person.
      final thin = summariseMistakes(List.filled(4, m(MistakeKind.misread)));
      expect(thin.isThin, isTrue);

      final enough = summariseMistakes(
        List.filled(8, m(MistakeKind.misread)),
      );
      expect(enough.isThin, isFalse);
    });

    test('finds where each kind concentrates', () {
      final pattern = summariseMistakes([
        m(MistakeKind.calculation, 'সুদকষা'),
        m(MistakeKind.calculation, 'সুদকষা'),
        m(MistakeKind.calculation, 'শতকরা'),
        m(MistakeKind.trap, 'কারক'),
      ]);

      expect(pattern.worstTopicByKind[MistakeKind.calculation]!.key, 'সুদকষা');
      expect(pattern.worstTopicByKind[MistakeKind.calculation]!.value, 2);
      expect(pattern.worstTopicByKind[MistakeKind.trap]!.key, 'কারক');
    });

    test('ties do not reshuffle between builds', () {
      // Equal counts are broken by the enum order, so the list a user looked
      // at yesterday is the list they see today.
      final first = summariseMistakes([
        m(MistakeKind.trap),
        m(MistakeKind.forgot),
      ]);
      final second = summariseMistakes([
        m(MistakeKind.forgot),
        m(MistakeKind.trap),
      ]);

      expect(
        first.byKind.map((e) => e.key),
        second.byKind.map((e) => e.key),
      );
    });

    test('nothing at all is empty, not a division by zero', () {
      final pattern = summariseMistakes([]);
      expect(pattern.dominant, isNull);
      expect(pattern.dominantShare, 0);
      expect(pattern.isThin, isTrue);
    });

    test('only untagged mistakes report no dominant kind', () {
      final pattern = summariseMistakes([m(null), m(null)]);
      expect(pattern.dominant, isNull);
      expect(pattern.dominantShare, 0);
      expect(pattern.untagged, 2);
    });
  });

  group('through the database', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<int> wrong({
      String topic = 'শতকরা',
      bool mastered = false,
      DateTime? at,
    }) {
      return db
          .into(db.drillQuestions)
          .insert(
            DrillQuestionsCompanion.insert(
              subject: 'গাণিতিক যুক্তি',
              topic: topic,
              questionText: 'প্রশ্ন ${DateTime.now().microsecondsSinceEpoch}',
              optionsJson: '["ক","খ"]',
              correctIndex: 0,
              selectedIndex: 1,
              isCorrect: false,
              isMastered: Value(mastered),
              attemptedAt: Value(at ?? DateTime.now()),
            ),
          );
    }

    test('a tag is written and read back', () async {
      final id = await wrong();

      expect(await db.setMistakeKind(id, MistakeKind.calculation), isTrue);

      final pattern = await db.getMistakePattern();
      expect(pattern.dominant, MistakeKind.calculation);
      expect(pattern.tagged, 1);
    });

    test('tagging again replaces, and null clears', () async {
      final id = await wrong();

      await db.setMistakeKind(id, MistakeKind.calculation);
      await db.setMistakeKind(id, MistakeKind.trap);
      expect((await db.getMistakePattern()).dominant, MistakeKind.trap);

      // A mis-tap must cost one tap to undo, or the tagging is a one-way
      // door and people stop using it.
      await db.setMistakeKind(id, null);
      final cleared = await db.getMistakePattern();
      expect(cleared.tagged, 0);
      expect(cleared.untagged, 1);
    });

    test('a mastered question leaves the pattern', () async {
      final id = await wrong();
      await db.setMistakeKind(id, MistakeKind.forgot);
      expect((await db.getMistakePattern()).tagged, 1);

      await db.markQuestionMastered(id, true);

      // Not a habit the user still has.
      expect((await db.getMistakePattern()).tagged, 0);
    });

    test('old mistakes fall out of the window', () async {
      final old = await wrong(
        at: DateTime.now().subtract(const Duration(days: 200)),
      );
      await db.setMistakeKind(old, MistakeKind.misread);

      expect((await db.getMistakePattern(withinDays: 90)).tagged, 0);
      expect((await db.getMistakePattern(withinDays: 365)).tagged, 1);
    });

    test('a correct answer is never in the pattern', () async {
      await db
          .into(db.drillQuestions)
          .insert(
            DrillQuestionsCompanion.insert(
              subject: 'গাণিতিক যুক্তি',
              topic: 'শতকরা',
              questionText: 'ঠিক উত্তর',
              optionsJson: '["ক","খ"]',
              correctIndex: 0,
              selectedIndex: 0,
              isCorrect: true,
            ),
          );

      expect((await db.getMistakePattern()).untagged, 0);
    });
  });
}
