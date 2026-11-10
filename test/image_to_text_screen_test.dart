import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/features/image_to_text/presentation/screens/image_to_text_screen.dart';

void main() {
  testWidgets('ImageToTextScreen renders empty state and action buttons',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ImageToTextScreen(),
      ),
    );

    expect(find.text('ইমেজ টু টেক্সট (অফলাইন)'), findsOneWidget);
    expect(find.text('১০০% অফলাইন • কোনো ক্লাউড AI নেই'), findsOneWidget);
    expect(find.text('ছবি থেকে লেখা বের করুন'), findsOneWidget);
    expect(find.text('ক্যামেরা'), findsOneWidget);
    expect(find.text('গ্যালারি'), findsOneWidget);
  });
}
