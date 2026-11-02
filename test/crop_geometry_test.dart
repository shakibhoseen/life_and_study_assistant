import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/services/media/crop_geometry.dart';

void main() {
  group('fittedImageRect', () {
    test('a wide photo sits in a band across the middle', () {
      final rect = CropGeometry.fittedImageRect(
        box: const Size(400, 400),
        imageWidth: 400,
        imageHeight: 100,
      );

      expect(rect.left, 0);
      expect(rect.width, 400);
      expect(rect.height, 100);
      expect(rect.top, 150); // centred
    });

    test('a tall photo sits in a column down the middle', () {
      final rect = CropGeometry.fittedImageRect(
        box: const Size(400, 400),
        imageWidth: 100,
        imageHeight: 400,
      );

      expect(rect.top, 0);
      expect(rect.height, 400);
      expect(rect.width, 100);
      expect(rect.left, 150);
    });
  });

  group('toImagePixels', () {
    test('the whole photo maps to the whole photo', () {
      final pixels = CropGeometry.toImagePixels(
        displayRect: const Rect.fromLTWH(0, 150, 400, 100),
        box: const Size(400, 400),
        imageWidth: 800,
        imageHeight: 200,
      );

      expect(pixels.left, 0);
      expect(pixels.top, 0);
      expect(pixels.width, 800);
      expect(pixels.height, 200);
    });

    test('half the width on screen is half the width in pixels', () {
      final pixels = CropGeometry.toImagePixels(
        displayRect: const Rect.fromLTWH(0, 150, 200, 100),
        box: const Size(400, 400),
        imageWidth: 800,
        imageHeight: 200,
      );

      expect(pixels.left, 0);
      expect(pixels.width, 400);
    });

    test('the offset of the fitted photo is taken off', () {
      // The photo starts 150px down the box, so a frame at y=150 is the top
      // of the photo, not 150px into it.
      final pixels = CropGeometry.toImagePixels(
        displayRect: const Rect.fromLTWH(100, 150, 100, 50),
        box: const Size(400, 400),
        imageWidth: 400,
        imageHeight: 100,
      );

      expect(pixels.left, 100);
      expect(pixels.top, 0);
      expect(pixels.width, 100);
      expect(pixels.height, 50);
    });

    test('a frame dragged past the edge crops to the edge', () {
      final pixels = CropGeometry.toImagePixels(
        displayRect: const Rect.fromLTWH(-50, 100, 600, 300),
        box: const Size(400, 400),
        imageWidth: 400,
        imageHeight: 100,
      );

      expect(pixels.left, 0);
      expect(pixels.top, 0);
      expect(pixels.right, 400);
      expect(pixels.bottom, 100);
    });

    test('an empty photo is handled rather than divided by', () {
      final pixels = CropGeometry.toImagePixels(
        displayRect: const Rect.fromLTWH(0, 0, 10, 10),
        box: const Size(400, 400),
        imageWidth: 0,
        imageHeight: 0,
      );

      expect(pixels.width, 0);
    });
  });
}
