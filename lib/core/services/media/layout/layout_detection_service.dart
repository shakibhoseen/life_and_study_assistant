import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'layout_detection_models.dart';
import 'skew_detection_service.dart';

/// Layout detection and segmentation service (Phase 1).
///
/// Detects page orientation, deskews text lines, discovers vertical gutters
/// or divider lines, and extracts clean column bounding boxes and crops.
class LayoutDetectionService {
  LayoutDetectionService._();
  static final LayoutDetectionService instance = LayoutDetectionService._();

  /// Minimum confidence threshold to accept a dual-column layout.
  /// If below this threshold, the engine safely falls back to single-column.
  static const double minDualColumnConfidence = 0.60;

  /// Analyzes the layout of [imageFile].
  ///
  /// Never modifies or overwrites [imageFile].
  Future<LayoutAnalysisResult> analyzeLayout(
    File imageFile, {
    bool autoDeskew = true,
  }) async {
    final bytes = await imageFile.readAsBytes();

    final resultData = await compute(_runLayoutAnalysis, {
      'bytes': bytes,
      'autoDeskew': autoDeskew,
      'originalPath': imageFile.path,
    });

    final tempDir = Directory.systemTemp;
    final stamp = DateTime.now().microsecondsSinceEpoch;

    // Write deskewed image file
    final deskewedFile = File('${tempDir.path}/layout_deskew_$stamp.jpg');
    await deskewedFile.writeAsBytes(resultData['deskewedBytes'] as Uint8List, flush: true);

    // Write column crop files
    final cropByteList = resultData['cropByteList'] as List<Uint8List>;
    final columnCropFiles = <File>[];
    for (int i = 0; i < cropByteList.length; i++) {
      final cropFile = File('${tempDir.path}/layout_crop_${i}_$stamp.jpg');
      await cropFile.writeAsBytes(cropByteList[i], flush: true);
      columnCropFiles.add(cropFile);
    }

    final gutterMap = resultData['gutter'] as Map<String, dynamic>?;
    GutterRegion? gutter;
    if (gutterMap != null) {
      gutter = GutterRegion(
        left: gutterMap['left'] as int,
        right: gutterMap['right'] as int,
        center: gutterMap['center'] as int,
        width: gutterMap['width'] as int,
        confidence: (gutterMap['confidence'] as num).toDouble(),
        hasDividerLine: gutterMap['hasDividerLine'] as bool,
      );
    }

    final rawBoxes = resultData['columnBoxes'] as List<dynamic>;
    final columnBoxes = rawBoxes.map((b) {
      final map = b as Map<String, dynamic>;
      return ColumnBoundingBox(
        index: map['index'] as int,
        left: map['left'] as int,
        top: map['top'] as int,
        width: map['width'] as int,
        height: map['height'] as int,
      );
    }).toList();

    final layoutTypeName = resultData['layoutType'] as String;
    final layoutType = LayoutType.values.firstWhere(
      (e) => e.name == layoutTypeName,
      orElse: () => LayoutType.singleColumn,
    );

    return LayoutAnalysisResult(
      originalImage: imageFile,
      deskewedImage: deskewedFile,
      layoutType: layoutType,
      skewAngle: (resultData['skewAngle'] as num).toDouble(),
      gutter: gutter,
      columnBoxes: columnBoxes,
      columnCrops: columnCropFiles,
      confidence: (resultData['confidence'] as num).toDouble(),
      failureReason: resultData['failureReason'] as String?,
      imageWidth: resultData['imageWidth'] as int,
      imageHeight: resultData['imageHeight'] as int,
    );
  }

  /// Background isolate processor function.
  static Map<String, dynamic> _runLayoutAnalysis(Map<String, dynamic> params) {
    final Uint8List rawBytes = params['bytes'];
    final bool autoDeskew = params['autoDeskew'] ?? true;

    // 1. Decode and bake EXIF orientation so pixels are physically upright
    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) {
      throw Exception('Failed to decode image bytes for layout analysis');
    }
    img.Image current = img.bakeOrientation(decoded);

    // 2. Skew detection and deskewing
    double skewAngle = 0.0;
    if (autoDeskew) {
      skewAngle = SkewDetectionService.instance.detectSkewAngle(current);
      if (skewAngle.abs() >= 0.3) {
        current = SkewDetectionService.instance.deskew(current, skewAngle);
      }
    }

    final int width = current.width;
    final int height = current.height;

    // 3. Vertical Projection Profile for column and gutter discovery
    final gutterResult = _detectGutterAndColumns(current);

    LayoutType layoutType;
    List<Map<String, dynamic>> columnBoxes;
    List<Uint8List> cropByteList = [];
    double overallConfidence;
    String? failureReason;
    Map<String, dynamic>? gutterData;

