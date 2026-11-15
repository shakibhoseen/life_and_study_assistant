import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/app_database.dart';
import '../utils/bengali_math_sanitizer.dart';

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
    'com.example.life_and_study_assistant/system_settings',
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
      if (exams.isEmpty) {
        // Cleared rather than left behind, so a widget added after the last
        // exam passed does not show one that is over.
        await prefs.remove(keyExamTitle);
        await prefs.remove(keyExamSubject);
        await prefs.remove(keyExamWhen);
        await prefs.remove(keyExamCountdown);
      } else {
        final next = exams.first;
        final daysLeft = daysUntil(next.examDate, now);
        await prefs.setString(keyExamTitle, next.title);
        await prefs.setString(keyExamSubject, next.subject);
        await prefs.setString(keyExamCountdown, countdownLabel(daysLeft));
        await prefs.setString(
          keyExamWhen,
          '${next.subject} • ${next.examTime}',
        );
      }

      // 3. Today's question, drawn from what the user has got wrong.
      final bank = await db.watchWrongDrillQuestions().first;
      final index = questionIndexForDay(bank.length, now);
      if (index < 0) {
        await prefs.setString(keyQuestion, 'ভুলের খাতা খালি — চমৎকার!');
        await prefs.setString(keyOptions, '[]');
        await prefs.setInt(keyCorrectIndex, -1);
      } else {
        final q = bank[index];
        await prefs.setString(keyQuestion, q.questionText);
        await prefs.setString(keyOptions, q.optionsJson);
        await prefs.setInt(keyCorrectIndex, q.correctIndex);
      }

      // A new day's question starts hidden again.
      if (prefs.getString(keyQotdDate) != today) {
        await prefs.setString(keyQotdDate, today);
        await prefs.setBool(keyQotdRevealed, false);
      }

      final hour12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
      await prefs.setString(
        keySyncTime,
        '${bn(hour12)}:${bn(now.minute.toString().padLeft(2, '0'))} '
        '${now.hour >= 12 ? 'PM' : 'AM'}',
      );

      await _channel.invokeMethod('updateStudyWidgets');
      debugPrint('StudyWidget: synced');
    } catch (e) {
      // A home screen widget is never worth taking the app down for.
      debugPrint('StudyWidget: sync failed: $e');
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
