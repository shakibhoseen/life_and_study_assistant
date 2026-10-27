import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/database/tables/weak_topics_table.dart';
import '../../data/repositories/topics_repository_impl.dart';
import '../../domain/repositories/topics_repository.dart';

final topicsRepositoryProvider = Provider<TopicsRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return TopicsRepositoryImpl(db);
});

final weakTopicsStreamProvider = StreamProvider<List<WeakTopic>>((ref) {
  final repo = ref.watch(topicsRepositoryProvider);
  return repo.watchAllTopics();
});

class TopicsNotifier extends Notifier<void> {
  @override
  void build() {}

  Future<void> addTopic({
    required String subject,
    required String topicName,
    required ProficiencyLevel proficiencyLevel,
    String? notes,
  }) async {
    final repo = ref.read(topicsRepositoryProvider);
    await repo.addTopic(
      subject: subject,
      topicName: topicName,
      proficiencyLevel: proficiencyLevel,
      notes: notes,
    );
  }

  Future<void> updateProficiency(int id, ProficiencyLevel level) async {
    final repo = ref.read(topicsRepositoryProvider);
    await repo.updateTopicProficiency(id: id, level: level);
  }

  Future<void> markReviewed(int id) async {
    final repo = ref.read(topicsRepositoryProvider);
    await repo.markReviewed(id);
  }

  Future<void> deleteTopic(int id) async {
    final repo = ref.read(topicsRepositoryProvider);
    await repo.deleteTopic(id);
  }
}

final topicsNotifierProvider = NotifierProvider<TopicsNotifier, void>(() {
  return TopicsNotifier();
});
