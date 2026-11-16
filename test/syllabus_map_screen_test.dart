import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/database/database_provider.dart';
import 'package:life_and_study_assistant/core/database/tables/syllabus_progress_table.dart';
import 'package:life_and_study_assistant/core/services/syllabus/syllabus_service.dart';
import 'package:life_and_study_assistant/features/syllabus_map/presentation/providers/syllabus_map_provider.dart';
import 'package:life_and_study_assistant/features/syllabus_map/presentation/screens/syllabus_map_screen.dart';

import 'support/ui_style_override.dart';

/// The map on screen, driven through a real database.
///
/// The arithmetic has its own tests; what these check is that the screen
/// shows the user's own figures and that tapping a topic actually moves
/// them — the join between the two halves, which is where a feature like
/// this usually turns out to be read-only.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  const track = SyllabusTrack(
    trackKey: 'primary',
    trackName: 'প্রাথমিক সহকারী শিক্ষক',
    totalMarks: 40,
    note: '',
    subjects: [
      SyllabusTrackSubject(
        name: 'গণিত',
        marks: 20,
        aliases: [],
        topics: [
          SyllabusTrackTopic(title: 'শতকরা', weight: 1),
          SyllabusTrackTopic(title: 'লাভ-ক্ষতি', weight: 1),
        ],
      ),
      SyllabusTrackSubject(
        name: 'বাংলা',
        marks: 20,
        aliases: [],
        topics: [SyllabusTrackTopic(title: 'সমাস', weight: 1)],
      ),
    ],
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await SyllabusService.instance.seed(db, tracks: const [track]);
  });
  tearDown(() => db.close());

  Widget screen() => ProviderScope(
    overrides: [
      classicUiStyle,
      appDatabaseProvider.overrideWithValue(db),
      // The real provider seeds from the asset bundle, which a widget test
      // has no business loading; the tracks are already in the database.
      syllabusTracksProvider.overrideWith((ref) async => ['primary']),
    ],
    child: const MaterialApp(home: SyllabusMapScreen()),
  );

  testWidgets('starts at nought percent with every subject listed', (
    tester,
  ) async {
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();

    expect(find.text('০%'), findsOneWidget);
    expect(find.text('গণিত'), findsOneWidget);
    expect(find.text('বাংলা'), findsOneWidget);
  });

  testWidgets('puts the subject with most marks missing first', (tester) async {
    await SyllabusService.instance.setStatus(
      db,
      nodeKey: topicNodeKey('primary', 'বাংলা', 'সমাস'),
      status: SyllabusStatus.done,
    );

    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();

    // বাংলা is finished, so গণিত has all twenty of its marks outstanding.
    final maths = tester.getTopLeft(find.text('গণিত')).dy;
    final bangla = tester.getTopLeft(find.text('বাংলা')).dy;
    expect(maths, lessThan(bangla));
  });

  testWidgets('tapping a topic moves the coverage figure', (tester) async {
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();

    await tester.tap(find.text('গণিত'));
    await tester.pumpAndSettle();

    // First tap is "reading", which must not move the headline figure.
    await tester.tap(find.text('শতকরা'));
    await tester.pumpAndSettle();
    expect(find.text('০%'), findsOneWidget);
    expect(find.text('পড়ছি'), findsOneWidget);

    // Second tap is "done": half of গণিত, which is half the exam's marks.
    await tester.tap(find.text('শতকরা'));
    await tester.pumpAndSettle();
    expect(find.text('২৫%'), findsOneWidget);
  });

  testWidgets('the whole-subject button fills the subject', (tester) async {
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();

    await tester.tap(find.text('বাংলা'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('পুরো বিষয় শেষ'));
    await tester.pumpAndSettle();

    expect(find.text('৫০%'), findsOneWidget);
  });

  testWidgets('asks about a topic the drill history supports', (tester) async {
    // Evidence strong enough for a "done" proposal: six attempts, five right.
    await db
        .into(db.drillQuestions)
        .insert(
          DrillQuestionsCompanion.insert(
            subject: 'গণিত',
            topic: 'শতকরা',
            questionText: 'প্রশ্ন',
            optionsJson: '["ক","খ"]',
            correctIndex: 0,
            selectedIndex: 0,
            isCorrect: true,
            attemptCount: const Value(6),
            wrongCount: const Value(1),
          ),
        );

    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();

    expect(find.text('একটু জিজ্ঞেস করি'), findsOneWidget);
    expect(find.text('"শতকরা" কি শেষ?'), findsOneWidget);

    // Nothing is counted until the user agrees.
    expect(find.text('০%'), findsOneWidget);

    await tester.tap(find.text('হ্যাঁ'));
    await tester.pumpAndSettle();

    expect(find.text('২৫%'), findsOneWidget);
  });
}
