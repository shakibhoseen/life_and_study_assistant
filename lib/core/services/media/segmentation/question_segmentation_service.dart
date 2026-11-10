import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../layout/layout_detection_models.dart';
import 'segmentation_models.dart';

/// Service responsible for Column-wise Question & Option Block Segmentation (Phase 2).
class QuestionSegmentationService {
  QuestionSegmentationService._();
  static final QuestionSegmentationService instance =
      QuestionSegmentationService._();

  /// Regex patterns for Question Number Detection.
  /// Supports: ১., ১।, ১), (১), 1., 1), Q1, Q.1, Q1: etc.
  static final RegExp _bengaliQuestionPattern = RegExp(
    r'^(?:(?:\(|\[)?([০-৯]+)(?:\)|\]|\.|\।|\:|\-))\s*(.*)$',
  );

  static final RegExp _englishQuestionPattern = RegExp(
    r'^(?:(?:Q|Question)\s*[\.\:\-]?\s*(\d+)|(?:\(|\[)?(\d+)(?:\)|\]|\.|\:|\-))\s*(.*)$',
    caseSensitive: false,
  );

  /// Regex pattern for Option Markers.
  /// Supports:
  /// - Bengali: ক, খ, গ, ঘ, (ক), (খ), ক।, ক., ㉠, ㉡, ㉢, ㉣
  /// - English: A, B, C, D, (A), (B), (a), (b), A., B.
  /// - Common OCR misreads of circled markers: ©, ®, @, €, ও), গু, ঘ)
  static final RegExp _optionMarkerPattern = RegExp(
    r'(?:^|\s+)('
    r'[\(\[]?[কখগঘ][\)\]\.\।\:\-]'
    r'|[\(\[]?[ABCDabcd][\)\]\.\:\-]'
    r'|[㉠㉡㉢㉣⓪①②③]'
    r'|[©®@€]'
    r'|ও\)'
    r'|গু[\.\)]'
    r'|ঘ[\.\)]'
    r')\s*',
  );

  /// Words indicating math, tables, or diagrams.
  static final RegExp _diagramKeywordPattern = RegExp(
    r'(চিত্র|চিত্রে|চিত্রটিতে|চিত্রানুযায়ী|লেখচিত্র|সারণি|সারণী|ছক|ডায়াগ্রাম|গ্রাফ|diagram|figure|table)',
    caseSensitive: false,
  );

  static final RegExp _mathSymbolPattern = RegExp(
    r'([\√\∑\∏\∫\±\×\÷\≠\≤\≥\∞\π\θ\α\β\γ\^]|\/|\\frac|\\sqrt|sin|cos|tan|log)',
  );

  /// Segments an analyzed page into structured questions and options.
  Future<PageSegmentationResult> segmentPage({
    required LayoutAnalysisResult layout,
    required Map<int, List<TextLineBox>> columnLines,
    File? originalImageFile,
    Directory? cropsOutputDir,
  }) async {
    final List<SegmentedQuestionBlock> allQuestions = [];
    final List<SegmentedQuestionBlock> allOrphans = [];

    img.Image? originalImage;
    if (originalImageFile != null && await originalImageFile.exists()) {
      try {
        final bytes = await originalImageFile.readAsBytes();
        originalImage = img.decodeImage(bytes);
      } catch (_) {
        originalImage = null;
      }
    }

    // Process Column 0 (Left) first, then Column 1 (Right)
    for (int colIdx = 0; colIdx < layout.columnBoxes.length; colIdx++) {
      final colBox = layout.columnBoxes[colIdx];
      final lines = columnLines[colIdx] ?? [];

      final colResult = _segmentSingleColumn(
        columnId: colIdx,
        columnBox: colBox,
        lines: lines,
        originalImage: originalImage,
        cropsOutputDir: cropsOutputDir,
      );

      allQuestions.addAll(colResult.questions);
      allOrphans.addAll(colResult.orphans);
    }

    return PageSegmentationResult(
      pageWidth: layout.imageWidth,
      pageHeight: layout.imageHeight,
      layoutType: layout.layoutType,
      questions: allQuestions,
      orphanBlocks: allOrphans,
    );
  }

