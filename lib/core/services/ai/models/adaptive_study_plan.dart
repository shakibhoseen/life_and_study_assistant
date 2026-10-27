import 'dart:convert';

import 'study_task.dart';

class AdaptiveStudyPlan {
  final String date;
  final String energyLevel; // High, Medium, Low
  final int fatigueScore; // 1-10
  final String motivationalQuote;
  final String summary;
  final int recommendedStudyMinutes;
  final int recommendedFamilyMinutes;
  final List<StudyTask> tasks;
  final String familyAndWellbeingAdvice;
  final String? burnoutWarning;

  AdaptiveStudyPlan({
    required this.date,
    required this.energyLevel,
    required this.fatigueScore,
    required this.motivationalQuote,
    required this.summary,
    required this.recommendedStudyMinutes,
    required this.recommendedFamilyMinutes,
    required this.tasks,
    required this.familyAndWellbeingAdvice,
    this.burnoutWarning,
  });

  factory AdaptiveStudyPlan.fromJson(Map<String, dynamic> json) {
    var rawTasks = json['tasks'];
    List<StudyTask> parsedTasks = [];
    if (rawTasks is List) {
      parsedTasks = rawTasks
          .map((item) => StudyTask.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    return AdaptiveStudyPlan(
      date:
          json['date'] as String? ??
          DateTime.now().toIso8601String().substring(0, 10),
      energyLevel: json['energyLevel'] as String? ?? 'Medium',
      fatigueScore: (json['fatigueScore'] as num?)?.toInt() ?? 5,
      motivationalQuote:
          json['motivationalQuote'] as String? ??
          'Small consistent steps lead to great achievements.',
      summary: json['summary'] as String? ?? 'Today’s customized study plan.',
      recommendedStudyMinutes:
          (json['recommendedStudyMinutes'] as num?)?.toInt() ?? 20,
      recommendedFamilyMinutes:
          (json['recommendedFamilyMinutes'] as num?)?.toInt() ?? 45,
      tasks: parsedTasks,
      familyAndWellbeingAdvice:
          json['familyAndWellbeingAdvice'] as String? ??
          'Ensure quality time with family to recharge your mental battery.',
      burnoutWarning: json['burnoutWarning'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'date': date,
    'energyLevel': energyLevel,
    'fatigueScore': fatigueScore,
    'motivationalQuote': motivationalQuote,
    'summary': summary,
    'recommendedStudyMinutes': recommendedStudyMinutes,
    'recommendedFamilyMinutes': recommendedFamilyMinutes,
    'tasks': tasks.map((t) => t.toJson()).toList(),
    'familyAndWellbeingAdvice': familyAndWellbeingAdvice,
    'burnoutWarning': burnoutWarning,
  };

  String toJsonString() => jsonEncode(toJson());

  static AdaptiveStudyPlan? fromJsonString(String jsonString) {
    try {
      final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
      return AdaptiveStudyPlan.fromJson(decoded);
    } catch (e) {
      return null;
    }
  }
}
