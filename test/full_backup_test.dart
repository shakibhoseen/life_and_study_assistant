import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/config/notification_constants.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/database/tables/syllabus_progress_table.dart';
import 'package:life_and_study_assistant/core/services/export/preference_backup.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A backup is only worth what it brings back. Version 1 held four tables and
/// left out the record of actually working through them — the drill history
/// the heatmap is drawn from, the spaced-repetition schedule, the settings —
/// so a restore returned the questions and none of the progress.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  Future<void> seed() async {
    await db.into(db.drillRecords).insert(
          DrillRecordsCompanion.insert(
            subject: 'বাংলা',
            topic: 'কারক',
            totalQuestions: 10,
            correctCount: 7,
            incorrectCount: 3,
            scorePercentage: 70,
          ),
        );
    await db.into(db.spacedReviewItems).insert(
          SpacedReviewItemsCompanion.insert(
            subject: 'বাংলা',
            topic: 'সমাস',
            title: 'দ্বন্দ্ব সমাস',
            keyRule: 'উভয় পদের অর্থ প্রধান',
            nextReviewDate: DateTime(2026, 11, 20),
          ),
        );
    await db.into(db.appSettings).insert(
          AppSettingsCompanion.insert(key: 'theme', value: 'oled'),
        );
    await db.into(db.referenceSheets).insert(
          ReferenceSheetsCompanion.insert(
            sheetKey: 'custom_law_articles',
            title: 'সংবিধানের গুরুত্বপূর্ণ অনুচ্ছেদ',
            category: 'আইন ও সংবিধান',
            subject: const Value('বাংলাদেশ বিষয়াবলী'),
            note: const Value('পরীক্ষার জন্য জরুরি'),
            columnsJson: '["অনুচ্ছেদ", "বিষয়", "টীকা"]',
            isCustom: const Value(true),
          ),
        );
    await db.into(db.referenceRows).insert(
          ReferenceRowsCompanion.insert(
            sheetKey: 'custom_law_articles',
            cellsJson: '["অনুচ্ছেদ ৭ক", "সংবিধান লঙ্ঘন", "রাষ্ট্রদ্রোহিতার অপরাধ"]',
            note: const Value('পঞ্চদশ সংশোধনীতে যুক্ত'),
            isCustom: const Value(true),
            detail: const Value('সংবিধান স্থগিত বা বাতিল রাষ্ট্রদ্রোহিতা হিসেবে গণ্য হবে।'),
          ),
        );
    await db.into(db.syllabusProgress).insert(
          SyllabusProgressCompanion.insert(
            nodeKey: 'math_algebra_formulas',
            status: SyllabusStatus.done,
            source: SyllabusProgressSource.self,
          ),
        );
  }

  group('what the file carries', () {
    test('the pieces version 1 left behind are in it now', () async {
      await seed();

      final decoded =
          jsonDecode(await db.exportBackupJson()) as Map<String, dynamic>;

      expect(decoded['version'], 2);
      // The database ships with seeded review cards, so these are checked by
      // what they contain rather than by how many there are.
      expect(jsonEncode(decoded['drill_records']), contains('কারক'));
      expect(
        jsonEncode(decoded['spaced_review_items']),
        contains('দ্বন্দ্ব সমাস'),
      );
      // The settings table ships with defaults, so this one is only ever
      // asked to be non-empty.
      expect((decoded['app_settings'] as List), isNotEmpty);
      expect(jsonEncode(decoded['reference_sheets']), contains('custom_law_articles'));
      expect(jsonEncode(decoded['reference_rows']), contains('অনুচ্ছেদ ৭ক'));
      expect(jsonEncode(decoded['syllabus_progress']), contains('math_algebra_formulas'));
    });

    test('a round trip brings them all back', () async {
      await seed();
      final json = await db.exportBackupJson();

      final fresh = AppDatabase(NativeDatabase.memory());
      final result = await fresh.importBackupJson(json);

      expect(result['drill_records'], 1);
      expect(result['spaced_reviews'], greaterThanOrEqualTo(1));
      expect(result['settings'], greaterThanOrEqualTo(1));
      expect(result['reference_rows'], greaterThanOrEqualTo(1));
      expect(result['syllabus_progress'], greaterThanOrEqualTo(1));

      final reviews = await fresh.select(fresh.spacedReviewItems).get();
      final restored = reviews.firstWhere((r) => r.title == 'দ্বন্দ্ব সমাস');
      expect(restored.keyRule, 'উভয় পদের অর্থ প্রধান');

      final drills = await fresh.select(fresh.drillRecords).get();
      expect(drills.single.correctCount, 7);

      final rows = await fresh.select(fresh.referenceRows).get();
      final restoredRow = rows.firstWhere((r) => r.sheetKey == 'custom_law_articles');
      expect(restoredRow.note, 'পঞ্চদশ সংশোধনীতে যুক্ত');
      expect(restoredRow.detail, contains('রাষ্ট্রদ্রোহিতা'));

      final progress = await fresh.select(fresh.syllabusProgress).get();
      final restoredProg = progress.firstWhere((p) => p.nodeKey == 'math_algebra_formulas');
      expect(restoredProg.status, SyllabusStatus.done);

      await fresh.close();
    });

    test('restoring the same file twice does not double anything', () async {
      await seed();
      final json = await db.exportBackupJson();

      final before = (await db.select(db.spacedReviewItems).get()).length;
      await db.importBackupJson(json);

      expect(await db.select(db.drillRecords).get(), hasLength(1));
      expect(await db.select(db.spacedReviewItems).get(), hasLength(before));
    });

    test('a version 1 file still restores', () async {
      // Somebody's only copy may be months old.
      const old = '{"version": 1, "weak_topics": [], "exam_schedules": [], '
          '"daily_energy_logs": [], "drill_questions": []}';

      expect(await db.importBackupJson(old), isNotEmpty);
    });
  });

  group('the settings that live outside the database', () {
    test('they are collected and put back', () async {
      SharedPreferences.setMockInitialValues({
        'pref_model': 'gemini-flash-latest',
        'scan_trust_printed': true,
        'study_tasks_done_2026-11-10': ['task_a'],
      });

      final saved = await PreferenceBackup.collect();
      expect(saved['pref_model'], 'gemini-flash-latest');
      expect(saved['scan_trust_printed'], true);
      expect(saved['study_tasks_done_2026-11-10'], ['task_a']);

      SharedPreferences.setMockInitialValues({});
      expect(await PreferenceBackup.restore(saved), 3);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pref_model'), 'gemini-flash-latest');
      expect(prefs.getStringList('study_tasks_done_2026-11-10'), ['task_a']);
    });

    test('the API key is never written to the file', () async {
      SharedPreferences.setMockInitialValues({
        NotificationConstants.prefGeminiApiKey: 'AQ.secret-value',
        'pref_model': 'gemini-flash-latest',
      });

      final saved = await PreferenceBackup.collect();

      // A backup goes to Downloads, gets mailed, gets copied to a laptop.
      expect(saved.containsKey(NotificationConstants.prefGeminiApiKey), isFalse);
      expect(jsonEncode(saved), isNot(contains('secret-value')));
      expect(saved['pref_model'], 'gemini-flash-latest');
    });

    test('a restore cannot overwrite a key entered since', () async {
      SharedPreferences.setMockInitialValues({
        NotificationConstants.prefGeminiApiKey: 'the-new-key',
      });

      await PreferenceBackup.restore({
        NotificationConstants.prefGeminiApiKey: 'an-old-key',
        'pref_model': 'x',
      });

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(NotificationConstants.prefGeminiApiKey),
        'the-new-key',
      );
    });

    test('the bubble\'s own scratch state is left out', () async {
      SharedPreferences.setMockInitialValues({
        'bubble_draft_text': 'গতকালের আধখানা বাক্য',
        'pref_model': 'x',
      });

      final saved = await PreferenceBackup.collect();

      // Restoring yesterday's half-sentence onto today's screen helps nobody.
      expect(saved.containsKey('bubble_draft_text'), isFalse);
    });
  });
}