  /// Segments a single column independently.
  /// Never attaches lines or options from other columns.
  _ColumnParseResult _segmentSingleColumn({
    required int columnId,
    required ColumnBoundingBox columnBox,
    required List<TextLineBox> lines,
    img.Image? originalImage,
    Directory? cropsOutputDir,
  }) {
    final List<SegmentedQuestionBlock> questions = [];
    final List<SegmentedQuestionBlock> orphans = [];

    if (lines.isEmpty) {
      return _ColumnParseResult(questions: questions, orphans: orphans);
    }

    // Sort lines from top to bottom
    final sortedLines = List<TextLineBox>.from(lines)
      ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

    _DraftQuestionBlock? currentBlock;

    for (int i = 0; i < sortedLines.length; i++) {
      final line = sortedLines[i];
      final lineText = line.text.trim();
      if (lineText.isEmpty) continue;

      // Check if this line is a question header
      final questionHeader = _detectQuestionHeader(
        lineText: lineText,
        box: line.boundingBox,
        columnWidth: columnBox.width,
      );

      if (questionHeader != null) {
        // Finalize previous block if any
        if (currentBlock != null) {
          final finalized = _finalizeBlock(
            draft: currentBlock,
            columnId: columnId,
            columnBox: columnBox,
            originalImage: originalImage,
            cropsOutputDir: cropsOutputDir,
          );
          if (finalized.isOrphan) {
            orphans.add(finalized);
          } else {
            questions.add(finalized);
          }
        }

        // Start new question block
        currentBlock = _DraftQuestionBlock(
          questionNumber: questionHeader.number,
          promptLines: [questionHeader.remainingText],
          allBoxes: [line.boundingBox],
          confidences: [line.confidence],
          isOrphan: false,
        );
      } else {
        // Line belongs to current block or is an orphan line before first question
        if (currentBlock == null) {
          // Orphan line before first question
          currentBlock = _DraftQuestionBlock(
            questionNumber: '',
            promptLines: [lineText],
            allBoxes: [line.boundingBox],
            confidences: [line.confidence],
            isOrphan: true,
          );
        } else {
          // Check if this line contains option markers
          final parsedOptions = _extractOptionsFromLine(lineText);
          if (parsedOptions.isNotEmpty) {
            currentBlock.optionItems.addAll(parsedOptions);
            currentBlock.allBoxes.add(line.boundingBox);
            currentBlock.confidences.add(line.confidence);
          } else {
            // Continues prompt or note
            if (currentBlock.optionItems.isEmpty) {
              currentBlock.promptLines.add(lineText);
            } else {
              // Note/explanation below options
              currentBlock.explanationLines.add(lineText);
            }
            currentBlock.allBoxes.add(line.boundingBox);
            currentBlock.confidences.add(line.confidence);
          }
        }
      }
    }

    // Finalize the last block
    if (currentBlock != null) {
      final finalized = _finalizeBlock(
        draft: currentBlock,
        columnId: columnId,
        columnBox: columnBox,
        originalImage: originalImage,
        cropsOutputDir: cropsOutputDir,
      );
      if (finalized.isOrphan) {
        orphans.add(finalized);
      } else {
        questions.add(finalized);
      }
    }

    return _ColumnParseResult(questions: questions, orphans: orphans);
  }

  /// Detects question number from line text and spatial position.
  _QuestionHeader? _detectQuestionHeader({
    required String lineText,
    required TextBoundingBox box,
    required int columnWidth,
  }) {
    // Spatial rule: A question start must begin in the left 40% of the column.
    // If a number appears far to the right, it is likely part of a sentence or math.
    if (box.left > columnWidth * 0.40) {
      return null;
    }

    // 1. Check Bengali numbers (১., ১।, ১), (১))
    final benMatch = _bengaliQuestionPattern.firstMatch(lineText);
    if (benMatch != null) {
      final numStr = benMatch.group(1) ?? '';
      final rest = benMatch.group(2)?.trim() ?? '';
      return _QuestionHeader(number: numStr, remainingText: rest);
    }

    // 2. Check English / Q numbers (1., 1), Q1, Q.1)
    final engMatch = _englishQuestionPattern.firstMatch(lineText);
    if (engMatch != null) {
      final numStr = engMatch.group(1) ?? engMatch.group(2) ?? '';
      final rest = engMatch.group(3)?.trim() ?? '';
      return _QuestionHeader(number: numStr, remainingText: rest);
    }

    return null;
  }

  /// Extracts one or more options from a line.
  /// Handles:
  /// - 1 option per line: "(ক) অপশন এক"
  /// - 2 options per line: "(ক) অপশন এক     (খ) অপশন দুই"
  /// - 4 options per line: "(ক) ১ (খ) ২ (গ) ৩ (ঘ) ৪"
  List<_ExtractedOption> _extractOptionsFromLine(String lineText) {
    final matches = _optionMarkerPattern.allMatches(lineText).toList();
    if (matches.isEmpty) return [];

    final List<_ExtractedOption> results = [];

    for (int i = 0; i < matches.length; i++) {
      final match = matches[i];
      final marker = _normalizeOptionMarker(match.group(1)?.trim() ?? '');
      final start = match.end;
      final end = (i + 1 < matches.length) ? matches[i + 1].start : lineText.length;

      final optionText = lineText.substring(start, end).trim();
      if (optionText.isNotEmpty || marker.isNotEmpty) {
        results.add(_ExtractedOption(marker: marker, text: optionText));
      }
    }

    return results;
  }

