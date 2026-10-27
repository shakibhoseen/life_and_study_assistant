import '../../../../core/database/app_database.dart';

abstract class ExamScheduleRepository {
  Stream<List<ExamSchedule>> watchUpcomingExams();
  Stream<List<ExamSchedule>> watchAllExams();
  Stream<List<ExamSchedule>> watchExamsByTrack(String track);
  Stream<List<String>> watchAllDistinctTracks();
  Future<List<ExamSchedule>> getUpcomingExams();

  /// Exams narrowed for an AI prompt: the next few only, so a bulk-imported
  /// routine cannot flood the request.
  Future<List<ExamSchedule>> getContextUpcomingExams({
    int limit,
    int withinDays,
  });
  Future<int> addExam({
    required DateTime examDate,
    required String title,
    required String topicsCovered,
    String? resourceSummary,
    String trackName = 'General BCS',
  });
  Future<bool> markExamCompleted(int id, {double? score});
  Future<bool> markExamIncomplete(int id);
  Future<int> deleteExam(int id);
}
