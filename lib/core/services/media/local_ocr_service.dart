import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:local_ocr/local_ocr.dart';

import 'layout/layout_detection_service.dart';
import 'ocr/page_ocr_result.dart';
import 'ocr_text_cleaner.dart';
import 'segmentation/question_segmentation_service.dart';
import 'segmentation/segmentation_models.dart';

/// Language preset options for offline OCR.
enum OcrLanguagePreset {
  bengaliMathEnglish(
    code: 'ben+eng+equ',
    label: 'বাংলা + অঙ্ক + English',
    description: 'সর্বোচ্চ অগ্রাধিকার (মিক্সড বাংলা, গণিত এবং ইংরেজি)',
  ),
  bengaliOnly(
    code: 'ben',
    label: 'শুধু বাংলা (Bengali)',
    description: 'শুধু বাংলা টেক্সট বা রচনার জন্য',
  ),
  englishMath(
    code: 'eng+equ',
    label: 'English + Math',
    description: 'ইংরেজি প্যারাগ্রাফ, অংক বা সমীকরণ',
  );

  const OcrLanguagePreset({
    required this.code,
    required this.label,
    required this.description,
  });

  final String code;
  final String label;
  final String description;
}

/// Page segmentation / layout modes for OCR.
enum OcrLayoutMode {
  twoColumnsBook(
    psm: '6',
    label: 'বইয়ের পুরো পাতা (২ কলাম)',
    description: 'স্বয়ংক্রিয়ভাবে বাম ও ডান কলাম আলাদা করে প্রশ্নানুসারে সাজায়',
  ),
  singleColumn(
    psm: '6',
    label: 'সিঙ্গেল কলাম / ক্রপ',
    description: 'ক্রপ করা প্যারাগ্রাফ বা এক কলামের জন্য নিখুঁত',
  ),
  autoPage(
    psm: '3',
    label: 'পুরো পৃষ্ঠা (সাধারণ)',
    description: 'সম্পূর্ণ পেজের সাধারণ শনাক্তকরণ',
  ),
  multiColumn(
    psm: '4',
    label: 'বহু কলাম (Multi-column)',
    description: 'পত্রিকা বা বহু কলামের পেজের জন্য',
  );

  const OcrLayoutMode({
    required this.psm,
    required this.label,
    required this.description,
  });

  final String psm;
  final String label;
  final String description;
}

/// Offline OCR service wrapping local Tesseract engine.
///
/// Operates 100% on-device with zero network latency and no cloud AI reliance.
class LocalOcrService {
  LocalOcrService._();
  static final LocalOcrService instance = LocalOcrService._();

  /// Extracts text from [imageFile] using local Tesseract LSTM engine.
  Future<String> extractText({
    required File imageFile,
    OcrLanguagePreset languagePreset = OcrLanguagePreset.bengaliMathEnglish,
    OcrLayoutMode layoutMode = OcrLayoutMode.twoColumnsBook,
    Map<String, String>? customArgs,
  }) async {
    if (!await imageFile.exists()) {
      throw Exception('ছবিটি খুঁজে পাওয়া যায়নি: ${imageFile.path}');
    }

    // Special handling for 2-column book/question paper pages
    if (layoutMode == OcrLayoutMode.twoColumnsBook) {
      try {
        final pageOcr = await processPage(
          imageFile: imageFile,
          languagePreset: languagePreset,
          customArgs: customArgs,
        );

        if (pageOcr.isDualColumn && pageOcr.columns.length == 2) {
          final clean1 = OcrTextCleaner.clean(pageOcr.columns[0].rawText);
          final clean2 = OcrTextCleaner.clean(pageOcr.columns[1].rawText);

          if (clean2.isEmpty) return clean1;
          if (clean1.isEmpty) return clean2;

          return '📌 [কলাম ১ (বাম পাশ)]:\n\n$clean1\n\n'
              '════════════════════════════════\n\n'
              '📌 [কলাম ২ (ডান পাশ)]:\n\n$clean2';
        } else {
          // Single-column page
          if (pageOcr.columns.isNotEmpty) {
            return pageOcr.columns[0].rawText.trim();
          }
        }
      } catch (_) {
        // Fallback to single extraction if layout analysis fails
      }
    }

    return _extractSingle(
      imageFile,
      languagePreset,
      layoutMode.psm,
      customArgs,
    );
  }

