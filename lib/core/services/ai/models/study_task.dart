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

  factory StudyTask.fromJson(Map<String, dynamic> json) {
    return StudyTask(
      id:
          json['id']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      title: json['title'] as String? ?? 'Micro Study Task',
      subject: json['subject'] as String? ?? 'General',
      estimatedMinutes: (json['estimatedMinutes'] as num?)?.toInt() ?? 10,
      taskType: json['taskType'] as String? ?? 'micro_mcq',
      actionablePrompt: json['actionablePrompt'] as String? ?? '',
      isCompleted: json['isCompleted'] as bool? ?? false,
    );
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
