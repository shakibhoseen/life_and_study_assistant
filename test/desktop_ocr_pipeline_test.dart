import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:life_and_study_assistant/core/services/media/layout/layout_detection_models.dart';
import 'package:life_and_study_assistant/core/services/media/layout/layout_detection_service.dart';
import 'package:life_and_study_assistant/core/services/media/local_ocr_service.dart';
import 'package:life_and_study_assistant/core/services/media/segmentation/question_segmentation_service.dart';
import 'package:life_and_study_assistant/core/services/media/segmentation/segmentation_models.dart';
import 'package:local_ocr/local_ocr.dart';

/// Desktop & Integration Test Harness for Local Offline OCR Pipeline.
class OcrPipelineHarness {
  final File inputImage;
  final Directory outputDir;

  OcrPipelineHarness({
    required this.inputImage,
    required this.outputDir,
  });

  /// Runs the full pipeline end-to-end.
  Future<Map<String, dynamic>> execute({
    bool allowMockFallbackOnDesktop = false,
  }) async {
    final report = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'inputFile': inputImage.path,
      'steps': <String, dynamic>{},
    };

    final totalTimer = Stopwatch()..start();

    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }

    // Step 1: Copy and save original image
    print('👉 Step 1: Loading original image...');
    final step1Timer = Stopwatch()..start();
    final originalBytes = await inputImage.readAsBytes();
    final originalImage = img.decodeImage(originalBytes);
    if (originalImage == null) {
      throw Exception('Failed to decode input image from ${inputImage.path}');
    }
    final file01Original = File('${outputDir.path}/01_original.png');
    await file01Original.writeAsBytes(img.encodePng(originalImage));
    step1Timer.stop();
    report['steps']['step1_original'] = {
      'dimensions': '${originalImage.width}x${originalImage.height}',
      'timeMs': step1Timer.elapsedMilliseconds,
      'path': file01Original.path,
    };

    // Step 2 & 3: Layout Detection (Phase 1)
    print('👉 Step 2 & 3: Running Phase 1 LayoutDetectionService...');
    final layoutTimer = Stopwatch()..start();
    final layoutResult = await LayoutDetectionService.instance.analyzeLayout(
      inputImage,
      autoDeskew: true,
    );
    layoutTimer.stop();

    // 02_deskewed.png
    final file02Deskewed = File('${outputDir.path}/02_deskewed.png');
    final deskewedBytes = await layoutResult.deskewedImage.readAsBytes();
    await file02Deskewed.writeAsBytes(deskewedBytes);

    // 03_layout_detected.png (annotated image with gutter and column boxes)
    final file03Layout = File('${outputDir.path}/03_layout_detected.png');
    final deskewedImg = img.decodeImage(deskewedBytes)!;
    final annotated = _drawLayoutAnnotations(deskewedImg, layoutResult);
    await file03Layout.writeAsBytes(img.encodePng(annotated));

    report['steps']['step2_layout_detection'] = {
      'layoutType': layoutResult.layoutType.name,
      'isDualColumn': layoutResult.isDualColumn,
      'skewAngle': layoutResult.skewAngle,
      'confidence': layoutResult.confidence,
      'columnCount': layoutResult.columnBoxes.length,
      'timeMs': layoutTimer.elapsedMilliseconds,
      'gutter': layoutResult.gutter != null
          ? {
              'left': layoutResult.gutter!.left,
              'right': layoutResult.gutter!.right,
              'center': layoutResult.gutter!.center,
              'width': layoutResult.gutter!.width,
            }
          : null,
    };

    // Step 4 & 5: Save Column Crops
    print('👉 Step 4 & 5: Saving column crops...');
    File? file04Left;
    File? file05Right;

    if (layoutResult.columnCrops.isNotEmpty) {
      file04Left = File('${outputDir.path}/04_left_column.png');
      final leftBytes = await layoutResult.columnCrops[0].readAsBytes();
      final leftImg = img.decodeImage(leftBytes)!;
      await file04Left.writeAsBytes(img.encodePng(leftImg));
    }

    file05Right = File('${outputDir.path}/05_right_column.png');
    if (layoutResult.columnCrops.length > 1) {
      final rightBytes = await layoutResult.columnCrops[1].readAsBytes();
      final rightImg = img.decodeImage(rightBytes)!;
      await file05Right.writeAsBytes(img.encodePng(rightImg));
    } else {
      // If single column layout was detected, create a 100x100 placeholder PNG
      final placeholder = img.Image(width: 100, height: 100);
      img.fill(placeholder, color: img.ColorRgb8(240, 240, 240));
      await file05Right.writeAsBytes(img.encodePng(placeholder));
    }

    report['steps']['step3_column_crops'] = {
      'leftColumnSaved': file04Left != null,
      'rightColumnSaved': layoutResult.columnCrops.length > 1,
      'isSingleColumnFallback': layoutResult.columnCrops.length <= 1,
    };

    // Step 6, 7, 8: OCR Execution (Testing platform capability)
    print('👉 Step 6, 7, 8: Checking Tesseract OCR capability...');
    bool isNativeOcrAvailable = false;
    String leftOcrText = '';
    String rightOcrText = '';
    final Map<int, List<TextLineBox>> columnLines = {};
    final Map<String, dynamic> ocrBoxesJson = {
      'columns': <String, dynamic>{},
    };

    final ocrTimer = Stopwatch()..start();
    try {
      if (file04Left != null) {
        final hocrLeft = await LocalOcr.extractHocr(file04Left.path);
        leftOcrText = await LocalOcr.extractText(file04Left.path);
        final lines0 = QuestionSegmentationService.parseHocrToLines(
          hocrText: hocrLeft,
          columnId: 0,
        );
        columnLines[0] = lines0;
        ocrBoxesJson['columns']['left'] = lines0
            .map((l) => {
                  'text': l.text,
                  'box': l.boundingBox.toJson(),
                  'confidence': l.confidence,
                })
            .toList();
        isNativeOcrAvailable = true;
      }

      if (file05Right != null) {
        final hocrRight = await LocalOcr.extractHocr(file05Right.path);
        rightOcrText = await LocalOcr.extractText(file05Right.path);
        final lines1 = QuestionSegmentationService.parseHocrToLines(
          hocrText: hocrRight,
          columnId: 1,
        );
        columnLines[1] = lines1;
        ocrBoxesJson['columns']['right'] = lines1
            .map((l) => {
                  'text': l.text,
                  'box': l.boundingBox.toJson(),
                  'confidence': l.confidence,
                })
            .toList();
      }
    } on MissingPluginException catch (e) {
      print('⚠️ Native OCR Plugin check: LocalOcr plugin is Android-only.');
      print('⚠️ Desktop host environment does not have native Tesseract registration: $e');
      isNativeOcrAvailable = false;
    } catch (e) {
      print('⚠️ Native OCR error: $e');
      isNativeOcrAvailable = false;
    }
    ocrTimer.stop();

    report['ocr_engine'] = {
      'nativeOcrAvailable': isNativeOcrAvailable,
      'timeMs': ocrTimer.elapsedMilliseconds,
      'platform': Platform.operatingSystem,
    };

    // Save OCR files
    final file06LeftOcr = File('${outputDir.path}/06_left_ocr.txt');
    await file06LeftOcr.writeAsString(leftOcrText);

    final file07RightOcr = File('${outputDir.path}/07_right_ocr.txt');
    await file07RightOcr.writeAsString(rightOcrText);

    final file08OcrBoxes = File('${outputDir.path}/08_ocr_boxes.json');
    await file08OcrBoxes.writeAsString(
      const JsonEncoder.withIndent('  ').convert(ocrBoxesJson),
    );

    // Step 9 & 10: Question Segmentation (Phase 2)
    print('👉 Step 9 & 10: Running Phase 2 QuestionSegmentationService...');
    final segTimer = Stopwatch()..start();
    final segResult = await QuestionSegmentationService.instance.segmentPage(
      layout: layoutResult,
      columnLines: columnLines,
      originalImageFile: inputImage,
      cropsOutputDir: outputDir,
    );
    segTimer.stop();

    // 09_segmented_questions.json
    final file09Segmented = File('${outputDir.path}/09_segmented_questions.json');
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
    await file09Segmented.writeAsString(
      const JsonEncoder.withIndent('  ').convert(segmentedJson),
    );

    // 10_final_quiz_questions.json
    final file10FinalQuiz = File('${outputDir.path}/10_final_quiz_questions.json');
    final quizQuestions = segResult.questions.map((q) => q.toQuizQuestion()).toList();
    final finalQuizJson = quizQuestions.map((q) => q.toJson()).toList();
    await file10FinalQuiz.writeAsString(
      const JsonEncoder.withIndent('  ').convert(finalQuizJson),
    );

    totalTimer.stop();

    // benchmark_report.json
    report['totalElapsedMs'] = totalTimer.elapsedMilliseconds;
    report['segmentation'] = {
      'totalQuestions': segResult.totalQuestions,
      'validMcqCount': segResult.validMcqCount,
      'reviewRequiredCount': segResult.reviewCount,
      'timeMs': segTimer.elapsedMilliseconds,
    };
    report['filesGenerated'] = [
      file01Original.path,
      file02Deskewed.path,
      file03Layout.path,
      if (file04Left != null) file04Left.path,
      if (file05Right != null) file05Right.path,
      file06LeftOcr.path,
      file07RightOcr.path,
      file08OcrBoxes.path,
      file09Segmented.path,
      file10FinalQuiz.path,
      '${outputDir.path}/benchmark_report.json',
    ];

    final fileBenchmarkReport = File('${outputDir.path}/benchmark_report.json');
    await fileBenchmarkReport.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
    );

    print('✅ Harness execution completed. Benchmark saved to ${fileBenchmarkReport.path}');
    return report;
  }

  /// Annotates image with bounding boxes for columns and gutter.
  img.Image _drawLayoutAnnotations(img.Image base, LayoutAnalysisResult layout) {
    final annotated = img.Image.from(base);

    // Draw Gutter if present (Red dashed/vertical line)
    if (layout.gutter != null) {
      final g = layout.gutter!;
      for (int y = 0; y < annotated.height; y++) {
        for (int x = g.left; x <= g.right && x < annotated.width; x++) {
          final cur = annotated.getPixel(x, y);
          // Highlight with semi-transparent red
          annotated.setPixelRgb(
            x,
            y,
            (cur.r * 0.5 + 128).toInt(),
            (cur.g * 0.5).toInt(),
            (cur.b * 0.5).toInt(),
          );
        }
      }
    }

    // Draw Column Boxes (Blue borders)
    for (final col in layout.columnBoxes) {
      final borderThickness = math.max(2, (annotated.width / 500).round());
      for (int t = 0; t < borderThickness; t++) {
        // Top and bottom horizontal edges
        for (int x = col.left; x < col.right && x < annotated.width; x++) {
          if (col.top + t < annotated.height) {
            annotated.setPixelRgb(x, col.top + t, 0, 120, 255);
          }
          if (col.bottom - 1 - t >= 0 && col.bottom - 1 - t < annotated.height) {
            annotated.setPixelRgb(x, col.bottom - 1 - t, 0, 120, 255);
          }
        }
        // Left and right vertical edges
        for (int y = col.top; y < col.bottom && y < annotated.height; y++) {
          if (col.left + t < annotated.width) {
            annotated.setPixelRgb(col.left + t, y, 0, 120, 255);
          }
          if (col.right - 1 - t >= 0 && col.right - 1 - t < annotated.width) {
            annotated.setPixelRgb(col.right - 1 - t, y, 0, 120, 255);
          }
        }
      }
    }

    return annotated;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Local OCR Pipeline Integration Test Harness', () {
    test(
      'Harness execution against real test fixture image',
      () async {
        final fixtureFile = File('test/fixtures/mcq_book_page.png');
        expect(await fixtureFile.exists(), isTrue,
            reason: 'Test fixture image test/fixtures/mcq_book_page.png must exist');

        final outputDir = Directory('test_results/local_ocr');
        final harness = OcrPipelineHarness(
          inputImage: fixtureFile,
          outputDir: outputDir,
        );

        final report = await harness.execute();

        expect(report['steps']['step1_original'], isNotNull);
        expect(report['steps']['step2_layout_detection'], isNotNull);
        expect(File('test_results/local_ocr/01_original.png').existsSync(), isTrue);
        expect(File('test_results/local_ocr/02_deskewed.png').existsSync(), isTrue);
        expect(File('test_results/local_ocr/03_layout_detected.png').existsSync(), isTrue);
        expect(File('test_results/local_ocr/04_left_column.png').existsSync(), isTrue);
        expect(File('test_results/local_ocr/05_right_column.png').existsSync(), isTrue);
        expect(File('test_results/local_ocr/06_left_ocr.txt').existsSync(), isTrue);
        expect(File('test_results/local_ocr/07_right_ocr.txt').existsSync(), isTrue);
        expect(File('test_results/local_ocr/08_ocr_boxes.json').existsSync(), isTrue);
        expect(File('test_results/local_ocr/09_segmented_questions.json').existsSync(), isTrue);
        expect(File('test_results/local_ocr/10_final_quiz_questions.json').existsSync(), isTrue);
        expect(File('test_results/local_ocr/benchmark_report.json').existsSync(), isTrue);
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });
}
