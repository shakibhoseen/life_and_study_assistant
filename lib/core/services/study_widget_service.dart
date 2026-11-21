import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/app_database.dart';
import '../utils/bengali_math_sanitizer.dart';
import 'background/workmanager_service.dart';

/// What the three study home screen widgets show.
///
/// The widgets themselves read SharedPreferences and nothing else — the native
/// side cannot open the drift database, and a background isolate that did
/// would be contending with the app for the same file. So this collects
/// everything in Dart and leaves it in prefs for the widget to render.
///
/// That has a consequence worth being honest about: pressing refresh on a
/// study widget while the app is closed repaints what was last collected. It
/// recomputes only when the app is running. Study figures move when the user
/// drills, which they do inside the app, so the snapshot is taken on launch
/// and after each drill is recorded.
class StudyWidgetService {
  static const MethodChannel _channel = MethodChannel(
    'com.shakib.life_and_study_assistant/system_settings',
  );

  // Widget 1: what needs attention today.
  // Stored as display text, already in Bengali numerals: the native widget
  // renders what it is given rather than re-deciding how numbers should look.
  static const String keyWrongCount = 'study_wrong_count_text';
  static const String keyDueCount = 'study_due_count_text';
  static const String keyAccuracy = 'study_accuracy_text';
  static const String keyWeakTopics = 'study_weak_topics';

  // Widget 2: the next exam.
  static const String keyExamTitle = 'study_exam_title';
  static const String keyExamSubject = 'study_exam_subject';
  static const String keyExamWhen = 'study_exam_when';
  static const String keyExamCountdown = 'study_exam_countdown';

  // Widget 3: a question to chew on.
  static const String keyQuestion = 'study_qotd_question';
  static const String keyOptions = 'study_qotd_options';
  static const String keyCorrectIndex = 'study_qotd_correct_index';
  static const String keyQotdDate = 'study_qotd_date';
  static const String keyQotdRevealed = 'study_qotd_revealed';
  static const String keyQotdQuestionId = 'study_qotd_question_id';
  // A short run of questions, so tapping "next" on the widget does not have
  // to wake the Flutter engine to fetch one.
  static const String keyQotdQueue = 'study_qotd_queue';
  static const String keyQotdCursor = 'study_qotd_cursor';

  static const String keySyncTime = 'study_widget_sync_time';

  static String bn(Object value) =>
      BengaliMathSanitizer.toBengaliDigits('$value');

  /// yyyy-MM-dd, the same shape the native side compares against.
  static String isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // --- wiring ------------------------------------------------------------

  static AppDatabase? _db;

  /// Where a widget tap wants to go, once the app is up.
  static final ValueNotifier<String?> pendingRoute = ValueNotifier(null);

  /// Hands the service the database and takes the first snapshot.
  ///
  /// Called from inside the widget tree rather than main(), because the
  /// database belongs to the provider scope — opening a second AppDatabase
  /// here would mean two connections to one file.
  static void attach(AppDatabase db) {
    _db = db;

    // Deliberately no setMethodCallHandler here. This is the same channel
    // HomeWidgetService uses, and setting a handler replaces whatever was
    // there — installing one here would silently stop the office widget's
    // refresh from ever reaching Dart. HomeWidgetService.init() owns the one
    // handler and routes the study calls back to handleNativeCall below.
    unawaited(refresh());
    unawaited(consumePendingRoute());
    // One job a day, so the countdown and the daily question turn over
    // without the app having to be opened.
    unawaited(WorkmanagerService.instance.scheduleDailyStudyRefresh());
  }

  /// The study half of the shared channel handler, called by
  /// [HomeWidgetService]. Returns true if the call was one of ours.
  static Future<bool> handleNativeCall(String method) async {
    switch (method) {
      case 'onStudyWidgetRefreshRequested':
        await refresh();
        return true;
      case 'onPendingRouteAvailable':
        await consumePendingRoute();
        return true;
    }
    return false;
  }

  /// Recollects the figures, if there is a database to read.
  static Future<void> refresh() async {
    final db = _db;
    if (db == null) return;
    await syncStudyData(db);
  }

  /// Asks the native side where a widget tap wanted to land.
  static Future<void> consumePendingRoute() async {
    try {
      final route = await _channel.invokeMethod<String>('consumePendingRoute');
      if (route != null && route.isNotEmpty) pendingRoute.value = route;
    } catch (e) {
      debugPrint('StudyWidget: could not read pending route: $e');
    }
  }

