import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'layout/skew_detection_service.dart';

/// Pre-processing filter modes for OCR image optimization.
enum ImageFilterMode {
  /// Keep the original image without any modifications.
  none,

  /// Convert to grayscale (8-bit single channel).
  grayscale,

  /// Grayscale + conservative auto-stretch contrast enhancement
  /// (clarifies faint ink and fades background ambient shadows without clipping vowel marks).
  enhancedContrast,

  /// Soft adaptive binarization (sharp black text on paper-white background,
  /// preserving thin Bengali strokes and circular option markers).
  binarized,
}

/// Quality assessment metrics of an image intended for OCR.
class ImageQualityAssessment {
  const ImageQualityAssessment({
    required this.width,
    required this.height,
    required this.aspectRatio,
    required this.isLowResolution,
    required this.meanLuminance,
    required this.contrastRatio,
    required this.isTooDark,
    required this.isOverexposed,
    required this.isLowContrast,
    required this.recommendation,
  });

  final int width;
  final int height;
  final double aspectRatio;
  final bool isLowResolution;
  final double meanLuminance;
  final double contrastRatio;
  final bool isTooDark;
  final bool isOverexposed;
  final bool isLowContrast;
  final String recommendation;

  /// Whether the image meets minimum standards for reliable offline OCR.
  bool get isAdequateForOcr =>
      !isLowResolution && !isTooDark && !isOverexposed && !isLowContrast;

  Map<String, dynamic> toJson() => {
        'width': width,
        'height': height,
        'aspectRatio': aspectRatio,
        'isLowResolution': isLowResolution,
        'meanLuminance': meanLuminance,
        'contrastRatio': contrastRatio,
        'isTooDark': isTooDark,
        'isOverexposed': isOverexposed,
        'isLowContrast': isLowContrast,
        'recommendation': recommendation,
        'isAdequateForOcr': isAdequateForOcr,
      };

  factory ImageQualityAssessment.fromJson(Map<String, dynamic> json) =>
      ImageQualityAssessment(
        width: json['width'] as int? ?? 0,
        height: json['height'] as int? ?? 0,
        aspectRatio: (json['aspectRatio'] as num?)?.toDouble() ?? 1.0,
        isLowResolution: json['isLowResolution'] as bool? ?? false,
        meanLuminance: (json['meanLuminance'] as num?)?.toDouble() ?? 128.0,
        contrastRatio: (json['contrastRatio'] as num?)?.toDouble() ?? 0.5,
        isTooDark: json['isTooDark'] as bool? ?? false,
        isOverexposed: json['isOverexposed'] as bool? ?? false,
        isLowContrast: json['isLowContrast'] as bool? ?? false,
        recommendation: json['recommendation'] as String? ?? '',
      );
}

/// Structured result of an OCR-optimized image processing pipeline.
class ProcessedImageResult {
  const ProcessedImageResult({
    required this.originalFile,
    required this.processedFile,
    required this.quality,
    required this.skewAngle,
    required this.wasDeskewed,
    required this.appliedFilter,
    required this.originalWidth,
    required this.originalHeight,
    required this.processedWidth,
    required this.processedHeight,
    required this.elapsedMs,
  });

  final File originalFile;
  final File processedFile;
  final ImageQualityAssessment quality;
  final double skewAngle;
  final bool wasDeskewed;
  final ImageFilterMode appliedFilter;
  final int originalWidth;
  final int originalHeight;
  final int processedWidth;
  final int processedHeight;
  final int elapsedMs;
}

/// Production-ready offline image pre-processing service.
///
/// Features:
/// 1. EXIF orientation correction (bakeOrientation so pixels are physically upright).
/// 2. Image dimension and quality assessment (brightness, contrast, resolution).
/// 3. Grayscale conversion with ITU-R 601 luminance weights.
/// 4. Conservative auto-stretch contrast enhancement preserving Bengali matras & conjuncts.
/// 5. Skew detection and deskewing with white background padding.
/// 6. Conservative noise reduction preserving fine vowel strokes.
/// 7. Resolution normalization (preserves full resolution up to 4096px).
/// 8. Two-column page layout splitting and cropping.
/// 9. Strict original image immutability (never overwrites original file).
/// 10. Runs heavy image transformations in background isolate.
class ImagePreprocessorService {
  ImagePreprocessorService._();
  static final ImagePreprocessorService instance =
      ImagePreprocessorService._();

  /// Assesses image quality and dimensions without modifying the file.
  Future<ImageQualityAssessment> assessImageQuality(File inputFile) async {
    final bytes = await inputFile.readAsBytes();
    final jsonMap = await compute(_runQualityAssessment, bytes);
    return ImageQualityAssessment.fromJson(jsonMap);
  }

