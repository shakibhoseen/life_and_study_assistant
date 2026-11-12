import 'dart:io';
import '../layout/layout_detection_models.dart';
import '../segmentation/segmentation_models.dart';

/// The OCR execution output of a single column slice.
class ColumnOcrResult {
  /// Column index (0 for left column, 1 for right column).
  final int columnIndex;

  /// The physical crop file on disk.
  final File cropFile;

  /// The bounding box of this column relative to the original page image.
  final TextBoundingBox cropBox;

  /// Raw UTF-8 text recognized by Tesseract.
  final String rawText;

  /// Raw hOCR XML output containing line and word bounding boxes.
  final String hocrText;

  /// Text lines with bounding boxes mapped to ORIGINAL PAGE coordinates.
  final List<TextLineBox> pageLines;

  /// Time taken in milliseconds for native Tesseract execution on this column.
  final int ocrElapsedMs;

  const ColumnOcrResult({
    required this.columnIndex,
    required this.cropFile,
    required this.cropBox,
    required this.rawText,
    required this.hocrText,
    required this.pageLines,
    required this.ocrElapsedMs,
  });

  Map<String, dynamic> toJson() => {
        'columnIndex': columnIndex,
        'cropBox': cropBox.toJson(),
        'lineCount': pageLines.length,
        'ocrElapsedMs': ocrElapsedMs,
        'lines': pageLines
            .map((l) => {
                  'text': l.text,
                  'box': l.boundingBox.toJson(),
                  'confidence': l.confidence,
                  'columnId': l.columnId,
                })
            .toList(),
      };
}

/// The aggregated full-page OCR output preserving reading order and global geometry.
class PageOcrResult {
  /// Original image width in pixels.
  final int pageWidth;

  /// Original image height in pixels.
  final int imageHeight;

  /// Detected layout type (dualColumnWhitespace, dualColumnDivider, or singleColumn).
  final LayoutType layoutType;

  /// Identified gutter information, if dual-column.
  final GutterRegion? gutter;

  /// Results for each individual column slice.
  final List<ColumnOcrResult> columns;

  /// Sequentially merged text lines in strict reading order:
  /// Left column (top to bottom) followed by Right column (top to bottom).
  final List<TextLineBox> mergedLines;

  /// Time taken for layout detection in milliseconds.
  final int layoutElapsedMs;

  /// Total OCR execution time across all columns in milliseconds.
  final int totalOcrElapsedMs;

  /// Total pipeline time in milliseconds.
  final int totalElapsedMs;

  const PageOcrResult({
    required this.pageWidth,
    required this.imageHeight,
    required this.layoutType,
    this.gutter,
    required this.columns,
    required this.mergedLines,
    required this.layoutElapsedMs,
    required this.totalOcrElapsedMs,
    required this.totalElapsedMs,
  });

  /// True if the page was recognized and processed as two independent columns.
  bool get isDualColumn => columns.length == 2;

  Map<String, dynamic> toJson() => {
        'pageWidth': pageWidth,
        'imageHeight': imageHeight,
        'layoutType': layoutType.name,
        'isDualColumn': isDualColumn,
        'gutter': gutter?.toJson(),
        'columnCount': columns.length,
        'mergedLineCount': mergedLines.length,
        'layoutElapsedMs': layoutElapsedMs,
        'totalOcrElapsedMs': totalOcrElapsedMs,
        'totalElapsedMs': totalElapsedMs,
        'columns': columns.map((c) => c.toJson()).toList(),
      };
}
