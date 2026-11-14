import 'dart:io';

/// Detected page layout format.
enum LayoutType {
  /// Single column layout (standard page, essay, or single column MCQs).
  singleColumn(
    label: 'সিঙ্গেল কলাম',
    description: 'সম্পূর্ণ পৃষ্ঠা একটি কলাম হিসেবে শনাক্ত হয়েছে',
  ),

  /// Dual column with pure whitespace gutter (no vertical line).
  dualColumnWhitespace(
    label: 'দুই কলাম (হোয়াইটস্পেস গাটার)',
    description:
        'মাঝের শূন্যস্থান (Whitespace) ব্যবহার করে দুটি কলাম আলাদা করা হয়েছে',
  ),

  /// Dual column separated by an explicit vertical line divider.
  dualColumnDivider(
    label: 'দুই কলাম (ভার্টিক্যাল ডিভাইডার)',
    description: 'মাঝের উল্লম্ব রেখা (Vertical Divider) শনাক্ত করে দুটি কলাম আলাদা করা হয়েছে',
  );

  const LayoutType({required this.label, required this.description});

  final String label;
  final String description;
}

/// Details of the detected vertical gutter (column separator).
class GutterRegion {
  final int left;
  final int right;
  final int center;
  final int width;
  final double confidence;
  final bool hasDividerLine;

  const GutterRegion({
    required this.left,
    required this.right,
    required this.center,
    required this.width,
    required this.confidence,
    required this.hasDividerLine,
  });

  Map<String, dynamic> toJson() => {
    'left': left,
    'right': right,
    'center': center,
    'width': width,
    'confidence': confidence,
    'hasDividerLine': hasDividerLine,
  };

  @override
  String toString() =>
      'GutterRegion(x: $left..$right, center: $center, w: ${width}px, conf: ${(confidence * 100).toStringAsFixed(1)}%, divider: $hasDividerLine)';
}

/// Bounding rectangle for a detected column.
class ColumnBoundingBox {
  final int index;
  final int left;
  final int top;
  final int width;
  final int height;

  const ColumnBoundingBox({
    required this.index,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  int get right => left + width;
  int get bottom => top + height;

  Map<String, dynamic> toJson() => {
    'index': index,
    'left': left,
    'top': top,
    'width': width,
    'height': height,
  };

  @override
  String toString() =>
      'ColumnBox#$index(left: $left, top: $top, width: $width, height: $height)';
}

/// Complete analysis result produced by the Layout Detection Engine (Phase 1).
class LayoutAnalysisResult {
  /// The unaltered input image file.
  final File originalImage;

  /// The deskewed and orientation-normalized image file.
  final File deskewedImage;

  /// The detected page layout format.
  final LayoutType layoutType;

  /// Estimated skew angle in degrees (e.g. +2.5° or -1.2°).
  final double skewAngle;

  /// Detected gutter region between columns, or null if single-column.
  final GutterRegion? gutter;

  /// Exact bounding boxes for each detected column.
  final List<ColumnBoundingBox> columnBoxes;

  /// Full-resolution image crops for each detected column.
  final List<File> columnCrops;

  /// Overall layout classification confidence (0.0 to 1.0).
  final double confidence;

  /// Human-readable explanation if fallback to single-column occurred.
  final String? failureReason;

  /// Original image dimensions in pixels.
  final int imageWidth;
  final int imageHeight;

  const LayoutAnalysisResult({
    required this.originalImage,
    required this.deskewedImage,
    required this.layoutType,
    required this.skewAngle,
    required this.gutter,
    required this.columnBoxes,
    required this.columnCrops,
    required this.confidence,
    this.failureReason,
    required this.imageWidth,
    required this.imageHeight,
  });

  bool get isDualColumn =>
      layoutType == LayoutType.dualColumnWhitespace ||
      layoutType == LayoutType.dualColumnDivider;

  Map<String, dynamic> toJson() => {
    'originalPath': originalImage.path,
    'deskewedPath': deskewedImage.path,
    'layoutType': layoutType.name,
    'skewAngle': skewAngle,
    'gutter': gutter?.toJson(),
    'columnBoxes': columnBoxes.map((b) => b.toJson()).toList(),
    'cropPaths': columnCrops.map((f) => f.path).toList(),
    'confidence': confidence,
    'failureReason': failureReason,
    'imageWidth': imageWidth,
    'imageHeight': imageHeight,
  };

  @override
  String toString() =>
      'LayoutAnalysisResult(type: ${layoutType.name}, skew: ${skewAngle.toStringAsFixed(1)}°, cols: ${columnBoxes.length}, conf: ${(confidence * 100).toStringAsFixed(1)}%)';
}
