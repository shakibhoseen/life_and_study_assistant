import '../claim_math_checker.dart';
import 'verification_result.dart';

/// What kind of checking a claim admits of.
///
/// This is the distinction that matters without web access: arithmetic and
/// internal logic can be settled here, a fact about the world cannot.
enum ClaimKind {
  mathematical,
  logical,
  factual;

  static ClaimKind parse(String? raw) =>
      switch ((raw ?? '').trim().toLowerCase()) {
        'mathematical' || 'math' => ClaimKind.mathematical,
        'logical' => ClaimKind.logical,
        _ => ClaimKind.factual,
      };

  String get label => switch (this) {
    ClaimKind.mathematical => 'গাণিতিক',
    ClaimKind.logical => 'যৌক্তিক',
    ClaimKind.factual => 'তথ্যগত',
  };

  /// True when settling this needs a source the app cannot consult.
  bool get needsExternalEvidence => this == ClaimKind.factual;
}

/// What the app actually had to go on when it judged a claim.
///
/// This exists because a verdict alone cannot be trusted: the model will call
/// a remembered fact "well established" and hand back `supported` with high
/// confidence. The basis records what was really available, and the policy
/// below refuses to show a green tick without one.
enum ClaimEvidence {
  /// A deterministic calculation ran and settled it.
  localComputation,

  /// Checked against the answer's own text, which the app does have.
  internalConsistency,

  /// Nothing the app could check. Covers every factual claim for as long as
  /// there is no source retrieval.
  none;

  String get label => switch (this) {
    ClaimEvidence.localComputation => 'স্থানীয় হিসাব',
    ClaimEvidence.internalConsistency => 'অভ্যন্তরীণ সঙ্গতি',
    ClaimEvidence.none => 'উৎস নেই',
  };
}

class VerifiedClaim {
  /// The claim as it appears in the answer, so the user can see exactly what
  /// was checked rather than a paraphrase.
  final String text;

  final VerificationVerdict verdict;
  final ClaimKind kind;
  final String reasoning;
  final double confidence;

  /// Set when the deterministic checker had something to say. Where it did,
  /// its verdict is the one in [verdict]: a computation beats recall.
  final MathCheck? localCheck;

  /// What the verdict actually rests on.
  final ClaimEvidence evidence;

  /// True when the model called this supported and the policy below refused
  /// it for want of evidence. Surfaced so the UI can say so plainly.
  final bool downgraded;

  const VerifiedClaim({
    required this.text,
    required this.verdict,
    required this.kind,
    required this.reasoning,
    required this.confidence,
    this.localCheck,
    this.evidence = ClaimEvidence.none,
    this.downgraded = false,
  });

  bool get checkedLocally => localCheck?.isDecisive ?? false;

  /// Settles the verdict on what the app can actually stand behind.
  ///
  /// Three rules, applied in order:
  ///
  /// 1. A deterministic calculation wins outright. Dividing by the gcd beats
  ///    any amount of recall about what 10:6 reduces to.
  /// 2. An internal-consistency judgement may stand, because the text it
  ///    checks against is in hand.
  /// 3. Anything else that came back `supported` is forced to
  ///    `inconclusive`. Without retrieval the app has no way to confirm a
  ///    fact about the world, and the model calling one "well established"
  ///    is recall wearing the costume of verification.
  ///
  /// `likely_incorrect` is deliberately left alone by rule 3. It asserts
  /// doubt rather than verification, so downgrading it would throw away a
  /// real warning and tell the user less than the model did.
  VerifiedClaim applyVerificationPolicy() {
    final check = ClaimMathChecker.check(text);
    if (check.isDecisive) {
      return VerifiedClaim(
        text: text,
        verdict: check.outcome == MathCheckOutcome.fails
            ? VerificationVerdict.likelyIncorrect
            : VerificationVerdict.supported,
        kind: ClaimKind.mathematical,
        reasoning: check.detail,
        // A computation is certain in a way a recalled fact is not.
        confidence: 1.0,
        localCheck: check,
        evidence: ClaimEvidence.localComputation,
      );
    }

    if (kind == ClaimKind.logical) {
      return VerifiedClaim(
        text: text,
        verdict: verdict,
        kind: kind,
        reasoning: reasoning,
        confidence: confidence,
        evidence: ClaimEvidence.internalConsistency,
      );
    }

    if (verdict != VerificationVerdict.supported) {
      return VerifiedClaim(
        text: text,
        verdict: verdict,
        kind: kind,
        reasoning: reasoning,
        confidence: confidence,
        evidence: ClaimEvidence.none,
      );
    }

    return VerifiedClaim(
      text: text,
      verdict: VerificationVerdict.inconclusive,
      kind: kind,
      reasoning: reasoning,
      // The model's figure measured its confidence in the fact, not in any
      // verification, so carrying it over would dress up the same claim.
      confidence: 0.0,
      evidence: ClaimEvidence.none,
      downgraded: true,
    );
  }

