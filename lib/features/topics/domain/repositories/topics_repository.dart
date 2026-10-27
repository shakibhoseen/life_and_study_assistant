import '../../../../core/database/app_database.dart';
import '../../../../core/database/tables/weak_topics_table.dart';

abstract class TopicsRepository {
  Stream<List<WeakTopic>> watchAllTopics();
  Future<List<WeakTopic>> getAllTopics();

  /// Topics narrowed for an AI prompt: still-weak ones only, capped.
  Future<List<WeakTopic>> getContextTopics({int limit});
  Future<int> addTopic({
    required String subject,
    required String topicName,
    required ProficiencyLevel proficiencyLevel,
    String? notes,
  });
  Future<bool> updateTopicProficiency({
    required int id,
    required ProficiencyLevel level,
  });
  Future<bool> markReviewed(int id);
  Future<int> deleteTopic(int id);
}