  /// Processes a full-page image through Stage 3.1 Layout Detection, performs
  /// sequential native Tesseract OCR on each column, maps all word and line
  /// bounding boxes to original page coordinates, and merges lines in strict
  /// top-to-bottom reading order (Left Column -> Right Column).
  Future<PageOcrResult> processPage({
    required File imageFile,
    OcrLanguagePreset languagePreset = OcrLanguagePreset.bengaliMathEnglish,
    Map<String, String>? customArgs,
  }) async {
    final overallStopwatch = Stopwatch()..start();

    // 1. Stage 3.1: Layout Analysis & Column Slicing
    final layoutStopwatch = Stopwatch()..start();
    final layoutResult = await LayoutDetectionService.instance.analyzeLayout(
      imageFile,
      autoDeskew: true,
    );
    layoutStopwatch.stop();

    final List<ColumnOcrResult> columnResults = [];
    final List<TextLineBox> allMergedLines = [];
    int totalOcrElapsedMs = 0;

    final crops = layoutResult.columnCrops;
    final boxes = layoutResult.columnBoxes;

    // 2. Sequential OCR Execution to prevent peak RAM pressure on low-memory devices
    for (int colIdx = 0; colIdx < crops.length; colIdx++) {
      final cropFile = crops[colIdx];
      final colBox = boxes[colIdx];
      final colCropBox = TextBoundingBox(
        left: colBox.left,
        top: colBox.top,
        width: colBox.width,
        height: colBox.height,
      );

      final colOcrStopwatch = Stopwatch()..start();

      // Native Tesseract extractText
      final rawText = await _extractSingle(
        cropFile,
        languagePreset,
        '6', // PSM 6: Assume a single uniform block of text
        customArgs,
      );

      // Native Tesseract extractHocr
      String hocrText = '';
      try {
        hocrText = await _extractHocrSingle(
          cropFile,
          languagePreset,
          '6',
          customArgs,
        );
      } catch (e) {
        debugPrint('Warning: hOCR extraction failed on column $colIdx: $e');
      }

      colOcrStopwatch.stop();
      final ocrElapsed = colOcrStopwatch.elapsedMilliseconds;
      totalOcrElapsedMs += ocrElapsed;

      // 3. Parse local hOCR lines
      List<TextLineBox> localLines = [];
      if (hocrText.isNotEmpty) {
        localLines = QuestionSegmentationService.parseHocrToLines(
          hocrText: hocrText,
          columnId: colIdx,
        );
      }

      // If hOCR returned no lines but rawText exists, synthesize fallback line boxes
      if (localLines.isEmpty && rawText.isNotEmpty) {
        localLines = _synthesizeLinesFromRawText(rawText, colCropBox, colIdx);
      }

      // 4. Map bounding boxes to Original Page Coordinates:
      // originalX = cropX + cropOriginX (clamp to [0, pageWidth])
      // originalY = cropY + cropOriginY (clamp to [0, pageHeight])
      final pageMappedLines = mapLinesToPageCoordinates(
        lines: localLines,
        cropBox: colCropBox,
        pageWidth: layoutResult.imageWidth,
        pageHeight: layoutResult.imageHeight,
        columnIndex: colIdx,
      );

      // Sort lines inside column strictly from top to bottom
      pageMappedLines.sort(
        (a, b) => a.boundingBox.top.compareTo(b.boundingBox.top),
      );

      columnResults.add(
        ColumnOcrResult(
          columnIndex: colIdx,
          cropFile: cropFile,
          cropBox: colCropBox,
          rawText: rawText,
          hocrText: hocrText,
          pageLines: pageMappedLines,
          ocrElapsedMs: ocrElapsed,
        ),
      );

      // Add to reading order collection
      allMergedLines.addAll(pageMappedLines);
    }

    overallStopwatch.stop();

    return PageOcrResult(
      pageWidth: layoutResult.imageWidth,
      imageHeight: layoutResult.imageHeight,
      layoutType: layoutResult.layoutType,
      gutter: layoutResult.gutter,
      columns: columnResults,
      mergedLines: allMergedLines,
      layoutElapsedMs: layoutStopwatch.elapsedMilliseconds,
      totalOcrElapsedMs: totalOcrElapsedMs,
      totalElapsedMs: overallStopwatch.elapsedMilliseconds,
    );
  }

