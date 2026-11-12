// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/services/media/layout/layout_detection_models.dart';
import 'package:life_and_study_assistant/core/services/media/segmentation/question_segmentation_service.dart';
import 'package:life_and_study_assistant/core/services/media/segmentation/segmentation_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Generate Real-world Book Scan Audit Report for Context-Aware Recovery', () async {
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

    // Exact OCR lines captured from Samsung Galaxy M32 running Tesseract
    final realOcrLines = <TextLineBox>[
      const TextLineBox(
        text: '১. এমবেডেড সিস্টেমে বিদ্যুৎ খরচ- সমাজসেবা অধিদ্ডরের',
        boundingBox: TextBoundingBox(left: 45, top: 120, width: 900, height: 35),
        confidence: 0.82,
      ),
      const TextLineBox(
        text: '(সমাজসেবা অফিসার): ১৩; বিজেএস (সহকারী জজ): ০৩1',
        boundingBox: TextBoundingBox(left: 60, top: 165, width: 750, height: 32),
        confidence: 0.88,
      ),
      const TextLineBox(
        text: 'ও কম (low) @ বেশি (many)',
        boundingBox: TextBoundingBox(left: 90, top: 210, width: 650, height: 30),
        confidence: 0.86,
      ),
      const TextLineBox(
        text: '@ ay (a few) @ কোনোটিই নয় উ.ক',
        boundingBox: TextBoundingBox(left: 90, top: 250, width: 650, height: 30),
        confidence: 0.85,
      ),
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
      const TextLineBox(
        text: '€) বাদ্যযন্ত্র € ছোট কম্পিউটার উ.ঘ',
        boundingBox: TextBoundingBox(left: 90, top: 435, width: 620, height: 30),
        confidence: 0.79,
      ),
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
      columnLines: {0: realOcrLines},
    );

    print('📊 [AUDIT SUMMARY] Total Questions Segmented: ${result.questions.length}');

    final auditOutput = <Map<String, dynamic>>[];

    for (final q in result.questions) {
      final qMap = <String, dynamic>{
        'questionNumber': q.questionNumber,
        'questionText': q.questionText,
        'optionsCount': q.options.length,
        'options': q.options,
        'optionMarkers': q.optionMarkers,
        'reviewRequired': q.reviewRequired,
        'reviewReasons': q.reviewReasons,
        'questionMarkerAudit': q.questionMarkerAudit?.toJson(),
        'optionAudits': q.optionAudits.map((a) => a.toJson()).toList(),
      };
      auditOutput.add(qMap);

      print('----------------------------------------------------');
      print('❓ Question: [${q.questionNumber}] "${q.questionText}"');
      if (q.questionMarkerAudit != null) {
        print('   Header Audit -> original: "${q.questionMarkerAudit!.originalText}", recovered: "${q.questionMarkerAudit!.recoveredText}", conf: ${q.questionMarkerAudit!.confidenceLevel.name}, altered: ${q.questionMarkerAudit!.isAltered}');
      }
      print('   Options (${q.options.length}):');
      for (int i = 0; i < q.options.length; i++) {
        final optAudit = (i < q.optionAudits.length) ? q.optionAudits[i] : null;
        if (optAudit != null) {
          print('     [${optAudit.recoveredText}] "${q.options[i]}" (orig: "${optAudit.originalText}", conf: ${optAudit.confidenceLevel.name}, signals: ${optAudit.evidenceSignals})');
        } else {
          print('     [${q.optionMarkers.length > i ? q.optionMarkers[i] : '?'}] "${q.options[i]}"');
        }
      }
      print('   Review Required: ${q.reviewRequired} ${q.reviewReasons}');
    }

    final auditFile = File('test_results/real_image_audit_output.json');
    auditFile.createSync(recursive: true);
    auditFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(auditOutput),
    );
    print('✅ Audit log written to: ${auditFile.path}');
  });
}
