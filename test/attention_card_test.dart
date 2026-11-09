import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/features/dashboard/presentation/widgets/attention_card.dart';

/// The backlog used to be three separate sections spread down the dashboard,
/// so comparing twelve unmastered questions against three weak topics meant
/// scrolling between them. One card answers "how much is waiting?" in a glance.
void main() {
  Widget host(List<AttentionItem> items) {
    return MaterialApp(
      home: Scaffold(body: AttentionCard(items: items)),
    );
  }

  AttentionItem item(
    String label,
    int count, {
    VoidCallback? onTap,
  }) {
    return AttentionItem(
      label: label,
      count: count,
      icon: Icons.error_outline,
      colour: const Color(0xFFF59E0B),
      onTap: onTap,
    );
  }

  testWidgets('only what is actually waiting gets a row', (tester) async {
    await tester.pumpWidget(
      host([item('ভুল প্রশ্ন', 12), item('দুর্বল টপিক', 0)]),
    );

    expect(find.text('ভুল প্রশ্ন'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    // A zero row is not information; it is a row saying there is no row.
    expect(find.text('দুর্বল টপিক'), findsNothing);
  });

  testWidgets('nothing waiting draws no card at all', (tester) async {
    await tester.pumpWidget(host([item('ভুল প্রশ্ন', 0), item('রিভিশন', 0)]));

    expect(find.text('যা মনোযোগ চায়'), findsNothing);
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('a row takes you to the drill it names', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      host([item('ভুল প্রশ্ন', 3, onTap: () => tapped++)]),
    );

    await tester.tap(find.text('ভুল প্রশ্ন'));
    await tester.pump();

    expect(tapped, 1);
  });

  testWidgets('a row with nowhere to go promises nothing', (tester) async {
    // The weak-topic row has no destination until a topic exists, and a
    // chevron on a dead row is a lie about where tapping leads.
    await tester.pumpWidget(host([item('দুর্বল টপিক', 2)]));

    expect(find.text('দুর্বল টপিক'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets('the rows keep the order they were given', (tester) async {
    // They follow pickNextStudyAction's priority, so the card and the
    // recommendation above it never look as though they disagree.
    await tester.pumpWidget(
      host([item('রিভিশন', 4), item('ভুল প্রশ্ন', 9), item('দুর্বল টপিক', 1)]),
    );

    final labels = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();

    expect(
      labels.indexOf('রিভিশন'),
      lessThan(labels.indexOf('ভুল প্রশ্ন')),
    );
    expect(
      labels.indexOf('ভুল প্রশ্ন'),
      lessThan(labels.indexOf('দুর্বল টপিক')),
    );
  });
}