  /// Applies [filterMode] to [inputFile] and writes the result to a new temporary file.
  ///
  /// The [inputFile] is strictly immutable and will NEVER be overwritten.
  /// [maxDimension] defaults to 4096 to prevent downsampling high-res scans.
  Future<File> processImage({
    required File inputFile,
    required ImageFilterMode filterMode,
    int maxDimension = 4096,
    bool autoDeskew = false,
    bool conservativeDenoise = false,
  }) async {
    if (filterMode == ImageFilterMode.none && !autoDeskew && !conservativeDenoise) {
      return inputFile;
    }

    final bytes = await inputFile.readAsBytes();
    final processedBytes = await compute(_runProcessing, {
      'bytes': bytes,
      'mode': filterMode.name,
      'maxDimension': maxDimension,
      'autoDeskew': autoDeskew,
      'conservativeDenoise': conservativeDenoise,
    });

    final tempDir = Directory.systemTemp;
    final outPath =
        '${tempDir.path}/ocr_prep_${DateTime.now().microsecondsSinceEpoch}.jpg';
    final outFile = File(outPath);
    await outFile.writeAsBytes(processedBytes, flush: true);
    return outFile;
  }

  /// One-stop optimization for OCR processing:
  /// Evaluates quality, bakes EXIF, conditionally deskews, applies conservative contrast,
  /// and returns a structured [ProcessedImageResult] with all transformation metadata.
  Future<ProcessedImageResult> optimizeForOcr({
    required File inputFile,
    ImageFilterMode filterMode = ImageFilterMode.enhancedContrast,
    bool autoDeskew = true,
    bool conservativeDenoise = false,
    int maxDimension = 4096,
  }) async {
    final sw = Stopwatch()..start();
    final bytes = await inputFile.readAsBytes();

    final resultData = await compute(_runFullOptimization, {
      'bytes': bytes,
      'mode': filterMode.name,
      'autoDeskew': autoDeskew,
      'conservativeDenoise': conservativeDenoise,
      'maxDimension': maxDimension,
    });

    sw.stop();

    final tempDir = Directory.systemTemp;
    final outPath =
        '${tempDir.path}/ocr_opt_${DateTime.now().microsecondsSinceEpoch}.jpg';
    final outFile = File(outPath);
    await outFile.writeAsBytes(resultData['processedBytes'] as Uint8List, flush: true);

    final quality = ImageQualityAssessment.fromJson(
      resultData['quality'] as Map<String, dynamic>,
    );

    return ProcessedImageResult(
      originalFile: inputFile,
      processedFile: outFile,
      quality: quality,
      skewAngle: (resultData['skewAngle'] as num).toDouble(),
      wasDeskewed: resultData['wasDeskewed'] as bool,
      appliedFilter: filterMode,
      originalWidth: resultData['originalWidth'] as int,
      originalHeight: resultData['originalHeight'] as int,
      processedWidth: resultData['processedWidth'] as int,
      processedHeight: resultData['processedHeight'] as int,
      elapsedMs: sw.elapsedMilliseconds,
    );
  }

  /// Splits a two-column book/exam page into separate left and right column images.
  Future<List<File>> splitTwoColumns(File inputFile) async {
    final bytes = await inputFile.readAsBytes();
    final splits = await compute(_runSplitTwoColumns, bytes);

    final tempDir = Directory.systemTemp;
    final ts = DateTime.now().microsecondsSinceEpoch;
    final file1 = File('${tempDir.path}/ocr_col1_$ts.jpg');
    final file2 = File('${tempDir.path}/ocr_col2_$ts.jpg');

    await file1.writeAsBytes(splits[0], flush: true);
    await file2.writeAsBytes(splits[1], flush: true);

    return [file1, file2];
  }

  // =========================================================================
  // Background Isolate Worker Functions
  // =========================================================================