    if (gutterResult != null && gutterResult.confidence >= minDualColumnConfidence) {
      gutterData = gutterResult.toJson();
      layoutType = gutterResult.hasDividerLine
          ? LayoutType.dualColumnDivider
          : LayoutType.dualColumnWhitespace;
      overallConfidence = gutterResult.confidence;

      // Create column bounding boxes
      // Left Column: 0 to gutter.left
      // Right Column: gutter.right to width
      final leftColBox = {
        'index': 0,
        'left': 0,
        'top': 0,
        'width': gutterResult.left.clamp(1, width),
        'height': height,
      };

      final rightWidth = (width - gutterResult.right).clamp(1, width);
      final rightColBox = {
        'index': 1,
        'left': gutterResult.right.clamp(0, width - 1),
        'top': 0,
        'width': rightWidth,
        'height': height,
      };

      columnBoxes = [leftColBox, rightColBox];

      // Extract high-resolution column crops
      final leftCrop = img.copyCrop(
        current,
        x: leftColBox['left'] as int,
        y: leftColBox['top'] as int,
        width: leftColBox['width'] as int,
        height: leftColBox['height'] as int,
      );
      final rightCrop = img.copyCrop(
        current,
        x: rightColBox['left'] as int,
        y: rightColBox['top'] as int,
        width: rightColBox['width'] as int,
        height: rightColBox['height'] as int,
      );

      cropByteList = [
        Uint8List.fromList(img.encodeJpg(leftCrop, quality: 95)),
        Uint8List.fromList(img.encodeJpg(rightCrop, quality: 95)),
      ];
    } else {
      // Safe fallback to single-column layout
      layoutType = LayoutType.singleColumn;
      overallConfidence = gutterResult != null ? (1.0 - gutterResult.confidence) : 0.90;
      failureReason = gutterResult == null
          ? 'No vertical gutter or divider detected across central page region'
          : 'Gutter confidence (${(gutterResult.confidence * 100).toInt()}%) below required threshold (${(minDualColumnConfidence * 100).toInt()}%). Safely defaulting to single column';

      columnBoxes = [
        {
          'index': 0,
          'left': 0,
          'top': 0,
          'width': width,
          'height': height,
        }
      ];

      // Single crop is the deskewed page
      cropByteList = [
        Uint8List.fromList(img.encodeJpg(current, quality: 95)),
      ];
    }

    final deskewedBytes = Uint8List.fromList(img.encodeJpg(current, quality: 95));

