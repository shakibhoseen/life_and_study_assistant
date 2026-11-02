import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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

  tearDown(() async {
    service.runCrop = (path, ui) async => path;
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