  /// Normalizes option markers to standard Bengali (ক, খ, গ, ঘ) or English (A, B, C, D).
  String _normalizeOptionMarker(String raw) {
    final clean = raw.replaceAll(RegExp(r'[\(\)\[\]\.\।\:\-\s]'), '');
    switch (clean) {
      case 'ক':
      case '㉠':
      case '⓪':
      case '①':
      case '©':
      case '€':
        return 'ক';
      case 'খ':
      case '㉡':
      case '②':
      case '®':
      case 'ও':
        return 'খ';
      case 'গ':
      case '㉢':
      case '③':
      case '@':
      case 'গু':
        return 'গ';
      case 'ঘ':
      case '㉣':
        return 'ঘ';
      case 'A':
      case 'a':
        return 'A';
      case 'B':
      case 'b':
        return 'B';
      case 'C':
      case 'c':
        return 'C';
      case 'D':
      case 'd':
        return 'D';
      default:
        return clean.isNotEmpty ? clean : raw;
    }
  }

  /// Finalizes a draft question block into [SegmentedQuestionBlock].
  SegmentedQuestionBlock _finalizeBlock({
    required _DraftQuestionBlock draft,
    required int columnId,
    required ColumnBoundingBox columnBox,
    img.Image? originalImage,
    Directory? cropsOutputDir,
  }) {
    // Compute unified bounding box in column coordinates
    TextBoundingBox colRelativeBox = draft.allBoxes.first;
    for (int i = 1; i < draft.allBoxes.length; i++) {
      colRelativeBox = colRelativeBox.union(draft.allBoxes[i]);
    }

    // Translate to absolute page coordinates
    final pageBox = colRelativeBox.shift(columnBox.left, columnBox.top);

    final questionPrompt = draft.promptLines.join(' ').trim();
    final List<String> options = [];
    final List<String> optionMarkers = [];

    for (final opt in draft.optionItems) {
      options.add(opt.text);
      optionMarkers.add(opt.marker);
    }

    final double avgOcrConf = draft.confidences.isNotEmpty
        ? draft.confidences.reduce((a, b) => a + b) / draft.confidences.length
        : 0.80;

    // Review & confidence assessment
    final List<String> reviewReasons = [];
    bool reviewRequired = false;

    if (draft.isOrphan || draft.questionNumber.isEmpty) {
      reviewRequired = true;
      reviewReasons.add('প্রশ্ন নম্বর পাওয়া যায়নি (অনাথ টেক্সট ব্লক)');
    }

    if (options.length != 4) {
      reviewRequired = true;
      reviewReasons.add('অপশন সংখ্যা ${options.length} (৪টি প্রত্যাশিত)');
    }

    if (avgOcrConf < 0.60) {
      reviewRequired = true;
      reviewReasons.add('OCR কনফিডেন্স কম (${(avgOcrConf * 100).toStringAsFixed(1)}%)');
    }

    // Check for math or diagram
    final bool hasDiagramOrMath = _diagramKeywordPattern.hasMatch(questionPrompt) ||
        _mathSymbolPattern.hasMatch(questionPrompt) ||
        (options.any((o) => _mathSymbolPattern.hasMatch(o)));

    // Segmentation confidence calculation
    double segConf = 1.0;
    if (draft.questionNumber.isEmpty) segConf -= 0.3;
    if (options.length != 4) segConf -= 0.35;
    if (avgOcrConf < 0.65) segConf -= 0.15;
    segConf = segConf.clamp(0.2, 1.0);

    // Save crops if image and directory are provided
    String? originalCropRef;
    String? diagramCropRef;

    if (originalImage != null && cropsOutputDir != null) {
      final safeLeft = pageBox.left.clamp(0, originalImage.width - 1);
      final safeTop = pageBox.top.clamp(0, originalImage.height - 1);
      final safeWidth = math.min(pageBox.width, originalImage.width - safeLeft);
      final safeHeight = math.min(pageBox.height, originalImage.height - safeTop);

      if (safeWidth > 10 && safeHeight > 10) {
        final crop = img.copyCrop(
          originalImage,
          x: safeLeft,
          y: safeTop,
          width: safeWidth,
          height: safeHeight,
        );

        final qId = draft.questionNumber.isNotEmpty
            ? draft.questionNumber
            : 'orphan_${DateTime.now().microsecondsSinceEpoch}';
        final cropFile = File(
          p.join(cropsOutputDir.path, 'col_${columnId}_q_$qId.jpg'),
        );
        cropFile.writeAsBytesSync(img.encodeJpg(crop, quality: 90));
        originalCropRef = cropFile.path;

        if (hasDiagramOrMath) {
          diagramCropRef = cropFile.path;
        }
      }
    }

    return SegmentedQuestionBlock(
      questionNumber: draft.questionNumber,
      questionText: questionPrompt,
      options: options,
      optionMarkers: optionMarkers,
      boundingBox: pageBox,
      columnId: columnId,
      ocrConfidence: avgOcrConf,
      segmentationConfidence: segConf,
      reviewRequired: reviewRequired,
      reviewReasons: reviewReasons,
      originalCropReference: originalCropRef,
      diagramCropPath: diagramCropRef,
      hasDiagram: hasDiagramOrMath,
      isOrphan: draft.isOrphan,
    );
  }

