import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/database/database_provider.dart';
import 'package:life_and_study_assistant/core/database/tables/weak_topics_table.dart';
import 'package:life_and_study_assistant/core/services/ai/models/quiz_question.dart';
import 'package:life_and_study_assistant/features/quiz/presentation/widgets/quiz_drill_modal.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A drill has to change something by itself.
///
/// It did not. Finishing one wrote the questions and the score and stopped
/// there; the weak-topics list was fed only by a "save mistakes" button on
/// the results screen. Skip the button — which is most of the time, since
/// the drill is over and the obvious move is to close it — and the whole
/// drill left no trace anywhere that decides what to study next.
///
/// These finish drills and never touch that button.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  QuizQuestion q(String text, {int correctIndex = 0, String? subject}) =>
      QuizQuestion(
        questionText: text,
        options: const ['ক. এক', 'খ. দুই', 'গ. তিন', 'ঘ. চার'],
        correctIndex: correctIndex,
        explanation: 'ব্যাখ্যা',
        subject: subject ?? 'গাণিতিক যুক্তি',
      );

  Future<void> runDrill(
    WidgetTester tester,
    List<QuizQuestion> questions, {
    required Future<void> Function(WidgetTester tester) answer,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Scaffold(
            body: QuizDrillModal(
              subject: 'গাণিতিক যুক্তি',
              topic: 'শতকরা',
              customQuestions: questions,
              initialMode: QuizMode.practice,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await answer(tester);
  }

  /// Skips every question, which the weak-topic signal counts as not knowing
  /// them — the clearest way to drive it from a widget test.
  Future<void> skipAll(WidgetTester tester, int count) async {
    for (var i = 0; i < count; i++) {
      final skip = find.text(
        i == count - 1 ? 'জানি না — ফলাফল দেখুন' : 'জানি না — পরেরটা',
      );
      await tester.ensureVisible(skip.first);
      await tester.pumpAndSettle();
      await tester.tap(skip.first);
      await tester.pumpAndSettle();
    }
  }

  Future<List<WeakTopic>> weakTopics() => db.select(db.weakTopics).get();

  testWidgets('finishing a drill records the weak topic with no button tap', (
    tester,
  ) async {
    final before = (await weakTopics()).length;
    // The database seeds review items of its own on create, so this is a
    // count to compare against rather than an expectation of emptiness.
    final reviewsBefore = (await db.select(db.spacedReviewItems).get()).length;

    await runDrill(
      tester,
      [q('প্রশ্ন ১'), q('প্রশ্ন ২'), q('প্রশ্ন ৩')],
      answer: (t) => skipAll(t, 3),
    );

    // The results screen is up and the save button has not been touched —
    // it still offers to add them, which it would not if it had been used.
    expect(find.textContaining('রিভিশনে যোগ করুন'), findsOneWidget);
    expect(find.text('রিভিশনে যোগ হয়েছে'), findsNothing);
    // And nothing has gone into the revision deck, which stays a choice:
    // that decides what the user gets asked at a bus stop.
    expect(
      (await db.select(db.spacedReviewItems).get()).length,
      reviewsBefore,
    );

    // And it is said out loud: a topic being marked weak changes what the
    // app recommends next, so it should not happen behind the user's back.
    expect(find.textContaining('দুর্বল তালিকায় গেল'), findsOneWidget);

    final after = await weakTopics();
    expect(after.length, before + 1);
    expect(after.map((t) => t.topicName), contains('শতকরা'));
    expect(
      after.firstWhere((t) => t.topicName == 'শতকরা').proficiencyLevel,
      ProficiencyLevel.weak,
    );
  });

  testWidgets('the drill itself is still saved', (tester) async {
    await runDrill(
      tester,
      [q('প্রশ্ন ১'), q('প্রশ্ন ২')],
      answer: (t) => skipAll(t, 2),
    );

    expect((await db.select(db.drillRecords).get()).length, 1);
    expect((await db.select(db.drillQuestions).get()).length, 2);
  });

  testWidgets('one unlucky question does not brand a topic weak', (
    tester,
  ) async {
    final before = (await weakTopics()).length;

    // The signal is thresholded — two asked, two wrong, more than half —
    // so a single miss must not reach the list.
    await runDrill(tester, [q('প্রশ্ন ১')], answer: (t) => skipAll(t, 1));

    expect((await weakTopics()).length, before);
    // Nothing claimed, either.
    expect(find.textContaining('দুর্বল তালিকায় গেল'), findsNothing);
  });

  testWidgets('a skipped question with no answer key still counts as wrong', (
    tester,
  ) async {
    final before = (await weakTopics()).length;

    // correctIndex -1 is what an import writes when the page had no answer
    // key. Skipping sets -1 too, and comparing the two indices directly made
    // that read as a correct answer — so a page of unanswered, unkeyed
    // questions looked like a clean sheet.
    await runDrill(
      tester,
      [
        q('প্রশ্ন ১', correctIndex: -1),
        q('প্রশ্ন ২', correctIndex: -1),
        q('প্রশ্ন ৩', correctIndex: -1),
      ],
      answer: (t) => skipAll(t, 3),
    );

    expect((await weakTopics()).length, before + 1);
  });
}
