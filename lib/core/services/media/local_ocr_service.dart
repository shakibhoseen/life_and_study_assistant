import 'dart:io';
import 'package:local_ocr/local_ocr.dart';

import 'layout/layout_detection_service.dart';
import 'ocr_text_cleaner.dart';

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
        final layout =
            await LayoutDetectionService.instance.analyzeLayout(imageFile);
        if (layout.isDualColumn && layout.columnCrops.length == 2) {
          final col1Text = await _extractSingle(
            layout.columnCrops[0],
            languagePreset,
            '6',
            customArgs,
          );
          final col2Text = await _extractSingle(
            layout.columnCrops[1],
            languagePreset,
            '6',
            customArgs,
          );

          final clean1 = OcrTextCleaner.clean(col1Text);
          final clean2 = OcrTextCleaner.clean(col2Text);

          if (clean2.isEmpty) return clean1;
          if (clean1.isEmpty) return clean2;

          return '📌 [কলাম ১ (বাম পাশ)]:\n\n$clean1\n\n'
              '════════════════════════════════\n\n'
              '📌 [কলাম ২ (ডান পাশ)]:\n\n$clean2';
        } else {
          // If layout analysis reliably determined it is single-column, use deskewed image
          return await _extractSingle(
            layout.deskewedImage,
            languagePreset,
            layoutMode.psm,
            customArgs,
          );
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
      // Fallback: if 'equ' or combination throws an unexpected error, attempt with 'ben+eng'
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
}
