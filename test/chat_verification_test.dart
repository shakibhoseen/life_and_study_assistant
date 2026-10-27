import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:life_and_study_assistant/core/services/ai/gemini_ai_service.dart';
import 'package:life_and_study_assistant/core/services/ai/gemini_result_cache.dart';
import 'package:life_and_study_assistant/core/services/ai/models/chat_verification_result.dart';
import 'package:life_and_study_assistant/core/services/ai/models/verification_result.dart';
import 'package:life_and_study_assistant/features/chat/domain/chat_verifiability.dart';

Map<String, Object?> claim({
  required String text,
  String kind = 'factual',
  String verdict = 'inconclusive',
  String reasoning = 'বাইরের উৎস ছাড়া নিশ্চিত নয়।',
  double confidence = 0.5,
}) => {
  'text': text,
  'kind': kind,
  'verdict': verdict,
  'reasoning': reasoning,
  'confidence': confidence,
};

String reply({
  required List<Map<String, Object?>> claims,
  int? found,
  int? evaluated,
  bool complete = true,
  String note = '',
}) => jsonEncode({
  'claims_found': found ?? claims.length,
  'claims_evaluated': evaluated ?? claims.length,
  'extraction_complete': complete,
  'extraction_note': note,
  'claims': claims,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('Claim Verdict Tests', () {
    test('a factual claim stays inconclusive without a source', () {
      final r = GeminiAiService.decodeChatVerification(
        reply(
          claims: [
            claim(text: '১৯৭১ সালের ১৭ এপ্রিল পতাকার রূপ চূড়ান্ত হয়।'),
          ],
        ),
      )!;

      expect(r.claims.single.verdict, VerificationVerdict.inconclusive);
      expect(r.claims.single.kind, ClaimKind.factual);
      expect(r.claims.single.kind.needsExternalEvidence, isTrue);
      expect(r.externalSourcesChecked, isFalse);
    });

    test('mixed claims keep their own verdicts', () {
      final r = GeminiAiService.decodeChatVerification(
        reply(
          claims: [
            claim(
              text: 'লাল বৃত্ত পতাকার ঠিক মাঝখানে নয়।',
              kind: 'logical',
              verdict: 'supported',
              reasoning: 'ব্যাখ্যার সাথে সঙ্গতিপূর্ণ।',
            ),
            claim(text: 'সবুজ রঙ শস্যের প্রতীক।'),
          ],
        ),
      )!;

      expect(r.countOf(VerificationVerdict.supported), 1);
      expect(r.countOf(VerificationVerdict.inconclusive), 1);
      expect(r.hasProblem, isFalse);
    });

    test('a wrong claim among right ones is surfaced', () {
      final r = GeminiAiService.decodeChatVerification(
        reply(
          claims: [
            claim(
              text: 'ঠিক কথা।',
              kind: 'logical',
              verdict: 'supported',
              reasoning: 'ঠিক।',
            ),
            claim(
              text: 'ভুল কথা।',
              kind: 'logical',
              verdict: 'likely_incorrect',
              reasoning: 'স্ববিরোধী।',
            ),
          ],
        ),
      )!;

      expect(r.hasProblem, isTrue);
      expect(r.countOf(VerificationVerdict.likelyIncorrect), 1);
    });
  });

  group('Local Arithmetic Override Tests', () {
    test('a computation overrules the model on a ratio', () {
      // The model called it supported; the gcd says otherwise, and the gcd wins.
      final r = GeminiAiService.decodeChatVerification(
        reply(
          claims: [
            claim(
              text: 'পতাকার অনুপাত ১০:৬, অর্থাৎ ৩:২।',
              kind: 'factual',
              verdict: 'supported',
              reasoning: 'মনে হয় ঠিক।',
              confidence: 0.9,
            ),
          ],
        ),
      )!;

      final c = r.claims.single;
      expect(c.verdict, VerificationVerdict.likelyIncorrect);
      expect(c.kind, ClaimKind.mathematical);
      expect(c.checkedLocally, isTrue);
      expect(c.confidence, 1.0);
      expect(c.reasoning, contains('৫:৩'));
    });

    test('a claim with no arithmetic keeps the model verdict', () {
      final r = GeminiAiService.decodeChatVerification(
        reply(
          claims: [
            claim(
              text: 'ব্রহ্মপুত্র মানস সরোবর থেকে উৎপন্ন।',
              verdict: 'inconclusive',
              reasoning: 'উৎস ছাড়া নিশ্চিত নয়।',
            ),
          ],
        ),
      )!;

      expect(r.claims.single.checkedLocally, isFalse);
      expect(r.claims.single.verdict, VerificationVerdict.inconclusive);
    });
  });

  group('Evidence Policy Override Tests', () {
    test('a remembered fact the model called supported is refused', () {
      // This is the failure seen on device: three grammar claims marked
      // "factual", all returned supported with confident prose.
      final r = GeminiAiService.decodeChatVerification(
        reply(
          claims: [
            claim(
              text: 'দ্বন্দ্ব সমাসে উভয় পদের অর্থ প্রধান থাকে।',
              kind: 'factual',
              verdict: 'supported',
              reasoning: 'এটি বাংলা ব্যাকরণের একটি অত্যন্ত প্রতিষ্ঠিত নিয়ম।',
              confidence: 0.95,
            ),
          ],
        ),
      )!;

      final c = r.claims.single;
      expect(c.verdict, VerificationVerdict.inconclusive);
      expect(c.downgraded, isTrue);
      expect(c.evidence, ClaimEvidence.none);
    });

    test("the model's confidence does not survive the refusal", () {
      final c = GeminiAiService.decodeChatVerification(
        reply(
          claims: [
            claim(
              text: 'একটি তথ্য।',
              kind: 'factual',
              verdict: 'supported',
              confidence: 0.99,
            ),
          ],
        ),
      )!.claims.single;

      // 0.99 measured its confidence in the fact, not in any verification.
      expect(c.confidence, 0.0);
    });

    test('calling something well established is not evidence', () {
      final c = GeminiAiService.decodeChatVerification(
        reply(
          claims: [
            claim(
              text: 'এটি সর্বজনস্বীকৃত।',
              kind: 'factual',
              verdict: 'supported',
              reasoning:
                  'This is a universally accepted, well-established fact.',
              confidence: 1.0,
            ),
          ],
        ),
      )!.claims.single;

      expect(c.verdict, VerificationVerdict.inconclusive);
      expect(c.evidence, ClaimEvidence.none);
    });

    test('a doubt the model raised is kept, not flattened to unverified', () {
      // likely_incorrect asserts doubt rather than verification, so refusing
      // it would tell the user less than the model did.
      final c = GeminiAiService.decodeChatVerification(
        reply(
          claims: [
            claim(
              text: 'সন্দেহজনক তথ্য।',
              kind: 'factual',
              verdict: 'likely_incorrect',
              reasoning: 'অন্য উৎসের সাথে মেলে না।',
            ),
          ],
        ),
      )!.claims.single;

      expect(c.verdict, VerificationVerdict.likelyIncorrect);
      expect(c.downgraded, isFalse);
    });

    test('an internal-consistency check may still be supported', () {
      final c = GeminiAiService.decodeChatVerification(
        reply(
          claims: [
            claim(
              text: 'ব্যাখ্যাটি নিজের সাথে সঙ্গতিপূর্ণ।',
              kind: 'logical',
              verdict: 'supported',
              reasoning: 'উত্তরের ভেতরেই মিলে যায়।',
            ),
          ],
        ),
      )!.claims.single;

      expect(c.verdict, VerificationVerdict.supported);
      expect(c.evidence, ClaimEvidence.internalConsistency);
    });

    test('a computation may still be supported', () {
      final c = GeminiAiService.decodeChatVerification(
        reply(
          claims: [
            claim(
              text: 'অনুপাত ১০:৬ অর্থাৎ ৫:৩।',
              kind: 'factual',
              verdict: 'inconclusive',
              reasoning: 'নিশ্চিত নই।',
            ),
          ],
        ),
      )!.claims.single;

      expect(c.verdict, VerificationVerdict.supported);
      expect(c.evidence, ClaimEvidence.localComputation);
      expect(c.confidence, 1.0);
    });

    test('one checked claim does not make the whole answer verified', () {
      final r = GeminiAiService.decodeChatVerification(
        reply(
          claims: [
            claim(
              text: '২ + ২ = ৪',
              kind: 'mathematical',
              verdict: 'supported',
              reasoning: 'ঠিক।',
            ),
            claim(text: 'প্রথম তথ্য।', kind: 'factual', verdict: 'supported'),
            claim(
              text: 'দ্বিতীয় তথ্য।',
              kind: 'factual',
              verdict: 'supported',
            ),
          ],
        ),
      )!;

      expect(r.claims.length, 3);
      expect(r.verifiableCount, 1);
      expect(r.countOf(VerificationVerdict.supported), 1);
      expect(r.countOf(VerificationVerdict.inconclusive), 2);
      expect(r.hasDowngrade, isTrue);
    });
  });

  group('Coverage Honesty Tests', () {
    test('partial coverage is visible, not hidden', () {
      final r = GeminiAiService.decodeChatVerification(
        reply(
          claims: [claim(text: 'একটি দাবি।')],
          found: 5,
          evaluated: 1,
          complete: false,
          note: 'উত্তরটি দীর্ঘ, সব দাবি দেখা যায়নি।',
        ),
      )!;

      expect(r.claimsFound, 5);
      expect(r.claimsEvaluated, 1);
      expect(r.isPartial, isTrue);
      expect(r.extractionNote, isNotEmpty);
    });

    test('counts cannot claim more coverage than there are claims', () {
      final r = GeminiAiService.decodeChatVerification(
        reply(claims: [claim(text: 'একটি')], found: 1, evaluated: 9),
      )!;

      expect(r.claimsEvaluated, 1);
    });

    test('a found count below the claim list is corrected upwards', () {
      final r = GeminiAiService.decodeChatVerification(
        reply(
          claims: [
            claim(text: 'ক'),
            claim(text: 'খ'),
          ],
          found: 1,
        ),
      )!;

      expect(r.claimsFound, 2);
      expect(r.isPartial, isFalse);
    });
  });

  group('Malformed Output Tests', () {
    test('garbage is rejected', () {
      expect(GeminiAiService.decodeChatVerification('not json'), isNull);
      expect(GeminiAiService.decodeChatVerification('[1,2]'), isNull);
      expect(GeminiAiService.decodeChatVerification(''), isNull);
    });

    test('an empty claim list is a failure, not an all-clear', () {
      expect(GeminiAiService.decodeChatVerification(reply(claims: [])), isNull);
    });

    test('claims missing text or reasoning are dropped', () {
      final r = GeminiAiService.decodeChatVerification(
        jsonEncode({
          'claims_found': 2,
          'claims_evaluated': 2,
          'extraction_complete': true,
          'claims': [
            {'text': '', 'reasoning': 'কিছু', 'verdict': 'supported'},
            claim(text: 'ভালো দাবি'),
          ],
        }),
      )!;

      expect(r.claims.length, 1);
    });

    test('markdown fences are tolerated', () {
      final wrapped = '```json\n${reply(claims: [claim(text: 'দাবি')])}\n```';
      expect(GeminiAiService.decodeChatVerification(wrapped), isNotNull);
    });
  });

  group('Verifiability Gate Tests', () {
    test('greetings and acknowledgements get no action', () {
      expect(ChatVerifiability.canVerify('ওয়ালাইকুম আসসালাম!'), isFalse);
      expect(ChatVerifiability.canVerify('ঠিক আছে।'), isFalse);
      expect(ChatVerifiability.canVerify(''), isFalse);
    });

    test('a factual answer gets one', () {
      const answer =
          'বাংলাদেশের জাতীয় পতাকার দৈর্ঘ্য ও প্রস্থের অনুপাত ১০:৬। লাল বৃত্তের '
          'ব্যাসার্ধ পতাকার দৈর্ঘ্যের এক-পঞ্চমাংশ এবং এটি ঠিক মাঝখানে থাকে না।';
      expect(ChatVerifiability.canVerify(answer), isTrue);
    });

    test('nothing is offered while the answer is still streaming', () {
      const answer =
          'বাংলাদেশের জাতীয় পতাকার দৈর্ঘ্য ও প্রস্থের অনুপাত ১০:৬। লাল বৃত্তের '
          'ব্যাসার্ধ পতাকার দৈর্ঘ্যের এক-পঞ্চমাংশ এবং এটি ঠিক মাঝখানে থাকে না।';
      expect(ChatVerifiability.canVerify(answer, isStreaming: true), isFalse);
    });

    test('a long answer with assertions but no digits still qualifies', () {
      const answer =
          'সমাস হলো একাধিক পদের একপদীকরণ, এবং এর মূল কারণ হলো ভাষাকে সংক্ষিপ্ত '
          'করা। দ্বন্দ্ব সমাসে উভয় পদ প্রধান হয় বলে এটি আলাদা।';
      expect(ChatVerifiability.canVerify(answer), isTrue);
    });
  });

  group('Follow-Up Context Tests', () {
    test('a follow-up carries the earlier turn', () {
      final ctx = ChatVerifiability.buildPriorContext(
        earlierUser: 'পতাকার অনুপাত কত?',
        earlierAnswer: 'অনুপাত ১০:৬।',
      );

      expect(ctx, contains('পতাকার অনুপাত কত?'));
      expect(ctx, contains('১০:৬'));
    });

    test('no earlier turn means no context, not a broken string', () {
      expect(ChatVerifiability.buildPriorContext(), '');
    });

    test('context is capped so a long thread cannot bloat the request', () {
      final ctx = ChatVerifiability.buildPriorContext(
        earlierAnswer: 'ক' * 4000,
        maxChars: 300,
      );
      expect(ctx.length, lessThanOrEqualTo(300));
    });
  });

  group('Cache Key Tests', () {
    String keyFor(String payload) =>
        GeminiResultCache.instance.computeKeyFromString(
          operation: 'chat_verification',
          promptVersion: 'v1.0',
          model: 'gemini-flash-lite-latest',
          payloadText: payload,
        );

    test('the same question, answer and context reuse a verdict', () {
      const p = 'ctx||প্রশ্ন||উত্তর';
      expect(keyFor(p), keyFor(p));
    });

    test('a different answer misses the cache', () {
      expect(
        keyFor('ctx||প্রশ্ন||উত্তর ১'),
        isNot(keyFor('ctx||প্রশ্ন||উত্তর ২')),
      );
    });

    test('the same answer under different context misses too', () {
      // A follow-up read against another thread is a different judgement.
      expect(
        keyFor('ctx A||প্রশ্ন||উত্তর'),
        isNot(keyFor('ctx B||প্রশ্ন||উত্তর')),
      );
    });
  });
}
