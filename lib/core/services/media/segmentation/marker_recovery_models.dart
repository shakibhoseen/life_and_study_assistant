import 'segmentation_models.dart';

/// Evidence-based confidence level for marker recovery.
enum EvidenceConfidenceLevel {
  high,    // Strong multi-signal evidence (spatial + layout + sequence + text body)
  medium,  // Partial evidence (e.g. 2x2 grid recovery where glyph requires human confirmation)
  low,     // Weak or circumstantial evidence
}

/// Status of the marker recovery evaluation.
enum MarkerRecoveryStatus {
  exactMatch,      // Naturally matched standard marker (e.g. '১.', '(ক)', 'A.')
  recovered,       // Successfully recovered via contextual evidence
  ambiguous,       // Multiple interpretations or weak evidence (original preserved)
  unmatched,       // Not a marker (normal sentence words, numbers in math)
}

/// Specific reason why options might be missing.
enum MissingOptionReason {
  incompleteExtraction,  // Some lines fell below OCR threshold
  possibleCrop,          // Question cut off by page/column crop boundary
  missingOptionMarkers,  // Options printed without formal markers
  ambiguousLayout,       // Irregular alignment or mixed column layout
  uncertain,             // Insufficient evidence to conclusively diagnose
}

/// Detailed audit trail for any evaluated marker candidate.
class RecoveredMarkerAudit {
  /// Original unaltered OCR string extracted from engine.
  final String originalText;

  /// The contextually recovered string (equals originalText if not recovered).
  final String recoveredText;

  /// Absolute or crop-relative bounding box for the glyph.
  final TextBoundingBox glyphBoundingBox;

  /// Evidence-based confidence level without arbitrary floating points.
  final EvidenceConfidenceLevel confidenceLevel;

  /// Recovery status classification.
  final MarkerRecoveryStatus status;

  /// Concrete signals that supported this decision.
  final List<String> evidenceSignals;

  /// Whether human verification is suggested.
  final bool needsReview;

  /// Specific human-readable reason for review.
  final String? reviewReason;

  /// True if recoveredText differs from originalText.
  bool get isAltered => originalText != recoveredText;

  const RecoveredMarkerAudit({
    required this.originalText,
    required this.recoveredText,
    required this.glyphBoundingBox,
    required this.confidenceLevel,
    required this.status,
    required this.evidenceSignals,
    required this.needsReview,
    this.reviewReason,
  });

  Map<String, dynamic> toJson() => {
    'originalText': originalText,
    'recoveredText': recoveredText,
    'glyphBoundingBox': glyphBoundingBox.toJson(),
    'confidenceLevel': confidenceLevel.name,
    'status': status.name,
    'evidenceSignals': evidenceSignals,
    'needsReview': needsReview,
    'reviewReason': reviewReason,
    'isAltered': isAltered,
  };
}

/// Option block packaging clean body text alongside the marker audit trail.
class ContextualOptionItem {
  final RecoveredMarkerAudit markerAudit;
  final String rawBodyText;
  final String cleanBodyText;
  final TextBoundingBox boundingBox;

  const ContextualOptionItem({
    required this.markerAudit,
    required this.rawBodyText,
    required this.cleanBodyText,
    required this.boundingBox,
  });

  Map<String, dynamic> toJson() => {
    'marker': markerAudit.toJson(),
    'rawBodyText': rawBodyText,
    'cleanBodyText': cleanBodyText,
    'boundingBox': boundingBox.toJson(),
  };
}
