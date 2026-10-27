import '../../../../core/database/tables/weak_topics_table.dart';

class TopicItem {
  final int id;
  final String subject;
  final String topicName;
  final ProficiencyLevel proficiencyLevel;
  final DateTime? lastReviewedAt;
  final String? notes;
  final DateTime createdAt;

  TopicItem({
    required this.id,
    required this.subject,
    required this.topicName,
    required this.proficiencyLevel,
    this.lastReviewedAt,
    this.notes,
    required this.createdAt,
  });

  TopicItem copyWith({
    int? id,
    String? subject,
    String? topicName,
    ProficiencyLevel? proficiencyLevel,
    DateTime? lastReviewedAt,
    String? notes,
    DateTime? createdAt,
  }) {
    return TopicItem(
      id: id ?? this.id,
      subject: subject ?? this.subject,
      topicName: topicName ?? this.topicName,
      proficiencyLevel: proficiencyLevel ?? this.proficiencyLevel,
      lastReviewedAt: lastReviewedAt ?? this.lastReviewedAt,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
