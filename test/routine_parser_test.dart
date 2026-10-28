import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/services/ai/models/parsed_routine_item.dart';
import 'package:life_and_study_assistant/core/services/ai/routine_parser_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('No Invented Routines', () {
    // Every one of these used to manufacture a single placeholder exam that
    // was indistinguishable from a real import, which is how a failed import
    // looked like a one-exam routine.
    test('unrecognisable text produces nothing', () async {
      final items = await RoutineParserService.instance.parseRoutineFromText(
        'হ্যালো, কেমন আছেন? আজ আবহাওয়া ভালো।',
      );

      expect(items, isEmpty);
    });

    test('an empty string produces nothing', () async {
      expect(
        await RoutineParserService.instance.parseRoutineFromText('   '),
        isEmpty,
      );
    });

    test('routine JSON is read directly, without the model', () async {
      const json = '''[
  {"date": "2026-11-02", "exam_time": "10:00 AM", "subject": "বাংলা সাহিত্য",
   "title": "পরীক্ষা – ০১", "topics": ["প্রাচীন যুগ"], "exam_type": "Daily",
   "track_name": "১০০ দিনে বিসিএস"},
  {"date": "2026-11-04", "exam_time": "10:00 PM", "subject": "বাংলা ব্যাকরণ",
   "title": "পরীক্ষা – ০২", "topics": ["কারক"], "exam_type": "Daily",
   "track_name": "১০০ দিনে বিসিএস"}
]''';

      final items = await RoutineParserService.instance.parseRoutineFromText(
        json,
      );

      expect(items.length, 2);
      expect(items.first.title, 'পরীক্ষা – ০১');
      expect(items.first.date, DateTime(2026, 11, 2));
      expect(items[1].trackName, '১০০ দিনে বিসিএস');
    });

    test('code-fenced routine JSON is read too', () async {
      const json = '''```json
[{"date": "2026-11-02", "subject": "Math", "title": "Model Test 01",
  "topics": ["Algebra"], "exam_type": "Model Test"}]
```''';

      final items = await RoutineParserService.instance.parseRoutineFromText(
        json,
      );

      expect(items.length, 1);
      expect(items.first.subject, 'Math');
    });

    test('an unrelated JSON array is not treated as a routine', () async {
      // fromJson fills in every missing field, so without a date check this
      // would become an exam scheduled for tomorrow.
      final items = await RoutineParserService.instance.parseRoutineFromText(
        '[{"foo": "bar"}, {"baz": 2}]',
      );

      expect(items, isEmpty);
    });

    test(
      'a partly dated array is rejected rather than half-imported',
      () async {
        final items = await RoutineParserService.instance.parseRoutineFromText(
          '[{"date": "2026-11-02", "subject": "Math"}, {"subject": "Bangla"}]',
        );

        expect(items, isEmpty);
      },
    );
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
          'title': 'Daily Exam 07',
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
        expect(item.title, equals('Daily Exam 07'));
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

    test('Envelope routine JSON format is parsed correctly with shared track', () async {
      const envelopeJson = '''{
  "track_name": "১০০ দিনে বিসিএস প্রস্তুতি",
  "exams": [
    {"date": "2026-11-01", "exam_time": "10:00 PM", "subject": "বাংলা", "title": "Day 01", "topics": ["ধ্বনি"]},
    {"date": "2026-11-02", "exam_time": "10:00 PM", "subject": "ইংরেজি", "title": "Day 02", "topics": ["Noun"]}
  ]
}''';

      final items = await RoutineParserService.instance.parseRoutineFromText(
        envelopeJson,
      );
      expect(items.length, equals(2));
      expect(items.first.trackName, equals('১০০ দিনে বিসিএস প্রস্তুতি'));
      expect(items.last.subject, equals('ইংরেজি'));
    });

    test('Token truncation recovery recovers all complete items from cut-off JSON', () async {
      // Simulates Gemini running out of maxOutputTokens mid-way through day 3
      const truncatedJson = '''```json
[
  {"date": "2026-11-01", "subject": "বাংলা সাহিত্য", "title": "Day 01", "topics": ["চর্যাপদ"]},
  {"date": "2026-11-02", "subject": "বাংলাদেশ বিষয়াবলী", "title": "Day 02", "topics": ["প্রাচীন বাংলা"]},
  {"date": "2026-11-03", "subject": "গণিত", "title": "Day 03", "topics": ["বাস্তব সং''';

      final items = RoutineParserService.instance.decodeResponseForTesting(
        truncatedJson,
      );
      expect(items.length, equals(2));
      expect(items[0].title, equals('Day 01'));
      expect(items[1].subject, equals('বাংলাদেশ বিষয়াবলী'));
    });

    test('Token truncation recovery recovers complete items from cut-off envelope format', () async {
      // Simulates Gemini envelope format truncated mid-stream
      const truncatedEnvelope = '''{
  "track_name": "100 Days BCS Challenge",
  "exams": [
    {"date": "2026-11-01", "subject": "Bangla", "title": "Day 01", "topics": ["Grammar"]},
    {"date": "2026-11-02", "subject": "English", "title": "Day 02", "topics": ["Vocabulary"]},
    {"date": "2026-11-03", "subject": "Math", "title": "Day 03", "top''';

      final items = RoutineParserService.instance.decodeResponseForTesting(
        truncatedEnvelope,
      );
      expect(items.length, equals(2));
      expect(items[0].trackName, equals('100 Days BCS Challenge'));
      expect(items[1].title, equals('Day 02'));
    });

    test('Object scanner recovers items even with deeply malformed/cut-off nested envelope', () async {
      // Simulates severe cut-off inside array with broken quotes
      const severelyBroken = '''{
  "track_name": "52nd BCS 135-Day",
  "exams": [
    {"date": "2026-11-01", "subject": "Bangla", "title": "Day 01", "topics": ["কারক ও বিভক্তি"]},
    {"date": "2026-11-02", "subject": "English", "title": "Day 02", "topics": ["Idioms"]},
    {"date": "2026-11-03", "subject": "Math", "title": "Day 03", "topics": ["শতকরা", "লাভ''';

      final items = RoutineParserService.instance.decodeResponseForTesting(
        severelyBroken,
      );
      expect(items.length, greaterThanOrEqualTo(2));
      expect(items[0].trackName, equals('52nd BCS 135-Day'));
      expect(items[1].title, equals('Day 02'));
    });

    test('RoutineParserException contains diagnostic details and formats user message', () {
      final ex = RoutineParserException(
        userMessage: 'Gemini AI টোকেন সীমার কারণে উত্তর প্রদান বন্ধ করেছে।',
        technicalDetails: 'FinishReason: maxTokens',
        finishReason: 'maxTokens',
        promptTokens: 1400,
        candidateTokens: 8192,
        totalTokens: 9592,
        modelName: 'gemini-flash-lite-latest',
      );
      expect(ex.toString(), contains('টোকেন সীমার কারণে'));
      expect(ex.finishReason, equals('maxTokens'));
      expect(ex.totalTokens, equals(9592));
      expect(ex.modelName, equals('gemini-flash-lite-latest'));
    });
  });
}