  // --- the decisions, kept pure so they can be tested ---------------------

  /// How many whole days until [examDate], counted in calendar days rather
  /// than elapsed hours.
  ///
  /// An exam at 10 PM tonight is "আজ", not "১ দিন বাকি" because 22 hours have
  /// not passed; an exam at 9 AM tomorrow is "১ দিন", not "আজ" because only
  /// 15 hours separate them. Hours are the wrong unit for a countdown someone
  /// reads off a home screen.
  static int daysUntil(DateTime examDate, DateTime now) {
    final exam = DateTime(examDate.year, examDate.month, examDate.day);
    final today = DateTime(now.year, now.month, now.day);
    return exam.difference(today).inDays;
  }

  /// "আজ", "আগামীকাল", "৩ দিন বাকি", or for one already gone, "আজ".
  static String countdownLabel(int daysLeft) {
    if (daysLeft <= 0) return 'আজ';
    if (daysLeft == 1) return 'আগামীকাল';
    return '${bn(daysLeft)} দিন বাকি';
  }

  /// The line under the counts: which topics are weakest, or encouragement
  /// when there is nothing to report.
  ///
  /// Empty is a real state — a new user, or someone who has cleared their
  /// bank — and a widget showing "দুর্বল: " with nothing after it looks
  /// broken rather than finished.
  static String weakTopicLine(List<String> topics, {int limit = 2}) {
    final named = topics
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .take(limit)
        .toList();
    if (named.isEmpty) return 'কোনো দুর্বল টপিক চিহ্নিত হয়নি';
    return 'দুর্বল: ${named.join(', ')}';
  }

  /// Strips a marker the option text already carries.
  ///
  /// Rows come from several places — typed in, parsed out of a question bank,
  /// returned by the AI — and some arrive as "ক. ২০%" while others are just
  /// "২০%". The widget puts its own "ক)" in front, so leaving the stored one
  /// renders "ক) ক. ২০%".
  @visibleForTesting
  static String stripOptionMarker(String option) {
    final trimmed = option.trim();
    // A single Bengali consonant, Latin letter or digit, then . ) : or ।
    // and a space. The range is ক-হ, the consonants: the Bengali vowels
    // sit *below* ক in Unicode, so a range starting at ক and ending at a
    // vowel is backwards and will not compile.
    final marker = RegExp(r'^([ক-হA-Ha-h০-৯0-9])\s*[.):।]\s+');
    final match = marker.firstMatch(trimmed);
    if (match == null) return trimmed;
    final rest = trimmed.substring(match.end).trim();
    // "ক." on its own is the whole answer, not a marker on something else.
    return rest.isEmpty ? trimmed : rest;
  }

  /// Which question to show today.
  ///
  /// Picked by the date so it is stable all day — a widget that showed a
  /// different question at every repaint would be unreadable — and moves on
  /// by itself tomorrow without anything having to schedule it.
  static int questionIndexForDay(int count, DateTime day) {
    if (count <= 0) return -1;
    final ordinal = DateTime(day.year, day.month, day.day)
        .difference(DateTime(2020, 1, 1))
        .inDays;
    return ordinal.remainder(count).abs();
  }

  /// Which question today's is, given what was chosen earlier today.
  ///
  /// [questionIndexForDay] alone is not stable within a day: it indexes into
  /// the mistake bank, and the bank changes size as soon as any drilling
  /// happens. Getting one question right could renumber the rest and swap the
  /// question on the home screen at eleven in the morning — mid-thought, for
  /// someone who had been looking at it.
  ///
  /// So the chosen one is held by id for the rest of the day. It only moves on
  /// when the day does, or when that question leaves the bank because it was
  /// finally learnt — in which case holding it would be worse.
  @visibleForTesting
  static int? dailyQuestionId({
    required List<int> bankIds,
    required int? heldId,
    required bool isSameDay,
    required DateTime day,
  }) {
    if (bankIds.isEmpty) return null;
    if (isSameDay && heldId != null && bankIds.contains(heldId)) {
      return heldId;
    }
    final index = questionIndexForDay(bankIds.length, day);
    return index < 0 ? null : bankIds[index];
  }