  /// Maps a list of [TextLineBox] from crop-local coordinates to original page coordinates.
  /// Formula: originalX = cropX + cropBox.left, originalY = cropY + cropBox.top
  /// All coordinates are clamped safely to avoid exceeding image dimensions.
  static List<TextLineBox> mapLinesToPageCoordinates({
    required List<TextLineBox> lines,
    required TextBoundingBox cropBox,
    required int pageWidth,
    required int pageHeight,
    required int columnIndex,
  }) {
    final List<TextLineBox> mapped = [];

    for (final line in lines) {
      final box = line.boundingBox;

      // Coordinate transformation
      final newLeft = (box.left + cropBox.left).clamp(0, pageWidth - 1);
      final newTop = (box.top + cropBox.top).clamp(0, pageHeight - 1);

      // Width and height clamping to image boundary
      final maxWidth = math.max(1, pageWidth - newLeft);
      final maxHeight = math.max(1, pageHeight - newTop);
      final newWidth = box.width.clamp(1, maxWidth);
      final newHeight = box.height.clamp(1, maxHeight);

      mapped.add(
        line.copyWith(
          boundingBox: TextBoundingBox(
            left: newLeft,
            top: newTop,
            width: newWidth,
            height: newHeight,
          ),
          columnId: columnIndex,
        ),
      );
    }

    return mapped;
  }

  /// Synthesizes proportional bounding boxes for raw text lines when hOCR is empty or unavailable.
  static List<TextLineBox> _synthesizeLinesFromRawText(
    String rawText,
    TextBoundingBox cropBox,
    int columnIndex,
  ) {
    final lines = rawText
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) return [];

    final double lineH = cropBox.height / (lines.length + 1);
    final List<TextLineBox> result = [];

    for (int i = 0; i < lines.length; i++) {
      final y = (i * lineH).round();
      result.add(
        TextLineBox(
          text: lines[i].trim(),
          boundingBox: TextBoundingBox(
            left: 0,
            top: y,
            width: cropBox.width,
            height: math.max(1, lineH.round()),
          ),
          confidence: 0.80,
          columnId: columnIndex,
        ),
      );
    }

    return result;
  }

  Future<String> _extractSingle(
    File file,
    OcrLanguagePreset languagePreset,
    String psm,
    Map<String, String>? customArgs,
  ) async {
    final defaultArgs = <String, String>{
      'psm': psm,
      'preserve_interword_spaces': '1',
    };

    if (customArgs != null) {
      defaultArgs.addAll(customArgs);
    }

    try {
      final rawResult = await LocalOcr.extractText(
        file.path,
        language: languagePreset.code,
        args: defaultArgs,
      );

      return rawResult.trim();
    } catch (e) {
      // Fallback: if 'equ' throws error, try 'ben+eng'
      if (languagePreset.code.contains('equ')) {
        try {
          final fallbackLang = languagePreset == OcrLanguagePreset.englishMath
              ? 'eng'
              : 'ben+eng';
          final fallbackResult = await LocalOcr.extractText(
            file.path,
            language: fallbackLang,
            args: defaultArgs,
          );
          return fallbackResult.trim();
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<String> _extractHocrSingle(
    File file,
    OcrLanguagePreset languagePreset,
    String psm,
    Map<String, String>? customArgs,
  ) async {
    final defaultArgs = <String, String>{
      'psm': psm,
      'preserve_interword_spaces': '1',
    };

    if (customArgs != null) {
      defaultArgs.addAll(customArgs);
    }

    try {
      final rawResult = await LocalOcr.extractHocr(
        file.path,
        language: languagePreset.code,
        args: defaultArgs,
      );

      return rawResult.trim();
    } catch (e) {
      if (languagePreset.code.contains('equ')) {
        try {
          final fallbackLang = languagePreset == OcrLanguagePreset.englishMath
              ? 'eng'
              : 'ben+eng';
          final fallbackResult = await LocalOcr.extractHocr(
            file.path,
            language: fallbackLang,
            args: defaultArgs,
          );
          return fallbackResult.trim();
        } catch (_) {}
      }
      rethrow;
    }
  }
}
