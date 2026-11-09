import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/services/ai/models/study_task.dart';
import 'package:life_and_study_assistant/features/dashboard/domain/today_progress.dart';

/// The dashboard could say what last month looked like and how many days the
/// streak ran, and nothing at all about today — so "have I done enough?" had
/// to be answered by scrolling and counting ticks.
void main() {
  StudyTask task({
    required String id,
    int minutes = 10,
    bool done = false,
  }) {
    return StudyTask(
      id: id,
      title: 'টাস্ক $id',
      subject: 'বাংলা',
      estimatedMinutes: minutes,
      taskType: 'micro_mcq',
      actionablePrompt: '',
      isCompleted: done,
    );
  }

  group('counting today', () {
    test('a fresh plan is nought out of its tasks', () {
      final progress = summariseToday(
        tasks: [task(id: '1'), task(id: '2')],
        recommendedStudyMinutes: 60,
        questionsAnsweredToday: 0,
      );

      expect(progress.tasksDone, 0);
      expect(progress.tasksTotal, 2);
      expect(progress.taskFraction, 0);
      expect(progress.allTasksDone, isFalse);
    });

    test('the minutes are the plan\'s, for the tasks actually ticked', () {
      final progress = summariseToday(
        tasks: [
          task(id: '1', minutes: 7, done: true),
          task(id: '2', minutes: 15, done: true),
          task(id: '3', minutes: 20),
        ],
        recommendedStudyMinutes: 60,
        questionsAnsweredToday: 0,
      );

      expect(progress.tasksDone, 2);
      expect(progress.routineMinutesDone, 22);
      expect(progress.routineMinutesTarget, 60);
      expect(progress.metMinuteTarget, isFalse);
    });

    test('the day is done when every task is', () {
      final progress = summariseToday(
        tasks: [task(id: '1', done: true), task(id: '2', done: true)],
        recommendedStudyMinutes: 20,
        questionsAnsweredToday: 0,
      );

      expect(progress.allTasksDone, isTrue);
      expect(progress.taskFraction, 1);
      expect(progress.metMinuteTarget, isTrue);
    });

    test('questions answered are counted whether or not there is a plan', () {
      final progress = summariseToday(
        tasks: const [],
        recommendedStudyMinutes: 0,
        questionsAnsweredToday: 12,
      );

      expect(progress.questionsAnswered, 12);
      expect(progress.hasPlan, isFalse);
      expect(progress.isUntouched, isFalse);
    });
  });

  group('an empty day is not a finished one', () {
    test('no plan and nothing answered has nothing to show', () {
      final progress = summariseToday(
        tasks: const [],
        recommendedStudyMinutes: 0,
        questionsAnsweredToday: 0,
      );

      expect(progress.isUntouched, isTrue);
    });

    test('no plan does not count as all tasks done', () {
      // Zero of zero is not a day's work finished, and a green tick for having
      // no plan would be a lie told in the most encouraging way.
      final progress = summariseToday(
        tasks: const [],
        recommendedStudyMinutes: 60,
        questionsAnsweredToday: 3,
      );

      expect(progress.allTasksDone, isFalse);
      expect(progress.taskFraction, 0);
    });
  });

  test('the fraction stays within bounds however odd the plan', () {
    // Defensive: a plan that reports a task twice should not push the bar past
    // its end.
    final progress = summariseToday(
      tasks: [task(id: '1', done: true), task(id: '1', done: true)],
      recommendedStudyMinutes: 10,
      questionsAnsweredToday: 0,
    );

    expect(progress.taskFraction, lessThanOrEqualTo(1));
    expect(progress.taskFraction, greaterThanOrEqualTo(0));
  });
}
