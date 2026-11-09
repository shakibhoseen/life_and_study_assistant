import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/tables/daily_energy_logs_table.dart';
import '../../../../core/services/ai/gemini_ai_service.dart';
import '../../../../core/services/ai/models/adaptive_study_plan.dart';
import '../../../../core/services/ai/models/study_task.dart';
import '../../../energy_log/presentation/providers/energy_log_provider.dart';
import '../../../live_mcq/presentation/providers/exam_schedule_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../topics/presentation/providers/topics_provider.dart';
import '../../domain/study_task_completions.dart';

class AdaptivePlannerNotifier extends AsyncNotifier<AdaptiveStudyPlan?> {
  @override
  Future<AdaptiveStudyPlan?> build() async {
    return generatePlan();
  }

  Future<AdaptiveStudyPlan?> generatePlan({
    EnergyLevel? overrideEnergy,
    int? overrideFatigue,
  }) async {
    state = const AsyncValue.loading();
    try {
      final topicsRepo = ref.read(topicsRepositoryProvider);
      final examsRepo = ref.read(examScheduleRepositoryProvider);
      final energyRepo = ref.read(energyLogRepositoryProvider);

      // Capped: a bulk-imported routine holds hundreds of future exams, and
      // sending all of them made one plan request the most expensive call in
      // the app. A day's plan needs the near horizon, not the whole syllabus.
      final weakTopics = await topicsRepo.getContextTopics();
      final upcomingExams = await examsRepo.getContextUpcomingExams();
      final todayLog = await energyRepo.getTodayLog();
      final settings = await ref.read(settingsNotifierProvider.future);

      final energy =
          overrideEnergy ?? todayLog?.energyLevel ?? EnergyLevel.medium;
      final fatigue = overrideFatigue ?? todayLog?.officeFatigueScore ?? 5;
      final isOffDay = settings.isTodayOffDay;

      final plan = await GeminiAiService.instance.generateAdaptivePlan(
        energyLevel: energy.name,
        fatigueScore: fatigue,
        weakTopics: weakTopics,
        upcomingExams: upcomingExams,
        isOffDay: isOffDay,
      );

      // The plan arrives from the model (usually from the day's cache) with
      // every task unfinished, because that is what the model wrote. What the
      // user has actually ticked off lives separately and is laid over the
      // top, or the tick disappears on every rebuild.
      final restored = await _withCompletions(plan);
      state = AsyncValue.data(restored);
      return restored;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  /// Marks a task finished, and keeps it that way.
  ///
  /// Separate from [toggleTaskCompletion] because the focus timer wants to
  /// finish a task, not flip it: running the timer on something already ticked
  /// off used to untick it.
  Future<void> markTaskCompleted(String taskId) =>
      _setTaskCompletion(taskId, done: true);

  /// Flips a task, for the checkbox the user taps themselves.
  Future<void> toggleTaskCompletion(String taskId) {
    final current = state.value?.tasks
        .where((t) => t.id == taskId)
        .firstOrNull;
    return _setTaskCompletion(taskId, done: !(current?.isCompleted ?? false));
  }

  Future<AdaptiveStudyPlan?> _withCompletions(AdaptiveStudyPlan? plan) async {
    if (plan == null) return null;
    final done = await StudyTaskCompletions.instance.load(
      StudyTaskCompletions.today(),
    );
    if (done.isEmpty) return plan;
    return _planWithTasks(
      plan,
      plan.tasks
          .map((t) => t.copyWith(isCompleted: done.contains(t.id)))
          .toList(),
    );
  }

  Future<void> _setTaskCompletion(String taskId, {required bool done}) async {
    final currentPlan = state.value;
    if (currentPlan == null) return;

    // Written before the screen is told, so a rebuild between the two cannot
    // show a tick the storage does not know about.
    await StudyTaskCompletions.instance.setCompleted(
      StudyTaskCompletions.today(),
      taskId,
      done: done,
    );

    final updatedTasks = currentPlan.tasks.map((task) {
      if (task.id == taskId) {
        return task.copyWith(isCompleted: done);
      }
      return task;
    }).toList();

    state = AsyncValue.data(_planWithTasks(currentPlan, updatedTasks));
  }

  /// The same plan with a different task list. Written out by hand because
  /// AdaptiveStudyPlan has no copyWith.
  AdaptiveStudyPlan _planWithTasks(
    AdaptiveStudyPlan plan,
    List<StudyTask> tasks,
  ) {
    return AdaptiveStudyPlan(
      date: plan.date,
      energyLevel: plan.energyLevel,
      fatigueScore: plan.fatigueScore,
      motivationalQuote: plan.motivationalQuote,
      summary: plan.summary,
      recommendedStudyMinutes: plan.recommendedStudyMinutes,
      recommendedFamilyMinutes: plan.recommendedFamilyMinutes,
      tasks: tasks,
      familyAndWellbeingAdvice: plan.familyAndWellbeingAdvice,
      burnoutWarning: plan.burnoutWarning,
    );
  }
}

final adaptivePlannerProvider =
    AsyncNotifierProvider<AdaptivePlannerNotifier, AdaptiveStudyPlan?>(() {
      return AdaptivePlannerNotifier();
    });
