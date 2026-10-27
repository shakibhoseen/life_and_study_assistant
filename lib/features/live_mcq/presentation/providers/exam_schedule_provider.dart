import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../data/repositories/exam_schedule_repository_impl.dart';
import '../../domain/repositories/exam_schedule_repository.dart';

final examScheduleRepositoryProvider = Provider<ExamScheduleRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return ExamScheduleRepositoryImpl(db);
});

final upcomingExamsStreamProvider = StreamProvider<List<ExamSchedule>>((ref) {
  final repo = ref.watch(examScheduleRepositoryProvider);
  return repo.watchUpcomingExams();
});

final allExamsStreamProvider = StreamProvider<List<ExamSchedule>>((ref) {
  final repo = ref.watch(examScheduleRepositoryProvider);
  return repo.watchAllExams();
});

/// Currently selected track filter ('All' means all programs/routines)
class SelectedTrackNotifier extends Notifier<String> {
  @override
  String build() => 'All';

  void setTrack(String track) {
    state = track;
  }
}

final selectedTrackProvider = NotifierProvider<SelectedTrackNotifier, String>(
  () {
    return SelectedTrackNotifier();
  },
);

enum ExamTimelineFilter {
  upcoming, // Next & Upcoming (Today + Future) - DEFAULT
  past, // Past & Passed exams (yesterday, 2 days ago...)
  completed, // Marked as done
  all, // All exams grouped
}

class ExamTimelineFilterNotifier extends Notifier<ExamTimelineFilter> {
  @override
  ExamTimelineFilter build() => ExamTimelineFilter.upcoming;

  void setFilter(ExamTimelineFilter filter) {
    state = filter;
  }
}

final examTimelineFilterProvider =
    NotifierProvider<ExamTimelineFilterNotifier, ExamTimelineFilter>(() {
      return ExamTimelineFilterNotifier();
    });

class ExamSearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String q) {
    state = q;
  }
}

final examSearchQueryProvider =
    NotifierProvider<ExamSearchQueryNotifier, String>(() {
      return ExamSearchQueryNotifier();
    });

/// Stream of all distinct track names present in the database
final distinctTracksStreamProvider = StreamProvider<List<String>>((ref) {
  final repo = ref.watch(examScheduleRepositoryProvider);
  return repo.watchAllDistinctTracks();
});

/// Stream of exams filtered by the selected track
final filteredExamsStreamProvider = StreamProvider<List<ExamSchedule>>((ref) {
  final repo = ref.watch(examScheduleRepositoryProvider);
  final selectedTrack = ref.watch(selectedTrackProvider);
  if (selectedTrack == 'All') {
    return repo.watchAllExams();
  } else {
    return repo.watchExamsByTrack(selectedTrack);
  }
});

class ExamScheduleNotifier extends Notifier<void> {
  @override
  void build() {}

  Future<void> addExam({
    required DateTime examDate,
    required String title,
    required String topicsCovered,
    String? resourceSummary,
    String trackName = 'General BCS',
  }) async {
    final repo = ref.read(examScheduleRepositoryProvider);
    await repo.addExam(
      examDate: examDate,
      title: title,
      topicsCovered: topicsCovered,
      resourceSummary: resourceSummary,
      trackName: trackName,
    );
  }

  Future<void> markCompleted(int id, {double? score}) async {
    final repo = ref.read(examScheduleRepositoryProvider);
    await repo.markExamCompleted(id, score: score);
  }

  Future<void> markIncomplete(int id) async {
    final repo = ref.read(examScheduleRepositoryProvider);
    await repo.markExamIncomplete(id);
  }

  Future<void> deleteExam(int id) async {
    final repo = ref.read(examScheduleRepositoryProvider);
    await repo.deleteExam(id);
  }
}

final examScheduleNotifierProvider =
    NotifierProvider<ExamScheduleNotifier, void>(() {
      return ExamScheduleNotifier();
    });