  /// Parses hOCR HTML into structured [TextLineBox] objects.
  static List<TextLineBox> parseHocrToLines({
    required String hocrText,
    required int columnId,
  }) {
    if (hocrText.isEmpty) return [];

    final lineHeaderRegex = RegExp(
      r'''<span[^>]*class=['"]ocr_line['"][^>]*title=['"]bbox (\d+) (\d+) (\d+) (\d+)[^'"]*['"][^>]*>''',
      caseSensitive: false,
    );

    final wordRegex = RegExp(
      r'''<span[^>]*class=['"]ocrx_word['"][^>]*title=['"][^'"]*x_wconf (\d+)[^'"]*['"][^>]*>([^<]*)</span>''',
      caseSensitive: false,
    );

    final List<TextLineBox> resultLines = [];
    final lineMatches = lineHeaderRegex.allMatches(hocrText).toList();

    for (int i = 0; i < lineMatches.length; i++) {
      final lm = lineMatches[i];
      final x1 = int.tryParse(lm.group(1) ?? '0') ?? 0;
      final y1 = int.tryParse(lm.group(2) ?? '0') ?? 0;
      final x2 = int.tryParse(lm.group(3) ?? '0') ?? 0;
      final y2 = int.tryParse(lm.group(4) ?? '0') ?? 0;

      final contentStart = lm.end;
      final contentEnd = (i + 1 < lineMatches.length)
          ? lineMatches[i + 1].start
          : hocrText.length;
      final lineContent = hocrText.substring(contentStart, contentEnd);

      // Extract words and confidence
      final List<int> confidences = [];
      final StringBuffer lineBuffer = StringBuffer();

      final wordMatches = wordRegex.allMatches(lineContent);
      if (wordMatches.isNotEmpty) {
        for (final wm in wordMatches) {
          final conf = int.tryParse(wm.group(1) ?? '80') ?? 80;
          confidences.add(conf);
          final wordClean = wm.group(2)
                  ?.replaceAll(RegExp(r'<[^>]*>'), '')
                  .replaceAll(RegExp(r'\s+'), ' ')
                  .trim() ??
              '';
          if (wordClean.isNotEmpty) {
            if (lineBuffer.isNotEmpty) lineBuffer.write(' ');
            lineBuffer.write(wordClean);
          }
        }
      } else {
        // Fallback: strip tags
        final clean = lineContent.replaceAll(RegExp(r'<[^>]*>'), '').trim();
        lineBuffer.write(clean);
        confidences.add(80);
      }

      final text = lineBuffer.toString().trim();
      if (text.isEmpty) continue;

      final double avgConf = confidences.isNotEmpty
          ? (confidences.reduce((a, b) => a + b) / confidences.length) / 100.0
          : 0.80;

      resultLines.add(
        TextLineBox(
          text: text,
          boundingBox: TextBoundingBox(
            left: x1,
            top: y1,
            width: math.max(0, x2 - x1),
            height: math.max(0, y2 - y1),
          ),
          confidence: avgConf,
          columnId: columnId,
        ),
      );
    }

    return resultLines;
  }
}

class _DraftQuestionBlock {
  final String questionNumber;
  final List<String> promptLines;
  final List<_ExtractedOption> optionItems = [];
  final List<String> explanationLines = [];
  final List<TextBoundingBox> allBoxes;
  final List<double> confidences;
  final bool isOrphan;

  _DraftQuestionBlock({
    required this.questionNumber,
    required this.promptLines,
    required this.allBoxes,
    required this.confidences,
    required this.isOrphan,
  });
}

class _QuestionHeader {
  final String number;
  final String remainingText;
  _QuestionHeader({required this.number, required this.remainingText});
}

class _ExtractedOption {
  final String marker;
  final String text;
  _ExtractedOption({required this.marker, required this.text});
}

class _ColumnParseResult {
  final List<SegmentedQuestionBlock> questions;
  final List<SegmentedQuestionBlock> orphans;
  _ColumnParseResult({required this.questions, required this.orphans});
}
