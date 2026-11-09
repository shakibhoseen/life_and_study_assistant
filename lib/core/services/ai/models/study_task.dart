import 'dart:convert';

import 'package:crypto/crypto.dart';

/// One micro-commitment on the day's plan.
class StudyTask {
  final String id;
  final String title;
  final String subject;
  final int estimatedMinutes;
  final String taskType; // micro_mcq, quick_rule, formula_drill, concept_skim
  final String actionablePrompt;
  bool isCompleted;

  StudyTask({
    required this.id,
    required this.title,
    required this.subject,
    required this.estimatedMinutes,
    required this.taskType,
    required this.actionablePrompt,
    this.isCompleted = false,
  });

  /// [index] is the task's place in the plan, used only to tell two otherwise
  /// identical tasks apart when the model gives neither of them an id.
  factory StudyTask.fromJson(Map<String, dynamic> json, {int index = 0}) {
    return StudyTask(
      id: idFor(json, index),
      title: json['title'] as String? ?? 'Micro Study Task',
      subject: json['subject'] as String? ?? 'General',
      estimatedMinutes: (json['estimatedMinutes'] as num?)?.toInt() ?? 10,
      taskType: json['taskType'] as String? ?? 'micro_mcq',
      actionablePrompt: json['actionablePrompt'] as String? ?? '',
      isCompleted: json['isCompleted'] as bool? ?? false,
    );
  }

  /// A task's id, which has to be the same every time the same plan is read.
  ///
  /// It used to fall back to `DateTime.now().millisecondsSinceEpoch` when the
  /// model gave no id — a new id at every parse. The day's plan is re-read from
  /// the cache on every rebuild, so those ids changed constantly and nothing
  /// keyed on them could survive; ticking a task off and coming back found a
  /// task the app had never heard of. Derived from what the task *is*, the
  /// same plan gives the same ids for as long as it says the same thing.
  static String idFor(Map<String, dynamic> json, int index) {
    final given = json['id']?.toString().trim() ?? '';
    if (given.isNotEmpty) return given;

    final seed = [
      json['title']?.toString().trim() ?? '',
      json['subject']?.toString().trim() ?? '',
      json['taskType']?.toString().trim() ?? '',
      '$index',
    ].join('|');
    final digest = sha256.convert(utf8.encode(seed)).toString();
    return 'task_${digest.substring(0, 12)}';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'subject': subject,
    'estimatedMinutes': estimatedMinutes,
    'taskType': taskType,
    'actionablePrompt': actionablePrompt,
    'isCompleted': isCompleted,
  };

  StudyTask copyWith({
    String? id,
    String? title,
    String? subject,
    int? estimatedMinutes,
    String? taskType,
    String? actionablePrompt,
    bool? isCompleted,
  }) {
    return StudyTask(
      id: id ?? this.id,
      title: title ?? this.title,
      subject: subject ?? this.subject,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      taskType: taskType ?? this.taskType,
      actionablePrompt: actionablePrompt ?? this.actionablePrompt,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}
