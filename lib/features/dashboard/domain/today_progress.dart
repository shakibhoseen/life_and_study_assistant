import 'package:flutter/foundation.dart';

import '../../../core/services/ai/models/study_task.dart';

/// How much of today's plan has actually been done.
///
/// The dashboard had no answer to this. The heatmap shows history, the streak
/// shows days, and nothing showed today — so the one question somebody asks
/// before deciding whether to stop ("have I done enough?") had to be answered
/// by scrolling and counting ticks.
///
/// **There is no measured study time anywhere in this app.** The activity
/// table records drills, questions and energy logs per day, not minutes, and
/// the focus timer writes nothing when it finishes. So the minutes here are
/// the plan's own arithmetic — what the plan allotted to the tasks that are
/// ticked off, against what it allotted for the day — and are named as routine
/// minutes rather than dressed up as time spent. Inventing a measurement would
/// be worse than not showing one.
@immutable
class TodayProgress {
  const TodayProgress({
    required this.tasksDone,
    required this.tasksTotal,
    required this.routineMinutesDone,
    required this.routineMinutesTarget,
    required this.questionsAnswered,
  });

  final int tasksDone;
  final int tasksTotal;

  /// Minutes the plan allotted to the tasks that are ticked off.
  final int routineMinutesDone;

  /// Minutes the plan allotted for the whole day.
  final int routineMinutesTarget;

  /// Questions answered today, from the activity table. A real count.
  final int questionsAnswered;

  bool get hasPlan => tasksTotal > 0;

  bool get allTasksDone => hasPlan && tasksDone >= tasksTotal;

  /// Nothing to show yet — no plan and nothing answered.
  bool get isUntouched => !hasPlan && questionsAnswered == 0;

  /// How far through the day's tasks, 0 to 1. Zero when there is no plan,
  /// rather than one: an empty plan is not a finished day.
  double get taskFraction =>
      tasksTotal == 0 ? 0 : (tasksDone / tasksTotal).clamp(0, 1).toDouble();

  /// Whether the day's allotted minutes have been covered.
  bool get metMinuteTarget =>
      routineMinutesTarget > 0 && routineMinutesDone >= routineMinutesTarget;
}

/// Counts up today, from the tasks as they stand and the day's real activity.
TodayProgress summariseToday({
  required List<StudyTask> tasks,
  required int recommendedStudyMinutes,
  required int questionsAnsweredToday,
}) {
  final done = tasks.where((t) => t.isCompleted).toList();
  return TodayProgress(
    tasksDone: done.length,
    tasksTotal: tasks.length,
    routineMinutesDone: done.fold<int>(0, (sum, t) => sum + t.estimatedMinutes),
    routineMinutesTarget: recommendedStudyMinutes,
    questionsAnswered: questionsAnsweredToday,
  );
}
