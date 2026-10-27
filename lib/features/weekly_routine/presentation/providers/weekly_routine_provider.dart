import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_provider.dart';
import '../../../../core/services/ai/weekly_routine_service.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../domain/models/weekly_routine.dart';

/// Key the routine lives under in app_settings. It is one document edited as
/// a whole, so a row per field would buy nothing.
const String kWeeklyRoutineKey = 'weekly_routine';

/// The routine as stored, falling back to the default until something is
/// saved over it.
final weeklyRoutineProvider = StreamProvider<WeeklyRoutine>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db
      .watchSetting(kWeeklyRoutineKey)
      .map(
        (raw) => WeeklyRoutine.tryDecode(raw) ?? WeeklyRoutine.defaultRoutine,
      );
});

class WeeklyRoutineState {
  final bool isRevising;
  final String? errorMessage;

  const WeeklyRoutineState({this.isRevising = false, this.errorMessage});
}

class WeeklyRoutineNotifier extends Notifier<WeeklyRoutineState> {
  @override
  WeeklyRoutineState build() => const WeeklyRoutineState();

  /// Hands the user's instruction and the current routine to the model, and
  /// saves whatever comes back.
  ///
  /// A failed revision leaves the stored routine untouched: a half-written
  /// week is worse than yesterday's.
  Future<bool> applyCommand(String command) async {
    final trimmed = command.trim();
    if (trimmed.isEmpty || state.isRevising) return false;

    state = const WeeklyRoutineState(isRevising: true);
    final db = ref.read(appDatabaseProvider);

    try {
      final current =
          WeeklyRoutine.tryDecode(await db.getSetting(kWeeklyRoutineKey)) ??
          WeeklyRoutine.defaultRoutine;

      // The model should plan around what the user is actually weak at and
      // what is actually coming up, not a generic exam calendar.
      final weakTopics = (await db.getContextWeakTopics())
          .map(
            (t) => {
              'subject': t.subject,
              'topic': t.topicName,
              'proficiency': t.proficiencyLevel.name,
            },
          )
          .toList();

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final exams = (await db.getContextUpcomingExams(limit: 8, withinDays: 21))
          .map(
            (e) => {
              'title': e.title,
              'track': e.trackName,
              'daysAway': DateTime(
                e.examDate.year,
                e.examDate.month,
                e.examDate.day,
              ).difference(todayStart).inDays,
              'topics': e.topicsCovered.length > 100
                  ? '${e.topicsCovered.substring(0, 100)}…'
                  : e.topicsCovered,
            },
          )
          .toList();

      // Off days are a user setting, not a constant: the routine has to
      // follow whatever two days they actually have.
      final settings = await ref.read(settingsNotifierProvider.future);

      final revised = await WeeklyRoutineService.instance.revise(
        current: current,
        command: trimmed,
        weakTopics: weakTopics,
        upcomingExams: exams,
        offDays: _bengaliDays(settings.offDays),
      );

      if (revised == null) {
        state = const WeeklyRoutineState(
          errorMessage: 'ছক বদলানো গেল না। API key বা ইন্টারনেট দেখুন।',
        );
        return false;
      }

      await db.setSetting(kWeeklyRoutineKey, revised.encode());
      state = const WeeklyRoutineState();
      return true;
    } catch (e) {
      state = WeeklyRoutineState(errorMessage: 'ছক বদলানো গেল না: $e');
      return false;
    }
  }

  /// DateTime weekday integers as the names the routine is written in.
  static String _bengaliDays(List<int> weekdays) {
    const names = {
      DateTime.monday: 'সোম',
      DateTime.tuesday: 'মঙ্গল',
      DateTime.wednesday: 'বুধ',
      DateTime.thursday: 'বৃহস্পতি',
      DateTime.friday: 'শুক্র',
      DateTime.saturday: 'শনি',
      DateTime.sunday: 'রবি',
    };
    final mapped = weekdays.map((d) => names[d]).whereType<String>().toList();
    return mapped.isEmpty ? 'বৃহস্পতি, শুক্র' : mapped.join(', ');
  }

  /// Puts the starting routine back, for when a few edits have wandered.
  Future<void> resetToDefault() async {
    final db = ref.read(appDatabaseProvider);
    await db.setSetting(
      kWeeklyRoutineKey,
      WeeklyRoutine.defaultRoutine.copyWith(updatedAt: DateTime.now()).encode(),
    );
    state = const WeeklyRoutineState();
  }
}

final weeklyRoutineNotifierProvider =
    NotifierProvider<WeeklyRoutineNotifier, WeeklyRoutineState>(
      WeeklyRoutineNotifier.new,
    );
