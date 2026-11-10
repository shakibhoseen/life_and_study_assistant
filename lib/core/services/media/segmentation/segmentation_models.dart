import 'dart:math' as math;

import '../../ai/models/quiz_question.dart';
import '../layout/layout_detection_models.dart';
import 'marker_recovery_models.dart';

/// A bounding box for layout or text segment in pixel coordinates.
class TextBoundingBox {
  final int left;
  final int top;
  final int width;
  final int height;

  const TextBoundingBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  int get right => left + width;
  int get bottom => top + height;

  /// Returns a new box shifted by [dx] and [dy].
  TextBoundingBox shift(int dx, int dy) {
    return TextBoundingBox(
      left: left + dx,
      top: top + dy,
      width: width,
      height: height,
    );
  }

  /// Expands this box to enclose [other].
  TextBoundingBox union(TextBoundingBox other) {
    final newLeft = math.min(left, other.left);
    final newTop = math.min(top, other.top);
    final newRight = math.max(right, other.right);
    final newBottom = math.max(bottom, other.bottom);
    return TextBoundingBox(
      left: newLeft,
      top: newTop,
      width: math.max(0, newRight - newLeft),
      height: math.max(0, newBottom - newTop),
    );
  }

  Map<String, dynamic> toJson() => {
        'left': left,
        'top': top,
        'width': width,
        'height': height,
      };

  factory TextBoundingBox.fromJson(Map<String, dynamic> json) =>
      TextBoundingBox(
        left: (json['left'] as num?)?.toInt() ?? 0,
        top: (json['top'] as num?)?.toInt() ?? 0,
        width: (json['width'] as num?)?.toInt() ?? 0,
        height: (json['height'] as num?)?.toInt() ?? 0,
      );

  @override
  String toString() => 'Box($left, $top, $width, $height)';
}

/// A recognized line of text with spatial information.
class TextLineBox {
  final String text;
  final TextBoundingBox boundingBox;
  final double confidence;
  final int columnId;

  const TextLineBox({
    required this.text,
    required this.boundingBox,
    required this.confidence,
    this.columnId = 0,
  });

  TextLineBox copyWith({
    String? text,
    TextBoundingBox? boundingBox,
    double? confidence,
    int? columnId,
  }) {
    return TextLineBox(
      text: text ?? this.text,
      boundingBox: boundingBox ?? this.boundingBox,
      confidence: confidence ?? this.confidence,
      columnId: columnId ?? this.columnId,
    );
  }
}

/// A segmented MCQ block comprising question prompt and options.
class SegmentedQuestionBlock {
  final String questionNumber;
  final String questionText;
  final List<String> options;
  final List<String> optionMarkers;
  final TextBoundingBox boundingBox;
  final int columnId;
  final double ocrConfidence;
  final double segmentationConfidence;
  final bool reviewRequired;
  final List<String> reviewReasons;
  final String? originalCropReference;
  final String? diagramCropPath;
  final bool hasDiagram;
  final bool isOrphan;
  final RecoveredMarkerAudit? questionMarkerAudit;
  final List<RecoveredMarkerAudit> optionAudits;

  const SegmentedQuestionBlock({
    required this.questionNumber,
    required this.questionText,
    required this.options,
    this.optionMarkers = const [],
    required this.boundingBox,
    required this.columnId,
    required this.ocrConfidence,
    required this.segmentationConfidence,
    required this.reviewRequired,
    this.reviewReasons = const [],
    this.originalCropReference,
    this.diagramCropPath,
    this.hasDiagram = false,
    this.isOrphan = false,
    this.questionMarkerAudit,
    this.optionAudits = const [],
  });

  /// Seamlessly bridges into the standard application [QuizQuestion].
  QuizQuestion toQuizQuestion({String? subjectHint}) {
    return QuizQuestion(
      questionText: questionText,
      options: options.isNotEmpty ? options : const ['ক', 'খ', 'গ', 'ঘ'],
      // Strictly -1 in Phase 2 unless dependable key is provided
      correctIndex: -1,
      explanation: hasDiagram
          ? 'সংযুক্ত ডায়াগ্রাম/চিত্র সংরক্ষিত রয়েছে।'
          : '',
      subject: subjectHint,
      legible: !reviewRequired && options.length == 4,
      answerSource: AnswerSource.guess,
      printedNumber: questionNumber.isNotEmpty ? questionNumber : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'questionNumber': questionNumber,
        'questionText': questionText,
        'options': options,
        'optionMarkers': optionMarkers,
        'boundingBox': boundingBox.toJson(),
        'columnId': columnId,
        'ocrConfidence': ocrConfidence,
        'segmentationConfidence': segmentationConfidence,
        'reviewRequired': reviewRequired,
        'reviewReasons': reviewReasons,
        'originalCropReference': originalCropReference,
        'diagramCropPath': diagramCropPath,
        'hasDiagram': hasDiagram,
        'isOrphan': isOrphan,
        'questionMarkerAudit': questionMarkerAudit?.toJson(),
        'optionAudits': optionAudits.map((a) => a.toJson()).toList(),
      };

  SegmentedQuestionBlock copyWith({
    String? questionNumber,
    String? questionText,
    List<String>? options,
    List<String>? optionMarkers,
    TextBoundingBox? boundingBox,
    int? columnId,
    double? ocrConfidence,
    double? segmentationConfidence,
    bool? reviewRequired,
    List<String>? reviewReasons,
    String? originalCropReference,
    String? diagramCropPath,
    bool? hasDiagram,
    bool? isOrphan,
  }) {
    return SegmentedQuestionBlock(
      questionNumber: questionNumber ?? this.questionNumber,
      questionText: questionText ?? this.questionText,
      options: options ?? this.options,
      optionMarkers: optionMarkers ?? this.optionMarkers,
      boundingBox: boundingBox ?? this.boundingBox,
      columnId: columnId ?? this.columnId,
      ocrConfidence: ocrConfidence ?? this.ocrConfidence,
      segmentationConfidence:
          segmentationConfidence ?? this.segmentationConfidence,
      reviewRequired: reviewRequired ?? this.reviewRequired,
      reviewReasons: reviewReasons ?? this.reviewReasons,
      originalCropReference:
          originalCropReference ?? this.originalCropReference,
      diagramCropPath: diagramCropPath ?? this.diagramCropPath,
      hasDiagram: hasDiagram ?? this.hasDiagram,
      isOrphan: isOrphan ?? this.isOrphan,
    );
  }
}

/// The complete segmented result of a page after layout & segmentation.
class PageSegmentationResult {
  final int pageWidth;
  final int pageHeight;
  final LayoutType layoutType;
  final List<SegmentedQuestionBlock> questions;
  final List<SegmentedQuestionBlock> orphanBlocks;

  const PageSegmentationResult({
    required this.pageWidth,
    required this.pageHeight,
    required this.layoutType,
    required this.questions,
    this.orphanBlocks = const [],
  });

  int get totalQuestions => questions.length;
  int get validMcqCount => questions.where((q) => q.options.length == 4).length;
  int get reviewCount => questions.where((q) => q.reviewRequired).length;
}
