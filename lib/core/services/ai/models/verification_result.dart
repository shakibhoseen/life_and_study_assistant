/// How much the check could actually establish.
enum VerificationVerdict {
  /// The question, options, answer and explanation hang together.
  supported,

  /// Something is demonstrably wrong — usually the explanation contradicting
  /// itself or the stated answer.
  likelyIncorrect,

  /// The answer turns on an outside fact that this check cannot confirm.
  inconclusive;

  static VerificationVerdict parse(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'supported':
        return VerificationVerdict.supported;
      case 'likely_incorrect':
      case 'likely incorrect':
        return VerificationVerdict.likelyIncorrect;
      default:
        return VerificationVerdict.inconclusive;
    }
  }

  String get label => switch (this) {
    VerificationVerdict.supported => 'সঙ্গতিপূর্ণ',
    VerificationVerdict.likelyIncorrect => 'সম্ভবত ভুল',
    VerificationVerdict.inconclusive => 'নিশ্চিত নয়',
  };
}

/// A single supporting point.
///
/// [sourceUrl] exists so that a later version backed by real source retrieval
/// can fill it in without reshaping the model or the stored results. Until
/// that exists it is always null, and [VerificationResult.externalSourcesChecked]
/// stays false, because a URL the model recalls is not a source it checked.
class VerificationEvidence {
  final String claim;
  final String? sourceUrl;

  const VerificationEvidence({required this.claim, this.sourceUrl});

  Map<String, Object?> toJson() => {'claim': claim, 'source_url': sourceUrl};

  static VerificationEvidence fromJson(Map<String, Object?> json) =>
      VerificationEvidence(
        claim: (json['claim'] ?? '').toString(),
        // Deliberately dropped: without retrieval, a URL here would be recalled
        // rather than visited, and showing it would be a false citation.
        sourceUrl: null,
      );
}

class VerificationResult {
  final VerificationVerdict verdict;

  /// What the check thinks the answer should be, when it has a view.
  final String? proposedAnswer;

  final String reasoning;

  /// 0.0–1.0, the model's own stated confidence.
  final double confidence;

  /// What this check could not establish. Never empty in practice: at minimum
  /// it records that no external source was consulted.
  final String limitations;

  final List<VerificationEvidence> evidence;

  /// False for as long as the app has no source retrieval.
  final bool externalSourcesChecked;

  const VerificationResult({
    required this.verdict,
    required this.reasoning,
    required this.confidence,
    required this.limitations,
    this.proposedAnswer,
    this.evidence = const [],
    this.externalSourcesChecked = false,
  });

  /// True when there is a concrete correction to consider. Acting on it is a
  /// separate workflow: nothing here writes to the question.
  bool get hasProposal =>
      verdict == VerificationVerdict.likelyIncorrect &&
      (proposedAnswer ?? '').trim().isNotEmpty;

  Map<String, Object?> toJson() => {
    'verdict': switch (verdict) {
      VerificationVerdict.supported => 'supported',
      VerificationVerdict.likelyIncorrect => 'likely_incorrect',
      VerificationVerdict.inconclusive => 'inconclusive',
    },
    'proposed_answer': proposedAnswer,
    'reasoning': reasoning,
    'confidence': confidence,
    'limitations': limitations,
    'evidence': evidence.map((e) => e.toJson()).toList(),
  };

  /// Returns null for anything that cannot be read as a result, so a garbled
  /// reply surfaces as a failure rather than as a confident verdict.
  static VerificationResult? tryFromJson(Map<String, Object?>? json) {
    if (json == null) return null;

    final reasoning = (json['reasoning'] ?? '').toString().trim();
    if (reasoning.isEmpty) return null;

    final rawConfidence = json['confidence'];
    final confidence = rawConfidence is num
        ? rawConfidence.toDouble().clamp(0.0, 1.0)
        : 0.0;

    final rawEvidence = json['evidence'];
    final evidence = rawEvidence is List
        ? rawEvidence
              .whereType<Map>()
              .map(
                (e) => VerificationEvidence.fromJson(e.cast<String, Object?>()),
              )
              .where((e) => e.claim.trim().isNotEmpty)
              .toList()
        : <VerificationEvidence>[];

    final stated = (json['limitations'] ?? '').toString().trim();
    const noSources = 'External sources not checked';

    return VerificationResult(
      verdict: VerificationVerdict.parse(json['verdict']?.toString()),
      proposedAnswer: (json['proposed_answer'] ?? '').toString().trim().isEmpty
          ? null
          : json['proposed_answer'].toString().trim(),
      reasoning: reasoning,
      confidence: confidence,
      // The no-sources caveat is appended by the app, not trusted to the
      // model: it is a fact about the app, not a judgement about the answer.
      limitations: stated.isEmpty ? noSources : '$stated · $noSources',
      evidence: evidence,
      externalSourcesChecked: false,
    );
  }
}
