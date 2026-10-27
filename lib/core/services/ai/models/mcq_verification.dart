import '../claim_math_checker.dart';
import 'chat_verification_result.dart';
import 'verification_result.dart';

/// Why a question might not have one defensible answer.
enum McqAmbiguity {
  none,
  multipleCorrect,
  unclearQuestion;

  static McqAmbiguity parse(String? raw) =>
      switch ((raw ?? '').trim().toLowerCase()) {
        'multiple_correct' => McqAmbiguity.multipleCorrect,
        'unclear_question' => McqAmbiguity.unclearQuestion,
        _ => McqAmbiguity.none,
      };

  String get label => switch (this) {
    McqAmbiguity.none => '',
    McqAmbiguity.multipleCorrect => 'একাধিক অপশন সঠিক হতে পারে',
    McqAmbiguity.unclearQuestion => 'প্রশ্নটি অস্পষ্ট',
  };
}

/// The verifier's own answer, worked out without being shown the stored one.
class IndependentSolve {
  /// Which option it picked, or -1 when it would not commit.
  final int chosenIndex;
  final String reasoning;
  final double confidence;
  final McqAmbiguity ambiguity;

  /// What the pick rests on. `recall` means it is remembering, which is not
  /// verification however sure it sounds.
  final ClaimEvidence basis;

  const IndependentSolve({
    required this.chosenIndex,
    required this.reasoning,
    required this.confidence,
    this.ambiguity = McqAmbiguity.none,
    this.basis = ClaimEvidence.none,
  });

  static IndependentSolve? tryFromJson(Map<String, Object?> json) {
    final reasoning = (json['reasoning'] ?? '').toString().trim();
    if (reasoning.isEmpty) return null;

    final rawIndex = json['chosen_index'];
    final rawConfidence = json['confidence'];

    return IndependentSolve(
      chosenIndex: rawIndex is num ? rawIndex.toInt() : -1,
      reasoning: reasoning,
      confidence: rawConfidence is num
          ? rawConfidence.toDouble().clamp(0.0, 1.0)
          : 0.0,
      ambiguity: McqAmbiguity.parse(json['ambiguity']?.toString()),
      basis: switch ((json['basis'] ?? '').toString().trim().toLowerCase()) {
        'computation' => ClaimEvidence.localComputation,
        'internal_logic' => ClaimEvidence.internalConsistency,
        _ => ClaimEvidence.none,
      },
    );
  }
}

/// The app's own conclusion about a stored MCQ.
///
/// The verdict is worked out here rather than asked of the model, because the
/// model was never told what the stored answer is. All it did was answer the
/// question; the comparison, and what that comparison is worth, is the app's
/// judgement.
class McqVerification {
  final VerificationVerdict verdict;
  final IndependentSolve solve;

  /// The answer currently saved on the question.
  final int storedIndex;

  /// Set when the verifier landed somewhere else and a correction is on offer.
  final int? proposedIndex;

  /// What the stored explanation's own arithmetic came to, when it had any.
  final MathCheck explanationCheck;

  final ClaimEvidence evidence;
  final String limitations;

  const McqVerification({
    required this.verdict,
    required this.solve,
    required this.storedIndex,
    required this.explanationCheck,
    required this.evidence,
    required this.limitations,
    this.proposedIndex,
  });

  bool get hasProposal => proposedIndex != null;

  /// Something is demonstrably wrong here, whether or not a better option was
  /// named: a stored explanation whose own arithmetic fails is a problem even
  /// when the verifier picked the same option.
  bool get hasProblem =>
      hasProposal || explanationCheck.outcome == MathCheckOutcome.fails;
  bool get agrees => solve.chosenIndex == storedIndex;

  /// True only where something was actually settled, not merely agreed on.
  bool get independentlyVerified => evidence != ClaimEvidence.none;

