import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/services/ai/models/quiz_question.dart';
import 'package:life_and_study_assistant/core/services/ai/quiz_batch_correction_service.dart';
import 'package:life_and_study_assistant/features/quiz/domain/external_audit_brief.dart';

/// The notebook copies its questions out with ids printed beside them, asks
/// another assistant to check them, and reads the reply back. Everything below
/// is about the join between those three: a reply keyed on the printed ids, a
/// verdict that changes no answer, and a reply that points at nothing.
void main() {
  QuizQuestion q(String text, {int correct = 0, String explanation = ''}) {
    return QuizQuestion(
      questionText: text,
      options: const ['ক-টা', 'খ-টা', 'গ-টা', 'ঘ-টা'],
      correctIndex: correct,
      explanation: explanation,
    );
  }

  final questions = [
    q('সামান্তরিকের কর্ণদ্বয়?', correct: 2, explanation: 'পুরোনো ব্যাখ্যা'),
    q('জর্জ বার্নার্ড শ-র নাটক?', correct: 3),
    q('কৃত্রিম হৃৎপিণ্ড প্রতিস্থাপন?', correct: 1),
  ];
  const ids = [180, 186, 136];

  group('finding the question', () {
    test('the printed id is what the reply comes back on', () {
      // The notebook shows [Q-180]; it does not show "question 1 of 3".
      final item = QuestionCorrectionItem.tryFromJson(
        {'question_id': 136, 'status': 'incorrect', 'proposed_correct_index': 2,
          'reason': 'নকশাকার আর প্রতিস্থাপনকারী আলাদা'},
        questions,
        questionIds: ids,
      );

      expect(item, isNotNull);
      expect(item!.questionIndex, 2);
      expect(item.proposedCorrectIndex, 2);
    });

    test('an id from another batch is dropped, not bent into range', () {
      expect(
        QuestionCorrectionItem.tryFromJson(
          {'question_id': 999, 'status': 'incorrect',
            'proposed_correct_index': 1, 'reason': 'x'},
          questions,
          questionIds: ids,
        ),
        isNull,
      );
    });

    test('a position still works when no ids were printed', () {
      final item = QuestionCorrectionItem.tryFromJson(
        {'question_index': 1, 'status': 'incorrect',
          'proposed_correct_index': 0, 'reason': 'x'},
        questions,
      );

      expect(item?.questionIndex, 1);
    });

    test('the serial the copy prints is one-based', () {
      // "প্রশ্ন ৩" in the copied text is the third question.
      final item = QuestionCorrectionItem.tryFromJson(
        {'serial': 3, 'status': 'incorrect', 'proposed_correct_index': 0,
          'reason': 'x'},
        questions,
      );

      expect(item?.questionIndex, 2);
    });

    test('a reply that names no question at all is dropped', () {
      expect(
        QuestionCorrectionItem.tryFromJson(
          {'status': 'incorrect', 'reason': 'কোথাও একটা ভুল আছে'},
          questions,
        ),
        isNull,
      );
    });
  });

  group('a verdict that changes no answer', () {
    test('ambiguous marks the question and leaves the key alone', () {
      final item = QuestionCorrectionItem.tryFromJson(
        {'question_id': 180, 'status': 'ambiguous',
          'proposed_correct_index': -1, 'reason': 'খ ও গ একই অর্থ'},
        questions,
        questionIds: ids,
      )!;

      expect(item.proposedCorrectIndex, isNull);
      expect(item.newExplanation, contains('পুরোনো ব্যাখ্যা'));
      expect(item.newExplanation, contains('একাধিক উত্তর সম্ভব'));
      expect(item.newExplanation, contains('খ ও গ একই অর্থ'));
      // It has to apply, or the flag never reaches the question.
      expect(item.hasEdit, isTrue);
    });

    test('doubt cannot move a key even when it names one', () {
      // An audit that says "not sure, but maybe খ" is still not sure.
      final item = QuestionCorrectionItem.tryFromJson(
        {'question_id': 186, 'status': 'needs_source',
          'proposed_correct_index': 0, 'reason': 'মূল বই দেখা দরকার'},
        questions,
        questionIds: ids,
      )!;

      expect(item.proposedCorrectIndex, isNull);
      expect(item.newExplanation, contains('উৎস যাচাই দরকার'));
    });

    test('a duplicate is flagged, never deleted on its own', () {
      final item = QuestionCorrectionItem.tryFromJson(
        {'question_id': 186, 'status': 'duplicate', 'reason': 'Q-184 একই'},
        questions,
        questionIds: ids,
      )!;

      expect(item.isDelete, isFalse);
      expect(item.proposedCorrectIndex, isNull);
      expect(item.newExplanation, contains('একই প্রশ্ন আরেকবার আছে'));
    });

    test('verified earns no mark and no edit', () {
      final item = QuestionCorrectionItem.tryFromJson(
        {'question_id': 180, 'status': 'verified', 'reason': 'ঠিক আছে'},
        questions,
        questionIds: ids,
      )!;

      expect(item.newExplanation, isNull);
      expect(item.hasEdit, isFalse);
    });

    test('a flag is not stacked twice on the same question', () {
      final marked = [
        q('x', correct: 1, explanation: 'ব্যাখ্যা\n⚠️ উৎস যাচাই দরকার: বই দেখুন'),
      ];

      final item = QuestionCorrectionItem.tryFromJson(
        {'question_id': 7, 'status': 'needs_source', 'reason': 'বই দেখুন'},
        marked,
        questionIds: const [7],
      )!;

      expect(item.newExplanation, isNull);
    });

    test('a stated correction still moves the key', () {
      final item = QuestionCorrectionItem.tryFromJson(
        {'question_id': 180, 'status': 'incorrect',
          'proposed_correct_index': 1, 'new_explanation': 'নতুন ব্যাখ্যা',
          'reason': 'কর্ণ সমদ্বিখণ্ডিত করে'},
        questions,
        questionIds: ids,
      )!;

      expect(item.proposedCorrectIndex, 1);
      expect(item.newExplanation, 'নতুন ব্যাখ্যা');
    });
  });

  group('the brief that goes out with the questions', () {
    test('it names the id, not the serial', () {
      expect(externalAuditBrief, contains('question_id'));
      expect(externalAuditBrief, contains('[Q-180]'));
    });

    test('it lists every verdict the reader understands', () {
      for (final status in QuestionAuditStatus.values) {
        if (status == QuestionAuditStatus.verified) continue;
        expect(
          externalAuditBrief,
          contains('"${status.wireName}"'),
          reason: '${status.wireName} is readable but never asked for',
        );
      }
    });

    test('it says doubt leaves the answer alone', () {
      expect(externalAuditBrief, contains('-1'));
      expect(externalAuditBrief, contains('[]'));
    });
  });

  group('the verdicts themselves', () {
    test('only doubt blocks an answer change', () {
      // A reply that just gives a corrected answer and names no verdict is
      // the ordinary case, and every reply written before this vocabulary
      // existed looks like that.
      expect(QuestionAuditStatus.verified.blocksAnswerChange, isFalse);
      expect(QuestionAuditStatus.incorrect.blocksAnswerChange, isFalse);
      expect(QuestionAuditStatus.ambiguous.blocksAnswerChange, isTrue);
      expect(QuestionAuditStatus.needsSource.blocksAnswerChange, isTrue);
      expect(QuestionAuditStatus.duplicate.blocksAnswerChange, isTrue);
    });

    test('a correction with no verdict at all still applies', () {
      final plain = QuestionCorrectionItem.tryFromJson(
        {'question_index': 0, 'proposed_correct_index': 3, 'reason': 'x'},
        [
          QuizQuestion(
            questionText: 'x',
            options: const ['a', 'b', 'c', 'd'],
            correctIndex: 0,
            explanation: '',
          ),
        ],
      )!;

      expect(plain.proposedCorrectIndex, 3);
    });

    test('unknown wording is read as verified, which changes nothing', () {
      expect(QuestionAuditStatus.parse('গোলমেলে'), QuestionAuditStatus.verified);
      expect(QuestionAuditStatus.parse(null), QuestionAuditStatus.verified);
      expect(
        QuestionAuditStatus.parse('NEEDS-SOURCE'),
        QuestionAuditStatus.needsSource,
      );
    });
  });
}
