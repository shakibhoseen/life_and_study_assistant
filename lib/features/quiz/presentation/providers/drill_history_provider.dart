import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';

final drillHistoryStreamProvider = StreamProvider<List<DrillRecord>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.watchAllDrillRecords();
});

final wrongQuestionsStreamProvider = StreamProvider<List<DrillQuestion>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.watchWrongDrillQuestions();
});

final allMistakesStreamProvider = StreamProvider<List<DrillQuestion>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.watchAllMistakeQuestions();
});

final allDrillQuestionsStreamProvider = StreamProvider<List<DrillQuestion>>((
  ref,
) {
  final db = ref.watch(appDatabaseProvider);
  return db.watchAllDrillQuestions();
});

final drillStatsStreamProvider = StreamProvider<Map<String, dynamic>>((
  ref,
) async* {
  final db = ref.watch(appDatabaseProvider);
  // Re-emit stats whenever drill questions or records change
  await for (final _ in db.watchAllDrillQuestions()) {
    yield await db.getDrillStats();
  }
});

class DrillHistoryNotifier extends Notifier<void> {
  @override
  void build() {}

  Future<int> saveDrillSession({
    required String subject,
    required String topic,
    required int totalQuestions,
    required int correctCount,
    required int incorrectCount,
    required double scorePercentage,
    required List<DrillQuestionsCompanion> questions,
  }) async {
    final db = ref.read(appDatabaseProvider);
    return db.recordFullDrillSession(
      subject: subject,
      topic: topic,
      totalQuestions: totalQuestions,
      correctCount: correctCount,
      incorrectCount: incorrectCount,
      scorePercentage: scorePercentage,
      questions: questions,
    );
  }

  Future<void> markQuestionMastered(int id, bool mastered) async {
    final db = ref.read(appDatabaseProvider);
    await db.markQuestionMastered(id, mastered);
  }

  Future<void> deleteQuestion(int id) async {
    final db = ref.read(appDatabaseProvider);
    await db.deleteDrillQuestion(id);
  }
}

final drillHistoryNotifierProvider =
    NotifierProvider<DrillHistoryNotifier, void>(() {
      return DrillHistoryNotifier();
    });
