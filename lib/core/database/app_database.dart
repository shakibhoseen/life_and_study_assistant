import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../services/ai/models/routine_import_result.dart';
import 'tables/app_settings_table.dart';
import 'tables/chat_messages_table.dart';
import 'tables/chat_sessions_table.dart';
import 'tables/daily_energy_logs_table.dart';
import 'tables/drill_questions_table.dart';
import 'tables/drill_records_table.dart';
import 'tables/exam_schedules_table.dart';
import 'tables/spaced_review_items_table.dart';
import 'tables/weak_topics_table.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    WeakTopics,
    ExamSchedules,
    DailyEnergyLogs,
    AppSettings,
    ChatSessions,
    ChatMessages,
    DrillRecords,
    DrillQuestions,
    SpacedReviewItems,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 12;

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'life_and_study_assistant');
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      // Seed realistic default weak topics & initial settings
      await _seedInitialData();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(chatMessages);
      }
      if (from < 3) {
        await m.addColumn(examSchedules, examSchedules.trackName);
      }
      if (from < 4) {
        await m.createTable(drillRecords);
        await m.createTable(drillQuestions);
      }
      if (from < 5) {
        await m.createTable(chatSessions);
        await m.addColumn(chatMessages, chatMessages.sessionId);
      }
      if (from < 6) {
        await m.createTable(spacedReviewItems);
      }
      if (from < 7) {
        await m.addColumn(chatSessions, chatSessions.summary);
        await m.addColumn(chatSessions, chatSessions.summarizedUpToId);
      }
      if (from < 8) {
        // Topics added automatically had piled up as duplicates before
        // insertWeakTopic started collapsing them.
        await dedupeWeakTopics();
      }
      if (from < 9) {
        await m.addColumn(drillQuestions, drillQuestions.originalCorrectIndex);
        await m.addColumn(drillQuestions, drillQuestions.originalExplanation);
        await m.addColumn(drillQuestions, drillQuestions.correctedAt);
      }
      if (from < 10) {
        // A question whose options are themselves broken cannot be fixed by
        // choosing a different one, so the wording and the option set became
        // editable too -- and so had to be snapshotted like the answer.
        await m.addColumn(drillQuestions, drillQuestions.originalQuestionText);
        await m.addColumn(drillQuestions, drillQuestions.originalOptionsJson);
      }
      if (from < 11) {
        // A verification used to live only in the open sheet, so closing it
        // threw the answer away and the next look paid for it again.
        await m.addColumn(drillQuestions, drillQuestions.verificationStatus);
        await m.addColumn(drillQuestions, drillQuestions.verificationNote);
        await m.addColumn(drillQuestions, drillQuestions.verifiedAt);
      }
      if (from < 12) {
        // Corrections used to change the answer key without re-grading the
        // attempt, so a user who had picked the now-correct option stayed
        // marked wrong. Only rows whose key actually moved are touched.
        await customStatement(
          'UPDATE drill_questions '
          'SET is_correct = (selected_index = correct_index) '
          'WHERE corrected_at IS NOT NULL',
        );
      }
    },
  );

  Future<void> _seedInitialData() async {
    // Seed default chat session
    await into(chatSessions).insert(
      ChatSessionsCompanion.insert(
        title: 'General BCS & Study Companion',
        subject: const Value('General'),
        topic: const Value('Study Plan & Mentorship'),
      ),
      mode: InsertMode.insertOrIgnore,
    );

    // Seed initial high-yield spaced review rules
    final initialSpacedReviews = [
      SpacedReviewItemsCompanion.insert(
        subject: 'Bangla Grammar',
        topic: 'কারক ও বিভক্তি',
        title: 'অপাদান বনাম অধিকরণ কারক চেনার শর্টকাট',
        keyRule: 'যা থেকে কিছু বিচ্যুত, জাত, ভীত, উৎপন্ন, গৃহিত, মুক্ত হয় তা অপাদান (যেমন: তিলে তৈল হয়)। আর যেখানে ক্রিয়া সম্পন্ন হয় বা স্থান/কাল তা অধিকরণ (যেমন: তিলে তৈল আছে)।',
        repetitionLevel: const Value(1),
        intervalDays: const Value(1),
        nextReviewDate: DateTime.now().add(const Duration(days: 1)),
      ),
      SpacedReviewItemsCompanion.insert(
        subject: 'Mathematics',
        topic: 'শতকরা ও লাভ-ক্ষতি',
        title: 'ক্রয়মূল্য ও বিক্রয়মূল্যের শর্টকাট সূত্র',
        keyRule: 'r% লাভে বিক্রয়মূল্য দেওয়া থাকলে: ক্রয়মূল্য = (বিক্রয়মূল্য × ১০০) ÷ (১০০ + r)। r% ক্ষতিতে: ক্রয়মূল্য = (বিক্রয়মূল্য × ১০০) ÷ (১০০ - r)।',
        repetitionLevel: const Value(1),
        intervalDays: const Value(1),
        nextReviewDate: DateTime.now().add(const Duration(days: 1)),
      ),
      SpacedReviewItemsCompanion.insert(
        subject: 'General Science',
        topic: 'আলো ও প্রতিসরণ',
        title: 'পূর্ণ অভ্যন্তরীণ প্রতিফলন ও সংকট কোণ',
        keyRule: 'আলোকরশ্মি ঘন মাধ্যম থেকে লঘু মাধ্যমে প্রবেশের সময় আপতন কোণ সংকট কোণের চেয়ে বড় হলে আলো প্রতিফলিত হয়ে একই মাধ্যমে ফিরে আসে। অপটিক্যাল ফাইবার ও মরিচিকা এই নীতির বাস্তব উদাহরণ।',
        repetitionLevel: const Value(2),
        intervalDays: const Value(3),
        nextReviewDate: DateTime.now().add(const Duration(days: 3)),
      ),
    ];

    for (final item in initialSpacedReviews) {
      await into(spacedReviewItems)
          .insert(item, mode: InsertMode.insertOrIgnore);
    }

    // Seed default settings
    await into(appSettings).insert(
      AppSettingsCompanion.insert(
        key: 'office_wifi_ssid',
        value: 'Zavisoft, SecretStar',
      ),
      mode: InsertMode.insertOrReplace,
    );
    await into(appSettings).insert(
      AppSettingsCompanion.insert(key: 'dinner_reminder_hour', value: '16'),
      mode: InsertMode.insertOrReplace,
    );
    await into(appSettings).insert(
      AppSettingsCompanion.insert(key: 'dinner_reminder_minute', value: '0'),
      mode: InsertMode.insertOrReplace,
    );
    await into(appSettings).insert(
      AppSettingsCompanion.insert(key: 'auto_checkin_enabled', value: 'true'),
      mode: InsertMode.insertOrReplace,
    );

    // Seed common BCS / Competitive Exam weak topics
    final initialTopics = [
      WeakTopicsCompanion.insert(
        subject: 'Bangla Grammar',
        topicName: 'কারক ও বিভক্তি (Case & Inflection)',
        proficiencyLevel: ProficiencyLevel.weak,
        notes: const Value(
          'Confusing accusative vs instrumental cases; review LiveMCQ notes',
        ),
      ),
      WeakTopicsCompanion.insert(
        subject: 'Bangla Grammar',
        topicName: 'সন্ধি ও সমাস (Sandhi & Compound words)',
        proficiencyLevel: ProficiencyLevel.moderate,
        notes: const Value(
          'Need quick rules revision for বহুব্রীহি and তৎপুরুষ সমাস',
        ),
      ),
      WeakTopicsCompanion.insert(
        subject: 'Mathematics',
        topicName: 'শতকরা ও লাভ-ক্ষতি (Percentage & Profit-Loss)',
        proficiencyLevel: ProficiencyLevel.weak,
        notes: const Value(
          'Practice 10 shortcut formulas for speed calculation',
        ),
      ),
      WeakTopicsCompanion.insert(
        subject: 'General Science',
        topicName: 'আলো ও আলোকীয় যন্ত্রপাতি (Optics & Wave)',
        proficiencyLevel: ProficiencyLevel.weak,
        notes: const Value('Refraction, total internal reflection, lenses'),
      ),
      WeakTopicsCompanion.insert(
        subject: 'English',
        topicName: 'Subject-Verb Agreement & Inversion',
        proficiencyLevel: ProficiencyLevel.moderate,
        notes: const Value('Hard rules with neither/nor, not only/but also'),
      ),
    ];

    for (final topic in initialTopics) {
      await into(weakTopics).insert(topic);
    }

    // Seed upcoming LiveMCQ Multi-Track Exams
    final now = DateTime.now();
    await into(examSchedules).insert(
      ExamSchedulesCompanion.insert(
        examDate: now.add(const Duration(days: 2)),
        title: '52nd BCS: Bangla Grammar & Math Drill',
        topicsCovered: 'কারক ও বিভক্তি, সমাস, শতকরা, লাভ-ক্ষতি',
        trackName: const Value('52nd BCS 135-Day'),
        examType: const Value('Subject Drill'),
        resourceSummary: const Value(
          'Part of 135-day routine. Focus areas: 25 marks Bangla, 15 marks Math.',
        ),
      ),
    );

    await into(examSchedules).insert(
      ExamSchedulesCompanion.insert(
        examDate: now.add(const Duration(days: 1)),
        title: 'Daily Vocabulary Booster: 30 High-Yield Words',
        topicsCovered: 'Synonyms, Antonyms, Prepositions, Idioms',
        trackName: const Value('Vocabulary Booster'),
        examType: const Value('Daily Booster'),
        resourceSummary: const Value(
          'LiveMCQ 10-minute micro test every evening at 10 PM.',
        ),
      ),
    );

    await into(examSchedules).insert(
      ExamSchedulesCompanion.insert(
        examDate: now.add(
          Duration(days: (DateTime.friday - now.weekday + 7) % 7),
        ),
        title: 'Friday 200 Marks Full BCS Model Test',
        topicsCovered: 'Full BCS Preliminary Syllabus (10 Subjects)',
        trackName: const Value('Friday Mega Model Test'),
        examType: const Value('Model Test'),
        resourceSummary: const Value(
          'Full-length simulation. Perfect for weekly off-day prep.',
        ),
      ),
    );
  }

  // --- Weak Topics Queries ---
  Stream<List<WeakTopic>> watchAllWeakTopics() {
    return (select(weakTopics)..orderBy([
          (t) => OrderingTerm(
            expression: t.proficiencyLevel,
            mode: OrderingMode.asc,
          ),
          (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
        ]))
        .watch();
  }

  Future<List<WeakTopic>> getAllWeakTopics() {
    return (select(weakTopics)..orderBy([
          (t) => OrderingTerm(
            expression: t.proficiencyLevel,
            mode: OrderingMode.asc,
          ),
        ]))
        .get();
  }

  /// Weak topics narrowed down for AI prompt context.
  ///
  /// Only topics the user is still struggling with, capped so the prompt
  /// cannot grow unbounded as the topic list accumulates over months.
  /// Never-reviewed topics come first, since those need the mentor most.
  Future<List<WeakTopic>> getContextWeakTopics({int limit = 10}) {
    return (select(weakTopics)
          ..where(
            (t) => t.proficiencyLevel.isInValues([
              ProficiencyLevel.weak,
              ProficiencyLevel.moderate,
            ]),
          )
          ..orderBy([
            (t) => OrderingTerm(
              expression: t.proficiencyLevel,
              mode: OrderingMode.asc,
            ),
            (t) => OrderingTerm(
              expression: t.lastReviewedAt,
              mode: OrderingMode.asc,
            ),
          ])
          ..limit(limit))
        .get();
  }

  /// Normalised key for "the same topic": trimmed and case-folded, so
  /// "সমাস" and " সমাস " are one entry.
  static String _topicKey(String subject, String topic) =>
      '${subject.trim().toLowerCase()}|${topic.trim().toLowerCase()}';

  /// Adds a weak topic, or returns the existing one's id.
  ///
  /// Four paths add topics without the user typing them -- a voice mistake,
  /// an ADD_TOPIC tag from chat, a scanned study sheet, a quiz drill -- so the
  /// same topic arrived repeatedly and the list filled with duplicates, which
  /// then went to the model twice in every prompt.
  ///
  /// A repeat insert never changes the proficiency already recorded: that is
  /// the user's own assessment, and an automated "weak" must not quietly
  /// overwrite it. Use [updateWeakTopic] to change a rating. Notes are merged
  /// so nothing a caller wrote is lost.
  Future<int> insertWeakTopic(WeakTopicsCompanion entry) async {
    final subject = entry.subject.value;
    final topic = entry.topicName.value;
    final key = _topicKey(subject, topic);

    final existing = await select(weakTopics).get();
    for (final row in existing) {
      if (_topicKey(row.subject, row.topicName) != key) continue;

      final incomingNote = entry.notes.present ? (entry.notes.value ?? '') : '';
      final currentNote = row.notes ?? '';
      if (incomingNote.trim().isNotEmpty &&
          !currentNote.contains(incomingNote.trim())) {
        final merged = currentNote.trim().isEmpty
            ? incomingNote.trim()
            : '$currentNote\n${incomingNote.trim()}';
        await (update(weakTopics)..where((t) => t.id.equals(row.id))).write(
          WeakTopicsCompanion(notes: Value(merged)),
        );
      }
      return row.id;
    }

    return into(weakTopics).insert(entry);
  }

  /// Collapses topics that were added more than once before the insert above
  /// started deduplicating.
  ///
  /// Where a group disagrees about proficiency, the weakest rating wins: a
  /// topic someone once marked weak is the one worth keeping on the list.
  Future<int> dedupeWeakTopics() async {
    final rows = await select(weakTopics).get();
    final groups = <String, List<WeakTopic>>{};
    for (final row in rows) {
      groups
          .putIfAbsent(_topicKey(row.subject, row.topicName), () => [])
          .add(row);
    }

    var removed = 0;
    for (final group in groups.values) {
      if (group.length < 2) continue;

      group.sort((a, b) => a.id.compareTo(b.id));
      final keeper = group.first;

      final weakest = group
          .map((r) => r.proficiencyLevel.index)
          .reduce((a, b) => a < b ? a : b);

      final reviewed = group
          .map((r) => r.lastReviewedAt)
          .whereType<DateTime>()
          .fold<DateTime?>(
            null,
            (latest, d) => latest == null || d.isAfter(latest) ? d : latest,
          );

      await (update(weakTopics)..where((t) => t.id.equals(keeper.id))).write(
        WeakTopicsCompanion(
          proficiencyLevel: Value(ProficiencyLevel.values[weakest]),
          lastReviewedAt: Value(reviewed),
        ),
      );

      for (final dup in group.skip(1)) {
        await (delete(weakTopics)..where((t) => t.id.equals(dup.id))).go();
        removed++;
      }
    }
    return removed;
  }

  Future<bool> updateWeakTopic(WeakTopic entry) {
    return update(weakTopics).replace(entry);
  }

  Future<int> deleteWeakTopic(int id) {
    return (delete(weakTopics)..where((t) => t.id.equals(id))).go();
  }

  // --- Exam Schedules Queries ---
  Stream<List<ExamSchedule>> watchUpcomingExams() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    return (select(examSchedules)
          ..where(
            (t) =>
                t.completedStatus.equals(false) &
                t.examDate.isBiggerOrEqualValue(todayStart),
          )
          ..orderBy([
            (t) => OrderingTerm(expression: t.examDate, mode: OrderingMode.asc),
          ]))
        .watch();
  }

  Stream<List<ExamSchedule>> watchAllExams() {
    return (select(examSchedules)..orderBy([
          (t) => OrderingTerm(expression: t.examDate, mode: OrderingMode.asc),
        ]))
        .watch();
  }

  Future<List<ExamSchedule>> getUpcomingExams() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final futureExams =
        await (select(examSchedules)
              ..where(
                (t) =>
                    t.completedStatus.equals(false) &
                    t.examDate.isBiggerOrEqualValue(todayStart),
              )
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.examDate,
                  mode: OrderingMode.asc,
                ),
              ]))
            .get();

    if (futureExams.isNotEmpty) return futureExams;

    // Fallback if no future exams exist: return uncompleted exams
    return (select(examSchedules)
          ..where((t) => t.completedStatus.equals(false))
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.examDate, mode: OrderingMode.desc),
          ]))
        .get();
  }

  /// Upcoming exams narrowed down for AI prompt context.
  ///
  /// A bulk-imported routine (e.g. a 135-day BCS syllabus) can hold hundreds
  /// of future rows; sending all of them with every chat message is both
  /// expensive and distracting, so only the next few imminent ones are used.
  Future<List<ExamSchedule>> getContextUpcomingExams({
    int limit = 5,
    int withinDays = 21,
  }) async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final horizon = todayStart.add(Duration(days: withinDays));

    final imminent =
        await (select(examSchedules)
              ..where(
                (t) =>
                    t.completedStatus.equals(false) &
                    t.examDate.isBiggerOrEqualValue(todayStart) &
                    t.examDate.isSmallerOrEqualValue(horizon),
              )
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.examDate,
                  mode: OrderingMode.asc,
                ),
              ])
              ..limit(limit))
            .get();

    if (imminent.isNotEmpty) return imminent;

    // Nothing within the horizon: fall back to the next few scheduled exams
    // so the mentor still knows what the user is working towards.
    return (select(examSchedules)
          ..where(
            (t) =>
                t.completedStatus.equals(false) &
                t.examDate.isBiggerOrEqualValue(todayStart),
          )
          ..orderBy([
            (t) => OrderingTerm(expression: t.examDate, mode: OrderingMode.asc),
          ])
          ..limit(limit))
        .get();
  }

  Future<int> insertExamSchedule(ExamSchedulesCompanion entry) async {
    final newDate = entry.examDate.value;
    final newTrack = entry.trackName.present
        ? entry.trackName.value.trim().toLowerCase()
        : 'general bcs';
    final newTitle = entry.title.value.trim().toLowerCase();

    final existing = await select(examSchedules).get();
    for (final e in existing) {
      final isSameDate =
          e.examDate.year == newDate.year &&
          e.examDate.month == newDate.month &&
          e.examDate.day == newDate.day;
      final isSameTrack = e.trackName.trim().toLowerCase() == newTrack;
      final isSameTitle = e.title.trim().toLowerCase() == newTitle;

      if (isSameDate && isSameTrack && isSameTitle) {
        return e.id;
      }
    }

    return into(examSchedules).insert(entry);
  }

  /// Inserts a batch of exam schedules while intelligently detecting and skipping duplicates.
  /// Deduplication is based on: same track + same calendar date (year, month,
  /// day) + matching title, or an exact matching subject and topics pair.
  /// If an existing exam is found, it will update any newly found details while strictly preserving completedStatus and score.
  Future<RoutineImportResult> insertExamSchedulesDeduplicated(
    List<ExamSchedulesCompanion> entries,
  ) async {
    if (entries.isEmpty) {
      return const RoutineImportResult(
        totalParsed: 0,
        insertedCount: 0,
        skippedCount: 0,
      );
    }

    final allExisting = await select(examSchedules).get();
    int inserted = 0;
    int skipped = 0;
    int updated = 0;

    for (final newEntry in entries) {
      final newDate = newEntry.examDate.value;
      final newTrack = newEntry.trackName.present
          ? newEntry.trackName.value.trim().toLowerCase()
          : 'general bcs';
      final newTitle = newEntry.title.value.trim().toLowerCase();
      // An absent time becomes the column default once written, so compare
      // against that rather than against an empty string -- otherwise a
      // re-import never matches what it inserted last time.
      final newTime = newEntry.examTime.present
          ? newEntry.examTime.value.trim().toLowerCase()
          : '10:00 pm';
      final newSubject = newEntry.subject.present
          ? newEntry.subject.value.trim().toLowerCase()
          : '';
      final newTopics = newEntry.topicsCovered.value.trim().toLowerCase();

      ExamSchedule? match;
      for (final existing in allExisting) {
        final existingDate = existing.examDate;
        final isSameDate =
            existingDate.year == newDate.year &&
            existingDate.month == newDate.month &&
            existingDate.day == newDate.day;

        if (!isSameDate) continue;

        final isSameTrack = existing.trackName.trim().toLowerCase() == newTrack;
        if (!isSameTrack) continue;

        // Two exams at different hours are two exams, whatever they are
        // called. Titles are often generated rather than read from the
        // routine ("Bangla Grammar Daily Exam"), so the same title on one day
        // is routine, not a duplicate -- and matching on it alone silently
        // swallowed the second sitting.
        final isSameTime = existing.examTime.trim().toLowerCase() == newTime;
        if (!isSameTime) continue;

        final isSameTitle = existing.title.trim().toLowerCase() == newTitle;
        final isSameSubject =
            newSubject.isNotEmpty &&
            existing.subject.trim().toLowerCase() == newSubject;
        final isSameTopics =
            existing.topicsCovered.trim().toLowerCase() == newTopics;

        // A routine can legitimately have several Bangla/Math tests on the
        // same date. Matching merely by subject (or merely by a generic
        // topic) collapsed those separate schedule rows into one.
        if (isSameTitle || (isSameSubject && isSameTopics)) {
          match = existing;
          break;
        }
      }

      if (match != null) {
        final existingTopics = match.topicsCovered.trim();
        final incomingTopics = newEntry.topicsCovered.value.trim();
        final hasMoreTopics = incomingTopics.length > existingTopics.length;
        final hasNewSummary =
            (match.resourceSummary == null || match.resourceSummary!.isEmpty) &&
            (newEntry.resourceSummary.present &&
                newEntry.resourceSummary.value != null);
        final hasNewRef =
            (match.rawReference == null || match.rawReference!.isEmpty) &&
            (newEntry.rawReference.present &&
                newEntry.rawReference.value != null);

        if (hasMoreTopics || hasNewSummary || hasNewRef) {
          await update(examSchedules).replace(
            match.copyWith(
              topicsCovered: hasMoreTopics
                  ? incomingTopics
                  : match.topicsCovered,
              resourceSummary: hasNewSummary
                  ? newEntry.resourceSummary
                  : Value(match.resourceSummary),
              rawReference: hasNewRef
                  ? newEntry.rawReference
                  : Value(match.rawReference),
              examTime: newEntry.examTime.present
                  ? newEntry.examTime.value
                  : match.examTime,
            ),
          );
          updated++;
        } else {
          skipped++;
        }
      } else {
        final id = await into(examSchedules).insert(newEntry);
        // Include entries inserted earlier in this batch too; an imported
        // PDF occasionally repeats a row on a later page.
        allExisting.add(
          await (select(
            examSchedules,
          )..where((table) => table.id.equals(id))).getSingle(),
        );
        inserted++;
      }
    }

    return RoutineImportResult(
      totalParsed: entries.length,
      insertedCount: inserted,
      skippedCount: skipped,
      updatedCount: updated,
    );
  }

  Future<void> batchInsertExamSchedules(
    List<ExamSchedulesCompanion> entries,
  ) async {
    await batch((b) {
      b.insertAll(examSchedules, entries);
    });
  }

  Future<bool> updateExamSchedule(ExamSchedule entry) {
    return update(examSchedules).replace(entry);
  }

  Future<int> deleteExamSchedule(int id) {
    return (delete(examSchedules)..where((t) => t.id.equals(id))).go();
  }

  Future<int> deleteExamsByTrack(String trackName) {
    return (delete(examSchedules)..where((t) => t.trackName.equals(trackName)))
        .go();
  }

  Future<int> clearAllExams() => delete(examSchedules).go();
  Future<int> clearAllWeakTopics() => delete(weakTopics).go();

  Stream<List<ExamSchedule>> watchExamsByTrack(String track) {
    if (track == 'All') return watchAllExams();
    return (select(examSchedules)
          ..where((t) => t.trackName.equals(track))
          ..orderBy([
            (t) => OrderingTerm(expression: t.examDate, mode: OrderingMode.asc),
          ]))
        .watch();
  }

  Stream<List<String>> watchAllDistinctTracks() {
    return select(examSchedules).watch().map((exams) {
      final tracks = <String>{};
      for (final e in exams) {
        if (e.trackName.isNotEmpty) {
          tracks.add(e.trackName);
        }
      }
      return tracks.toList()..sort();
    });
  }

  // --- Daily Energy Logs Queries ---
  Stream<DailyEnergyLog?> watchTodayLog(DateTime date) {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);
    return (select(dailyEnergyLogs)
          ..where(
            (t) =>
                t.date.isBiggerOrEqualValue(startOfDay) &
                t.date.isSmallerOrEqualValue(endOfDay),
          )
          ..limit(1))
        .watchSingleOrNull();
  }

  Future<DailyEnergyLog?> getTodayLog(DateTime date) {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);
    return (select(dailyEnergyLogs)
          ..where(
            (t) =>
                t.date.isBiggerOrEqualValue(startOfDay) &
                t.date.isSmallerOrEqualValue(endOfDay),
          )
          ..limit(1))
        .getSingleOrNull();
  }

  Future<int> insertOrUpdateDailyLog(DailyEnergyLogsCompanion entry) async {
    final entryDate = entry.date.value;
    final existing = await getTodayLog(entryDate);
    if (existing != null) {
      final updated = existing.copyWith(
        energyLevel: entry.energyLevel.value,
        officeFatigueScore: entry.officeFatigueScore.value,
        completedTasks: entry.completedTasks.value,
        notes: entry.notes.present
            ? Value(entry.notes.value)
            : Value(existing.notes),
      );
      await update(dailyEnergyLogs).replace(updated);
      return existing.id;
    } else {
      return into(dailyEnergyLogs).insert(entry);
    }
  }

  Stream<List<DailyEnergyLog>> watchRecentDailyLogs({int limit = 7}) {
    return (select(dailyEnergyLogs)
          ..orderBy([
            (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
          ])
          ..limit(limit))
        .watch();
  }

  // --- App Settings Queries ---
  Future<String?> getSetting(String key) async {
    final query = select(appSettings)..where((t) => t.key.equals(key));
    final result = await query.getSingleOrNull();
    return result?.value;
  }

  Stream<String?> watchSetting(String key) {
    final query = select(appSettings)..where((t) => t.key.equals(key));
    return query.watchSingleOrNull().map((entry) => entry?.value);
  }

  Future<void> setSetting(String key, String value) {
    return into(appSettings).insert(
      AppSettingsCompanion.insert(key: key, value: value),
      mode: InsertMode.insertOrReplace,
    );
  }

  // --- Chat Sessions & Threaded Messages Queries ---

  Future<ChatSession> getOrCreateDefaultSession() async {
    final sessions = await select(chatSessions).get();
    if (sessions.isNotEmpty) {
      await (update(chatMessages)..where((m) => m.sessionId.isNull())).write(
        ChatMessagesCompanion(sessionId: Value(sessions.first.id)),
      );
      return sessions.first;
    }

    final id = await into(chatSessions).insert(
      ChatSessionsCompanion.insert(
        title: 'General BCS & Study Companion',
        subject: const Value('General'),
        topic: const Value('Study Plan & Mentorship'),
      ),
    );

    await (update(chatMessages)..where((m) => m.sessionId.isNull())).write(
      ChatMessagesCompanion(sessionId: Value(id)),
    );

    return (select(chatSessions)..where((s) => s.id.equals(id))).getSingle();
  }

  Stream<List<ChatSession>> watchAllChatSessions() {
    return (select(chatSessions)..orderBy([
          (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
          (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
        ]))
        .watch();
  }

  Future<List<ChatSession>> getAllChatSessions() {
    return (select(chatSessions)..orderBy([
          (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
          (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
        ]))
        .get();
  }

  Future<ChatSession?> getChatSessionById(int id) {
    return (select(
      chatSessions,
    )..where((s) => s.id.equals(id))).getSingleOrNull();
  }

  Future<ChatSession> getOrCreateTopicSession({
    required String subject,
    required String topic,
  }) async {
    final normSub = subject.trim().toLowerCase();
    final normTop = topic.trim().toLowerCase();

    final all = await select(chatSessions).get();
    for (final s in all) {
      final sSub = (s.subject ?? '').trim().toLowerCase();
      final sTop = (s.topic ?? '').trim().toLowerCase();
      if (sSub == normSub && sTop == normTop) {
        await (update(chatSessions)..where((entry) => entry.id.equals(s.id)))
            .write(ChatSessionsCompanion(updatedAt: Value(DateTime.now())));
        return (select(
          chatSessions,
        )..where((entry) => entry.id.equals(s.id))).getSingle();
      }
    }

    final title = '$subject: $topic';
    final id = await into(chatSessions).insert(
      ChatSessionsCompanion.insert(
        title: title,
        subject: Value(subject.trim()),
        topic: Value(topic.trim()),
      ),
    );

    return (select(chatSessions)..where((s) => s.id.equals(id))).getSingle();
  }

  Future<int> createChatSession({
    required String title,
    String? subject,
    String? topic,
  }) {
    return into(chatSessions).insert(
      ChatSessionsCompanion.insert(
        title: title,
        subject: subject != null ? Value(subject) : const Value.absent(),
        topic: topic != null ? Value(topic) : const Value.absent(),
      ),
    );
  }

  Future<bool> updateChatSessionTitle(int sessionId, String newTitle) async {
    final rows =
        await (update(
          chatSessions,
        )..where((s) => s.id.equals(sessionId))).write(
          ChatSessionsCompanion(
            title: Value(newTitle),
            updatedAt: Value(DateTime.now()),
          ),
        );
    return rows > 0;
  }

  Future<void> touchChatSession(int sessionId) async {
    await (update(chatSessions)..where((s) => s.id.equals(sessionId))).write(
      ChatSessionsCompanion(updatedAt: Value(DateTime.now())),
    );
  }

  Future<int> deleteChatSession(int sessionId) async {
    await (delete(
      chatMessages,
    )..where((m) => m.sessionId.equals(sessionId))).go();
    return (delete(chatSessions)..where((s) => s.id.equals(sessionId))).go();
  }

  Stream<List<ChatMessage>> watchChatMessagesForSession(int sessionId) {
    return (select(chatMessages)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.timestamp, mode: OrderingMode.asc),
            (t) => OrderingTerm(expression: t.id, mode: OrderingMode.asc),
          ]))
        .watch();
  }

  Future<List<ChatMessage>> getRecentChatMessagesForSession(
    int sessionId, {
    int limit = 20,
  }) async {
    final list =
        await (select(chatMessages)
              ..where((t) => t.sessionId.equals(sessionId))
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.timestamp,
                  mode: OrderingMode.desc,
                ),
                (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
              ])
              ..limit(limit))
            .get();
    return list.reversed.toList();
  }

  /// Every message in a session, oldest first. Used when rebuilding the
  /// running summary, where the whole thread has to be partitioned into
  /// "already summarised" and "still live".
  /// Replaces a streaming placeholder's text as the reply arrives.
  Future<void> updateChatMessageText(int messageId, String text) async {
    await (update(chatMessages)..where((m) => m.id.equals(messageId))).write(
      ChatMessagesCompanion(textContent: Value(text)),
    );
  }

  /// Writes the finished reply and its extracted actions in one go.
  Future<void> finalizeChatMessage(
    int messageId, {
    required String text,
    String? suggestedAction,
  }) async {
    await (update(chatMessages)..where((m) => m.id.equals(messageId))).write(
      ChatMessagesCompanion(
        textContent: Value(text),
        suggestedAction: Value(suggestedAction),
      ),
    );
  }

  /// Removes a placeholder whose reply never arrived.
  Future<void> deleteChatMessage(int messageId) async {
    await (delete(chatMessages)..where((m) => m.id.equals(messageId))).go();
  }

  Future<List<ChatMessage>> getAllChatMessagesForSession(int sessionId) {
    return (select(chatMessages)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.timestamp, mode: OrderingMode.asc),
            (t) => OrderingTerm(expression: t.id, mode: OrderingMode.asc),
          ]))
        .get();
  }

  Future<void> updateChatSessionSummary(
    int sessionId, {
    required String summary,
    required int upToId,
  }) async {
    await (update(chatSessions)..where((t) => t.id.equals(sessionId))).write(
      ChatSessionsCompanion(
        summary: Value(summary),
        summarizedUpToId: Value(upToId),
      ),
    );
  }

  /// Applies a verification correction the user accepted.
  ///
  /// Updates what the question now says is correct, and keeps a copy of what
  /// it said before. Deliberately untouched: [DrillQuestions.selectedIndex]
  /// and [DrillQuestions.isCorrect]. Those record the attempt -- what was
  /// answered and how it was scored -- and rewriting them would silently
  /// change the mistake list, the statistics and the review schedule for an
  /// attempt that already happened.
  ///
  /// Calling it twice keeps the first snapshot, so the original survives a
  /// second correction.
  Future<void> acceptAnswerCorrection(
    int questionId, {
    required int correctedIndex,
    required String correctedExplanation,
  }) async {
    final row = await (select(
      drillQuestions,
    )..where((t) => t.id.equals(questionId))).getSingleOrNull();
    if (row == null) return;

    await (update(drillQuestions)..where((t) => t.id.equals(questionId))).write(
      DrillQuestionsCompanion(
        correctIndex: Value(correctedIndex),
        explanation: Value(correctedExplanation),
        // selectedIndex is history and stays. isCorrect is not history, it is
        // a grade against a key -- and the key just changed, so a user who
        // picked the now-correct option stops being marked wrong.
        isCorrect: Value(row.selectedIndex == correctedIndex),
        originalCorrectIndex: Value(
          row.originalCorrectIndex ?? row.correctIndex,
        ),
        originalExplanation: Value(row.originalExplanation ?? row.explanation),
        correctedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Records how a question was last checked, and by whom.
  ///
  /// Kept apart from the answer itself: a mark says something about the
  /// checking, not about what the question says.
  Future<void> saveVerificationMark(
    int questionId, {
    required String status,
    String? note,
  }) async {
    await (update(drillQuestions)..where((t) => t.id.equals(questionId))).write(
      DrillQuestionsCompanion(
        verificationStatus: Value(status),
        verificationNote: Value(note),
        verifiedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Drops the mark, for when the question itself changed under it.
  Future<void> clearVerificationMark(int questionId) async {
    await (update(drillQuestions)..where((t) => t.id.equals(questionId))).write(
      const DrillQuestionsCompanion(
        verificationStatus: Value(null),
        verificationNote: Value(null),
        verifiedAt: Value(null),
      ),
    );
  }

  /// Saves the user's edit to a question, snapshotting whatever it replaces.
  ///
  /// Every field is optional: the caller passes only what the user actually
  /// changed. The attempt itself -- what was answered and how it was scored --
  /// is never touched, because that is history rather than content.
  Future<void> applyQuestionEdit(
    int questionId, {
    String? questionText,
    List<String>? options,
    int? correctIndex,
    String? explanation,
  }) async {
    final row = await (select(
      drillQuestions,
    )..where((t) => t.id.equals(questionId))).getSingleOrNull();
    if (row == null) return;
    if (questionText == null &&
        options == null &&
        correctIndex == null &&
        explanation == null) {
      return;
    }

    await (update(drillQuestions)..where((t) => t.id.equals(questionId))).write(
      DrillQuestionsCompanion(
        questionText: questionText == null
            ? const Value.absent()
            : Value(questionText),
        optionsJson: options == null
            ? const Value.absent()
            : Value(jsonEncode(options)),
        correctIndex: correctIndex == null
            ? const Value.absent()
            : Value(correctIndex),
        // Regraded against the new key, for the same reason as above.
        isCorrect: correctIndex == null
            ? const Value.absent()
            : Value(row.selectedIndex == correctIndex),
        explanation: explanation == null
            ? const Value.absent()
            : Value(explanation),
        // Snapshots are taken once, so the first saved version is the one
        // that can be returned to however many edits follow.
        originalQuestionText: Value(
          row.originalQuestionText ?? row.questionText,
        ),
        originalOptionsJson: Value(row.originalOptionsJson ?? row.optionsJson),
        originalCorrectIndex: Value(
          row.originalCorrectIndex ?? row.correctIndex,
        ),
        originalExplanation: Value(row.originalExplanation ?? row.explanation),
        correctedAt: Value(DateTime.now()),
        // Whatever was concluded was concluded about the old wording.
        verificationStatus: const Value(null),
        verificationNote: const Value(null),
        verifiedAt: const Value(null),
      ),
    );
  }

  /// Puts a corrected question back to what it said originally.
  Future<void> revertAnswerCorrection(int questionId) async {
    final row = await (select(
      drillQuestions,
    )..where((t) => t.id.equals(questionId))).getSingleOrNull();
    if (row == null || row.correctedAt == null) return;

    await (update(drillQuestions)..where((t) => t.id.equals(questionId))).write(
      DrillQuestionsCompanion(
        questionText: Value(row.originalQuestionText ?? row.questionText),
        optionsJson: Value(row.originalOptionsJson ?? row.optionsJson),
        correctIndex: Value(row.originalCorrectIndex ?? row.correctIndex),
        isCorrect: Value(
          row.selectedIndex == (row.originalCorrectIndex ?? row.correctIndex),
        ),
        explanation: Value(row.originalExplanation ?? row.explanation),
        originalQuestionText: const Value(null),
        originalOptionsJson: const Value(null),
        originalCorrectIndex: const Value(null),
        originalExplanation: const Value(null),
        correctedAt: const Value(null),
      ),
    );
  }

  Future<int> clearSessionMessages(int sessionId) async {
    // The running summary describes the messages being deleted, so it has to
    // go with them -- otherwise a cleared thread still carries its old memory.
    await (update(chatSessions)..where((t) => t.id.equals(sessionId))).write(
      const ChatSessionsCompanion(
        summary: Value(null),
        summarizedUpToId: Value(null),
      ),
    );
    return (delete(
      chatMessages,
    )..where((m) => m.sessionId.equals(sessionId))).go();
  }

  // --- General Chat Messages Queries (Fallback) ---
  Stream<List<ChatMessage>> watchChatMessages() {
    return (select(chatMessages)..orderBy([
          (t) => OrderingTerm(expression: t.timestamp, mode: OrderingMode.asc),
          (t) => OrderingTerm(expression: t.id, mode: OrderingMode.asc),
        ]))
        .watch();
  }

  Future<List<ChatMessage>> getRecentChatMessages({int limit = 20}) async {
    final list =
        await (select(chatMessages)
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.timestamp,
                  mode: OrderingMode.desc,
                ),
                (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
              ])
              ..limit(limit))
            .get();
    return list.reversed.toList();
  }

  Future<int> insertChatMessage(ChatMessagesCompanion entry) {
    return into(chatMessages).insert(entry);
  }

  Future<int> clearChatHistory() {
    return delete(chatMessages).go();
  }

  // --- Backup & Restore Queries ---

  /// Exports all weak topics, exam schedules, and energy logs as a JSON string.
  Future<String> exportBackupJson() async {
    final allTopics = await (select(
      weakTopics,
    )..orderBy([(t) => OrderingTerm(expression: t.id)])).get();

    final allExams = await (select(
      examSchedules,
    )..orderBy([(t) => OrderingTerm(expression: t.id)])).get();

    final allLogs = await (select(
      dailyEnergyLogs,
    )..orderBy([(t) => OrderingTerm(expression: t.date)])).get();

    final allMistakes = await (select(
      drillQuestions,
    )..orderBy([(t) => OrderingTerm(expression: t.id)])).get();

    final backupMap = {
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'weak_topics': allTopics
          .map(
            (t) => {
              'subject': t.subject,
              'topic_name': t.topicName,
              'proficiency_level': t.proficiencyLevel.name,
              'notes': t.notes,
              'last_reviewed_at': t.lastReviewedAt?.toIso8601String(),
            },
          )
          .toList(),
      'exam_schedules': allExams
          .map(
            (e) => {
              'exam_date': e.examDate.toIso8601String(),
              'exam_time': e.examTime,
              'subject': e.subject,
              'title': e.title,
              'topics_covered': e.topicsCovered,
              'exam_type': e.examType,
              'track_name': e.trackName,
              'resource_summary': e.resourceSummary,
              'raw_reference': e.rawReference,
              'completed_status': e.completedStatus,
              'score': e.score,
            },
          )
          .toList(),
      'daily_energy_logs': allLogs
          .map(
            (l) => {
              'date': l.date.toIso8601String(),
              'energy_level': l.energyLevel.name,
              'office_fatigue_score': l.officeFatigueScore,
              'completed_tasks': l.completedTasks,
              'notes': l.notes,
            },
          )
          .toList(),
      'drill_questions': allMistakes
          .map(
            (q) => {
              'subject': q.subject,
              'topic': q.topic,
              'question_text': q.questionText,
              'options_json': q.optionsJson,
              'correct_index': q.correctIndex,
              'selected_index': q.selectedIndex,
              'is_correct': q.isCorrect,
              'explanation': q.explanation,
              'is_mastered': q.isMastered,
              'attempted_at': q.attemptedAt.toIso8601String(),
              'original_correct_index': q.originalCorrectIndex,
              'original_explanation': q.originalExplanation,
              'corrected_at': q.correctedAt?.toIso8601String(),
              'verification_status': q.verificationStatus,
              'verification_note': q.verificationNote,
            },
          )
          .toList(),
    };

    return const JsonEncoder.withIndent('  ').convert(backupMap);
  }

  /// Imports and restores study data from JSON with smart deduplication.
  Future<Map<String, int>> importBackupJson(String jsonString) async {
    var cleaned = jsonString.trim().replaceFirst(RegExp(r'^\uFEFF'), '');
    if (cleaned.startsWith('```')) {
      cleaned = cleaned
          .replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '')
          .replaceFirst(RegExp(r'\s*```$'), '')
          .trim();
    }
    final decoded = jsonDecode(cleaned);
    if (decoded is! Map) {
      throw const FormatException('Backup JSON must be an object, not a list.');
    }
    final data = Map<String, dynamic>.from(decoded);

    int importedTopics = 0;
    int importedExams = 0;
    int importedLogs = 0;

    // 1. Weak Topics
    if (data.containsKey('weak_topics') && data['weak_topics'] is List) {
      final existingTopics = await select(weakTopics).get();
      final topicList = data['weak_topics'] as List;

      for (final raw in topicList) {
        if (raw is! Map) continue;
        final subject = (raw['subject'] ?? raw['subjectName'] ?? 'General')
            .toString()
            .trim();
        final topicName = (raw['topic_name'] ?? raw['topicName'] ?? '')
            .toString()
            .trim();
        if (topicName.isEmpty) continue;

        final levelStr = (raw['proficiency_level'] ?? 'weak')
            .toString()
            .toLowerCase();
        ProficiencyLevel level = ProficiencyLevel.weak;
        if (levelStr == 'moderate') level = ProficiencyLevel.moderate;
        if (levelStr == 'strong') level = ProficiencyLevel.strong;

        final notes = raw['notes']?.toString();
        DateTime? lastReviewed;
        if (raw['last_reviewed_at'] != null) {
          lastReviewed = DateTime.tryParse(raw['last_reviewed_at'].toString());
        }

        // Check if existing
        WeakTopic? match;
        for (final t in existingTopics) {
          if (t.subject.toLowerCase() == subject.toLowerCase() &&
              t.topicName.toLowerCase() == topicName.toLowerCase()) {
            match = t;
            break;
          }
        }

        if (match != null) {
          if (notes != null &&
              notes.isNotEmpty &&
              (match.notes == null || match.notes!.isEmpty)) {
            await update(weakTopics).replace(
              match.copyWith(
                notes: Value(notes),
                proficiencyLevel: level,
                lastReviewedAt: lastReviewed != null
                    ? Value(lastReviewed)
                    : Value(match.lastReviewedAt),
              ),
            );
            importedTopics++;
          }
        } else {
          await into(weakTopics).insert(
            WeakTopicsCompanion.insert(
              subject: subject,
              topicName: topicName,
              proficiencyLevel: level,
              notes: notes != null ? Value(notes) : const Value.absent(),
              lastReviewedAt: lastReviewed != null
                  ? Value(lastReviewed)
                  : const Value.absent(),
            ),
          );
          importedTopics++;
        }
      }
    }

    // 2. Exam Schedules
    if (data.containsKey('exam_schedules') && data['exam_schedules'] is List) {
      final examList = data['exam_schedules'] as List;
      final companions = <ExamSchedulesCompanion>[];

      for (final raw in examList) {
        if (raw is! Map) continue;
        final dateStr = (raw['exam_date'] ?? raw['examDate'] ?? raw['date'])
            ?.toString();
        if (dateStr == null) continue;
        final parsedDate = DateTime.tryParse(dateStr);
        if (parsedDate == null) continue;

        final title = (raw['title'] ?? raw['exam_title'] ?? 'LiveMCQ Exam')
            .toString();
        // Hand-written and AI-written backups often give topics as an array.
        // Calling toString() on one stores the brackets as part of the text.
        final rawTopics = raw['topics_covered'] ?? raw['topics'] ?? '';
        final topics = rawTopics is List
            ? rawTopics.map((t) => t.toString().trim()).join(', ')
            : rawTopics.toString();
        final track = (raw['track_name'] ?? raw['trackName'] ?? 'General BCS')
            .toString();
        final examTime = (raw['exam_time'] ?? raw['examTime'] ?? '10:00 PM')
            .toString();
        final subject = (raw['subject'] ?? 'General').toString();
        final examType = (raw['exam_type'] ?? raw['examType'] ?? 'Daily')
            .toString();
        final resourceSummary =
            (raw['resource_summary'] ?? raw['resourceSummary'])?.toString();
        final rawReference = (raw['raw_reference'] ?? raw['rawReference'])
            ?.toString();
        final isCompleted =
            raw['completed_status'] == true || raw['completedStatus'] == true;
        final score = raw['score'] is num
            ? (raw['score'] as num).toDouble()
            : double.tryParse(raw['score']?.toString() ?? '');

        companions.add(
          ExamSchedulesCompanion.insert(
            title: title,
            examDate: parsedDate,
            topicsCovered: topics,
            examTime: Value(examTime),
            subject: Value(subject),
            examType: Value(examType),
            trackName: Value(track),
            resourceSummary: resourceSummary != null
                ? Value(resourceSummary)
                : const Value.absent(),
            rawReference: rawReference != null
                ? Value(rawReference)
                : const Value.absent(),
            completedStatus: Value(isCompleted),
            score: score != null ? Value(score) : const Value.absent(),
          ),
        );
      }

      final result = await insertExamSchedulesDeduplicated(companions);
      importedExams = result.insertedCount + result.updatedCount;
    }

    // 3. Daily Energy Logs
    if (data.containsKey('daily_energy_logs') &&
        data['daily_energy_logs'] is List) {
      final logList = data['daily_energy_logs'] as List;
      for (final raw in logList) {
        if (raw is! Map) continue;
        final dateStr = (raw['date'] ?? raw['logged_at'] ?? raw['loggedAt'])
            ?.toString();
        if (dateStr == null) continue;
        final parsedDate = DateTime.tryParse(dateStr);
        if (parsedDate == null) continue;

        final levelStr = (raw['energy_level'] ?? 'medium')
            .toString()
            .toLowerCase();
        EnergyLevel level = EnergyLevel.medium;
        if (levelStr == 'low') level = EnergyLevel.low;
        if (levelStr == 'high') level = EnergyLevel.high;

        final fatigue = raw['office_fatigue_score'] is num
            ? (raw['office_fatigue_score'] as num).round()
            : int.tryParse(raw['office_fatigue_score']?.toString() ?? '') ?? 5;
        final completedTasks = raw['completed_tasks'] ?? raw['completedTasks'];
        final tasks = completedTasks is List
            ? jsonEncode(completedTasks)
            : (completedTasks ?? '[]').toString();
        final notes = raw['notes']?.toString();

        await insertOrUpdateDailyLog(
          DailyEnergyLogsCompanion.insert(
            date: parsedDate,
            energyLevel: level,
            officeFatigueScore: Value(fatigue),
            completedTasks: Value(tasks),
            notes: notes != null ? Value(notes) : const Value.absent(),
          ),
        );
        importedLogs++;
      }
    }

    // 4. Drill Questions (Mistake Notebook)
    int importedMistakes = 0;
    if (data.containsKey('drill_questions') &&
        data['drill_questions'] is List) {
      final qList = data['drill_questions'] as List;
      final existingDq = await select(drillQuestions).get();
      final existingTexts = existingDq
          .map((e) => e.questionText.trim())
          .toSet();

      for (final raw in qList) {
        if (raw is! Map) continue;
        final qText = (raw['question_text'] ?? raw['questionText'])
            ?.toString()
            .trim();
        if (qText == null || qText.isEmpty) continue;
        if (existingTexts.contains(qText)) continue;

        final subject = (raw['subject'] ?? 'General').toString();
        final topic = (raw['topic'] ?? '').toString();
        final optionsJson = (raw['options_json'] ?? raw['optionsJson'] ?? '[]')
            .toString();
        final correctIndex =
            int.tryParse(raw['correct_index']?.toString() ?? '0') ?? 0;
        final selectedIndex =
            int.tryParse(raw['selected_index']?.toString() ?? '-1') ?? -1;
        final isCorrect = raw['is_correct'] == true || raw['isCorrect'] == true;
        final explanation = raw['explanation']?.toString();
        final isMastered =
            raw['is_mastered'] == true || raw['isMastered'] == true;
        final attemptedAt = DateTime.tryParse(
          (raw['attempted_at'] ?? raw['attemptedAt'])?.toString() ?? '',
        );

        await into(drillQuestions).insert(
          DrillQuestionsCompanion.insert(
            subject: subject,
            topic: topic,
            questionText: qText,
            optionsJson: optionsJson,
            correctIndex: correctIndex,
            selectedIndex: selectedIndex,
            isCorrect: isCorrect,
            explanation: Value(explanation ?? ''),
            isMastered: Value(isMastered),
            attemptedAt: attemptedAt != null
                ? Value(attemptedAt)
                : const Value.absent(),
          ),
        );
        existingTexts.add(qText);
        importedMistakes++;
      }
    }

    final result = <String, int>{
      'weak_topics': importedTopics,
      'exam_schedules': importedExams,
      'daily_energy_logs': importedLogs,
    };
    if (data.containsKey('drill_questions')) {
      result['mistakes'] = importedMistakes;
    }
    return result;
  }

  // --- Drill Records & Question Bank Queries ---
  Future<int> insertDrillRecord(DrillRecordsCompanion entry) =>
      into(drillRecords).insert(entry);
  Future<int> insertDrillQuestion(DrillQuestionsCompanion entry) =>
      into(drillQuestions).insert(entry);

  Future<int> recordFullDrillSession({
    required String subject,
    required String topic,
    required int totalQuestions,
    required int correctCount,
    required int incorrectCount,
    required double scorePercentage,
    required List<DrillQuestionsCompanion> questions,
  }) async {
    return transaction(() async {
      final recordId = await into(drillRecords).insert(
        DrillRecordsCompanion.insert(
          subject: subject,
          topic: topic,
          totalQuestions: totalQuestions,
          correctCount: correctCount,
          incorrectCount: incorrectCount,
          scorePercentage: scorePercentage,
        ),
      );

      for (final q in questions) {
        await into(drillQuestions)
            .insert(q.copyWith(drillRecordId: Value(recordId)));
      }

      return recordId;
    });
  }

  Stream<List<DrillRecord>> watchAllDrillRecords() {
    return (select(drillRecords)..orderBy([
          (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
        ]))
        .watch();
  }

  Stream<List<DrillQuestion>> watchWrongDrillQuestions() {
    return (select(drillQuestions)
          ..where((t) => t.isCorrect.equals(false) & t.isMastered.equals(false))
          ..orderBy([
            (t) => OrderingTerm(
              expression: t.attemptedAt,
              mode: OrderingMode.desc,
            ),
          ]))
        .watch();
  }

  Stream<List<DrillQuestion>> watchAllMistakeQuestions() {
    return (select(drillQuestions)
          ..where((t) => t.isCorrect.equals(false))
          ..orderBy([
            (t) => OrderingTerm(
              expression: t.attemptedAt,
              mode: OrderingMode.desc,
            ),
          ]))
        .watch();
  }

  Stream<List<DrillQuestion>> watchAllDrillQuestions() {
    return (select(drillQuestions)..orderBy([
          (t) =>
              OrderingTerm(expression: t.attemptedAt, mode: OrderingMode.desc),
        ]))
        .watch();
  }

  Future<bool> markQuestionMastered(int id, bool mastered) async {
    final rows = await (update(drillQuestions)..where((t) => t.id.equals(id)))
        .write(DrillQuestionsCompanion(isMastered: Value(mastered)));
    return rows > 0;
  }

  Future<int> deleteDrillQuestion(int id) {
    return (delete(drillQuestions)..where((t) => t.id.equals(id))).go();
  }

  Future<Map<String, dynamic>> getDrillStats() async {
    final records = await select(drillRecords).get();
    final allQuestions = await select(drillQuestions).get();

    final totalDrills = records.length;
    final totalAnswered = allQuestions.length;
    final totalCorrect = allQuestions.where((q) => q.isCorrect).length;
    final totalWrong = allQuestions.where((q) => !q.isCorrect).length;
    final accuracy = totalAnswered > 0
        ? (totalCorrect / totalAnswered) * 100
        : 0.0;
    final activeWrongCount = allQuestions
        .where((q) => !q.isCorrect && !q.isMastered)
        .length;

    return {
      'total_drills': totalDrills,
      'total_answered': totalAnswered,
      'total_correct': totalCorrect,
      'total_wrong': totalWrong,
      'accuracy_percentage': accuracy,
      'active_wrong_count': activeWrongCount,
    };
  }

  // --- Spaced Repetition (Ebbinghaus Forgetting Curve) Queries ---

  Stream<List<SpacedReviewItem>> watchAllSpacedReviewItems() {
    return (select(spacedReviewItems)..orderBy([
          (t) => OrderingTerm(
            expression: t.nextReviewDate,
            mode: OrderingMode.asc,
          ),
          (t) => OrderingTerm(expression: t.id, mode: OrderingMode.asc),
        ]))
        .watch();
  }

  Stream<List<SpacedReviewItem>> watchDueSpacedReviewItems() {
    final now = DateTime.now();
    return (select(spacedReviewItems)
          ..where(
            (t) =>
                t.nextReviewDate.isSmallerOrEqualValue(now) &
                t.isMastered.equals(false),
          )
          ..orderBy([
            (t) => OrderingTerm(
              expression: t.nextReviewDate,
              mode: OrderingMode.asc,
            ),
          ]))
        .watch();
  }

  Future<List<SpacedReviewItem>> getDueSpacedReviewItems() {
    final now = DateTime.now();
    return (select(spacedReviewItems)
          ..where(
            (t) =>
                t.nextReviewDate.isSmallerOrEqualValue(now) &
                t.isMastered.equals(false),
          )
          ..orderBy([
            (t) => OrderingTerm(
              expression: t.nextReviewDate,
              mode: OrderingMode.asc,
            ),
          ]))
        .get();
  }

  Future<int> insertSpacedReviewItem(SpacedReviewItemsCompanion entry) {
    return into(spacedReviewItems).insert(entry);
  }

  Future<int> insertSpacedReviewItemsBatch(
    List<SpacedReviewItemsCompanion> entries,
  ) async {
    if (entries.isEmpty) return 0;
    return transaction(() async {
      int count = 0;
      for (final entry in entries) {
        await into(spacedReviewItems).insert(entry);
        count++;
      }
      return count;
    });
  }

  Future<bool> advanceSpacedReview(int id) async {
    final item = await (select(
      spacedReviewItems,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (item == null) return false;

    final nextLevel = item.repetitionLevel + 1;
    int nextInterval;
    bool isMastered = false;

    switch (nextLevel) {
      case 2:
        nextInterval = 3;
        break;
      case 3:
        nextInterval = 7;
        break;
      case 4:
        nextInterval = 14;
        break;
      case 5:
        nextInterval = 30;
        break;
      default:
        nextInterval = 60;
        isMastered = true;
    }

    final now = DateTime.now();
    final nextDate = now.add(Duration(days: nextInterval));

    final rows =
        await (update(spacedReviewItems)..where((t) => t.id.equals(id))).write(
          SpacedReviewItemsCompanion(
            repetitionLevel: Value(nextLevel),
            intervalDays: Value(nextInterval),
            nextReviewDate: Value(nextDate),
            lastReviewedAt: Value(now),
            isMastered: Value(isMastered),
          ),
        );
    return rows > 0;
  }

  Future<bool> resetSpacedReview(int id) async {
    final now = DateTime.now();
    final nextDate = now.add(const Duration(days: 1));

    final rows =
        await (update(spacedReviewItems)..where((t) => t.id.equals(id))).write(
          SpacedReviewItemsCompanion(
            repetitionLevel: const Value(1),
            intervalDays: const Value(1),
            nextReviewDate: Value(nextDate),
            lastReviewedAt: Value(now),
            isMastered: const Value(false),
          ),
        );
    return rows > 0;
  }

  Future<int> deleteSpacedReviewItem(int id) {
    return (delete(spacedReviewItems)..where((t) => t.id.equals(id))).go();
  }

  // --- GitHub-Style Study Activity Heatmap & Subject Analytics ---

  Future<Map<String, dynamic>> getActivityHeatmapData({
    int daysBack = 98,
  }) async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final startDate = todayStart.subtract(Duration(days: daysBack));

    final drills = await (select(
      drillRecords,
    )..where((t) => t.createdAt.isBiggerOrEqualValue(startDate))).get();

    final energyLogs = await (select(
      dailyEnergyLogs,
    )..where((t) => t.date.isBiggerOrEqualValue(startDate))).get();

    final questions = await (select(
      drillQuestions,
    )..where((t) => t.attemptedAt.isBiggerOrEqualValue(startDate))).get();

    final Map<String, int> dailyScores = {};
    final Map<String, Map<String, dynamic>> dailyDetails = {};

    for (int i = 0; i <= daysBack; i++) {
      final d = startDate.add(Duration(days: i));
      final key =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      dailyScores[key] = 0;
      dailyDetails[key] = {
        'drills': 0,
        'questions': 0,
        'correct': 0,
        'hasEnergyLog': false,
      };
    }

    for (final dr in drills) {
      final d = dr.createdAt;
      final key =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      dailyScores[key] = (dailyScores[key] ?? 0) + 2;
      if (dailyDetails.containsKey(key)) {
        dailyDetails[key]!['drills'] =
            (dailyDetails[key]!['drills'] as int) + 1;
      }
    }

    for (final q in questions) {
      final d = q.attemptedAt;
      final key =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      dailyScores[key] = (dailyScores[key] ?? 0) + 1;
      if (dailyDetails.containsKey(key)) {
        dailyDetails[key]!['questions'] =
            (dailyDetails[key]!['questions'] as int) + 1;
        if (q.isCorrect) {
          dailyDetails[key]!['correct'] =
              (dailyDetails[key]!['correct'] as int) + 1;
        }
      }
    }

    for (final e in energyLogs) {
      final d = e.date;
      final key =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      dailyScores[key] = (dailyScores[key] ?? 0) + 1;
      if (dailyDetails.containsKey(key)) {
        dailyDetails[key]!['hasEnergyLog'] = true;
      }
    }

    int activeDaysCount = 0;
    int currentStreak = 0;
    bool streakBroken = false;

    for (int i = 0; i <= daysBack; i++) {
      final d = todayStart.subtract(Duration(days: i));
      final key =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final score = dailyScores[key] ?? 0;
      if (score > 0) {
        if (!streakBroken) currentStreak++;
      } else {
        if (i > 0) streakBroken = true;
      }
    }

    for (final score in dailyScores.values) {
      if (score > 0) activeDaysCount++;
    }

    return {
      'scores': dailyScores,
      'details': dailyDetails,
      'activeDays': activeDaysCount,
      'currentStreak': currentStreak,
      'totalDays': daysBack + 1,
    };
  }

  Future<List<Map<String, dynamic>>> getSubjectStudyDistribution() async {
    final allQuestions = await select(drillQuestions).get();
    final allTopics = await select(weakTopics).get();

    final Map<String, int> subjectCounts = {};
    for (final q in allQuestions) {
      subjectCounts[q.subject] = (subjectCounts[q.subject] ?? 0) + 1;
    }
    for (final t in allTopics) {
      subjectCounts[t.subject] = (subjectCounts[t.subject] ?? 0) + 2;
    }

    final total = subjectCounts.values.fold<int>(
      0,
      (sum, count) => sum + count,
    );
    if (total == 0) return [];

    final List<Map<String, dynamic>> result = [];
    subjectCounts.forEach((subject, count) {
      result.add({
        'subject': subject,
        'count': count,
        'percentage': (count / total) * 100.0,
      });
    });

    result.sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
    return result;
  }
}