  static VerifiedClaim? tryFromJson(Map<String, Object?> json) {
    final text = (json['text'] ?? '').toString().trim();
    final reasoning = (json['reasoning'] ?? '').toString().trim();
    if (text.isEmpty || reasoning.isEmpty) return null;

    final rawConfidence = json['confidence'];
    return VerifiedClaim(
      text: text,
      verdict: VerificationVerdict.parse(json['verdict']?.toString()),
      kind: ClaimKind.parse(json['kind']?.toString()),
      reasoning: reasoning,
      confidence: rawConfidence is num
          ? rawConfidence.toDouble().clamp(0.0, 1.0)
          : 0.0,
    );
  }
}

class ChatVerificationResult {
  /// How many verifiable claims the answer was judged to contain.
  final int claimsFound;

  /// How many of those actually came back with a verdict. Shown next to
  /// [claimsFound] so a check that covered three of seven claims cannot read
  /// as a check of the whole answer.
  final int claimsEvaluated;

  final bool extractionComplete;
  final String extractionNote;
  final List<VerifiedClaim> claims;

  /// False for as long as the app has no source retrieval.
  final bool externalSourcesChecked;

  const ChatVerificationResult({
    required this.claimsFound,
    required this.claimsEvaluated,
    required this.claims,
    this.extractionComplete = true,
    this.extractionNote = '',
    this.externalSourcesChecked = false,
  });

  bool get hasProblem =>
      claims.any((c) => c.verdict == VerificationVerdict.likelyIncorrect);

  /// True when the answer holds more claims than were looked at.
  bool get isPartial => !extractionComplete || claimsEvaluated < claimsFound;

  int countOf(VerificationVerdict v) =>
      claims.where((c) => c.verdict == v).length;

  /// How many claims the app could genuinely check, as opposed to merely
  /// read. Shown so a wall of "not verified" is not mistaken for a failure.
  int get verifiableCount =>
      claims.where((c) => c.evidence != ClaimEvidence.none).length;

  /// True when the model's own verdict was refused for at least one claim.
  bool get hasDowngrade => claims.any((c) => c.downgraded);

  /// Builds a result from a model reply, then puts every claim through
  /// [VerifiedClaim.applyVerificationPolicy] so no verdict survives that the
  /// app cannot stand behind.
  ///
  /// Returns null for anything unreadable, so a garbled reply surfaces as a
  /// failure rather than as an empty all-clear.
  static ChatVerificationResult? tryFromJson(Map<String, Object?>? json) {
    if (json == null) return null;

    final rawClaims = json['claims'];
    if (rawClaims is! List) return null;

    final claims = rawClaims
        .whereType<Map>()
        .map((c) => VerifiedClaim.tryFromJson(c.cast<String, Object?>()))
        .whereType<VerifiedClaim>()
        .map((c) => c.applyVerificationPolicy())
        .toList();

    if (claims.isEmpty) return null;

    final found = (json['claims_found'] as num?)?.toInt() ?? claims.length;
    final evaluated =
        (json['claims_evaluated'] as num?)?.toInt() ?? claims.length;

    return ChatVerificationResult(
      // Never let the stated counts imply more coverage than there is.
      claimsFound: found < claims.length ? claims.length : found,
      claimsEvaluated: evaluated > claims.length ? claims.length : evaluated,
      extractionComplete: json['extraction_complete'] != false,
      extractionNote: (json['extraction_note'] ?? '').toString().trim(),
      claims: claims,
    );
  }
}