  /// What to call the result on screen.
  ///
  /// Three different things end up inconclusive — the model agreed but proved
  /// nothing, the question has no single answer, or the model would not pick.
  /// Calling all three "could not verify" undersells the first and hides the
  /// second, so each says what actually happened.
  String get headline => switch (verdict) {
    VerificationVerdict.supported => 'প্রমাণসহ যাচাই হয়েছে',
    VerificationVerdict.likelyIncorrect => 'সম্ভবত ভুল',
    VerificationVerdict.inconclusive
        when solve.ambiguity != McqAmbiguity.none =>
      'প্রশ্নটি অস্পষ্ট',
    // Saying "the verifier agreed" above a red arithmetic mismatch reads as
    // reassurance the result does not support, so the mismatch leads.
    VerificationVerdict.inconclusive
        when explanationCheck.outcome == MathCheckOutcome.fails =>
      'ব্যাখ্যার হিসাব মিলছে না',
    VerificationVerdict.inconclusive when agrees =>
      'স্বাধীনভাবে একই উত্তর এসেছে',
    VerificationVerdict.inconclusive => 'নিশ্চিতভাবে যাচাই করা যায়নি',
  };

  /// Decides what the app is willing to say, given an independent answer and
  /// the stored one.
  ///
  /// Two agreeing models are two opinions, not evidence, so agreement alone
  /// never reaches "verified". It gets there only when a deterministic check
  /// settled the arithmetic. Anything ambiguous stops at inconclusive and
  /// offers no correction, because a question with two defensible answers
  /// should not be rewritten on one model's preference.
  static McqVerification decide({
    required IndependentSolve solve,
    required int storedIndex,
    required String storedExplanation,
    required int optionCount,
  }) {
    final mathCheck = ClaimMathChecker.check(storedExplanation);
    const noSources = 'External sources not checked';

    // A question that does not have one defensible answer is not a question
    // to correct.
    if (solve.ambiguity != McqAmbiguity.none) {
      return McqVerification(
        verdict: VerificationVerdict.inconclusive,
        solve: solve,
        storedIndex: storedIndex,
        explanationCheck: mathCheck,
        evidence: ClaimEvidence.none,
        limitations: '${solve.ambiguity.label} · $noSources',
      );
    }

    final chosen = solve.chosenIndex;
    final validPick = chosen >= 0 && chosen < optionCount;

    if (!validPick) {
      return McqVerification(
        verdict: VerificationVerdict.inconclusive,
        solve: solve,
        storedIndex: storedIndex,
        explanationCheck: mathCheck,
        evidence: ClaimEvidence.none,
        limitations: 'যাচাইকারী কোনো অপশনে স্থির হতে পারেনি · $noSources',
      );
    }

    if (chosen != storedIndex) {
      return McqVerification(
        verdict: VerificationVerdict.likelyIncorrect,
        solve: solve,
        storedIndex: storedIndex,
        proposedIndex: chosen,
        explanationCheck: mathCheck,
        evidence: ClaimEvidence.none,
        limitations: noSources,
      );
    }

    // Agreement. Worth something only if a computation backed it.
    final settled =
        solve.basis == ClaimEvidence.localComputation ||
        mathCheck.outcome == MathCheckOutcome.holds;

    return McqVerification(
      verdict: settled
          ? VerificationVerdict.supported
          : VerificationVerdict.inconclusive,
      solve: solve,
      storedIndex: storedIndex,
      explanationCheck: mathCheck,
      evidence: settled ? ClaimEvidence.localComputation : ClaimEvidence.none,
      limitations: settled
          ? 'গাণিতিকভাবে যাচাই করা · $noSources'
          : mathCheck.outcome == MathCheckOutcome.fails
          ? 'যাচাইকারী একই উত্তর দিলেও সংরক্ষিত ব্যাখ্যার হিসাব মিলছে না · $noSources'
          : 'যাচাইকারীও একই উত্তর দিয়েছে, তবে এটি স্বাধীন প্রমাণ নয় · $noSources',
    );
  }
}
