class ExamScheduleItem {
  final int id;
  final DateTime examDate;
  final String title;
  final String topicsCovered;
  final String? resourceSummary;
  final bool completedStatus;
  final double? score;
  final DateTime createdAt;

  ExamScheduleItem({
    required this.id,
    required this.examDate,
    required this.title,
    required this.topicsCovered,
    this.resourceSummary,
    this.completedStatus = false,
    this.score,
    required this.createdAt,
  });
}