  /// Minutes past midnight for an exam time like "10:00 PM", or null if it
  /// cannot be read.
  ///
  /// examTime is free text on the row, not a stored time, so it arrives in
  /// whatever shape it was typed or imported in.
  @visibleForTesting
  static int? minutesOfDay(String? examTime) {
    if (examTime == null) return null;
    final m = RegExp(
      r'(\d{1,2})\s*[:.]\s*(\d{2})\s*([AaPp])?\.?\s*[Mm]?',
    ).firstMatch(examTime.trim());
    if (m == null) return null;

    var hour = int.tryParse(m.group(1)!);
    final minute = int.tryParse(m.group(2)!);
    if (hour == null || minute == null) return null;
    if (minute > 59) return null;

    final meridiem = m.group(3)?.toLowerCase();
    if (meridiem == 'p' && hour < 12) hour += 12;
    if (meridiem == 'a' && hour == 12) hour = 0;
    if (hour > 23) return null;

    return hour * 60 + minute;
  }

  /// The exam the countdown should name.
  ///
  /// Two things the database query does not do. It orders by date alone, so
  /// several exams on one day come back in whatever order SQLite feels like —
  /// the countdown would name an arbitrary one rather than the next. And when
  /// nothing is upcoming it falls back to *past* uncompleted exams, which
  /// arrive with a negative day count and would have been labelled "আজ".
  ///
  /// Anything already past is dropped, and same-day exams are ordered by the
  /// time written on them. An exam with no readable time sorts after those
  /// that have one, rather than jumping the queue at midnight.
  @visibleForTesting
  static ExamSchedule? pickNextExam(List<ExamSchedule> exams, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final upcoming = exams
        .where((e) => !DateTime(
              e.examDate.year,
              e.examDate.month,
              e.examDate.day,
            ).isBefore(today))
        .toList();
    if (upcoming.isEmpty) return null;

    upcoming.sort((a, b) {
      final byDate = DateTime(a.examDate.year, a.examDate.month, a.examDate.day)
          .compareTo(
            DateTime(b.examDate.year, b.examDate.month, b.examDate.day),
          );
      if (byDate != 0) return byDate;
      final at = minutesOfDay(a.examTime);
      final bt = minutesOfDay(b.examTime);
      if (at == null && bt == null) return a.id.compareTo(b.id);
      if (at == null) return 1;
      if (bt == null) return -1;
      return at.compareTo(bt);
    });
    return upcoming.first;
  }

  /// How many questions to leave ready for the widget.
  ///
  /// Enough to keep tapping through for a while; small enough that it is not
  /// a weight in the preferences file, which Android reads in full at launch.
  static const int questionQueueLength = 12;

  /// The bank, rotated so [startId] comes first, trimmed to [limit].
  ///
  /// The widget answers and advances entirely on its own, with no Flutter
  /// engine running — on a home screen a tap has to land immediately, and
  /// waking an engine to fetch the next question would make it feel broken.
  /// So the questions are handed over in advance, in the order they will be
  /// used.
  @visibleForTesting
  static List<Map<String, Object?>> buildQuestionQueue({
    required List<DrillQuestion> bank,
    required int? startId,
    int limit = questionQueueLength,
  }) {
    if (bank.isEmpty) return const [];
    var start = bank.indexWhere((q) => q.id == startId);
    if (start < 0) start = 0;

    return List.generate(
      bank.length < limit ? bank.length : limit,
      (i) {
        final q = bank[(start + i) % bank.length];
        return {
          'id': q.id,
          'q': q.questionText,
          'o': parseOptions(q.optionsJson).map(stripOptionMarker).toList(),
          'c': q.correctIndex,
        };
      },
    );
  }

  // --- collection ---------------------------------------------------------

  /// Reads the study figures and leaves them where the widgets can find them.
  static Future<void> syncStudyData(AppDatabase db) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final today = isoDate(now);

      // 1. What needs attention.
      final stats = await db.getDrillStats();
      await prefs.setString(
        keyWrongCount,
        bn((stats['active_wrong_count'] as int?) ?? 0),
      );
      await prefs.setString(
        keyAccuracy,
        '${bn(((stats['accuracy_percentage'] as num?) ?? 0).round())}%',
      );

      final due = await db.getDueSpacedReviewItems();
      await prefs.setString(keyDueCount, bn(due.length));

