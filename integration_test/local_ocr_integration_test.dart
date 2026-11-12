import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:life_and_study_assistant/core/services/media/layout/layout_detection_service.dart';
import 'package:life_and_study_assistant/core/services/media/segmentation/question_segmentation_service.dart';
import 'package:life_and_study_assistant/core/services/media/segmentation/segmentation_models.dart';
import 'package:local_ocr/local_ocr.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('End-to-End Real Device Local OCR Pipeline Benchmark',
      (WidgetTester tester) async {
    print('🚀 [DEVICE TEST] Starting Real Device Local OCR Pipeline Benchmark...');
    
    // 1. Load image from /sdcard/mcq_book_page.jpg
    final imageFile = File('/sdcard/mcq_book_page.jpg');
    expect(await imageFile.exists(), isTrue, reason: '/sdcard/mcq_book_page.jpg must exist on device');
    print('📦 Step 1: Loaded test image from ${imageFile.path} (${await imageFile.length()} bytes)');

    final outDir = Directory('/sdcard/test_results_local_ocr');
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }

    // Copy as 01_original.png / 01_original.jpg
    final file01Original = File('${outDir.path}/01_original.jpg');
    await file01Original.writeAsBytes(await imageFile.readAsBytes(), flush: true);

    // 2. Layout Detection (Phase 1)
    print('🔍 Step 2: Running Phase 1 LayoutDetectionService on device...');
    final layoutStopwatch = Stopwatch()..start();
    final layoutResult = await LayoutDetectionService.instance.analyzeLayout(imageFile, autoDeskew: true);
    layoutStopwatch.stop();

    print('📊 Layout Detection completed in ${layoutStopwatch.elapsedMilliseconds} ms:');
    print('   - LayoutType: ${layoutResult.layoutType.name}');
    print('   - isDualColumn: ${layoutResult.isDualColumn}');
    print('   - Skew Angle: ${layoutResult.skewAngle}');
    print('   - Confidence: ${layoutResult.confidence}');
    print('   - Columns found: ${layoutResult.columnBoxes.length}');

    // Save deskewed
    final file02Deskewed = File('${outDir.path}/02_deskewed.jpg');
    await file02Deskewed.writeAsBytes(await layoutResult.deskewedImage.readAsBytes(), flush: true);

    // 3. Column crops
    final crops = layoutResult.columnCrops.isNotEmpty
        ? layoutResult.columnCrops
        : [layoutResult.deskewedImage];

    final leftCrop = crops[0];
    final File? rightCrop = crops.length > 1 ? crops[1] : null;

    final file04Left = File('${outDir.path}/04_left_column.jpg');
    await file04Left.writeAsBytes(await leftCrop.readAsBytes(), flush: true);

    if (rightCrop != null) {
      final file05Right = File('${outDir.path}/05_right_column.jpg');
      await file05Right.writeAsBytes(await rightCrop.readAsBytes(), flush: true);
    }

    // 4. Real Native OCR (Tesseract4Android on ARM64)
    print('⚡ Step 3: Running Real Native Tesseract OCR on Device...');
    final ocrStopwatch = Stopwatch()..start();

    print('   - Running OCR on Left Column...');
    final hocrLeft = await LocalOcr.extractHocr(leftCrop.path, language: 'ben+eng+equ');
    final textLeft = await LocalOcr.extractText(leftCrop.path, language: 'ben+eng+equ');
    print('   - Left OCR complete (${textLeft.length} characters extracted)');

    String hocrRight = '';
    String textRight = '';
    if (rightCrop != null) {
      print('   - Running OCR on Right Column...');
      hocrRight = await LocalOcr.extractHocr(rightCrop.path, language: 'ben+eng+equ');
      textRight = await LocalOcr.extractText(rightCrop.path, language: 'ben+eng+equ');
      print('   - Right OCR complete (${textRight.length} characters extracted)');
    }
    ocrStopwatch.stop();
    print('⚡ Tesseract OCR completed in ${ocrStopwatch.elapsedMilliseconds} ms');

    await File('${outDir.path}/06_left_ocr.txt').writeAsString(textLeft);
    await File('${outDir.path}/07_right_ocr.txt').writeAsString(textRight);

    // Parse hOCR to line boxes
    final Map<int, List<TextLineBox>> columnLines = {
      0: QuestionSegmentationService.parseHocrToLines(hocrText: hocrLeft, columnId: 0),
    };
    if (rightCrop != null && hocrRight.isNotEmpty) {
      columnLines[1] = QuestionSegmentationService.parseHocrToLines(hocrText: hocrRight, columnId: 1);
    }

    final ocrBoxesJson = {
      'left': columnLines[0]?.map((l) => {'text': l.text, 'box': l.boundingBox.toJson(), 'confidence': l.confidence}).toList(),
      'right': columnLines[1]?.map((l) => {'text': l.text, 'box': l.boundingBox.toJson(), 'confidence': l.confidence}).toList() ?? [],
    };
    await File('${outDir.path}/08_ocr_boxes.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(ocrBoxesJson),
    );

    // 5. Question Segmentation (Phase 2)
    print('🧩 Step 4: Running QuestionSegmentationService...');
    final segStopwatch = Stopwatch()..start();
    final segResult = await QuestionSegmentationService.instance.segmentPage(
      layout: layoutResult,
      columnLines: columnLines,
      originalImageFile: imageFile,
      cropsOutputDir: outDir,
    );
    segStopwatch.stop();

    print('🧩 Question Segmentation completed in ${segStopwatch.elapsedMilliseconds} ms:');
    print('   - Total questions found: ${segResult.totalQuestions}');
    print('   - Valid 4-option MCQs: ${segResult.validMcqCount}');
    print('   - Review required: ${segResult.reviewCount}');

    final segmentedJson = {
      'pageWidth': segResult.pageWidth,
      'pageHeight': segResult.pageHeight,
      'layoutType': segResult.layoutType.name,
      'totalQuestions': segResult.totalQuestions,
      'validMcqCount': segResult.validMcqCount,
      'reviewCount': segResult.reviewCount,
      'questions': segResult.questions.map((q) => q.toJson()).toList(),
      'orphans': segResult.orphanBlocks.map((o) => o.toJson()).toList(),
    };
    await File('${outDir.path}/09_segmented_questions.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(segmentedJson),
    );

    // 6. Convert to QuizQuestion
    final quizQuestions = segResult.questions.map((q) => q.toQuizQuestion()).toList();
    await File('${outDir.path}/10_final_quiz_questions.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(quizQuestions.map((q) => q.toJson()).toList()),
    );

    // 7. Benchmark Report
    final report = {
      'timestamp': DateTime.now().toIso8601String(),
      'device': 'SM M325F (Android 13 ARM64)',
      'metrics': {
        'layoutDetectionMs': layoutStopwatch.elapsedMilliseconds,
        'tesseractOcrMs': ocrStopwatch.elapsedMilliseconds,
        'segmentationMs': segStopwatch.elapsedMilliseconds,
        'totalMs': layoutStopwatch.elapsedMilliseconds + ocrStopwatch.elapsedMilliseconds + segStopwatch.elapsedMilliseconds,
      },
      'results': {
        'layoutType': layoutResult.layoutType.name,
        'totalQuestions': segResult.totalQuestions,
        'validMcqCount': segResult.validMcqCount,
        'reviewRequiredCount': segResult.reviewCount,
        'leftTextLength': textLeft.length,
        'rightTextLength': textRight.length,
      },
    };
    await File('${outDir.path}/benchmark_report.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
    );

    print('🎉 SUCCESS! All files saved on device in /sdcard/test_results_local_ocr/');
  });
}
