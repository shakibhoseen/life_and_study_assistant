import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('v8 data survives the upgrade to v11', () async {
    final file = File(
      '${Directory.systemTemp.createTempSync('mig').path}/app.sqlite',
    );

    // Build a v9 database, then roll it back to what v8 looked like so the
    // real onUpgrade runs over a populated file.
    var db = AppDatabase(NativeDatabase(file));
    final id = await db
        .into(db.drillQuestions)
        .insert(
          DrillQuestionsCompanion.insert(
            subject: 'Bangladesh Affairs',
            topic: 'জাতীয় প্রতীক',
            questionText: 'পতাকার অনুপাত কত?',
            optionsJson: jsonEncode(['৩:২', '৫:৩']),
            correctIndex: 0,
            selectedIndex: 1,
            isCorrect: false,
            explanation: const Value('১০:৬, অর্থাৎ ৩:২।'),
          ),
        );
    for (final c in [
      'original_correct_index',
      'original_explanation',
      'corrected_at',
      'original_question_text',
      'original_options_json',
      'verification_status',
      'verification_note',
      'verified_at',
    ]) {
      await db.customStatement('ALTER TABLE drill_questions DROP COLUMN $c');
    }
    await db.customStatement('PRAGMA user_version = 8');
    await db.close();

    db = AppDatabase(NativeDatabase(file));
    final row = await (db.select(
      db.drillQuestions,
    )..where((t) => t.id.equals(id))).getSingle();

    // The columns are back, empty, and the attempt is untouched.
    expect(row.originalCorrectIndex, isNull);
    expect(row.originalQuestionText, isNull);
    expect(row.verificationStatus, isNull);
    expect(row.verifiedAt, isNull);
    expect(row.originalOptionsJson, isNull);
    expect(row.correctedAt, isNull);
    expect(row.selectedIndex, 1);
    expect(row.isCorrect, isFalse);
    expect(row.questionText, 'পতাকার অনুপাত কত?');

    // And a correction still works on the migrated row.
    await db.acceptAnswerCorrection(
      id,
      correctedIndex: 1,
      correctedExplanation: '১০:৬ = ৫:৩।',
    );
    final fixed = await (db.select(
      db.drillQuestions,
    )..where((t) => t.id.equals(id))).getSingle();
    expect(fixed.correctIndex, 1);
    expect(fixed.originalCorrectIndex, 0);
    expect(fixed.selectedIndex, 1);

    await db.close();
  });
}
