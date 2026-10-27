import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/services/ai/models/parsed_routine_item.dart';
import 'package:life_and_study_assistant/core/services/ai/routine_parser_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('RoutineParserService & Models Tests', () {
    test(
      'ParsedRoutineItem parses JSON structure accurately with trackName',
      () {
        final json = {
          'date': '2026-10-29',
          'exam_time': '10:00 PM',
          'subject': 'Bangla Grammar',
          'topics': ['কারক ও বিভক্তি', 'সমাস'],
          'exam_type': 'Daily',
          'track_name': '52nd BCS 135-Day',
        };

        final item = ParsedRoutineItem.fromJson(json, rawRef: 'Sample Post');

        expect(item.date.year, equals(2026));
        expect(item.date.month, equals(10));
        expect(item.date.day, equals(29));
        expect(item.examTime, equals('10:00 PM'));
        expect(item.subject, equals('Bangla Grammar'));
        expect(item.topics.length, equals(2));
        expect(item.topics.first, equals('কারক ও বিভক্তি'));
        expect(item.examType, equals('Daily'));
        expect(item.trackName, equals('52nd BCS 135-Day'));
        expect(item.rawReference, equals('Sample Post'));
      },
    );

    test(
      'ParsedRoutineItem converts to Drift Companion with track override',
      () {
        final item = ParsedRoutineItem(
          date: DateTime(2026, 10, 30),
          examTime: '09:00 PM',
          subject: 'Mathematics',
          topics: ['শতকরা', 'লাভ-ক্ষতি'],
          examType: 'Model Test',
          trackName: 'General BCS',
        );

        final companion = item.toCompanion(overrideTrack: 'Vocabulary Booster');
        expect(companion.examDate.value, equals(DateTime(2026, 10, 30)));
        expect(companion.examTime.value, equals('09:00 PM'));
        expect(companion.subject.value, equals('Mathematics'));
        expect(companion.title.value, equals('Mathematics Model Test Exam'));
        expect(companion.topicsCovered.value, contains('শতকরা, লাভ-ক্ষতি'));
        expect(companion.trackName.value, equals('Vocabulary Booster'));
      },
    );

    test(
      'Local fallback parses multi-track text routine headers accurately',
      () async {
        const multiTrackRoutineText = '''
52nd BCS 135-Day Syllabus Routine:
2026-10-28 | 10:00 PM | Bangla Grammar: কারক ও বিভক্তি | Daily Exam

Daily Vocabulary Booster:
2026-10-29 | 10:30 PM | English: Synonyms & Antonyms | Micro Drill

Friday Full Mega Model Test:
2026-10-31 | 09:00 PM | Full Syllabus: 200 Marks Simulation
''';

        final items = await RoutineParserService.instance.parseRoutineFromText(
          multiTrackRoutineText,
        );
        expect(items.length, greaterThanOrEqualTo(2));
        expect(
          items.any(
            (e) => e.trackName.contains('135') || e.trackName.contains('BCS'),
          ),
          isTrue,
        );
      },
    );

    test(
      'Local fallback parses text routine lines with dates and topics',
      () async {
        const routineText = '''
LiveMCQ BCS Crash Routine:
2026-10-28 | 10:00 PM | Bangla: কারক ও বিভক্তি | Daily Exam
2026-10-29 | 10:00 PM | Math: লাভ-ক্ষতি | Daily Exam
''';

        final items = await RoutineParserService.instance.parseRoutineFromText(
          routineText,
        );
        expect(items, isNotEmpty);
        expect(
          items.any((e) => e.topics.any((t) => t.contains('কারক ও বিভক্তি'))),
          isTrue,
        );
      },
    );
  });
}
