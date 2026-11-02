import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/services/ai/models/voice_mistake_result.dart';
import 'package:life_and_study_assistant/core/services/ai/voice_mistake_parser_service.dart';
import 'package:life_and_study_assistant/core/services/overlay/live_mcq_bubble_service.dart';
import 'package:life_and_study_assistant/core/services/voice/voice_recording_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.record/messages'),
          (MethodCall call) async {
            return null;
          },
        );
  });

  tearDown(() async {
    await db.close();
  });

  group('Voice Mistake Result Models & Serialization Tests', () {
    test('VoiceMistakeResult JSON serialization and deserialization', () {
      final json = {
        'question': 'তিব্বতের মানস সরোবর হতে উৎপন্ন নদী কোনটি?',
        'options': ['ব্রহ্মপুত্র', 'পদ্মা', 'মেঘনা', 'যমুনা'],
        'correct_index': 0,
        'explanation': 'ব্রহ্মপুত্র নদ তিব্বতের মানস সরোবরের চেমায়ুংদুং হিমবাহ থেকে উৎপন্ন হয়েছে।',
        'subject': 'Bangladesh Affairs',
        'topic': 'বাংলাদেশের নদ-নদী',
        'key_rule': 'মানস সরোবর ➔ চেমায়ুংদুং হিমবাহ ➔ ব্রহ্মপুত্র',
      };

      final result = VoiceMistakeResult.fromJson(
        json,
        spokenRef: 'Voice note #1',
      );
      expect(result.questionText, 'তিব্বতের মানস সরোবর হতে উৎপন্ন নদী কোনটি?');
      expect(result.options.length, 4);
      expect(result.correctIndex, 0);
      expect(result.subject, 'Bangladesh Affairs');
      expect(result.topic, 'বাংলাদেশের নদ-নদী');
      expect(result.spokenSummary, 'Voice note #1');

      final quizQuestion = result.toQuizQuestion();
      expect(quizQuestion.questionText, result.questionText);
      expect(quizQuestion.options.length, 4);
      expect(quizQuestion.correctIndex, 0);

      final encoded = result.toJson();
      expect(encoded['question'], result.questionText);
      expect(encoded['correct_index'], 0);
    });
  });

  group('VoiceMistakeParserService without a model', () {
    // What the user said is never turned into a question by keyword. The
    // fallback this replaces answered anything containing "নদী" with a fixed
    // ব্রহ্মপুত্র question and anything else with a placeholder whose options
    // read "বিকল্প অপশন খ/গ/ঘ" — then saved it to the mistake notebook as a
    // question the user had got wrong.
    for (final spoken in const [
      '১২ নম্বর প্রশ্নে মানস সরোবর থেকে উৎপন্ন নদী ভুল করছিলাম',
      'বাংলা ব্যাকরণে পরপদের অর্থ প্রধান সমাস কোনটা ছিল',
      'English adept preposition question mistake',
    ]) {
      test('"$spoken" reports failure rather than inventing a question', () {
        expect(
          VoiceMistakeParserService.instance.parseMistakeFromText(spoken),
          throwsA(isA<VoiceParseException>()),
        );
      });
    }

    test('silence and stray words are not worth reporting', () async {
      // Nothing was asked, so nothing failed.
      expect(
        await VoiceMistakeParserService.instance.parseMistakeFromText(''),
        isNull,
      );
      expect(
        await VoiceMistakeParserService.instance.parseMistakeFromText('   '),
        isNull,
      );
    });
  });

  group('VoiceMistakeParserService Database Persistence Tests', () {
    test('saveVoiceMistakeToDatabase populates SpacedReviewItems, Mistake Bank, and WeakTopics', () async {
      final mistake = VoiceMistakeResult(
        questionText: 'কোন মুঘল সুবাদার ঢাকাকে বাংলার রাজধানী করেন?',
        options: ['ইসলাম খান', 'মীর জুমলা', 'শায়েস্তা খান', 'ইব্রাহিম খান'],
        correctIndex: 0,
        explanation: '১৬১০ সালে সুবাদার ইসলাম খান ঢাকাকে বাংলার প্রথম রাজধানী ঘোষণা করেন।',
        subject: 'Bangladesh Affairs',
        topic: 'মুঘল আমল',
        keyRule: '১৬১০ সাল ➔ সুবাদার ইসলাম খান ➔ ঢাকা রাজধানী (জাহাঙ্গীরনগর)',
        spokenSummary: 'ঢাকা রাজধানী ভুল করছিলাম',
      );

      await VoiceMistakeParserService.instance.saveVoiceMistakeToDatabase(
        db,
        mistake,
      );

      // 1. Verify Spaced Review item inserted with tomorrow review date
      final allReviews = await db.watchAllSpacedReviewItems().first;
      expect(allReviews.isNotEmpty, true);
      final savedReview = allReviews.firstWhere((r) => r.topic == 'মুঘল আমল');
      expect(savedReview.subject, 'Bangladesh Affairs');
      expect(savedReview.keyRule.contains('ইসলাম খান'), true);

      // 2. Verify Mistake Bank question inserted
      final wrongQuestions = await db.watchWrongDrillQuestions().first;
      expect(wrongQuestions.isNotEmpty, true);
      final savedMistake = wrongQuestions.firstWhere(
        (q) => q.questionText == mistake.questionText,
      );
      expect(savedMistake.correctIndex, 0);
      expect(savedMistake.isMastered, false);

      // 3. Verify Weak Topics inserted
      final weakTopics = await db.getAllWeakTopics();
      expect(weakTopics.any((w) => w.topicName == 'মুঘল আমল'), true);
    });
  });

  group('LiveMcqBubbleService & BubbleLaunchResult Tests', () {
    test('BubbleLaunchResult enum states and helper behavior', () {
      expect(BubbleLaunchResult.success.isSuccess, true);
      expect(BubbleLaunchResult.overlayPermissionDenied.isSuccess, false);
      expect(BubbleLaunchResult.microphonePermissionDenied.isSuccess, false);
      expect(BubbleLaunchResult.failed.isSuccess, false);
    });

    test('LiveMcqBubbleService singleton is configured properly', () {
      final service = LiveMcqBubbleService.instance;
      expect(service, isNotNull);
      expect(service.isBubbleRunning, false);
    });
  });

  group('VoiceRecordingService Permission & State Tests', () {
    test(
      'VoiceRecordingService singleton is configured with default states',
      () {
        final service = VoiceRecordingService.instance;
        expect(service, isNotNull);
        expect(service.isRecording, false);
        expect(service.currentFilePath, isNull);
      },
    );

    test('VoiceRecordingService hasPermission returns true when permission_handler reports granted', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('flutter.baseflow.com/permissions/methods'),
            (MethodCall call) async {
              if (call.method == 'checkPermissionStatus') {
                return 1; // PermissionStatus.granted
              }
              return 1;
            },
          );

      final hasPerm = await VoiceRecordingService.instance.hasPermission();
      expect(hasPerm, isTrue);
    });
  });
}
