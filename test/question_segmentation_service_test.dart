import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:life_and_study_assistant/core/services/media/layout/layout_detection_models.dart';
import 'package:life_and_study_assistant/core/services/media/segmentation/question_segmentation_service.dart';
import 'package:life_and_study_assistant/core/services/media/segmentation/segmentation_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late QuestionSegmentationService service;
  late Directory tempDir;

  setUp(() {
    service = QuestionSegmentationService.instance;
    tempDir = Directory.systemTemp.createTempSync('segmentation_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Phase 2: Question & Option Block Segmentation Benchmarks', () {
    test('Benchmark 1: Standard Bengali 4-Option MCQ segmentation', () async {
      final layout = LayoutAnalysisResult(
        originalImage: File('dummy.jpg'),
        deskewedImage: File('dummy.jpg'),
        layoutType: LayoutType.singleColumn,
        skewAngle: 0.0,
        gutter: null,
        confidence: 0.95,
        imageWidth: 800,
        imageHeight: 1200,
        columnBoxes: const [
          ColumnBoundingBox(index: 0, left: 0, top: 0, width: 800, height: 1200),
        ],
        columnCrops: [],
      );

      final columnLines = <int, List<TextLineBox>>{
        0: [
          const TextLineBox(
            text: '১. পামটপ কম্পিউটার বা পিডিএ (PDA) এর পূর্ণরূপ কী?',
            boundingBox: TextBoundingBox(left: 40, top: 100, width: 600, height: 30),
            confidence: 0.95,
          ),
          const TextLineBox(
            text: '(ক) Personal Digital Assistant',
            boundingBox: TextBoundingBox(left: 60, top: 140, width: 300, height: 25),
            confidence: 0.92,
          ),
          const TextLineBox(
            text: '(খ) Programmable Data Analyzer',
            boundingBox: TextBoundingBox(left: 60, top: 170, width: 300, height: 25),
            confidence: 0.90,
          ),
          const TextLineBox(
            text: '(গ) Pushdown Automaton',
            boundingBox: TextBoundingBox(left: 60, top: 200, width: 300, height: 25),
            confidence: 0.91,
          ),
          const TextLineBox(
            text: '(ঘ) Portable Data Analyzer',
            boundingBox: TextBoundingBox(left: 60, top: 230, width: 300, height: 25),
            confidence: 0.94,
          ),
        ],
      };

      final result = await service.segmentPage(
        layout: layout,
        columnLines: columnLines,
      );

      expect(result.questions.length, 1);
      final q = result.questions.first;
      expect(q.questionNumber, '১');
      expect(q.questionText, 'পামটপ কম্পিউটার বা পিডিএ (PDA) এর পূর্ণরূপ কী?');
      expect(q.options.length, 4);
      expect(q.options[0], 'Personal Digital Assistant');
      expect(q.options[1], 'Programmable Data Analyzer');
      expect(q.options[2], 'Pushdown Automaton');
      expect(q.options[3], 'Portable Data Analyzer');
      expect(q.reviewRequired, isFalse);
      expect(q.segmentationConfidence, greaterThanOrEqualTo(0.9));
    });

    test('Benchmark 2: Dual Column Sequential Reading Order & Column Isolation', () async {
      // 2 columns: Column 0 (left: 0..400), Column 1 (right: 450..850)
      final layout = LayoutAnalysisResult(
        originalImage: File('dummy.jpg'),
        deskewedImage: File('dummy.jpg'),
        layoutType: LayoutType.dualColumnWhitespace,
        skewAngle: 0.0,
        gutter: null,
        confidence: 0.88,
        imageWidth: 850,
        imageHeight: 1200,
        columnBoxes: const [
          ColumnBoundingBox(index: 0, left: 0, top: 0, width: 400, height: 1200),
          ColumnBoundingBox(index: 1, left: 450, top: 0, width: 400, height: 1200),
        ],
        columnCrops: [],
      );

      final columnLines = <int, List<TextLineBox>>{
        // Left Column (Col 0): Q1 and Q2
        0: [
          const TextLineBox(
            text: '১. প্রথম কলামের প্রথম প্রশ্ন?',
            boundingBox: TextBoundingBox(left: 20, top: 100, width: 300, height: 30),
            confidence: 0.90,
          ),
          const TextLineBox(
            text: '(ক) উত্তর ১ (খ) উত্তর ২',
            boundingBox: TextBoundingBox(left: 30, top: 140, width: 300, height: 25),
            confidence: 0.88,
          ),
          const TextLineBox(
            text: '(গ) উত্তর ৩ (ঘ) উত্তর ৪',
            boundingBox: TextBoundingBox(left: 30, top: 170, width: 300, height: 25),
            confidence: 0.88,
          ),
          const TextLineBox(
            text: '২. প্রথম কলামের দ্বিতীয় প্রশ্ন?',
            boundingBox: TextBoundingBox(left: 20, top: 220, width: 300, height: 30),
            confidence: 0.92,
          ),
          const TextLineBox(
            text: '(ক) A (খ) B (গ) C (ঘ) D',
            boundingBox: TextBoundingBox(left: 30, top: 260, width: 300, height: 25),
            confidence: 0.85,
          ),
        ],
        // Right Column (Col 1): Q3 and Q4
        1: [
          const TextLineBox(
            text: '৩. দ্বিতীয় কলামের প্রথম প্রশ্ন?',
            boundingBox: TextBoundingBox(left: 20, top: 100, width: 300, height: 30),
            confidence: 0.90,
          ),
          const TextLineBox(
            text: '(ক) X (খ) Y (গ) Z (ঘ) W',
            boundingBox: TextBoundingBox(left: 30, top: 140, width: 300, height: 25),
            confidence: 0.89,
          ),
          const TextLineBox(
            text: '৪. দ্বিতীয় কলামের শেষ প্রশ্ন?',
            boundingBox: TextBoundingBox(left: 20, top: 220, width: 300, height: 30),
            confidence: 0.91,
          ),
          const TextLineBox(
            text: '(ক) ১ (খ) ২ (গ) ৩ (ঘ) ৪',
            boundingBox: TextBoundingBox(left: 30, top: 260, width: 300, height: 25),
            confidence: 0.87,
          ),
        ],
      };

      final result = await service.segmentPage(
        layout: layout,
        columnLines: columnLines,
      );

      // Verify exact count and reading order
      expect(result.questions.length, 4);
      expect(result.questions[0].questionNumber, '১');
      expect(result.questions[0].columnId, 0);
      expect(result.questions[1].questionNumber, '২');
      expect(result.questions[1].columnId, 0);

      expect(result.questions[2].questionNumber, '৩');
      expect(result.questions[2].columnId, 1);
      // Verify absolute page coordinate shift (Col 1 left is 450)
      expect(result.questions[2].boundingBox.left, greaterThanOrEqualTo(450));

      expect(result.questions[3].questionNumber, '৪');
      expect(result.questions[3].columnId, 1);

      // Verify Column 0 questions never got options from Column 1
      expect(result.questions[0].options, contains('উত্তর ১'));
      expect(result.questions[0].options, isNot(contains('X')));
    });

    test('Benchmark 3: Multi-Option per line parsing (2x2 grid & single-line 4 options)', () async {
      final layout = LayoutAnalysisResult(
        originalImage: File('dummy.jpg'),
        deskewedImage: File('dummy.jpg'),
        layoutType: LayoutType.singleColumn,
        skewAngle: 0.0,
        gutter: null,
        confidence: 0.90,
        imageWidth: 800,
        imageHeight: 600,
        columnBoxes: const [
          ColumnBoundingBox(index: 0, left: 0, top: 0, width: 800, height: 600),
        ],
        columnCrops: [],
      );

      final columnLines = <int, List<TextLineBox>>{
        0: [
          const TextLineBox(
            text: '1. Which city is known as the port city of Bangladesh?',
            boundingBox: TextBoundingBox(left: 20, top: 50, width: 500, height: 30),
            confidence: 0.95,
          ),
          // 2x2 grid format
          const TextLineBox(
            text: '(A) Dhaka           (B) Chattogram',
            boundingBox: TextBoundingBox(left: 40, top: 90, width: 500, height: 25),
            confidence: 0.90,
          ),
          const TextLineBox(
            text: '(C) Sylhet          (D) Rajshahi',
            boundingBox: TextBoundingBox(left: 40, top: 120, width: 500, height: 25),
            confidence: 0.91,
          ),
        ],
      };

      final result = await service.segmentPage(
        layout: layout,
        columnLines: columnLines,
      );

      expect(result.questions.length, 1);
      final q = result.questions.first;
      expect(q.questionNumber, '1');
      expect(q.options.length, 4);
      expect(q.options[0], 'Dhaka');
      expect(q.options[1], 'Chattogram');
      expect(q.options[2], 'Sylhet');
      expect(q.options[3], 'Rajshahi');
      expect(q.reviewRequired, isFalse);
    });

    test('Benchmark 4: Real-world Scanned OCR Artifacts (from user book page)', () async {
      // Simulating actual OCR symbols produced by Tesseract for Bengali circled markers
      final layout = LayoutAnalysisResult(
        originalImage: File('dummy.jpg'),
        deskewedImage: File('dummy.jpg'),
        layoutType: LayoutType.singleColumn,
        skewAngle: 0.0,
        gutter: null,
        confidence: 0.85,
        imageWidth: 800,
        imageHeight: 600,
        columnBoxes: const [
          ColumnBoundingBox(index: 0, left: 0, top: 0, width: 800, height: 600),
        ],
        columnCrops: [],
      );

      final columnLines = <int, List<TextLineBox>>{
        0: [
          const TextLineBox(
            text: '১২. এমবেডেড কম্পিউটার ব্যবহৃত হয় না কোনটিতে?',
            boundingBox: TextBoundingBox(left: 20, top: 50, width: 500, height: 30),
            confidence: 0.88,
          ),
          // Real OCR output with symbols ©, ও), @
          const TextLineBox(
            text: '© এয়ার কন্ডিশনার   ও) লাইট',
            boundingBox: TextBoundingBox(left: 30, top: 90, width: 450, height: 25),
            confidence: 0.82,
          ),
          const TextLineBox(
            text: '@ এটিএম   ঘ) ওয়াশিং মেশিন',
            boundingBox: TextBoundingBox(left: 30, top: 120, width: 450, height: 25),
            confidence: 0.84,
          ),
        ],
      };

      final result = await service.segmentPage(
        layout: layout,
        columnLines: columnLines,
      );

      expect(result.questions.length, 1);
      final q = result.questions.first;
      expect(q.questionNumber, '১২');
      expect(q.questionText, 'এমবেডেড কম্পিউটার ব্যবহৃত হয় না কোনটিতে?');
      expect(q.options.length, 4);
      expect(q.options[0], 'এয়ার কন্ডিশনার');
      expect(q.options[1], 'লাইট');
      expect(q.options[2], 'এটিএম');
      expect(q.options[3], 'ওয়াশিং মেশিন');
      expect(q.reviewRequired, isFalse);
    });

    test('Benchmark 5: Math & Diagram Preservation with High-Res Crop', () async {
      // Create a dummy image
      final sampleImg = img.Image(width: 800, height: 1000);
      img.fill(sampleImg, color: img.ColorRgb8(255, 255, 255));
      final imgFile = File('${tempDir.path}/math_page.jpg');
      await imgFile.writeAsBytes(img.encodeJpg(sampleImg));

      final layout = LayoutAnalysisResult(
        originalImage: imgFile,
        deskewedImage: imgFile,
        layoutType: LayoutType.singleColumn,
        skewAngle: 0.0,
        gutter: null,
        confidence: 0.90,
        imageWidth: 800,
        imageHeight: 1000,
        columnBoxes: const [
          ColumnBoundingBox(index: 0, left: 0, top: 0, width: 800, height: 1000),
        ],
        columnCrops: [],
      );

      final columnLines = <int, List<TextLineBox>>{
        0: [
          const TextLineBox(
            text: '৫. নিম্নের চিত্রে প্রদর্শিত সমীকরণের মান কত? y = \\sqrt{x^2 + 1}',
            boundingBox: TextBoundingBox(left: 30, top: 100, width: 550, height: 35),
            confidence: 0.85,
          ),
          const TextLineBox(
            text: '(ক) 1 (খ) 2 (গ) 3 (ঘ) 4',
            boundingBox: TextBoundingBox(left: 40, top: 150, width: 400, height: 25),
            confidence: 0.88,
          ),
        ],
      };

      final result = await service.segmentPage(
        layout: layout,
        columnLines: columnLines,
        originalImageFile: imgFile,
        cropsOutputDir: tempDir,
      );

      expect(result.questions.length, 1);
      final q = result.questions.first;
      expect(q.hasDiagram, isTrue);
      expect(q.diagramCropPath, isNotNull);
      expect(File(q.diagramCropPath!).existsSync(), isTrue);
      expect(q.originalCropReference, isNotNull);
    });

    test('Benchmark 6: Incomplete / Orphan Text Review Flagging (Safety Check)', () async {
      final layout = LayoutAnalysisResult(
        originalImage: File('dummy.jpg'),
        deskewedImage: File('dummy.jpg'),
        layoutType: LayoutType.singleColumn,
        skewAngle: 0.0,
        gutter: null,
        confidence: 0.80,
        imageWidth: 600,
        imageHeight: 800,
        columnBoxes: const [
          ColumnBoundingBox(index: 0, left: 0, top: 0, width: 600, height: 800),
        ],
        columnCrops: [],
      );

      final columnLines = <int, List<TextLineBox>>{
        0: [
          // Orphan header line (e.g. Chapter title or instructions without question number)
          const TextLineBox(
            text: 'অধ্যায় ৩: তথ্য ও যোগাযোগ প্রযুক্তি',
            boundingBox: TextBoundingBox(left: 20, top: 30, width: 400, height: 30),
            confidence: 0.95,
          ),
          // Question with only 3 options (incomplete read)
          const TextLineBox(
            text: '৭. কম্পিউটার মেমোরি কয় প্রকার?',
            boundingBox: TextBoundingBox(left: 20, top: 80, width: 400, height: 30),
            confidence: 0.90,
          ),
          const TextLineBox(
            text: '(ক) ২ প্রকার',
            boundingBox: TextBoundingBox(left: 30, top: 120, width: 200, height: 25),
            confidence: 0.88,
          ),
          const TextLineBox(
            text: '(খ) ৩ প্রকার',
            boundingBox: TextBoundingBox(left: 30, top: 150, width: 200, height: 25),
            confidence: 0.88,
          ),
          const TextLineBox(
            text: '(গ) ৪ প্রকার',
            boundingBox: TextBoundingBox(left: 30, top: 180, width: 200, height: 25),
            confidence: 0.88,
          ),
        ],
      };

      final result = await service.segmentPage(
        layout: layout,
        columnLines: columnLines,
      );

      // Verify orphan text is preserved and not thrown away
      expect(result.orphanBlocks.length, 1);
      expect(result.orphanBlocks.first.questionText, contains('তথ্য ও যোগাযোগ প্রযুক্তি'));

      // Verify question with 3 options is flagged for review
      expect(result.questions.length, 1);
      final q = result.questions.first;
      expect(q.reviewRequired, isTrue);
      expect(q.reviewReasons, anyElement(contains('৪টি প্রত্যাশিত')));

      // Bridge to QuizQuestion
      final quizQ = q.toQuizQuestion();
      expect(quizQ.correctIndex, -1); // Strictly -1 in Phase 2
      expect(quizQ.legible, isFalse); // Flagged for review
      expect(quizQ.printedNumber, '৭');
    });

    test('Benchmark 7: hOCR HTML Parser extracts lines and word confidences', () {
      const sampleHocr = '''
<div class='ocr_page' id='page_1' title='bbox 0 0 1000 1500'>
  <div class='ocr_carea' id='block_1_1' title='bbox 50 100 800 300'>
    <p class='ocr_par' id='par_1_1' title='bbox 50 100 800 300'>
      <span class='ocr_line' id='line_1_1' title='bbox 50 100 700 140'>
        <span class='ocrx_word' id='word_1_1' title='bbox 50 100 90 140; x_wconf 95'>১.</span>
        <span class='ocrx_word' id='word_1_2' title='bbox 100 100 200 140; x_wconf 90'>বাংলা</span>
        <span class='ocrx_word' id='word_1_3' title='bbox 210 100 350 140; x_wconf 92'>প্রশ্ন?</span>
      </span>
      <span class='ocr_line' id='line_1_2' title='bbox 60 150 600 185'>
        <span class='ocrx_word' id='word_1_4' title='bbox 60 150 120 185; x_wconf 88'>(ক)</span>
        <span class='ocrx_word' id='word_1_5' title='bbox 130 150 250 185; x_wconf 86'>উত্তর</span>
      </span>
    </p>
  </div>
</div>
''';

      final lines = QuestionSegmentationService.parseHocrToLines(
        hocrText: sampleHocr,
        columnId: 0,
      );

      expect(lines.length, 2);
      expect(lines[0].text, '১. বাংলা প্রশ্ন?');
      expect(lines[0].boundingBox.left, 50);
      expect(lines[0].boundingBox.top, 100);
      expect(lines[0].confidence, closeTo(0.92, 0.02));

      expect(lines[1].text, '(ক) উত্তর');
      expect(lines[1].boundingBox.left, 60);
      expect(lines[1].boundingBox.top, 150);
    });
  });
}
