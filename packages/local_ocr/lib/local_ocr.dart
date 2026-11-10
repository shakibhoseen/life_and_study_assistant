import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Local offline Optical Character Recognition (OCR) engine.
class LocalOcr {
  static const String _tessDataConfig = 'assets/tessdata_config.json';
  static const String _tessDataPath = 'assets/tessdata';
  static const MethodChannel _channel = MethodChannel('com.zavisoft.local_ocr');

  /// Extracts text from an image at [imagePath] using local Tesseract engine.
  static Future<String> extractText(
    String imagePath, {
    String language = 'ben+eng',
    Map<String, String>? args,
  }) async {
    final imageFile = File(imagePath);
    if (!await imageFile.exists()) {
      throw FileSystemException('Image file not found', imagePath);
    }

    final String tessDataParent = await _ensureTessDataReady();

    final String? text = await _channel.invokeMethod<String>(
      'extractText',
      <String, dynamic>{
        'imagePath': imagePath,
        'tessData': tessDataParent,
        'language': language,
        'args': args,
      },
    );

    return text ?? '';
  }

  /// Extracts hOCR HTML containing bounding boxes, word confidences, and lines.
  static Future<String> extractHocr(
    String imagePath, {
    String language = 'ben+eng',
    Map<String, String>? args,
  }) async {
    final imageFile = File(imagePath);
    if (!await imageFile.exists()) {
      throw FileSystemException('Image file not found', imagePath);
    }

    final String tessDataParent = await _ensureTessDataReady();

    final String? hocr = await _channel.invokeMethod<String>(
      'extractHocr',
      <String, dynamic>{
        'imagePath': imagePath,
        'tessData': tessDataParent,
        'language': language,
        'args': args,
      },
    );

    return hocr ?? '';
  }

  /// Copies tessdata files from Flutter assets to local application directory if needed.
  static Future<String> _ensureTessDataReady() async {
    final Directory appDocDir = await getApplicationDocumentsDirectory();
    final Directory tessDir = Directory(p.join(appDocDir.path, 'tessdata'));

    if (!await tessDir.exists()) {
      await tessDir.create(recursive: true);
    }

    try {
      final String configStr = await rootBundle.loadString(_tessDataConfig);
      final Map<String, dynamic> config = jsonDecode(configStr);
      final List<dynamic> files = config['files'] as List<dynamic>? ?? [];

      for (final file in files) {
        final fileName = file.toString();
        final targetFile = File(p.join(tessDir.path, fileName));

        if (!await targetFile.exists() || await targetFile.length() == 0) {
          final ByteData data =
              await rootBundle.load('$_tessDataPath/$fileName');
          final Uint8List bytes = data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
          await targetFile.writeAsBytes(bytes, flush: true);
        }
      }
    } catch (e) {
      // In tests where rootBundle is mock or unavailable, continue if directory exists
      if (Platform.environment.containsKey('FLUTTER_TEST')) {
        return appDocDir.path;
      }
      rethrow;
    }

    return appDocDir.path;
  }
}
