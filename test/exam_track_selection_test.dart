import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/features/chat/domain/models/chat_action.dart';
import 'package:life_and_study_assistant/features/live_mcq/data/repositories/exam_schedule_repository_impl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);

  group('ChatAction Self-Test & Custom Track Normalization Tests', () {
    test('normalizes empty track for self-tests to Self Test', () {
      const reply = '''
আমি আপনার জন্য সেলফ টেস্ট শিডিউল তৈরি করেছি:
[[ACTION:ADD_EXAM|2026-10-28|সেলফ টেস্ট: বাংলা ব্যাকরণ (প্রত্যয়)|বাংলা ব্যাকরণ|কৃৎ ও তদ্ধিত প্রত্যয়||10:00 PM]]
''';
      final actions = ChatAction.extractActions(reply);
      expect(actions.length, equals(1));
      expect(actions.first.type, equals(ChatActionType.addExam));
      expect(
        actions.first.title,
        equals('সেলফ টেস্ট: বাংলা ব্যাকরণ (প্রত্যয়)'),
      );
      expect(actions.first.trackName, equals('Self Test'));
    });

    test(
      'prevents self-tests from being misassigned to 100-day PDF routine track',
      () {
        const reply = '''
[[ACTION:ADD_EXAM|2026-10-28|সেলফ টেস্ট: বাংলা ব্যাকরণ (প্রত্যয়)|বাংলা ব্যাকরণ|কৃৎ ও তদ্ধিত প্রত্যয়|১০০ দিনে বিসিএস|10:00 PM]]
''';
        final actions = ChatAction.extractActions(reply);
        expect(actions.length, equals(1));
        // Should normalize to Self Test so it does not pollute the 100-day routine tab
        expect(actions.first.trackName, equals('Self Test'));
      },
    );

    test('preserves user explicit custom track', () {
      const reply = '''
[[ACTION:ADD_EXAM|2026-10-28|সাধারণ জ্ঞান কুইজ|GK|মুক্তিযুদ্ধ|আমার কাস্টম রিভিশন|10:00 PM]]
''';
      final actions = ChatAction.extractActions(reply);
      expect(actions.length, equals(1));
      expect(actions.first.trackName, equals('আমার কাস্টম রিভিশন'));
    });

    test('defaults general exams without track to Self Study', () {
      const reply = '''
[[ACTION:ADD_EXAM|2026-10-28|ইংরেজি ভোকাবুলারি টেস্ট|English|Synonyms||10:00 PM]]
''';
      final actions = ChatAction.extractActions(reply);
      expect(actions.length, equals(1));
      expect(actions.first.effectiveTrackName, equals('Self Study'));
    });
  });

  group('updateExamTrack Persistence Tests', () {
    late AppDatabase db;
    late ExamScheduleRepositoryImpl repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = ExamScheduleRepositoryImpl(db);
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'updateExamTrack moves exam from 100 days routine to Self Test track',
      () async {
        // 1. Insert exam currently in 100 days routine
        final id = await repo.addExam(
          examDate: todayStart,
          title: 'সেলফ টেস্ট: বাংলা ব্যাকরণ (প্রত্যয়)',
          topicsCovered: 'কৃৎ ও তদ্ধিত প্রত্যয়',
          trackName: '১০০ দিনে বিসিএস',
        );

        final initial = await (db.select(
          db.examSchedules,
        )..where((t) => t.id.equals(id))).getSingle();
        expect(initial.trackName, equals('১০০ দিনে বিসিএস'));

        // 2. Move exam to Self Test track
        final success = await repo.updateExamTrack(id, 'Self Test');
        expect(success, isTrue);

        // 3. Verify in database
        final updated = await (db.select(
          db.examSchedules,
        )..where((t) => t.id.equals(id))).getSingle();
        expect(updated.trackName, equals('Self Test'));

        // 4. Verify distinct tracks now includes Self Test
        final distinctTracks = await repo.watchAllDistinctTracks().first;
        expect(distinctTracks.contains('Self Test'), isTrue);
      },
    );
  });
}
