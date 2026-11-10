import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/services/media/segmentation/context_aware_marker_recovery_service.dart';
import 'package:life_and_study_assistant/core/services/media/segmentation/marker_recovery_models.dart';
import 'package:life_and_study_assistant/core/services/media/segmentation/segmentation_models.dart';

void main() {
  late ContextAwareMarkerRecoveryService service;

  setUp(() {
    service = ContextAwareMarkerRecoveryService.instance;
  });

  group('Context-Aware Marker Recovery Test Suite (TC-01 to TC-09)', () {
    // -------------------------------------------------------------------------
    // TC-01: Negative Guard - Normal Bengali Sentence with 'ও'
    // -------------------------------------------------------------------------
    test('TC-01: Normal Bengali sentence containing "ও" is preserved and never converted to option', () {
      const line = TextLineBox(
        text: 'কম্পিউটার ও তথ্যপ্রযুক্তি বিষয়ের মূল ধারণা।',
        boundingBox: TextBoundingBox(left: 40, top: 100, width: 600, height: 30),
        confidence: 0.95,
      );

      final options = service.extractOptionsWithContext(
        line: line,
        columnWidth: 800,
        existingOptionsInCurrentQuestion: [],
      );

      expect(options, isEmpty, reason: 'Normal conjunction "ও" in sentence must NOT produce any option marker');
    });

    // -------------------------------------------------------------------------
    // TC-02: Negative Guard - Normal Text with Currency / Math Symbol (€)
    // -------------------------------------------------------------------------
    test('TC-02: Currency symbol "€" in body text is not converted to question number', () {
      const line = TextLineBox(
        text: 'পণ্যটির মূল্য প্রায় ১০০ € নির্ধারিত।',
        boundingBox: TextBoundingBox(left: 350, top: 150, width: 400, height: 30), // Far to the right
        confidence: 0.90,
      );

      final audit = service.evaluateQuestionHeader(
        line: line,
        columnWidth: 800,
        columnId: 0,
        previousQuestionNumberInSameColumn: '৪',
        hasOpenQuestionBlock: true,
        allPreviousOptionsCompleted: false,
      );

      expect(audit, isNull, reason: '€ far into the column must NOT be treated as a question start');
    });

    // -------------------------------------------------------------------------
    // TC-03: Contextual Question 5 Recovery from '€.'
    // -------------------------------------------------------------------------
    test('TC-03: Degraded Bengali question 5 ("€.") is recovered with multi-signal evidence', () {
      const line = TextLineBox(
        text: '€. আধুনিক এমবেডেড সিস্টেমে কীসের ব্যবহার পরিলক্ষিত হয়?',
        boundingBox: TextBoundingBox(left: 45, top: 500, width: 700, height: 32),
        confidence: 0.93,
      );

      final audit = service.evaluateQuestionHeader(
        line: line,
        columnWidth: 800,
        columnId: 0,
        previousQuestionNumberInSameColumn: '৪',
        hasOpenQuestionBlock: false,
        allPreviousOptionsCompleted: true,
      );

      expect(audit, isNotNull);
      expect(audit!.originalText, '€.');
      expect(audit.recoveredText, '৫.');
      expect(audit.confidenceLevel, EvidenceConfidenceLevel.medium,
          reason: 'Per user specification, confidence must remain medium until ground-truth calibrated');
      expect(audit.status, MarkerRecoveryStatus.recovered);
      expect(audit.needsReview, isFalse);
      expect(audit.isAltered, isTrue);
      expect(audit.glyphBoundingBox.width, greaterThan(0));
    });

    // -------------------------------------------------------------------------
    // TC-04: Ambiguous Question Header without Sequence
    // -------------------------------------------------------------------------
    test('TC-04: Ambiguous marker without sequence continuity flags review without guessing', () {
      const line = TextLineBox(
        text: '€. আধুনিক এমবেডেড সিস্টেমে কীসের ব্যবহার?',
        boundingBox: TextBoundingBox(left: 50, top: 500, width: 700, height: 32),
        confidence: 0.85,
      );

      // Previous question was '১' (not '৪'), so sequence '১' -> '৫' does not match
      final audit = service.evaluateQuestionHeader(
        line: line,
        columnWidth: 800,
        columnId: 0,
        previousQuestionNumberInSameColumn: '১',
        hasOpenQuestionBlock: false,
        allPreviousOptionsCompleted: true,
      );

      expect(audit, isNotNull);
      expect(audit!.originalText, '€.');
      expect(audit.recoveredText, '€.', reason: 'Must not guess; keep original text');
      expect(audit.status, MarkerRecoveryStatus.ambiguous);
      expect(audit.needsReview, isTrue);
      expect(audit.confidenceLevel, EvidenceConfidenceLevel.low);
    });

    // -------------------------------------------------------------------------
    // TC-05: Column Boundary & Reset Awareness
    // -------------------------------------------------------------------------
    test('TC-05: Column boundary reset evaluates new column headers independently', () {
      // Column 0 ended at question 18.
      // Column 1 starts with '১. নতুন প্রশ্ন'
      const col1Line = TextLineBox(
        text: '১. কম্পিউটারের মূল মেমোরি কোনটি?',
        boundingBox: TextBoundingBox(left: 30, top: 80, width: 600, height: 30),
        confidence: 0.96,
        columnId: 1,
      );

      final audit = service.evaluateQuestionHeader(
        line: col1Line,
        columnWidth: 800,
        columnId: 1,
        previousQuestionNumberInSameColumn: null, // Reset for new column
        hasOpenQuestionBlock: false,
        allPreviousOptionsCompleted: true,
      );

      expect(audit, isNotNull);
      expect(audit!.recoveredText, '১.');
      expect(audit.status, MarkerRecoveryStatus.exactMatch);
      expect(audit.needsReview, isFalse);
    });

    // -------------------------------------------------------------------------
    // TC-06: 2x2 Grid Option Recovery with Medium Confidence
    // -------------------------------------------------------------------------
    test('TC-06: 2x2 grid recovery assigns Medium confidence to recovered "ও" & "@"', () {
      const line1 = TextLineBox(
        text: 'ও কম (low)   @ বেশি (many)',
        boundingBox: TextBoundingBox(left: 60, top: 200, width: 650, height: 28),
        confidence: 0.86,
      );

      final optionsLine1 = service.extractOptionsWithContext(
        line: line1,
        columnWidth: 800,
        existingOptionsInCurrentQuestion: [],
      );

      expect(optionsLine1.length, 2);
      
      // First option recovered from 'ও'
      final opt1 = optionsLine1[0];
      expect(opt1.markerAudit.originalText, 'ও');
      expect(opt1.markerAudit.recoveredText, '(ক)');
      expect(opt1.markerAudit.confidenceLevel, EvidenceConfidenceLevel.medium,
          reason: 'Per user specification, 2x2 recovery must not claim high confidence without GT glyph verification');
      expect(opt1.cleanBodyText, 'কম (low)');

      // Second option recovered from '@'
      final opt2 = optionsLine1[1];
      expect(opt2.markerAudit.originalText, '@');
      expect(opt2.markerAudit.recoveredText, '(খ)');
      expect(opt2.markerAudit.confidenceLevel, EvidenceConfidenceLevel.medium);
      expect(opt2.cleanBodyText, 'বেশি (many)');
    });

    // -------------------------------------------------------------------------
    // TC-07: Multiline Option Sequence
    // -------------------------------------------------------------------------
    test('TC-07: Multiline option sequence extracts (ক) through (ঘ) across lines', () {
      const lineKa = TextLineBox(
        text: 'ও অপশন এক',
        boundingBox: TextBoundingBox(left: 60, top: 150, width: 300, height: 25),
        confidence: 0.90,
      );
      final optKaList = service.extractOptionsWithContext(
        line: lineKa,
        columnWidth: 800,
        existingOptionsInCurrentQuestion: [],
      );
      expect(optKaList.length, 1);
      expect(optKaList.first.markerAudit.recoveredText, '(ক)');

      const lineKha = TextLineBox(
        text: '@ অপশন দুই',
        boundingBox: TextBoundingBox(left: 60, top: 180, width: 300, height: 25),
        confidence: 0.90,
      );
      final optKhaList = service.extractOptionsWithContext(
        line: lineKha,
        columnWidth: 800,
        existingOptionsInCurrentQuestion: optKaList,
      );
      expect(optKhaList.length, 1);
      expect(optKhaList.first.markerAudit.recoveredText, '(খ)');
    });

    // -------------------------------------------------------------------------
    // TC-08: Incomplete Option Sequence Preservation & Evidence-based Diagnosis
    // -------------------------------------------------------------------------
    test('TC-08: Incomplete option count preserves found options and diagnoses reason based on evidence', () {
      final diagCrop = service.diagnoseMissingOptions(
        optionCount: 2,
        isNearColumnBottom: true,
        hasAmbiguousLinesNearby: false,
      );
      expect(diagCrop, MissingOptionReason.possibleCrop,
          reason: 'Question near column bottom with missing options should be diagnosed as possibleCrop');

      final diagIncomplete = service.diagnoseMissingOptions(
        optionCount: 2,
        isNearColumnBottom: false,
        hasAmbiguousLinesNearby: true,
      );
      expect(diagIncomplete, MissingOptionReason.incompleteExtraction);

      final diagUncertain = service.diagnoseMissingOptions(
        optionCount: 2,
        isNearColumnBottom: false,
        hasAmbiguousLinesNearby: false,
      );
      expect(diagUncertain, MissingOptionReason.uncertain,
          reason: 'Without concrete boundary or ambiguous evidence, diagnosis must remain uncertain');
    });

    // -------------------------------------------------------------------------
    // TC-09: Image Evidence Coordinates Validation
    // -------------------------------------------------------------------------
    test('TC-09: All recovered markers preserve non-zero glyph bounding box coordinates', () {
      const line = TextLineBox(
        text: 'ও প্রথম অপশন   (খ) দ্বিতীয় অপশন',
        boundingBox: TextBoundingBox(left: 80, top: 300, width: 500, height: 30),
        confidence: 0.91,
      );

      final options = service.extractOptionsWithContext(
        line: line,
        columnWidth: 800,
        existingOptionsInCurrentQuestion: [],
      );

      for (final opt in options) {
        expect(opt.markerAudit.glyphBoundingBox.left, greaterThanOrEqualTo(80));
        expect(opt.markerAudit.glyphBoundingBox.width, greaterThan(0));
        expect(opt.markerAudit.glyphBoundingBox.height, greaterThan(0));
      }
    });
  });
}
