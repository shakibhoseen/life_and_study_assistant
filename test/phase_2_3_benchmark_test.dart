// ignore_for_file: unused_import
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/services/media/layout/layout_detection_models.dart';
import 'package:life_and_study_assistant/core/services/media/segmentation/question_segmentation_service.dart';
import 'package:life_and_study_assistant/core/services/media/segmentation/segmentation_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 2.3: Ground Truth Benchmark & Regression Validation', () {
    // -------------------------------------------------------------------------
    // Regression Case 1: Question 4 and Question 5 Strict Separation
    // -------------------------------------------------------------------------
    test('Regression 1: Question 4 retains all 4 options and Line 6 never becomes Question 5 header', () async {
      final layout = LayoutAnalysisResult(
        originalImage: File('dummy.jpg'),
        deskewedImage: File('dummy.jpg'),
        layoutType: LayoutType.singleColumn,
        skewAngle: 0.0,
        gutter: null,
        confidence: 0.95,
        imageWidth: 1547,
        imageHeight: 4424,
        columnBoxes: const [
          ColumnBoundingBox(index: 0, left: 0, top: 0, width: 1547, height: 4424),
        ],
        columnCrops: [],
      );

      final lines = <TextLineBox>[
        const TextLineBox(
          text: '৪. পামটপ কি? শিক্ষক নিবন্ধন ও প্রত্যয়ন পরীক্ষা (শিক্ষক) BA: ১২1',
          boundingBox: TextBoundingBox(left: 48, top: 350, width: 950, height: 36),
          confidence: 0.81,
        ),
        const TextLineBox(
          text: '@ ছোট কুকুর @ পর্বতারোহণ সামগ্রী',
          boundingBox: TextBoundingBox(left: 90, top: 395, width: 600, height: 30),
          confidence: 0.90,
        ),
        // Line 6 contains the 2nd row of options for Q4 and printed answer 'উ.ঘ'
        const TextLineBox(
          text: '€) বাদ্যযন্ত্র € ছোট কম্পিউটার উ.ঘ',
          boundingBox: TextBoundingBox(left: 90, top: 435, width: 620, height: 30),
          confidence: 0.79,
        ),
        // Line 7 is the true Question 5 header
        const TextLineBox(
          text: '€. আধুনিক এমবেডেড সিস্টেমে কীসের ব্যবহার পরিলক্ষিত হয়?',
          boundingBox: TextBoundingBox(left: 44, top: 520, width: 980, height: 36),
          confidence: 0.93,
        ),
        const TextLineBox(
          text: '[বাংলাদেশ প্রাণিসম্পদ অধিদণ্ডরের (সহকারী পরিচালক): ০৫]',
          boundingBox: TextBoundingBox(left: 60, top: 565, width: 800, height: 32),
          confidence: 0.83,
        ),
        const TextLineBox(
          text: '@ চিপস @ প্রসেসর',
          boundingBox: TextBoundingBox(left: 90, top: 610, width: 500, height: 30),
          confidence: 0.85,
        ),
      ];

      final result = await QuestionSegmentationService.instance.segmentPage(
        layout: layout,
        columnLines: {0: lines},
      );

      // Verify that Q4 and Q5 are cleanly separated into 2 distinct questions
      expect(result.questions.length, 2, reason: 'Line 6 must NOT be broken into a standalone question');
      
      final q4 = result.questions[0];
      expect(q4.questionNumber, '৪');
      expect(q4.questionText, contains('পামটপ কি?'));
      expect(q4.options.length, 4, reason: 'Question 4 must collect all 4 options across both rows');
      expect(q4.options[0], contains('ছোট কুকুর'));
      expect(q4.options[1], contains('পর্বতারোহণ সামগ্রী'));
      expect(q4.options[2], contains('বাদ্যযন্ত্র'));
      expect(q4.options[3], contains('ছোট কম্পিউটার'));

      final q5 = result.questions[1];
      expect(q5.questionNumber, '৫', reason: 'Line 7 must be recognized as Question 5');
      expect(q5.questionText, contains('আধুনিক এমবেডেড'));
      expect(q5.options.length, 2, reason: 'Question 5 options row 1 (চিপস, প্রসেসর) must attach to Question 5');
      expect(q5.options[0], contains('চিপস'));
      expect(q5.options[1], contains('প্রসেসর'));
    });

    // -------------------------------------------------------------------------
    // Scale Test: Invariance across 100%, 75%, and 50% coordinate scaling
    // -------------------------------------------------------------------------
    test('Scale Test: Question segmentation remains consistent across multiple scale factors', () async {
      for (final scale in [1.0, 0.75, 0.50]) {
        final scaledLayout = LayoutAnalysisResult(
          originalImage: File('dummy.jpg'),
          deskewedImage: File('dummy.jpg'),
          layoutType: LayoutType.singleColumn,
          skewAngle: 0.0,
          gutter: null,
          confidence: 0.95,
          imageWidth: (1547 * scale).round(),
          imageHeight: (4424 * scale).round(),
          columnBoxes: [
            ColumnBoundingBox(index: 0, left: 0, top: 0, width: (1547 * scale).round(), height: (4424 * scale).round()),
          ],
          columnCrops: [],
        );

        final scaledLines = <TextLineBox>[
          TextLineBox(
            text: '১. এমবেডেড সিস্টেমে বিদ্যুৎ খরচ-',
            boundingBox: TextBoundingBox(
              left: (45 * scale).round(),
              top: (120 * scale).round(),
              width: (900 * scale).round(),
              height: (35 * scale).round(),
            ),
            confidence: 0.82,
          ),
          TextLineBox(
            text: 'ও কম (low) @ বেশি (many)',
            boundingBox: TextBoundingBox(
              left: (90 * scale).round(),
              top: (210 * scale).round(),
              width: (650 * scale).round(),
              height: (30 * scale).round(),
            ),
            confidence: 0.86,
          ),
        ];

        final res = await QuestionSegmentationService.instance.segmentPage(
          layout: scaledLayout,
          columnLines: {0: scaledLines},
        );

        expect(res.questions.length, 1, reason: 'Scale factor $scale must preserve question detection');
        expect(res.questions.first.questionNumber, '১');
        expect(res.questions.first.options.length, 2);
      }
    });
  });
}