    return {
      'deskewedBytes': deskewedBytes,
      'cropByteList': cropByteList,
      'layoutType': layoutType.name,
      'skewAngle': skewAngle,
      'gutter': gutterData,
      'columnBoxes': columnBoxes,
      'confidence': overallConfidence,
      'failureReason': failureReason,
      'imageWidth': width,
      'imageHeight': height,
    };
  }

  /// Examines vertical projection profile across middle 25%-75% of page.
  static GutterRegion? _detectGutterAndColumns(img.Image image) {
    final width = image.width;
    final height = image.height;
    if (width < 200 || height < 200) return null;

    // Downsample vertically to speed up projection computation
    final sampleHeight = min(height, 800);
    final scaleY = height / sampleHeight;

    // Sample background luminance across the central region to make ink threshold illumination-adaptive
    final sampleLums = <int>[];
    final lumSampleStepX = max(1, (width * 0.05).round());
    final lumSampleStepY = max(1, (sampleHeight * 0.10).round());
    for (int sx = (width * 0.35).round(); sx <= (width * 0.65).round(); sx += lumSampleStepX) {
      for (int sy = 0; sy < sampleHeight; sy += lumSampleStepY) {
        final y = (sy * scaleY).round().clamp(0, height - 1);
        final p = image.getPixel(sx, y);
        if (p.a != 0) {
          sampleLums.add((p.r * 299 + p.g * 587 + p.b * 114) ~/ 1000);
        }
      }
    }
    sampleLums.sort();
    // 80th percentile luminance represents paper background
    final bgLum = sampleLums.isNotEmpty ? sampleLums[(sampleLums.length * 0.80).floor()] : 240;
    // Ink threshold: significantly darker than paper background, capped at 135
    final inkThreshold = min(135, (bgLum * 0.72).round());

    // Search window: central 25% to 75% of width
    final searchStartX = (width * 0.25).round();
    final searchEndX = (width * 0.75).round();

    final profile = List<int>.filled(width, 0);

    for (int x = 0; x < width; x++) {
      int ink = 0;
      for (int sy = 0; sy < sampleHeight; sy++) {
        final y = (sy * scaleY).round().clamp(0, height - 1);
        final p = image.getPixel(x, y);
        // If transparent padding from rotation, treat as background
        if (p.a == 0) continue;
        final lum = (p.r * 299 + p.g * 587 + p.b * 114) ~/ 1000;
        if (lum < inkThreshold) {
          ink++;
        }
      }
      profile[x] = ink;
    }

    // 1. Check for Vertical Divider Line:
    // A divider line shows up as a sharp peak spanning > 65% of sample height
    int bestDividerX = -1;
    int maxDividerInk = 0;
    for (int x = searchStartX; x <= searchEndX; x++) {
      if (profile[x] > (sampleHeight * 0.65) && profile[x] > maxDividerInk) {
        // Must have whitespace (low ink) on both sides of divider
        final leftInk = (profile[x - 5] + profile[x - 10]) ~/ 2;
        final rightInk = (profile[x + 5] + profile[x + 10]) ~/ 2;
        if (leftInk < (sampleHeight * 0.3) && rightInk < (sampleHeight * 0.3)) {
          maxDividerInk = profile[x];
          bestDividerX = x;
        }
      }
    }

    if (bestDividerX > 0) {
      final leftBoundary = max(0, bestDividerX - (width * 0.015).round());
      final rightBoundary = min(width - 1, bestDividerX + (width * 0.015).round());
      return GutterRegion(
        left: leftBoundary,
        right: rightBoundary,
        center: bestDividerX,
        width: rightBoundary - leftBoundary,
        confidence: 0.95,
        hasDividerLine: true,
      );
    }

    // 2. Check for Whitespace Gutter (Adaptive Trough Detection):
    // Smooth the profile in the central region with a moving average window
    final windowSize = max(4, min(24, (width * 0.008).round()));
    final smoothed = List<double>.filled(width, 0.0);
    for (int x = windowSize; x < width - windowSize; x++) {
      double sum = 0;
      for (int k = -windowSize; k <= windowSize; k++) {
        sum += profile[x + k];
      }
      smoothed[x] = sum / (2 * windowSize + 1);
    }

    // Search for minimum ink trough in central 38% to 62% of width
    final troughStartX = (width * 0.38).round();
    final troughEndX = (width * 0.62).round();

    double minVal = double.infinity;
    int minX = -1;
    for (int x = troughStartX; x <= troughEndX; x++) {
      if (smoothed[x] < minVal) {
        minVal = smoothed[x];
        minX = x;
      }
    }

    if (minX == -1) return null;

    // Measure peak ink in left column text zone (12% to minX - windowSize)
    double leftPeak = 0;
    final leftTextStart = (width * 0.12).round();
    final leftTextEnd = max(leftTextStart + 1, minX - windowSize);
    for (int x = leftTextStart; x < leftTextEnd; x++) {
      if (smoothed[x] > leftPeak) leftPeak = smoothed[x];
    }

    // Measure peak ink in right column text zone (minX + windowSize to 88%)
    double rightPeak = 0;
    final rightTextStart = min(width - 1, minX + windowSize);
    final rightTextEnd = (width * 0.88).round();
    for (int x = rightTextStart; x < rightTextEnd; x++) {
      if (smoothed[x] > rightPeak) rightPeak = smoothed[x];
    }

    final avgPeak = (leftPeak + rightPeak) / 2.0;
    if (avgPeak < 5.0) {
      // Empty or blank page
      return null;
    }

    // Depth ratio: how much the ink drops in the gutter compared to the text peaks
    final depthRatio = (1.0 - (minVal / avgPeak)).clamp(0.0, 1.0);

    // Gutter width expansion around minX
    final threshold = min(avgPeak * 0.45, minVal + max(3.0, (avgPeak - minVal) * 0.25));
    int valleyLeft = minX;
    while (valleyLeft > (width * 0.25) && smoothed[valleyLeft] <= threshold) {
      valleyLeft--;
    }
    int valleyRight = minX;
    while (valleyRight < (width * 0.75) && smoothed[valleyRight] <= threshold) {
      valleyRight++;
    }

    final valleyWidth = valleyRight - valleyLeft;
    final minRequiredWidth = max(6, (width * 0.010).round());

    // Both peaks must have substantial content (ratio between left and right peaks >= 0.35)
    final peakBalance = min(leftPeak, rightPeak) / max(leftPeak, rightPeak);

    if (depthRatio >= 0.40 && valleyWidth >= minRequiredWidth && peakBalance >= 0.35) {
      final valleyCenter = (valleyLeft + valleyRight) ~/ 2;

      final widthScore = (valleyWidth / (width * 0.04)).clamp(0.0, 1.0);
      final centerOffsetRatio = (valleyCenter - (width * 0.50)).abs() / (width * 0.25);
      final centralityScore = (1.0 - centerOffsetRatio).clamp(0.0, 1.0);

      final confidence = (depthRatio * 0.45) +
          (widthScore * 0.25) +
          (centralityScore * 0.15) +
          (peakBalance * 0.15);

      return GutterRegion(
        left: valleyLeft,
        right: valleyRight,
        center: valleyCenter,
        width: valleyWidth,
        confidence: double.parse(confidence.clamp(0.0, 0.99).toStringAsFixed(3)),
        hasDividerLine: false,
      );
    }

    return null;
  }
}