  static Map<String, dynamic> _runQualityAssessment(Uint8List rawBytes) {
    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) {
      throw Exception('Failed to decode image bytes for quality assessment');
    }
    final upright = img.bakeOrientation(decoded);
    return _evaluateQuality(upright).toJson();
  }

  static Uint8List _runProcessing(Map<String, dynamic> params) {
    final Uint8List rawBytes = params['bytes'];
    final String modeName = params['mode'];
    final int maxDimension = params['maxDimension'] ?? 4096;
    final bool autoDeskew = params['autoDeskew'] ?? false;
    final bool conservativeDenoise = params['conservativeDenoise'] ?? false;

    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) return rawBytes;

    // 1. Bake EXIF orientation so pixels are physically upright
    img.Image current = img.bakeOrientation(decoded);

    // 2. Safe dimension capping (only downsamples if exceeding maxDimension, preserving aspect ratio)
    if (current.width > maxDimension || current.height > maxDimension) {
      current = current.width > current.height
          ? img.copyResize(current, width: maxDimension)
          : img.copyResize(current, height: maxDimension);
    }

    // 3. Conditional deskewing
    if (autoDeskew) {
      final skewAngle = SkewDetectionService.instance.detectSkewAngle(current);
      if (skewAngle.abs() >= 0.3) {
        current = SkewDetectionService.instance.deskew(current, skewAngle);
      }
    }

    // 4. Conservative noise reduction (gentle blur to remove camera sensor noise without eroding text)
    if (conservativeDenoise) {
      current = img.gaussianBlur(current, radius: 1);
    }

    // 5. Apply selected filter mode
    if (modeName == ImageFilterMode.grayscale.name) {
      current = img.grayscale(current);
    } else if (modeName == ImageFilterMode.enhancedContrast.name) {
      current = img.grayscale(current);
      current = _applyConservativeContrast(current);
    } else if (modeName == ImageFilterMode.binarized.name) {
      current = img.grayscale(current);
      current = _applyConservativeContrast(current);
      // Soft thresholding at 52% preserving thin Bengali vowel stems & option circles
      current = img.luminanceThreshold(current, threshold: 0.52);
    }

    return Uint8List.fromList(img.encodeJpg(current, quality: 95));
  }

  static Map<String, dynamic> _runFullOptimization(Map<String, dynamic> params) {
    final Uint8List rawBytes = params['bytes'];
    final String modeName = params['mode'];
    final bool autoDeskew = params['autoDeskew'] ?? true;
    final bool conservativeDenoise = params['conservativeDenoise'] ?? false;
    final int maxDimension = params['maxDimension'] ?? 4096;

    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) {
      throw Exception('Failed to decode image bytes for OCR optimization');
    }

    // 1. Bake EXIF orientation
    img.Image current = img.bakeOrientation(decoded);
    final originalWidth = current.width;
    final originalHeight = current.height;

    // 2. Assess quality on upright image
    final quality = _evaluateQuality(current);

    // 3. Conditional deskewing
    double skewAngle = 0.0;
    bool wasDeskewed = false;
    if (autoDeskew) {
      skewAngle = SkewDetectionService.instance.detectSkewAngle(current);
      if (skewAngle.abs() >= 0.3) {
        current = SkewDetectionService.instance.deskew(current, skewAngle);
        wasDeskewed = true;
      }
    }

    // 4. Safe dimension capping
    if (current.width > maxDimension || current.height > maxDimension) {
      current = current.width > current.height
          ? img.copyResize(current, width: maxDimension)
          : img.copyResize(current, height: maxDimension);
    }

    // 5. Conservative noise reduction
    if (conservativeDenoise) {
      current = img.gaussianBlur(current, radius: 1);
    }

    // 6. Contrast & script enhancement
    if (modeName == ImageFilterMode.grayscale.name) {
      current = img.grayscale(current);
    } else if (modeName == ImageFilterMode.enhancedContrast.name) {
      current = img.grayscale(current);
      current = _applyConservativeContrast(current);
    } else if (modeName == ImageFilterMode.binarized.name) {
      current = img.grayscale(current);
      current = _applyConservativeContrast(current);
      current = img.luminanceThreshold(current, threshold: 0.52);
    }

    final processedBytes = Uint8List.fromList(img.encodeJpg(current, quality: 95));

    return {
      'processedBytes': processedBytes,
      'quality': quality.toJson(),
      'skewAngle': skewAngle,
      'wasDeskewed': wasDeskewed,
      'originalWidth': originalWidth,
      'originalHeight': originalHeight,
      'processedWidth': current.width,
      'processedHeight': current.height,
    };
  }

  static List<Uint8List> _runSplitTwoColumns(Uint8List rawBytes) {
    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) return [rawBytes, rawBytes];

    final upright = img.bakeOrientation(decoded);
    final width = upright.width;
    final height = upright.height;

    // Left column: 0 to 52% of page width (small overlap to ensure no cut-off)
    final leftWidth = (width * 0.52).round().clamp(1, width);
    final leftImg = img.copyCrop(upright, x: 0, y: 0, width: leftWidth, height: height);

    // Right column: 48% to 100% of page width
    final rightStartX = (width * 0.48).round().clamp(0, width - 1);
    final rightWidth = (width - rightStartX).clamp(1, width);
    final rightImg = img.copyCrop(upright, x: rightStartX, y: 0, width: rightWidth, height: height);

    return [
      Uint8List.fromList(img.encodeJpg(leftImg, quality: 95)),
      Uint8List.fromList(img.encodeJpg(rightImg, quality: 95)),
    ];
  }

  /// Conservative linear histogram stretch:
  /// Identifies 2nd percentile (ink baseline) and 98th percentile (paper baseline)
  /// and scales the dynamic range so paper background becomes clean white ($255$)
  /// and ink becomes crisp dark ($0$), preserving thin vowel marks and circular markers.
  static img.Image _applyConservativeContrast(img.Image gray) {
    final hist = List<int>.filled(256, 0);
    final totalPixels = gray.width * gray.height;
    final sampleStep = (totalPixels > 2000000) ? 2 : 1;
    int sampledCount = 0;

    for (int y = 0; y < gray.height; y += sampleStep) {
      for (int x = 0; x < gray.width; x += sampleStep) {
        final p = gray.getPixel(x, y);
        hist[p.r.toInt()]++;
        sampledCount++;
      }
    }

    int cumulative = 0;
    int pLow = 0;
    int pHigh = 255;
    final lowTarget = (sampledCount * 0.02).round();
    final highTarget = (sampledCount * 0.98).round();

    for (int i = 0; i < 256; i++) {
      cumulative += hist[i];
      if (cumulative >= lowTarget && pLow == 0) {
        pLow = i;
      }
      if (cumulative >= highTarget) {
        pHigh = i;
        break;
      }
    }

    // If contrast range is sufficient (> 30), perform linear stretch with soft knee
    if (pHigh - pLow > 30) {
      final range = pHigh - pLow;
      final lookup = Uint8List(256);
      for (int i = 0; i < 256; i++) {
        if (i <= pLow) {
          lookup[i] = 0;
        } else if (i >= pHigh) {
          lookup[i] = 255;
        } else {
          lookup[i] = (((i - pLow) * 255) ~/ range).clamp(0, 255);
        }
      }

      for (int y = 0; y < gray.height; y++) {
        for (int x = 0; x < gray.width; x++) {
          final p = gray.getPixel(x, y);
          final newLum = lookup[p.r.toInt()];
          gray.setPixelRgb(x, y, newLum, newLum, newLum);
        }
      }
    } else {
      // Very flat contrast: apply gentle linear contrast
      gray = img.contrast(gray, contrast: 120);
    }
    return gray;
  }

  /// Calculates image quality assessment metrics.
  static ImageQualityAssessment _evaluateQuality(img.Image image) {
    final width = image.width;
    final height = image.height;
    final aspectRatio = width / (height > 0 ? height : 1);
    final isLowResolution = width < 600 || height < 600;

    int sumLum = 0;
    int sampleCount = 0;
    int minLum = 255;
    int maxLum = 0;
    final stepX = math.max(1, width ~/ 80);
    final stepY = math.max(1, height ~/ 80);

    for (int y = 0; y < height; y += stepY) {
      for (int x = 0; x < width; x += stepX) {
        final p = image.getPixel(x, y);
        final lum = (p.r * 299 + p.g * 587 + p.b * 114) ~/ 1000;
        sumLum += lum;
        if (lum < minLum) minLum = lum;
        if (lum > maxLum) maxLum = lum;
        sampleCount++;
      }
    }

    final meanLuminance = sampleCount > 0 ? sumLum / sampleCount : 128.0;
    final contrastRatio = sampleCount > 0 ? (maxLum - minLum) / 255.0 : 0.5;
    final isTooDark = meanLuminance < 60.0;
    final isOverexposed = meanLuminance > 225.0;
    final isLowContrast = contrastRatio < 0.25;

    String recommendation;
    if (isLowResolution) {
      recommendation =
          'রেজোলিউশন কম। পরিষ্কার পাঠযোগ্যতার জন্য কাছে থেকে বা উচ্চ রেজোলিউশনে ছবি তুলুন।';
    } else if (isTooDark) {
      recommendation =
          'ছবিটিতে পর্যাপ্ত আলো নেই। পর্যাপ্ত আলোতে বা ফ্ল্যাশ ব্যবহার করে ছবি তুলুন।';
    } else if (isOverexposed) {
      recommendation =
          'ছবিতে অতিরিক্ত আলো বা প্রতিফলন রয়েছে। আলো কিছুটা কমিয়ে বা কোণ বদলে ছবি তুলুন।';
    } else if (isLowContrast) {
      recommendation =
          'কালি ও কাগজের বৈসাদৃশ্য (কন্ট্রাস্ট) কম। গ্রেস্কেল বা কন্ট্রাস্ট ফিল্টার ব্যবহার করুন।';
    } else {
      recommendation = 'ছবির গুণমান ও রেজোলিউশন OCR-এর জন্য উপযুক্ত।';
    }

    return ImageQualityAssessment(
      width: width,
      height: height,
      aspectRatio: double.parse(aspectRatio.toStringAsFixed(2)),
      isLowResolution: isLowResolution,
      meanLuminance: double.parse(meanLuminance.toStringAsFixed(1)),
      contrastRatio: double.parse(contrastRatio.toStringAsFixed(2)),
      isTooDark: isTooDark,
      isOverexposed: isOverexposed,
      isLowContrast: isLowContrast,
      recommendation: recommendation,
    );
  }
}
