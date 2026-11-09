import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/features/dashboard/domain/next_study_action.dart';

/// The dashboard offers six calls to action and ranks none of them. After a
/// day's work, choosing between six is the hard part — which is the whole
/// reason micro-commitments exist. This picks one.
void main() {
  group('what gets chosen', () {
    test('due reviews come first, because only they are time-sensitive', () {
      // Everything else is waiting too, and all of it loses to the one thing
      // that is worth less tomorrow than today.
      final action = pickNextStudyAction(
        dueReviews: 7,
        unfinishedTaskTitle: 'MCQ ১০টি',
        activeMistakes: 20,
        weakTopics: 4,
      );

      expect(action.kind, StudyActionKind.dueReviews);
      expect(action.count, 7);
      expect(action.title, contains('7'));
    });

    test("today's task comes next, since the plan already sized it", () {
      final action = pickNextStudyAction(
        dueReviews: 0,
        unfinishedTaskTitle: 'সূত্র মুখস্থ',
        unfinishedTaskMinutes: 7,
        activeMistakes: 20,
        weakTopics: 4,
      );

      expect(action.kind, StudyActionKind.unfinishedTask);
      expect(action.title, 'সূত্র মুখস্থ');
      expect(action.minutes, 7);
    });

    test('then mistakes, which are known-wrong but can wait a day', () {
      final action = pickNextStudyAction(
        dueReviews: 0,
        activeMistakes: 4,
        weakTopics: 4,
      );

      expect(action.kind, StudyActionKind.mistakeDrill);
      expect(action.count, 4);
    });

    test('a weak topic last, being the broadest thing on the list', () {
      final action = pickNextStudyAction(
        dueReviews: 0,
        activeMistakes: 0,
        weakTopics: 3,
      );

      expect(action.kind, StudyActionKind.weakTopic);
    });

    test('and nothing waiting says so rather than inventing work', () {
      final action = pickNextStudyAction(
        dueReviews: 0,
        activeMistakes: 0,
        weakTopics: 0,
      );

      expect(action.kind, StudyActionKind.allClear);
      expect(action.isAllClear, isTrue);
      expect(action.minutes, 0);
    });

    test('a blank task title is not a task', () {
      final action = pickNextStudyAction(
        dueReviews: 0,
        unfinishedTaskTitle: '   ',
        activeMistakes: 2,
        weakTopics: 0,
      );

      expect(action.kind, StudyActionKind.mistakeDrill);
    });
  });

  group('the minutes have to be startable', () {
    test('a pile of due reviews is still a few minutes, not an hour', () {
      // The figure decides whether a tired person begins at all. Forty minutes
      // is a reason to put the phone down.
      final action = pickNextStudyAction(
        dueReviews: 80,
        activeMistakes: 0,
        weakTopics: 0,
      );

      expect(action.minutes, lessThanOrEqualTo(12));
      expect(action.minutes, greaterThan(0));
    });

    test('a pile of mistakes likewise', () {
      final action = pickNextStudyAction(
        dueReviews: 0,
        activeMistakes: 200,
        weakTopics: 0,
      );

      expect(action.minutes, lessThanOrEqualTo(10));
    });

    test('one due review is one minute, not nought', () {
      final action = pickNextStudyAction(
        dueReviews: 1,
        activeMistakes: 0,
        weakTopics: 0,
      );

      expect(action.minutes, 1);
    });

    test('an absurd task estimate is brought back to an hour', () {
      final action = pickNextStudyAction(
        dueReviews: 0,
        unfinishedTaskTitle: 'পুরো বই',
        unfinishedTaskMinutes: 600,
        activeMistakes: 0,
        weakTopics: 0,
      );

      expect(action.minutes, 60);
    });
  });

  test('every choice carries a reason', () {
    // A recommendation whose grounds are invisible is just another thing to
    // second-guess, so none of them is allowed to arrive bare.
    for (final action in [
      pickNextStudyAction(dueReviews: 3, activeMistakes: 0, weakTopics: 0),
      pickNextStudyAction(
        dueReviews: 0,
        unfinishedTaskTitle: 'x',
        activeMistakes: 0,
        weakTopics: 0,
      ),
      pickNextStudyAction(dueReviews: 0, activeMistakes: 3, weakTopics: 0),
      pickNextStudyAction(dueReviews: 0, activeMistakes: 0, weakTopics: 3),
      pickNextStudyAction(dueReviews: 0, activeMistakes: 0, weakTopics: 0),
    ]) {
      expect(action.why.trim(), isNotEmpty, reason: '${action.kind}');
      expect(action.title.trim(), isNotEmpty, reason: '${action.kind}');
    }
  });
}
