import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/tables/daily_energy_logs_table.dart';
import '../../../../core/services/ai/gemini_ai_service.dart';
import '../../../../core/services/ai/models/adaptive_study_plan.dart';
import '../../../energy_log/presentation/providers/energy_log_provider.dart';
import '../../../live_mcq/presentation/providers/exam_schedule_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../topics/presentation/providers/topics_provider.dart';

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

      state = AsyncValue.data(plan);
      return plan;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  void toggleTaskCompletion(String taskId) {
    final currentPlan = state.value;
    if (currentPlan == null) return;

    final updatedTasks = currentPlan.tasks.map((task) {
      if (task.id == taskId) {
        return task.copyWith(isCompleted: !task.isCompleted);
      }
      return task;
    }).toList();

    final updatedPlan = AdaptiveStudyPlan(
      date: currentPlan.date,
      energyLevel: currentPlan.energyLevel,
      fatigueScore: currentPlan.fatigueScore,
      motivationalQuote: currentPlan.motivationalQuote,
      summary: currentPlan.summary,
      recommendedStudyMinutes: currentPlan.recommendedStudyMinutes,
      recommendedFamilyMinutes: currentPlan.recommendedFamilyMinutes,
      tasks: updatedTasks,
      familyAndWellbeingAdvice: currentPlan.familyAndWellbeingAdvice,
      burnoutWarning: currentPlan.burnoutWarning,
    );

    state = AsyncValue.data(updatedPlan);
  }
}

final adaptivePlannerProvider =
    AsyncNotifierProvider<AdaptivePlannerNotifier, AdaptiveStudyPlan?>(() {
      return AdaptivePlannerNotifier();
    });
