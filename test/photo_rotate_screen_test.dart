import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:life_and_study_assistant/core/services/media/photo_rotate_screen.dart';

/// Standing a photographed page upright.
///
/// The contract changed after the button was found doing nothing at all on a
/// real phone: turning used to re-encode the file on every tap, which on a
/// full-size photo froze the screen for seconds and, for a format the Dart
/// decoder could not read, failed silently for ever. Turning is now free and
/// instant, and the pixels move once, when the user goes on to the crop.
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

  File? popped;

  Future<void> open(WidgetTester tester, {File? photo}) async {
    popped = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                popped = await PhotoRotateScreen.show(
                  context,
                  photo ?? sideways,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  int shownTurns(WidgetTester tester) =>
      tester.widget<RotatedBox>(find.byType(RotatedBox).first).quarterTurns;

  File shownFile(WidgetTester tester) {
    final image = tester.widget<Image>(find.byType(Image).first);
    return (image.image as FileImage).file;
  }

  /// Taps the confirm button and lets the real codec work finish.
  ///
  /// Baking reads and writes a real file through Skia, which a widget test's
  /// fake async never runs, so it has to happen inside runAsync.
  Future<void> confirm(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.byType(FilledButton));
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
        if (popped != null) return;
        if (find.textContaining('ঘোরানো গেল না').evaluate().isNotEmpty) return;
      }
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

  testWidgets('a turn shows immediately and touches no file', (tester) async {
    await open(tester);
    expect(shownTurns(tester), 0);

    await tester.tap(find.byIcon(Icons.rotate_right_rounded));
    await tester.pump();

    // Instant, with no decode: this is the whole point of the redesign.
    expect(shownTurns(tester), 1);
    expect(shownFile(tester).path, sideways.path);
    expect(tester.takeException(), isNull);
  });

  testWidgets('turning left goes the other way', (tester) async {
    await open(tester);

    await tester.tap(find.byIcon(Icons.rotate_left_rounded));
    await tester.pump();

    // -1 is kept in range rather than going negative, which RotatedBox
    // would otherwise render as a turn in the wrong direction.
    expect(shownTurns(tester), 3);
  });

  testWidgets('four turns come back to where it started', (tester) async {
    await open(tester);

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byIcon(Icons.rotate_right_rounded));
      await tester.pump();
    }

    expect(shownTurns(tester), 0);
  });

  testWidgets('going on without turning hands back the very same file', (
    tester,
  ) async {
    await open(tester);
    await confirm(tester);

    // No turn means no re-encode: the photo must not be touched at all.
    expect(popped!.path, sideways.path);
  });

  testWidgets('going on after a turn hands back an upright file', (
    tester,
  ) async {
    await open(tester);

    await tester.tap(find.byIcon(Icons.rotate_right_rounded));
    await tester.pump();
    await confirm(tester);

    expect(popped, isNotNull);
    expect(popped!.path, isNot(sideways.path));

    final result = img.decodeImage(popped!.readAsBytesSync())!;
    expect(result.width, 100);
    expect(result.height, 400);
  });

  testWidgets('two turns put it back to landscape', (tester) async {
    await open(tester);

    await tester.tap(find.byIcon(Icons.rotate_right_rounded));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.rotate_right_rounded));
    await tester.pump();
    await confirm(tester);

    final result = img.decodeImage(popped!.readAsBytesSync())!;
    expect(result.width, 400);
    expect(result.height, 100);
  });

  testWidgets('a photo that cannot be turned says so', (tester) async {
    final broken = File('${tmp.path}/not-an-image.jpg')
      ..writeAsStringSync('this is not a photograph');

    await open(tester, photo: broken);

    await tester.tap(find.byIcon(Icons.rotate_right_rounded));
    await tester.pump();
    await confirm(tester);

    // The old code handed back the sideways original without a word, which
    // is exactly why a broken rotate went unreported for so long.
    expect(popped, isNull);
    expect(find.textContaining('ঘোরানো গেল না'), findsOneWidget);
  });
}