      final weak = await db.getAllWeakTopics();
      await prefs.setString(
        keyWeakTopics,
        weakTopicLine(weak.map((t) => t.topicName).toList()),
      );

      // 2. The next exam. getUpcomingExams already drops the ones that have
      // been and gone, so the first is the next.
      final exams = await db.getUpcomingExams();
      final next = pickNextExam(exams, now);
      if (next == null) {
        // Cleared rather than left behind, so a widget added after the last
        // exam passed does not show one that is over.
        await prefs.remove(keyExamTitle);
        await prefs.remove(keyExamSubject);
        await prefs.remove(keyExamWhen);
        await prefs.remove(keyExamCountdown);
      } else {
        final daysLeft = daysUntil(next.examDate, now);
        await prefs.setString(keyExamTitle, next.title);
        await prefs.setString(keyExamSubject, next.subject);
        await prefs.setString(keyExamCountdown, countdownLabel(daysLeft));
        await prefs.setString(
          keyExamWhen,
          '${next.subject} • ${bn(next.examTime)}',
        );
      }

      // 3. Today's question, drawn from what the user has got wrong.
      final bank = await db.watchWrongDrillQuestions().first;
      final wasSameDay = prefs.getString(keyQotdDate) == today;
      // Read before anything overwrites it: the reveal has to be cleared when
      // the question changes, and after the write the two always match.
      final previousId = prefs.getInt(keyQotdQuestionId);
      final chosenId = dailyQuestionId(
        bankIds: bank.map((q) => q.id).toList(),
        heldId: previousId,
        isSameDay: wasSameDay,
        day: now,
      );

      final queue = buildQuestionQueue(bank: bank, startId: chosenId);
      await prefs.setString(keyQotdQueue, jsonEncode(queue));

      if (chosenId == null) {
        await prefs.setString(keyQuestion, 'ভুলের খাতা খালি — চমৎকার!');
        await prefs.setString(keyOptions, '[]');
        await prefs.setInt(keyCorrectIndex, -1);
        await prefs.remove(keyQotdQuestionId);
      } else {
        final q = bank.firstWhere((e) => e.id == chosenId);
        await prefs.setString(keyQuestion, q.questionText);
        await prefs.setString(
          keyOptions,
          jsonEncode(parseOptions(q.optionsJson).map(stripOptionMarker).toList()),
        );
        await prefs.setInt(keyCorrectIndex, q.correctIndex);
        await prefs.setInt(keyQotdQuestionId, chosenId);
      }

      // A new day starts at the top of the queue with nothing answered. Within
      // a day the cursor is the widget's own: it moves as questions are
      // tapped through, and a sync must not drag it back to the start under
      // someone who is part-way along.
      if (!wasSameDay) {
        await prefs.setInt(keyQotdCursor, 0);
        await prefs.setBool(keyQotdRevealed, false);
      } else if (chosenId != previousId) {
        await prefs.setBool(keyQotdRevealed, false);
      }
      await prefs.setString(keyQotdDate, today);

      final hour12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
      await prefs.setString(
        keySyncTime,
        '${bn(hour12)}:${bn(now.minute.toString().padLeft(2, '0'))} '
        '${now.hour >= 12 ? 'PM' : 'AM'}',
      );

      debugPrint('StudyWidget: collected');
    } catch (e) {
      // A home screen widget is never worth taking the app down for.
      debugPrint('StudyWidget: could not collect the figures: $e');
    }

    // Repainting is attempted whatever happened above, and reported
    // separately. Collecting and repainting failing for the same reason once
    // made a native crash read as "sync failed", which pointed at the Dart
    // side and away from the receiver that was actually dying.
    try {
      await _channel.invokeMethod('updateStudyWidgets');
      debugPrint('StudyWidget: widgets repainted');
    } catch (e) {
      debugPrint('StudyWidget: collected, but the widgets did not repaint: $e');
    }
  }

  /// The options as the widget needs them: four strings, padded or trimmed.
  @visibleForTesting
  static List<String> parseOptions(String optionsJson) {
    try {
      final decoded = jsonDecode(optionsJson);
      if (decoded is List) {
        return decoded.map((e) => '$e').toList();
      }
    } catch (_) {
      // A malformed row should leave the widget blank, not crash the sync.
    }
    return const [];
  }
}
