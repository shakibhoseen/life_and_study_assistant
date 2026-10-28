import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/repositories/exam_schedule_repository.dart';

class ExamScheduleRepositoryImpl implements ExamScheduleRepository {
  final AppDatabase _db;

  ExamScheduleRepositoryImpl(this._db);

  @override
  Stream<List<ExamSchedule>> watchUpcomingExams() => _db.watchUpcomingExams();

  @override
  Stream<List<ExamSchedule>> watchAllExams() => _db.watchAllExams();

  @override
  Stream<List<ExamSchedule>> watchExamsByTrack(String track) =>
      _db.watchExamsByTrack(track);

  @override
  Stream<List<String>> watchAllDistinctTracks() => _db.watchAllDistinctTracks();

  @override
  Future<List<ExamSchedule>> getUpcomingExams() => _db.getUpcomingExams();

  @override
  Future<List<ExamSchedule>> getContextUpcomingExams({
    int limit = 8,
    int withinDays = 30,
  }) => _db.getContextUpcomingExams(limit: limit, withinDays: withinDays);

  @override
  Future<int> addExam({
    required DateTime examDate,
    required String title,
    required String topicsCovered,
    String? resourceSummary,
    String trackName = 'General BCS',
    String? rawReference,
  }) {
    return _db.insertExamSchedule(
      ExamSchedulesCompanion.insert(
        examDate: examDate,
        title: title,
        topicsCovered: topicsCovered,
        resourceSummary: Value(resourceSummary),
        trackName: Value(trackName),
        rawReference: Value(rawReference),
      ),
    );
  }

  @override
  Future<bool> markExamCompleted(int id, {double? score}) async {
    final existing = await (_db.select(
      _db.examSchedules,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (existing == null) return false;
    return _db.updateExamSchedule(
      existing.copyWith(completedStatus: true, score: Value(score)),
    );
  }

  @override
  Future<bool> markExamIncomplete(int id) async {
    final existing = await (_db.select(
      _db.examSchedules,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (existing == null) return false;
    return _db.updateExamSchedule(
      existing.copyWith(completedStatus: false, score: const Value(null)),
    );
  }

  @override
  Future<bool> updateExamTrack(int id, String newTrack) async {
    final existing = await (_db.select(
      _db.examSchedules,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (existing == null) return false;
    return _db.updateExamSchedule(existing.copyWith(trackName: newTrack));
  }

  @override
  Future<int> deleteExam(int id) => _db.deleteExamSchedule(id);

  @override
  Future<int> deleteExamsByTrack(String trackName) =>
      _db.deleteExamsByTrack(trackName);
}
