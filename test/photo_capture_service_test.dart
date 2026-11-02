import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:life_and_study_assistant/core/services/media/photo_capture_service.dart';

/// Stands in for the camera, which no test can open.
class _FakePicker extends ImagePicker {
  _FakePicker(this.result);
  final XFile? result;
  int calls = 0;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    calls++;
    return result;
  }
}

/// Gives the service a real BuildContext without pumping a whole screen.
Future<BuildContext> _context(WidgetTester tester) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox();
        },
      ),
    ),
  );
  return captured;
}

void main() {
  final service = PhotoCaptureService.instance;
  late Directory tmp;
  late File shot;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('capture_test');
    shot = File('${tmp.path}/page.jpg')..writeAsBytesSync([0xFF, 0xD8, 0xFF]);
  });

  setUp(() {
    // The straighten screen waits for a tap, so a test awaiting the capture
    // would hang on it. Passing the photo straight through leaves the crop
    // and cancel paths below as the thing under test.
    service.runRotate = (context, photo) async => photo;
  });

  tearDown(() async {
    service.runCrop = (path, ui) async => path;
    service.runRotate = (context, photo) async => photo;
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  testWidgets('the trimmed photo is the one handed on', (tester) async {
    final context = await _context(tester);
    final trimmed = File('${tmp.path}/page_cropped.jpg')
      ..writeAsBytesSync([0xFF, 0xD8, 0xFF]);

    service.picker = _FakePicker(XFile(shot.path));
    service.runCrop = (path, ui) async => trimmed.path;

    final result = await service.captureAndCrop(
      source: ImageSource.camera,
      context: context,
    );

    expect(result?.path, trimmed.path);
  });

  testWidgets('backing out of the camera hands on nothing', (tester) async {
    final context = await _context(tester);
    final picker = _FakePicker(null);
    service.picker = picker;
    var cropOpened = false;
    service.runCrop = (path, ui) async {
      cropOpened = true;
      return path;
    };

    final result = await service.captureAndCrop(
      source: ImageSource.camera,
      context: context,
    );

    expect(result, isNull);
    expect(picker.calls, 1);
    // Nothing was taken, so there is nothing to trim.
    expect(cropOpened, isFalse);
  });

  testWidgets('backing out of the trim keeps the photo as shot', (
    tester,
  ) async {
    final context = await _context(tester);
    service.picker = _FakePicker(XFile(shot.path));
    service.runCrop = (path, ui) async => null;

    final result = await service.captureAndCrop(
      source: ImageSource.camera,
      context: context,
    );

    // The photo is already taken; losing it would mean shooting it again.
    expect(result?.path, shot.path);
  });

  testWidgets('a crop screen that is not there does not cost the photo', (
    tester,
  ) async {
    final context = await _context(tester);
    service.picker = _FakePicker(XFile(shot.path));
    // What a missing UCropActivity throws on a device.
    service.runCrop = (path, ui) async =>
        throw PlatformException(code: 'ActivityNotFoundException');

    final result = await service.captureAndCrop(
      source: ImageSource.camera,
      context: context,
    );

    expect(result?.path, shot.path);
  });

  testWidgets('a photo already taken can be trimmed again', (tester) async {
    final context = await _context(tester);
    final narrower = File('${tmp.path}/half.jpg')
      ..writeAsBytesSync([0xFF, 0xD8, 0xFF]);
    service.runCrop = (path, ui) async => narrower.path;

    final result = await service.cropExisting(
      path: shot.path,
      context: context,
    );

    expect(result?.path, narrower.path);
  });

  testWidgets('straightening comes before trimming', (tester) async {
    final context = await _context(tester);
    final order = <String>[];
    service.picker = _FakePicker(XFile(shot.path));
    service.runRotate = (context, photo) async {
      order.add('rotate');
      return photo;
    };
    service.runCrop = (path, ui) async {
      order.add('crop');
      return path;
    };

    await service.captureAndCrop(source: ImageSource.camera, context: context);

    // Cropping a sideways page means framing a sideways rectangle.
    expect(order, ['rotate', 'crop']);
  });

  testWidgets('backing out of straightening hands on nothing', (tester) async {
    final context = await _context(tester);
    service.picker = _FakePicker(XFile(shot.path));
    service.runRotate = (context, photo) async => null;
    var cropOpened = false;
    service.runCrop = (path, ui) async {
      cropOpened = true;
      return path;
    };

    final result = await service.captureAndCrop(
      source: ImageSource.camera,
      context: context,
    );

    expect(result, isNull);
    expect(cropOpened, isFalse);
  });

  group('rotateQuarterTurn', () {
    /// A landscape page: wider than it is tall, like a book held sideways.
    File sidewaysPage() {
      final page = img.Image(width: 40, height: 10);
      img.fill(page, color: img.ColorRgb8(200, 200, 200));
      final file = File('${tmp.path}/sideways.jpg')
        ..writeAsBytesSync(img.encodeJpg(page));
      return file;
    }

    test('a sideways page comes out upright', () async {
      final turned = await service.rotateQuarterTurn(sidewaysPage());
      final result = img.decodeImage(turned.readAsBytesSync())!;

      expect(result.width, 10);
      expect(result.height, 40);
    });

    test('four turns come back to where they started', () async {
      var file = sidewaysPage();
      for (var i = 0; i < 4; i++) {
        file = await service.rotateQuarterTurn(file);
      }
      final result = img.decodeImage(file.readAsBytesSync())!;

      expect(result.width, 40);
      expect(result.height, 10);
    });

    test('turning the other way is the other way', () async {
      final right = await service.rotateQuarterTurn(sidewaysPage());
      final left = await service.rotateQuarterTurn(
        sidewaysPage(),
        clockwise: false,
      );

      // Both stand the page upright; they differ in which edge leads.
      final r = img.decodeImage(right.readAsBytesSync())!;
      final l = img.decodeImage(left.readAsBytesSync())!;
      expect(r.width, l.width);
      expect(r.height, l.height);
      expect(right.path, isNot(left.path));
    });

    test('the original file is left alone', () async {
      final original = sidewaysPage();
      final before = original.readAsBytesSync().length;

      final turned = await service.rotateQuarterTurn(original);

      expect(turned.path, isNot(original.path));
      expect(original.readAsBytesSync().length, before);
    });

    test('a file that is not an image is handed back untouched', () async {
      final notAnImage = File('${tmp.path}/notes.txt')
        ..writeAsStringSync('এটা ছবি নয়');

      final result = await service.rotateQuarterTurn(notAnImage);

      // Losing the photo would be worse than failing to turn it.
      expect(result.path, notAnImage.path);
    });
  });

  testWidgets('the crop screen is told what is being trimmed', (tester) async {
    final context = await _context(tester);
    service.picker = _FakePicker(XFile(shot.path));
    String? shownTitle;
    service.runCrop = (path, ui) async {
      final android = ui.whereType<AndroidUiSettings>().first;
      shownTitle = android.toMap()['android.toolbar_title'] as String?;
      return path;
    };

    await service.captureAndCrop(
      source: ImageSource.camera,
      context: context,
      title: 'উত্তরপত্র কেটে নিন',
    );

    expect(shownTitle, 'উত্তরপত্র কেটে নিন');
  });
}
