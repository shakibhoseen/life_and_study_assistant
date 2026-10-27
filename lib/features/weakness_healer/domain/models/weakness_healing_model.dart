import '../../../../core/database/app_database.dart';
import '../../../../core/database/tables/weak_topics_table.dart';

class WeaknessHealthSummary {
  final int totalTopics;
  final int healedCount;
  final int moderateCount;
  final int weakCount;
  final double healthPercentage;
  final WeakTopic? primaryFocusTopic;
  final int matchingMistakesCount;

  const WeaknessHealthSummary({
    required this.totalTopics,
    required this.healedCount,
    required this.moderateCount,
    required this.weakCount,
    required this.healthPercentage,
    this.primaryFocusTopic,
    required this.matchingMistakesCount,
  });

  bool get hasWeaknessToHeal =>
      totalTopics > 0 && (weakCount > 0 || moderateCount > 0);
}

WeaknessHealthSummary calculateWeaknessHealth({
  required List<WeakTopic> topics,
  required List<DrillQuestion> unmasteredMistakes,
}) {
  if (topics.isEmpty) {
    return const WeaknessHealthSummary(
      totalTopics: 0,
      healedCount: 0,
      moderateCount: 0,
      weakCount: 0,
      healthPercentage: 100.0,
      primaryFocusTopic: null,
      matchingMistakesCount: 0,
    );
  }

  int healed = 0;
  int moderate = 0;
  int weak = 0;

  for (final t in topics) {
    if (t.proficiencyLevel == ProficiencyLevel.strong) {
      healed++;
    } else if (t.proficiencyLevel == ProficiencyLevel.moderate) {
      moderate++;
    } else {
      weak++;
    }
  }

  // Health calculation: strong = 1.0, moderate = 0.5, weak = 0.0
  final double scorePoints = (healed * 1.0) + (moderate * 0.5);
  final double percentage = ((scorePoints / topics.length) * 100.0).clamp(
    0.0,
    100.0,
  );

  // Find the primary focus topic:
  // 1. Weakest first
  // 2. Least recently reviewed first
  late final WeakTopic focusTopic;
  final weakList = topics
      .where((t) => t.proficiencyLevel == ProficiencyLevel.weak)
      .toList();
  if (weakList.isNotEmpty) {
    weakList.sort((a, b) {
      if (a.lastReviewedAt == null && b.lastReviewedAt != null) return -1;
      if (a.lastReviewedAt != null && b.lastReviewedAt == null) return 1;
      if (a.lastReviewedAt == null && b.lastReviewedAt == null) return 0;
      return a.lastReviewedAt!.compareTo(b.lastReviewedAt!);
    });
    focusTopic = weakList.first;
  } else {
    final moderateList = topics
        .where((t) => t.proficiencyLevel == ProficiencyLevel.moderate)
        .toList();
    if (moderateList.isNotEmpty) {
      moderateList.sort((a, b) {
        if (a.lastReviewedAt == null && b.lastReviewedAt != null) return -1;
        if (a.lastReviewedAt != null && b.lastReviewedAt == null) return 1;
        if (a.lastReviewedAt == null && b.lastReviewedAt == null) return 0;
        return a.lastReviewedAt!.compareTo(b.lastReviewedAt!);
      });
      focusTopic = moderateList.first;
    } else {
      focusTopic = topics.first;
    }
  }

  // Count matching unmastered mistakes for this focus topic
  final focusSubjectLower = focusTopic.subject.toLowerCase();
  final focusTopicLower = focusTopic.topicName.toLowerCase();
  final matchingMistakes = unmasteredMistakes.where((m) {
    return m.subject.toLowerCase().contains(focusSubjectLower) ||
        m.topic.toLowerCase().contains(focusTopicLower) ||
        focusTopicLower.contains(m.topic.toLowerCase());
  }).length;

  return WeaknessHealthSummary(
    totalTopics: topics.length,
    healedCount: healed,
    moderateCount: moderate,
    weakCount: weak,
    healthPercentage: percentage,
    primaryFocusTopic: focusTopic,
    matchingMistakesCount: matchingMistakes,
  );
}
