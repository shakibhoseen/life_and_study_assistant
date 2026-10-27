import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/tables/weak_topics_table.dart';
import '../../domain/repositories/topics_repository.dart';

class TopicsRepositoryImpl implements TopicsRepository {
  final AppDatabase _db;

  TopicsRepositoryImpl(this._db);

  @override
  Stream<List<WeakTopic>> watchAllTopics() => _db.watchAllWeakTopics();

  @override
  Future<List<WeakTopic>> getAllTopics() => _db.getAllWeakTopics();

  @override
  Future<List<WeakTopic>> getContextTopics({int limit = 12}) =>
      _db.getContextWeakTopics(limit: limit);

  @override
  Future<int> addTopic({
    required String subject,
    required String topicName,
    required ProficiencyLevel proficiencyLevel,
    String? notes,
  }) {
    return _db.insertWeakTopic(
      WeakTopicsCompanion.insert(
        subject: subject,
        topicName: topicName,
        proficiencyLevel: proficiencyLevel,
        notes: Value(notes),
      ),
    );
  }

  @override
  Future<bool> updateTopicProficiency({
    required int id,
    required ProficiencyLevel level,
  }) async {
    final existing = await (_db.select(
      _db.weakTopics,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (existing == null) return false;
    return _db.updateWeakTopic(existing.copyWith(proficiencyLevel: level));
  }

  @override
  Future<bool> markReviewed(int id) async {
    final existing = await (_db.select(
      _db.weakTopics,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (existing == null) return false;
    return _db.updateWeakTopic(
      existing.copyWith(lastReviewedAt: Value(DateTime.now())),
    );
  }

  @override
  Future<int> deleteTopic(int id) => _db.deleteWeakTopic(id);
}
