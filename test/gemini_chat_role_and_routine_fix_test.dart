import 'package:flutter_test/flutter_test.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/services/ai/gemini_chat_service.dart';
import 'package:life_and_study_assistant/features/chat/domain/models/chat_action.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Gemini Chat Role & History Construction Tests', () {
    test(
      'buildFunctionResponseContent produces role "user" and NOT "function"',
      () {
        final responsePart = FunctionResponse('getUpcomingExams', {
          'count': 1,
          'exams': [
            {'title': 'BCS Model Test 17'},
          ],
        });

        final content = GeminiChatService.buildFunctionResponseContent([
          responsePart,
        ]);

        // Role must be 'user' to satisfy Gemini API protocol
        expect(content.role, 'user');
        expect(content.role, isNot('function'));

        // Serialized JSON check
        final json = content.toJson();
        expect(json['role'], 'user');
        expect(json['role'], isNot('function'));

        final parts = json['parts'] as List;
        expect(parts.length, 1);
        final firstPart = parts.first as Map<String, dynamic>;
        expect(firstPart['functionResponse'], isNotNull);
        expect(firstPart['functionResponse']['name'], 'getUpcomingExams');
      },
    );

    test('buildHistoryContents maps "assistant" to "model" and ignores "function" or "tool"', () {
      final now = DateTime.now();
      final messages = [
        ChatMessage(
          id: 1,
          sessionId: 1,
          role: 'user',
          textContent: 'Hello',
          timestamp: now,
        ),
        ChatMessage(
          id: 2,
          sessionId: 1,
          role: 'assistant', // OpenAI or legacy role
          textContent: 'Hi there',
          timestamp: now.add(const Duration(seconds: 1)),
        ),
        ChatMessage(
          id: 3,
          sessionId: 1,
          role: 'function', // Invalid Gemini role
          textContent: '{"result": 123}',
          timestamp: now.add(const Duration(seconds: 2)),
        ),
        ChatMessage(
          id: 4,
          sessionId: 1,
          role: 'tool', // Another invalid Gemini role
          textContent: 'tool output',
          timestamp: now.add(const Duration(seconds: 3)),
        ),
        ChatMessage(
          id: 5,
          sessionId: 1,
          role: 'user',
          textContent: 'How are you?',
          timestamp: now.add(const Duration(seconds: 4)),
        ),
        ChatMessage(
          id: 6,
          sessionId: 1,
          role: 'model',
          textContent: 'I am doing well',
          timestamp: now.add(const Duration(seconds: 5)),
        ),
      ];

      final (contents, _) = GeminiChatService.instance.buildHistoryContents(
        messages,
      );

      // Verify no invalid roles exist in the output Content list
      final roles = contents.map((c) => c.role).toList();
      expect(roles.contains('function'), isFalse);
      expect(roles.contains('tool'), isFalse);
      expect(roles.contains('assistant'), isFalse);

      // Verify alternating turns: user -> model -> user -> model
      expect(roles, ['user', 'model', 'user', 'model']);
      expect((contents[1].parts.first as TextPart).text, 'Hi there');
      expect((contents[3].parts.first as TextPart).text, 'I am doing well');
    });

    test('sanitizeErrorMessage strips AIza keys and query parameter keys', () {
      const errorWithKey =
          'GenerativeAIException: Server Error [400]: API key not valid. URL: https://generativelanguage.googleapis.com/v1beta/models/gemini-flash?key=AIzaSyB1234567890abcdefghijklmnopqrstuv&alt=json';

      final sanitized = GeminiChatService.sanitizeErrorMessage(errorWithKey);

      expect(
        sanitized.contains('AIzaSyB1234567890abcdefghijklmnopqrstuv'),
        isFalse,
      );
      expect(sanitized.contains('key=AIza'), isFalse);
      expect(sanitized, contains('[REDACTED_API_KEY]'));
    });
  });

  group('E-17 Routine Generation Request Tests', () {
    test('local fallback responds to 7-day routine request with 3 hours and E-17', () async {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);

      final exam17 = ExamSchedule(
        id: 17,
        examDate: todayStart.add(const Duration(days: 10)),
        examTime: '10:00 PM',
        subject: 'General BCS',
        title: '৪৭তম বিসিএস স্পেশাল টেস্ট ১৭',
        topicsCovered: 'বাংলা ব্যাকরণ, সমাস ও কারক, ইংরেজি সাহিত্য, আন্তর্জাতিক বিষয়াবলি, বাংলাদেশ বিষয়াবলি',
        examType: 'Live MCQ',
        trackName: '47th BCS Sprint',
        completedStatus: false,
        createdAt: now,
      );

      const userPrompt =
          'E-17 পরীক্ষার টপিকগুলো দিয়ে ৭ দিনের পড়ার রুটিন বানাও। প্রতিদিন ৩ ঘণ্টা পড়তে পারব।';

      final response = await GeminiChatService.instance.sendMessage(
        userMessage: userPrompt,
        history: const [],
        upcomingExams: [exam17],
        // No apiKey passed -> forces fallback mode
      );

      // 1. Verify a routinePlan action is returned
      expect(response.actions.length, 1);
      final action = response.actions.first;
      expect(action.type, ChatActionType.routinePlan);

      // 2. Title should reflect 7 days in Bengali
      expect(action.title, contains('৭ দিন'));

      // 3. Routine JSON items must have exactly 7 days
      final routineItems = action.routineItems;
      expect(routineItems.length, 7);

      // 4. Verify dates are sequential starting from tomorrow
      for (var i = 0; i < 7; i++) {
        final expectedDate = todayStart.add(Duration(days: i + 1));
        final expectedDateStr = expectedDate.toIso8601String().substring(0, 10);
        expect(
          routineItems[i].date.toIso8601String().substring(0, 10),
          expectedDateStr,
        );
      }

      // 5. Final day is a Mock Test, earlier days are Study Sessions
      expect(routineItems.last.examType, 'Mock Test');
      expect(routineItems.first.examType, 'Study Session');

      // 6. Text content reflects 7 days and daily 3 hours
      expect(response.text, contains('৭ দিন'));
      expect(response.text, contains('৩ ঘণ্টা'));
      expect(response.text, contains('রুটিন প্রিভিউ'));
    });

    test('referencedItems with E-17 provides syllabus even when upcomingExams list is empty', () async {
      const userPrompt =
          'E-17 পরীক্ষার টপিকগুলো দিয়ে ৭ দিনের পড়ার রুটিন বানাও। প্রতিদিন ৩ ঘণ্টা পড়তে পারব।';

      const referencedSyllabus = '''
REFERENCED ITEMS — the user pasted short tags that name exact saved rows in this app.
E-17 — scheduled exam: ৪৭তম বিসিএস স্পেশাল টেস্ট ১৭
  তারিখ: 2026-11-10 10:00 PM · ট্র্যাক: 47th BCS Sprint
  বিষয়: General BCS · সিলেবাস: সমাস, কারক, উপসর্গ, উপসর্গ ও প্রত্যয়
''';

      final response = await GeminiChatService.instance.sendMessage(
        userMessage: userPrompt,
        history: const [],
        referencedItems: referencedSyllabus,
        upcomingExams: const [], // Empty upcoming exams
      );

      expect(response.actions.length, 1);
      final action = response.actions.first;
      expect(action.type, ChatActionType.routinePlan);

      final items = action.routineItems;
      expect(items.length, 7);
      expect(action.trackName, '47th BCS Sprint');
      expect(action.subject, 'General BCS');

      // Verify that syllabus topics were used
      final allTopics = items.expand((it) => it.topics).toList();
      expect(
        allTopics.any((t) => t.contains('সমাস') || t.contains('কারক')),
        isTrue,
      );
    });

    test('error diagnosis redacts sensitive API key when reporting tech error in Bengali', () async {
      SharedPreferences.setMockInitialValues({
        'gemini_api_key': 'AIzaSyFakeKey1234567890abcdefghijklmnop',
      });

      const userPrompt = 'সহজভাবে সমাস ব্যাখ্যা করো';

      final response = await GeminiChatService.instance.sendMessage(
        userMessage: userPrompt,
        history: const [],
      );

      // Verify the response contains diagnosis
      expect(response.text, contains('API সংযোগে সমস্যা হয়েছে'));

      // Verify the secret key is NOT leaked into the diagnostic text
      expect(
        response.text.contains('AIzaSyFakeKey1234567890abcdefghijklmnop'),
        isFalse,
      );
    });
  });
}
