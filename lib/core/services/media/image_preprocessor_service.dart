import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Pre-processing filter modes for OCR image optimization.
enum ImageFilterMode {
  /// Keep the original image without any modifications.
  none,

  /// Convert to grayscale (8-bit single channel).
  grayscale,

  /// Grayscale + contrast enhancement (clarifies light text and fades background shadows).
  enhancedContrast,

  /// High contrast binarization (sharp black text on pure white paper).
  binarized,
}

/// Lightweight offline image pre-processing service.
///
/// Runs heavy transformations (grayscale, contrast boost, thresholding) in a
/// background isolate to keep UI frame-rate fluid on low-end devices.
class ImagePreprocessorService {
  ImagePreprocessorService._();
  static final ImagePreprocessorService instance = ImagePreprocessorService._();

  /// Applies [filterMode] to [inputFile] and writes the result to a temporary file.
  Future<File> processImage({
    required File inputFile,
    required ImageFilterMode filterMode,
    int maxDimension = 1920,
  }) async {
    if (filterMode == ImageFilterMode.none) {
      return inputFile;
    }

    final bytes = await inputFile.readAsBytes();
    final processedBytes = await compute(_runProcessing, {
      'bytes': bytes,
      'mode': filterMode.name,
      'maxDimension': maxDimension,
    });

    final tempDir = Directory.systemTemp;
    final outPath =
        '${tempDir.path}/ocr_prep_${DateTime.now().microsecondsSinceEpoch}.jpg';
    final outFile = File(outPath);
    await outFile.writeAsBytes(processedBytes);
    return outFile;
  }

  /// Splits a two-column book/exam page into separate left and right column images.
  Future<List<File>> splitTwoColumns(File inputFile) async {
    final bytes = await inputFile.readAsBytes();
    final splits = await compute(_runSplitTwoColumns, bytes);

    final tempDir = Directory.systemTemp;
    final ts = DateTime.now().microsecondsSinceEpoch;
    final file1 = File('${tempDir.path}/ocr_col1_$ts.jpg');
    final file2 = File('${tempDir.path}/ocr_col2_$ts.jpg');

    await file1.writeAsBytes(splits[0]);
    await file2.writeAsBytes(splits[1]);

    return [file1, file2];
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
      Uint8List.fromList(img.encodeJpg(leftImg, quality: 90)),
      Uint8List.fromList(img.encodeJpg(rightImg, quality: 90)),
    ];
  }

  /// Background isolate processor function.
  static Uint8List _runProcessing(Map<String, dynamic> params) {
    final Uint8List rawBytes = params['bytes'];
    final String modeName = params['mode'];
    final int maxDimension = params['maxDimension'];

    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) return rawBytes;

    img.Image current = img.bakeOrientation(decoded);

    // Limit oversized photos to prevent out-of-memory errors on 2GB RAM phones
    if (current.width > maxDimension || current.height > maxDimension) {
      current = current.width > current.height
          ? img.copyResize(current, width: maxDimension)
          : img.copyResize(current, height: maxDimension);
    }

    if (modeName == ImageFilterMode.grayscale.name) {
      current = img.grayscale(current);
    } else if (modeName == ImageFilterMode.enhancedContrast.name) {
      current = img.grayscale(current);
      current = img.contrast(current, contrast: 140);
    } else if (modeName == ImageFilterMode.binarized.name) {
      current = img.grayscale(current);
      current = img.contrast(current, contrast: 150);
      current = img.luminanceThreshold(current, threshold: 0.55);
    }

    return Uint8List.fromList(img.encodeJpg(current, quality: 90));
  }
}
