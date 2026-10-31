import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/services/ai/models/quiz_question.dart';
import 'package:life_and_study_assistant/core/services/ai/quiz_batch_correction_service.dart';

/// Applies corrections the real model produced to a real database.
///
/// The model call lives in tool/correction_roundtrip.dart because
/// `flutter test` blocks outbound HTTP; this half reads what that wrote. With
/// no such file the test is skipped, so the ordinary suite stays offline.
const _file = String.fromEnvironment('ROUNDTRIP_FILE');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'corrections from the real model land correctly in the database',
    () async {
      final data =
          jsonDecode(File(_file).readAsStringSync()) as Map<String, dynamic>;
      final quiz = (data['quiz'] as List)
          .map(
            (q) => QuizQuestion(
              questionText: q['question'] as String,
              options: (q['options'] as List).cast<String>(),
              correctIndex: q['correct_index'] as int,
              explanation: q['explanation'] as String,
            ),
          )
          .toList();

      final corrections = (data['corrections'] as List)
          .whereType<Map<String, dynamic>>()
          .map((m) => QuestionCorrectionItem.tryFromJson(m, quiz))
          .nonNulls
          .toList();

      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final rows = <DrillQuestion>[];
      for (final q in quiz) {
        final id = await db
            .into(db.drillQuestions)
            .insert(
              DrillQuestionsCompanion.insert(
                subject: 'বাংলাদেশ বিষয়াবলী',
                topic: 'সাধারণ জ্ঞান',
                questionText: q.questionText,
                optionsJson: jsonEncode(q.options),
                correctIndex: q.correctIndex,
                selectedIndex: 0,
                isCorrect: false,
                explanation: Value(q.explanation),
              ),
            );
        rows.add(
          await (db.select(
            db.drillQuestions,
          )..where((t) => t.id.equals(id))).getSingle(),
        );
      }

      await QuizBatchCorrectionService.instance
          .applyCorrectionsToMistakeQuestions(
            db,
            drillQuestions: rows,
            corrections: corrections,
          );

      Future<DrillQuestion> row(int i) => (db.select(
        db.drillQuestions,
      )..where((t) => t.id.equals(rows[i].id))).getSingle();
      List<String> opts(DrillQuestion r) =>
          (jsonDecode(r.optionsJson) as List).cast<String>();

      final report = StringBuffer('\n');
      void check(String label, bool ok, String detail) =>
          report.writeln('${ok ? "OK  " : "BAD "} $label — $detail');

      final q1 = await row(0);
      check(
        'wrong answer repointed',
        opts(q1)[q1.correctIndex] == 'শাপলা',
        'answer "${opts(q1)[q1.correctIndex]}"',
      );

      final q2 = await row(1);
      check(
        'missing answer added to options',
        opts(q2).contains('দোয়েল') && opts(q2)[q2.correctIndex] == 'দোয়েল',
        'answer "${opts(q2)[q2.correctIndex]}" in ${opts(q2)}',
      );

      final q3 = await row(2);
      check(
        'garbled question rewritten',
        !q3.questionText.contains('কপবসয়'),
        '"${q3.questionText}"',
      );

      final q4 = await row(3);
      check(
        'answer kept where only the explanation was wrong',
        opts(q4)[q4.correctIndex] == '১০০০',
        'answer "${opts(q4)[q4.correctIndex]}"',
      );
      check(
        'wrong explanation replaced',
        !q4.explanation.contains('১০০ মিটার') ||
            q4.explanation.contains('১০০০ মিটার'),
        '"${q4.explanation}"',
      );

      final q5 = await row(4);
      check(
        'duplicate options replaced',
        !(opts(q5).contains('১০:৬') && opts(q5).contains('৫:৩')),
        'options ${opts(q5)}',
      );

      final q6 = await row(5);
      check(
        'clean question untouched',
        q6.correctedAt == null,
        q6.correctedAt == null ? 'not modified' : 'MODIFIED',
      );

      // ignore: avoid_print
      print(report);
      expect(corrections, isNotEmpty);
    },
    skip: _file.isEmpty ? 'needs --dart-define=ROUNDTRIP_FILE' : null,
  );
}
