import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:life_and_study_assistant/core/widgets/photo_source_sheet.dart';

void main() {
  Future<ImageSource?> openAndTap(WidgetTester tester, String label) async {
    ImageSource? chosen;
    var answered = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              chosen = await PhotoSourceSheet.ask(context);
              answered = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
    await tester.pump();

    expect(answered, isTrue);
    return chosen;
  }

  testWidgets('both sources are offered', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => PhotoSourceSheet.ask(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // A page already photographed or shared should not have to be shot again.
    expect(find.text('ক্যামেরা'), findsOneWidget);
    expect(find.text('গ্যালারি'), findsOneWidget);
  });

  testWidgets('choosing the camera returns the camera', (tester) async {
    expect(await openAndTap(tester, 'ক্যামেরা'), ImageSource.camera);
  });

  testWidgets('choosing the gallery returns the gallery', (tester) async {
    expect(await openAndTap(tester, 'গ্যালারি'), ImageSource.gallery);
  });
}
