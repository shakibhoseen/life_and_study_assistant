import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/services/ai/claim_math_checker.dart';
import 'package:life_and_study_assistant/core/services/ai/gemini_ai_service.dart';
import 'package:life_and_study_assistant/core/services/ai/gemini_result_cache.dart';
import 'package:life_and_study_assistant/core/services/ai/models/chat_verification_result.dart';
import 'package:life_and_study_assistant/core/services/ai/models/evidence_review.dart';
import 'package:life_and_study_assistant/core/services/ai/models/mcq_verification.dart';
import 'package:life_and_study_assistant/core/services/ai/models/verification_mark.dart';
import 'package:life_and_study_assistant/core/services/ai/models/verification_result.dart';

String solveReply({
  required int chosen,
  String reasoning = 'বিকল্পগুলো বিশ্লেষণ করে এটিই সঠিক মনে হয়।',
  double confidence = 0.8,
  String ambiguity = 'none',
  String basis = 'recall',
}) => jsonEncode({
  'chosen_index': chosen,
  'reasoning': reasoning,
  'confidence': confidence,
  'ambiguity': ambiguity,
  'basis': basis,
});

McqVerification decide(
  String raw, {
  required int storedIndex,
  String explanation = '',
  int optionCount = 4,
}) => McqVerification.decide(
  solve: GeminiAiService.decodeSolve(raw)!,
  storedIndex: storedIndex,
  storedExplanation: explanation,
  optionCount: optionCount,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('Independent Solve Tests', () {
    test('a different answer is flagged and a correction offered', () {
      final r = decide(solveReply(chosen: 2), storedIndex: 0);

      expect(r.verdict, VerificationVerdict.likelyIncorrect);
      expect(r.hasProposal, isTrue);
      expect(r.proposedIndex, 2);
      expect(r.agrees, isFalse);
    });

    test('agreement offers no correction', () {
      final r = decide(solveReply(chosen: 1), storedIndex: 1);

      expect(r.hasProposal, isFalse);
      expect(r.agrees, isTrue);
    });

    test('agreement alone is not independent verification', () {
      // Two models reaching the same answer are two opinions.
      final r = decide(solveReply(chosen: 1, basis: 'recall'), storedIndex: 1);

      expect(r.verdict, VerificationVerdict.inconclusive);
      expect(r.independentlyVerified, isFalse);
      expect(r.limitations, contains('স্বাধীন প্রমাণ নয়'));
    });

    test('agreement backed by a computation does reach verified', () {
      final r = decide(
        solveReply(chosen: 1, basis: 'computation'),
        storedIndex: 1,
      );

      expect(r.verdict, VerificationVerdict.supported);
      expect(r.independentlyVerified, isTrue);
    });

    test('every result says no external source was consulted', () {
      for (final raw in [solveReply(chosen: 0), solveReply(chosen: 3)]) {
        expect(
          decide(raw, storedIndex: 0).limitations,
          contains('External sources not checked'),
        );
      }
    });
  });

  group('Headline Tests', () {
    test('agreement says so instead of claiming nothing was learned', () {
      final r = decide(solveReply(chosen: 1), storedIndex: 1);

      expect(r.verdict, VerificationVerdict.inconclusive);
      expect(r.headline, 'স্বাধীনভাবে একই উত্তর এসেছে');
    });

    test('an ambiguous question names the ambiguity', () {
      final r = decide(
        solveReply(chosen: 1, ambiguity: 'multiple_correct'),
        storedIndex: 1,
      );

      expect(r.headline, 'প্রশ্নটি অস্পষ্ট');
    });

    test('a refusal to pick reads as unverified', () {
      final r = decide(solveReply(chosen: -1), storedIndex: 0);

      expect(r.headline, 'নিশ্চিতভাবে যাচাই করা যায়নি');
    });

    test('proof and disagreement keep their own headlines', () {
      expect(
        decide(
          solveReply(chosen: 1, basis: 'computation'),
          storedIndex: 1,
        ).headline,
        'প্রমাণসহ যাচাই হয়েছে',
      );
      expect(
        decide(solveReply(chosen: 2), storedIndex: 0).headline,
        'সম্ভবত ভুল',
      );
    });
  });

  group('Ambiguity Tests', () {
    test('multiple defensible options yield no correction', () {
      final r = decide(
        solveReply(chosen: 2, ambiguity: 'multiple_correct'),
        storedIndex: 0,
      );

      expect(r.verdict, VerificationVerdict.inconclusive);
      expect(r.hasProposal, isFalse);
      expect(r.limitations, contains('একাধিক অপশন'));
    });

    test('an unclear question yields no correction', () {
      final r = decide(
        solveReply(chosen: 1, ambiguity: 'unclear_question'),
        storedIndex: 0,
      );

      expect(r.verdict, VerificationVerdict.inconclusive);
      expect(r.hasProposal, isFalse);
    });

    test('refusing to pick is inconclusive, not a correction', () {
      final r = decide(solveReply(chosen: -1), storedIndex: 0);

      expect(r.verdict, VerificationVerdict.inconclusive);
      expect(r.hasProposal, isFalse);
    });

    test('an index outside the options is rejected', () {
      final r = decide(solveReply(chosen: 9), storedIndex: 0, optionCount: 4);

      expect(r.verdict, VerificationVerdict.inconclusive);
      expect(r.hasProposal, isFalse);
    });
  });

  group('Explanation Check Tests', () {
    test('a self-contradicting explanation is caught locally', () {
      final r = decide(
        solveReply(chosen: 0),
        storedIndex: 0,
        explanation: 'অনুপাত ১০:৬, অর্থাৎ ৩:২।',
      );

      expect(r.explanationCheck.outcome, MathCheckOutcome.fails);
      expect(r.explanationCheck.detail, contains('৫:৩'));
    });

    test('sound arithmetic in the explanation supports agreement', () {
      final r = decide(
        solveReply(chosen: 0, basis: 'recall'),
        storedIndex: 0,
        explanation: '২০ + ১ = ২১ শতাংশ।',
      );

      expect(r.verdict, VerificationVerdict.supported);
      expect(r.evidence, ClaimEvidence.localComputation);
    });
  });

  group('Malformed Output Tests', () {
    test('garbage is rejected', () {
      expect(GeminiAiService.decodeSolve('not json'), isNull);
      expect(GeminiAiService.decodeSolve(''), isNull);
      expect(GeminiAiService.decodeSolve('[1,2]'), isNull);
    });

    test('a reply with no reasoning is rejected', () {
      expect(
        GeminiAiService.decodeSolve(jsonEncode({'chosen_index': 1})),
        isNull,
      );
    });

    test('markdown fences are tolerated', () {
      expect(
        GeminiAiService.decodeSolve('```json\n${solveReply(chosen: 1)}\n```'),
        isNotNull,
      );
    });
  });

  group('Cache Key Tests', () {
    String keyFor(String payload) =>
        GeminiResultCache.instance.computeKeyFromString(
          operation: 'mcq_independent_solve',
          promptVersion: 'v1.0',
          model: 'gemini-flash-lite-latest',
          payloadText: payload,
        );

    test('the same question and options reuse the solve', () {
      const p = 'গণিত|অনুপাত|প্রশ্ন|ক~খ~গ~ঘ';
      expect(keyFor(p), keyFor(p));
    });

    test('changed options miss the cache', () {
      expect(
        keyFor('গণিত|অনুপাত|প্রশ্ন|ক~খ'),
        isNot(keyFor('গণিত|অনুপাত|প্রশ্ন|ক~গ')),
      );
    });
  });

  group('User Evidence Review Tests', () {
    String reviewReply({
      bool sound = true,
      int reviewerIndex = 1,
      String flaw = 'none',
      String question = '',
      List<String> options = const [],
      String reasoning = 'আপনার যুক্তিটি খতিয়ে দেখলাম।',
    }) => jsonEncode({
      'user_reasoning_sound': sound,
      'reviewer_index': reviewerIndex,
      'reasoning': reasoning,
      'question_flaw': flaw,
      'suggested_question_text': question,
      'suggested_options': options,
    });

    EvidenceReview? review(
      String raw, {
      String evidence = 'কোনো হিসাব নেই',
      int optionCount = 4,
      int storedIndex = 0,
    }) => GeminiAiService.decodeEvidenceReview(
      raw,
      userEvidence: evidence,
      optionCount: optionCount,
      storedIndex: storedIndex,
    );

    test(
      'a reviewer landing elsewhere means the stored answer looks wrong',
      () {
        final r = review(reviewReply(reviewerIndex: 1), storedIndex: 0)!;

        expect(r.verdict, EvidenceVerdict.storedLooksWrong);
        expect(r.suggestedCorrectIndex, 1);
      },
    );

    test('a reviewer landing on the stored answer leaves it alone', () {
      final r = review(reviewReply(reviewerIndex: 0), storedIndex: 0)!;

      expect(r.verdict, EvidenceVerdict.storedHolds);
      expect(r.suggestedCorrectIndex, isNull);
    });

    test('the verdict ignores what the reviewer thought of the user', () {
      // The reviewer siding with the user decides nothing by itself; where it
      // actually landed is what counts.
      final agreed = review(
        reviewReply(sound: true, reviewerIndex: 0),
        storedIndex: 0,
      )!;

      expect(agreed.verdict, EvidenceVerdict.storedHolds);
      expect(agreed.opinion.userReasoningSound, isTrue);
    });

    test('siding with the user is not by itself proof', () {
      final r = review(reviewReply(reviewerIndex: 2), storedIndex: 0)!;

      expect(r.settled, isFalse);
      expect(r.limitations, contains('স্বাধীন প্রমাণ নয়'));
    });

    test('sound user arithmetic settles the review', () {
      final r = review(reviewReply(), evidence: '১০:৬ মানে ৫:৩।')!;

      expect(r.userArithmeticHolds, isTrue);
      expect(r.settled, isTrue);
      expect(r.limitations, contains('যাচাই করা হয়েছে'));
    });

    test('a refusal to pick settles nothing', () {
      final r = review(reviewReply(reviewerIndex: -1), storedIndex: 0)!;

      expect(r.verdict, EvidenceVerdict.stillUnclear);
      expect(r.suggestedCorrectIndex, isNull);
    });

    test('duplicate options are never fixed by choosing between them', () {
      final r = review(
        reviewReply(flaw: 'duplicate_options', reviewerIndex: 2),
        storedIndex: 0,
      )!;

      expect(r.verdict, EvidenceVerdict.stillUnclear);
      expect(r.suggestedCorrectIndex, isNull);
      expect(r.flaw.label, contains('একই উত্তর'));
      expect(r.flaw.guidance, isNotEmpty);
    });

    test('an index outside the options is dropped', () {
      expect(
        review(reviewReply(reviewerIndex: 9))!.suggestedCorrectIndex,
        isNull,
      );
    });

    test('empty rewrites are not treated as suggestions', () {
      final r = review(reviewReply(reviewerIndex: 0), storedIndex: 0)!;

      expect(r.suggestedQuestionText, isNull);
      expect(r.suggestedOptions, isNull);
      expect(r.suggestsEdit, isFalse);
    });

    test('a rewritten question and option set come through', () {
      final r = review(
        reviewReply(
          flaw: 'duplicate_options',
          question: 'পতাকার দৈর্ঘ্য ও প্রস্থের অনুপাত কত?',
          options: ['৫ : ৩', '৩ : ২', '২ : ১', '৪ : ৩'],
        ),
      )!;

      expect(r.suggestedQuestionText, contains('অনুপাত'));
      expect(r.suggestedOptions, hasLength(4));
      expect(r.suggestsEdit, isTrue);
    });

    test('a half-empty option set is rejected rather than half-applied', () {
      expect(review(reviewReply(options: ['ক', '']))!.suggestedOptions, isNull);
    });

    test('malformed replies are rejected', () {
      expect(review('not json'), isNull);
      expect(review(jsonEncode({'reviewer_index': 1})), isNull);
    });
  });

  group('Verification Mark Tests', () {
    test('unknown and missing statuses read as no mark', () {
      expect(VerificationMark.parse(null), VerificationMark.none);
      expect(VerificationMark.parse(''), VerificationMark.none);
      expect(VerificationMark.parse('something_else'), VerificationMark.none);
    });

    test('a stored key survives the round trip', () {
      for (final m in VerificationMark.values) {
        if (m == VerificationMark.none) continue;
        expect(VerificationMark.parse(m.storageKey), m);
      }
    });

    test('only the user\'s own mark counts as trusted', () {
      expect(VerificationMark.userVerified.isTrusted, isTrue);
      expect(VerificationMark.modelAgreed.isTrusted, isFalse);
      expect(VerificationMark.flagged.isTrusted, isFalse);
    });
  });

  group('Correction Persistence Tests', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    Future<int> insertAttempt() => db
        .into(db.drillQuestions)
        .insert(
          DrillQuestionsCompanion.insert(
            subject: 'Bangladesh Affairs',
            topic: 'জাতীয় প্রতীক',
            questionText: 'পতাকার অনুপাত কত?',
            optionsJson: jsonEncode(['৩:২', '৫:৩', '২:১', '৪:৩']),
            correctIndex: 0,
            selectedIndex: 2,
            isCorrect: false,
            explanation: const Value('১০:৬, অর্থাৎ ৩:২।'),
          ),
        );

    Future<DrillQuestion> reload(int id) => (db.select(
      db.drillQuestions,
    )..where((t) => t.id.equals(id))).getSingle();

    test('rejecting a correction changes nothing', () async {
      final id = await insertAttempt();
      final before = await reload(id);

      // No accept call: the proposal is shown and nothing else happens.
      final after = await reload(id);
      expect(after.correctIndex, before.correctIndex);
      expect(after.explanation, before.explanation);
      expect(after.correctedAt, isNull);
    });

    test('accepting updates the answer and keeps the original', () async {
      final id = await insertAttempt();

      await db.acceptAnswerCorrection(
        id,
        correctedIndex: 1,
        correctedExplanation: '১০:৬ = ৫:৩।',
      );

      final row = await reload(id);
      expect(row.correctIndex, 1);
      expect(row.explanation, contains('৫:৩'));
      expect(row.originalCorrectIndex, 0);
      expect(row.originalExplanation, contains('৩:২'));
      expect(row.correctedAt, isNotNull);
    });

    test('the attempt itself survives a correction', () async {
      final id = await insertAttempt();

      await db.acceptAnswerCorrection(
        id,
        correctedIndex: 1,
        correctedExplanation: 'সংশোধিত।',
      );

      final row = await reload(id);
      // What the user answered, and how it was scored, are history.
      expect(row.selectedIndex, 2);
      expect(row.isCorrect, isFalse);
    });

    test('a second correction keeps the first snapshot', () async {
      final id = await insertAttempt();

      await db.acceptAnswerCorrection(
        id,
        correctedIndex: 1,
        correctedExplanation: 'এক।',
      );
      await db.acceptAnswerCorrection(
        id,
        correctedIndex: 3,
        correctedExplanation: 'দুই।',
      );

      final row = await reload(id);
      expect(row.correctIndex, 3);
      expect(row.originalCorrectIndex, 0);
      expect(row.originalExplanation, contains('৩:২'));
    });

    test('a correction can be reverted', () async {
      final id = await insertAttempt();

      await db.acceptAnswerCorrection(
        id,
        correctedIndex: 1,
        correctedExplanation: 'সংশোধিত।',
      );
      await db.revertAnswerCorrection(id);

      final row = await reload(id);
      expect(row.correctIndex, 0);
      expect(row.explanation, contains('৩:২'));
      expect(row.originalCorrectIndex, isNull);
      expect(row.correctedAt, isNull);
    });

    test('editing the question snapshots what it replaced', () async {
      final id = await insertAttempt();

      await db.applyQuestionEdit(
        id,
        questionText: 'পতাকার দৈর্ঘ্য ও প্রস্থের অনুপাত কত?',
        options: ['৫:৩', '৩:২', '২:১', '৪:৩'],
        correctIndex: 0,
        explanation: '১০:৬ = ৫:৩।',
      );

      final row = await reload(id);
      expect(row.questionText, contains('দৈর্ঘ্য ও প্রস্থ'));
      expect(row.correctIndex, 0);
      expect(row.originalQuestionText, 'পতাকার অনুপাত কত?');
      expect(row.originalOptionsJson, contains('৩:২'));
      expect(row.originalCorrectIndex, 0);
      expect(row.correctedAt, isNotNull);
    });

    test('an edit leaves the attempt alone', () async {
      final id = await insertAttempt();

      await db.applyQuestionEdit(id, correctIndex: 1);

      final row = await reload(id);
      expect(row.selectedIndex, 2);
      expect(row.isCorrect, isFalse);
    });

    test('only the fields passed are changed', () async {
      final id = await insertAttempt();
      final before = await reload(id);

      await db.applyQuestionEdit(id, questionText: 'নতুন প্রশ্ন?');

      final row = await reload(id);
      expect(row.questionText, 'নতুন প্রশ্ন?');
      expect(row.optionsJson, before.optionsJson);
      expect(row.correctIndex, before.correctIndex);
      expect(row.explanation, before.explanation);
    });

    test('an empty edit writes nothing at all', () async {
      final id = await insertAttempt();

      await db.applyQuestionEdit(id);

      expect((await reload(id)).correctedAt, isNull);
    });

    test('an edited question can be reverted whole', () async {
      final id = await insertAttempt();

      await db.applyQuestionEdit(
        id,
        questionText: 'নতুন প্রশ্ন?',
        options: ['ক', 'খ'],
        correctIndex: 1,
        explanation: 'নতুন ব্যাখ্যা।',
      );
      await db.revertAnswerCorrection(id);

      final row = await reload(id);
      expect(row.questionText, 'পতাকার অনুপাত কত?');
      expect(row.optionsJson, contains('৫:৩'));
      expect(row.correctIndex, 0);
      expect(row.originalQuestionText, isNull);
      expect(row.correctedAt, isNull);
    });

    test(
      'an edit after an answer correction keeps the first snapshot',
      () async {
        final id = await insertAttempt();

        await db.acceptAnswerCorrection(
          id,
          correctedIndex: 1,
          correctedExplanation: 'এক।',
        );
        await db.applyQuestionEdit(id, questionText: 'নতুন প্রশ্ন?');

        final row = await reload(id);
        expect(row.originalCorrectIndex, 0);
        expect(row.originalQuestionText, 'পতাকার অনুপাত কত?');
      },
    );

    test('a verification mark is saved and read back', () async {
      final id = await insertAttempt();

      await db.saveVerificationMark(
        id,
        status: VerificationMark.userVerified.storageKey,
        note: 'নিজে মিলিয়ে দেখেছি।',
      );

      final row = await reload(id);
      expect(
        VerificationMark.parse(row.verificationStatus),
        VerificationMark.userVerified,
      );
      expect(row.verificationNote, contains('মিলিয়ে'));
      expect(row.verifiedAt, isNotNull);
    });

    test('a mark says nothing about the answer itself', () async {
      final id = await insertAttempt();
      final before = await reload(id);

      await db.saveVerificationMark(
        id,
        status: VerificationMark.modelAgreed.storageKey,
      );

      final row = await reload(id);
      expect(row.correctIndex, before.correctIndex);
      expect(row.selectedIndex, before.selectedIndex);
      expect(row.isCorrect, before.isCorrect);
      expect(row.correctedAt, isNull);
    });

    test('editing the question drops the old mark', () async {
      final id = await insertAttempt();

      await db.saveVerificationMark(
        id,
        status: VerificationMark.modelAgreed.storageKey,
        note: 'একমত।',
      );
      await db.applyQuestionEdit(id, questionText: 'নতুন প্রশ্ন?');

      final row = await reload(id);
      // The old conclusion was about the old wording.
      expect(
        VerificationMark.parse(row.verificationStatus),
        VerificationMark.none,
      );
      expect(row.verificationNote, isNull);
      expect(row.verifiedAt, isNull);
    });

    test('a mark can be cleared on its own', () async {
      final id = await insertAttempt();

      await db.saveVerificationMark(
        id,
        status: VerificationMark.flagged.storageKey,
      );
      await db.clearVerificationMark(id);

      expect((await reload(id)).verificationStatus, isNull);
    });

    test('statistics are unchanged by a correction', () async {
      final id = await insertAttempt();
      final before = await db.getAllWeakTopics();

      await db.acceptAnswerCorrection(
        id,
        correctedIndex: 1,
        correctedExplanation: 'সংশোধিত।',
      );

      final row = await reload(id);
      // isCorrect drives the mistake list and the stats; it did not move.
      expect(row.isCorrect, isFalse);
      expect((await db.getAllWeakTopics()).length, before.length);
    });
  });
}
