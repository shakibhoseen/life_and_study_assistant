import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:life_and_study_assistant/core/services/media/photo_rotate_screen.dart';

void main() {
  late Directory tmp;
  late File sideways;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('rotate_screen_test');
    // A page held sideways: much wider than it is tall.
    final page = img.Image(width: 400, height: 100);
    img.fill(page, color: img.ColorRgb8(220, 220, 220));
    sideways = File('${tmp.path}/sideways.jpg')
      ..writeAsBytesSync(img.encodeJpg(page));
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: PhotoRotateScreen(photo: sideways)),
    );
    await tester.pumpAndSettle();
  }

  /// Taps a turn and lets it finish.
  ///
  /// Rotation reads and writes a real file, and a widget test's fake async
  /// never runs that, so the tap has to happen inside runAsync or the screen
  /// keeps showing the photo it started with.
  File shownFile(WidgetTester tester) {
    final image = tester.widget<Image>(find.byType(Image).first);
    return (image.image as FileImage).file;
  }

  Future<void> turn(WidgetTester tester, IconData icon) async {
    final before = shownFile(tester).path;
    await tester.runAsync(() async {
      await tester.tap(find.byIcon(icon));
      // Waits for the work rather than for a fixed time: a decode, rotate
      // and encode takes as long as the machine takes, and a fixed delay
      // that is long enough alone is not long enough under a full suite.
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
        if (shownFile(tester).path != before) return;
      }
      fail('the photo did not change after $before');
    });
    await tester.pumpAndSettle();
  }

  testWidgets('the whole photo is shown, never cropped to fit', (tester) async {
    await open(tester);

    final image = tester.widget<Image>(find.byType(Image).first);
    // cover would cut the edges off a page that does not match the box.
    expect(image.fit, BoxFit.contain);
  });

  testWidgets('both directions are offered, and the way on', (tester) async {
    await open(tester);

    expect(find.byIcon(Icons.rotate_left_rounded), findsOneWidget);
    expect(find.byIcon(Icons.rotate_right_rounded), findsOneWidget);
    expect(find.text('এবার কেটে নিন'), findsOneWidget);
  });

  testWidgets('a turn stands the page upright and stays on screen', (
    tester,
  ) async {
    await open(tester);

    await turn(tester, Icons.rotate_right_rounded);

    // No overflow: a 400x100 page becoming 100x400 must still fit.
    expect(tester.takeException(), isNull);
  });

  testWidgets('a turn replaces the photo on screen with the upright one', (
    tester,
  ) async {
    // Awaiting the screen's own result deadlocks here: the caller resumes in
    // a microtask that only runs on a later pump. What matters is the same
    // either way — the file the screen is holding, which is what it hands on.
    await open(tester);

    await turn(tester, Icons.rotate_right_rounded);

    final file = shownFile(tester);
    final result = img.decodeImage(file.readAsBytesSync())!;

    expect(result.width, 100);
    expect(result.height, 400);
    expect(file.path, isNot(sideways.path));
  });

  testWidgets('turning twice keeps turning the newest photo', (tester) async {
    await open(tester);

    await turn(tester, Icons.rotate_right_rounded);
    await turn(tester, Icons.rotate_right_rounded);

    final result = img.decodeImage(shownFile(tester).readAsBytesSync())!;

    // Two quarter turns: back to landscape, upside down.
    expect(result.width, 400);
    expect(result.height, 100);
    expect(tester.takeException(), isNull);
  });
}
