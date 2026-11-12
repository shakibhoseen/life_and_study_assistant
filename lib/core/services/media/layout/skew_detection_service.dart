import 'package:image/image.dart' as img;

/// Automatic skew detection and deskewing service using Radon / Projection Profile Variance.
class SkewDetectionService {
  SkewDetectionService._();
  static final SkewDetectionService instance = SkewDetectionService._();

  /// Maximum thumbnail dimension for fast skew angle estimation.
  static const int _thumbnailDimension = 512;

  /// Detects skew angle of [image] in degrees within range [-10.0°, +10.0°].
  ///
  /// Positive angle means the image is tilted clockwise; negative means counter-clockwise.
  double detectSkewAngle(img.Image image) {
    if (image.width < 50 || image.height < 50) return 0.0;

    // 1. Create lightweight grayscale thumbnail for fast projection calculation
    final thumb = _createAnalysisThumbnail(image);

    // 2. Coarse search (-8° to +8° in 1.0° steps)
    double bestAngle = 0.0;
    double maxVariance = -1.0;
    double zeroAngleVariance = -1.0;

    for (double a = -8.0; a <= 8.0; a += 1.0) {
      final variance = _computeProjectionVariance(thumb, a);
      if (a == 0.0) {
        zeroAngleVariance = variance;
      }
      if (variance > maxVariance) {
        maxVariance = variance;
        bestAngle = a;
      }
    }

    // 3. Fine search around best coarse angle (±1.0° in 0.2° steps)
    final fineStart = bestAngle - 1.0;
    final fineEnd = bestAngle + 1.0;

    for (double a = fineStart; a <= fineEnd; a += 0.2) {
      final variance = _computeProjectionVariance(thumb, a);
      if (variance > maxVariance) {
        maxVariance = variance;
        bestAngle = a;
      }
    }

    // 4. Threshold check: if variance improvement over 0° is negligible (< 3%), assume no skew
    if (zeroAngleVariance > 0) {
      final relativeGain = (maxVariance - zeroAngleVariance) / zeroAngleVariance;
      if (relativeGain < 0.03 && bestAngle.abs() < 1.0) {
        return 0.0;
      }
    }

    // Clean small jitter
    if (bestAngle.abs() < 0.3) {
      return 0.0;
    }

    return double.parse(bestAngle.toStringAsFixed(2));
  }

  /// Deskews [image] by applying rotation of -[angleDegrees].
  ///
  /// Returns unaltered image if [angleDegrees] is near zero (|angle| < 0.3°).
  img.Image deskew(img.Image image, double angleDegrees) {
    if (angleDegrees.abs() < 0.3) {
      return image;
    }
    // Set background color to white before rotation so rotated canvas corners are paper-white
    image.backgroundColor = img.ColorRgb8(255, 255, 255);
    // copyRotate rotates clockwise by angle; to deskew we rotate by -angle
    return img.copyRotate(
      image,
      angle: -angleDegrees,
      interpolation: img.Interpolation.linear,
    );
  }

  img.Image _createAnalysisThumbnail(img.Image src) {
    final gray = img.grayscale(src);
    if (gray.width <= _thumbnailDimension && gray.height <= _thumbnailDimension) {
      return gray;
    }
    return gray.width > gray.height
        ? img.copyResize(gray, width: _thumbnailDimension)
        : img.copyResize(gray, height: _thumbnailDimension);
  }

  /// Calculates horizontal projection profile variance when rotated by [testAngle].
  double _computeProjectionVariance(img.Image thumb, double testAngle) {
    // If not rotating, compute directly
    if (testAngle == 0.0) {
      final startY = (thumb.height * 0.15).round();
      final endY = (thumb.height * 0.85).round();
      final startX = (thumb.width * 0.15).round();
      final endX = (thumb.width * 0.85).round();

      final counts = <int>[];
      int totalInk = 0;
      for (int y = startY; y < endY; y++) {
        int inkInRow = 0;
        for (int x = startX; x < endX; x++) {
          final p = thumb.getPixel(x, y);
          if (p.r < 140) inkInRow++;
        }
        counts.add(inkInRow);
        totalInk += inkInRow;
      }
      if (counts.isEmpty || totalInk == 0) return 0.0;
      final mean = totalInk / counts.length;
      double sumSquaredDiff = 0.0;
      for (final c in counts) {
        final diff = c - mean;
        sumSquaredDiff += diff * diff;
      }
      return sumSquaredDiff / counts.length;
    }

    // Set background color to white on thumb before rotating so canvas expansion is white
    thumb.backgroundColor = img.ColorRgb8(255, 255, 255);
    final candidate = img.copyRotate(
      thumb,
      angle: -testAngle,
      interpolation: img.Interpolation.nearest,
    );

    // Keep analysis well inside the central unrotated region
    final startY = (candidate.height * 0.25).round();
    final endY = (candidate.height * 0.75).round();
    final startX = (candidate.width * 0.25).round();
    final endX = (candidate.width * 0.75).round();

    final counts = <int>[];
    int totalInk = 0;

    for (int y = startY; y < endY; y++) {
      int inkInRow = 0;
      for (int x = startX; x < endX; x++) {
        final p = candidate.getPixel(x, y);
        // In grayscale, r channel is luminance. Ink pixels are dark (< 140)
        if (p.r < 140) {
          inkInRow++;
        }
      }
      counts.add(inkInRow);
      totalInk += inkInRow;
    }

    if (counts.isEmpty || totalInk == 0) return 0.0;

    final mean = totalInk / counts.length;
    double sumSquaredDiff = 0.0;
    for (final c in counts) {
      final diff = c - mean;
      sumSquaredDiff += diff * diff;
    }

    return sumSquaredDiff / counts.length;
  }
}
