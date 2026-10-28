import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/database/database_provider.dart';
import 'package:life_and_study_assistant/core/services/ai/entity_ref.dart';
import 'package:life_and_study_assistant/core/services/ai/entity_ref_resolver.dart';
import 'package:life_and_study_assistant/core/services/ai/models/parsed_routine_item.dart';
import 'package:life_and_study_assistant/core/services/ai/routine_parser_service.dart';
import 'package:life_and_study_assistant/features/chat/domain/models/chat_action.dart';
import 'package:life_and_study_assistant/features/chat/presentation/providers/chat_provider.dart';
import 'package:life_and_study_assistant/features/chat/presentation/screens/ai_chat_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);
  final day1 = todayStart.add(const Duration(days: 1));
  final day2 = todayStart.add(const Duration(days: 2));
  final day3 = todayStart.add(const Duration(days: 3));

  group('ChatAction ROUTINE_PLAN Extraction & Validation Tests', () {
    test(
      'extracts block-style ROUTINE_PLAN_BEGIN ... ROUTINE_PLAN_END correctly',
      () {
        final rawReply =
            '''
এখানে আপনার জন্য ৩ দিনের স্টাডি রুটিন দেওয়া হলো:
* দিন ১: প্রাচীন বাংলা
* দিন ২: মধ্যযুগীয় বাংলা
* দিন ৩: মুক্তিযুদ্ধ

[[ACTION:ROUTINE_PLAN_BEGIN]]
{
  "title": "৩ দিনের স্পেশাল ক্র্যাশ কোর্স",
  "subject": "Bangladesh Affairs",
  "track": "47th BCS Sprint",
  "items": [
    {
      "date": "${day1.toIso8601String().substring(0, 10)}",
      "exam_time": "10:00 PM",
      "subject": "Bangladesh Affairs",
      "title": "Day 1: প্রাচীন বাংলার ইতিহাস",
      "topics": ["প্রাচীন বাংলা", "জনপদ"],
      "exam_type": "Study Session"
    },
    {
      "date": "${day2.toIso8601String().substring(0, 10)}",
      "exam_time": "10:00 PM",
      "subject": "Bangladesh Affairs",
      "title": "Day 2: মধ্যযুগীয় বাংলা ও সুলতানি আমল",
      "topics": ["সুলতানি আমল", "মুঘল সুবা"],
      "exam_type": "Study Session"
    },
    {
      "date": "${day3.toIso8601String().substring(0, 10)}",
      "exam_time": "10:00 PM",
      "subject": "Bangladesh Affairs",
      "title": "Day 3: মুক্তিযুদ্ধ ও সংবিধান (মক টেস্ট)",
      "topics": ["মুক্তিযুদ্ধ", "সংবিধান"],
      "exam_type": "Mock Test"
    }
  ]
}
[[ACTION:ROUTINE_PLAN_END]]
''';

        final actions = ChatAction.extractActions(rawReply);
        expect(actions.length, 1);

        final action = actions.first;
        expect(action.type, ChatActionType.routinePlan);
        expect(action.title, '৩ দিনের স্পেশাল ক্র্যাশ কোর্স (৩ দিন)');
        expect(action.subject, 'Bangladesh Affairs');
        expect(action.trackName, '47th BCS Sprint');

        final items = action.routineItems;
        expect(items.length, 3);
        expect(items[0].title, 'Day 1: প্রাচীন বাংলার ইতিহাস');
        expect(items[0].examType, 'Study Session');
        expect(items[0].topics, ['প্রাচীন বাংলা', 'জনপদ']);
        expect(items[2].title, 'Day 3: মুক্তিযুদ্ধ ও সংবিধান (মক টেস্ট)');
        expect(items[2].examType, 'Mock Test');

        // Verify cleanActionTags removes the JSON block completely
        final clean = ChatAction.cleanActionTags(rawReply);
        expect(clean.contains('ROUTINE_PLAN'), isFalse);
        expect(clean.contains('Day 1: প্রাচীন বাংলা'), isFalse);
        expect(clean.contains('এখানে আপনার জন্য ৩ দিনের স্টাডি রুটিন'), isTrue);
      },
    );

    test('extracts single-line fallback ROUTINE_PLAN|... correctly', () {
      final rawReply =
          '''
[[ACTION:ROUTINE_PLAN|General BCS|{"title":"২ দিনের রিভিশন","items":[{"date":"${day1.toIso8601String().substring(0, 10)}","title":"Day 1","subject":"Bangla","topics":["সমাস"],"exam_type":"Study Session"},{"date":"${day2.toIso8601String().substring(0, 10)}","title":"Day 2","subject":"Bangla","topics":["কারক"],"exam_type":"Revision"}]}]]
''';

      final actions = ChatAction.extractActions(rawReply);
      expect(actions.length, 1);
      expect(actions.first.type, ChatActionType.routinePlan);
      expect(actions.first.routineItems.length, 2);
      expect(actions.first.trackName, 'General BCS');
    });

    test('rejects items with dates in the distant past (>1 day ago)', () {
      final pastDate = todayStart.subtract(const Duration(days: 10));
      final rawReply =
          '''
[[ACTION:ROUTINE_PLAN_BEGIN]]
{
  "title": "Expired Plan",
  "items": [
    {
      "date": "${pastDate.toIso8601String().substring(0, 10)}",
      "title": "Old Task",
      "subject": "Bangla",
      "topics": ["Old Topic"]
    }
  ]
}
[[ACTION:ROUTINE_PLAN_END]]
''';

      final actions = ChatAction.extractActions(rawReply);
      expect(actions, isEmpty);
    });

    test('rejects malformed or non-JSON payloads safely without crashing', () {
      const rawReply = '''
[[ACTION:ROUTINE_PLAN_BEGIN]]
This is not valid JSON at all: {foo: bar, [}
[[ACTION:ROUTINE_PLAN_END]]
''';

      final actions = ChatAction.extractActions(rawReply);
      expect(actions, isEmpty);
    });
  });

  group('Database & Execution Tests for Routine Plan', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.delete(db.examSchedules).go();
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'executing ChatActionType.routinePlan saves items with deduplication',
      () async {
        final items = [
          ParsedRoutineItem(
            date: day1,
            examTime: '10:00 PM',
            subject: 'Bangla',
            title: 'Day 1: সমাস প্রস্তুতি',
            topics: ['সমাস', 'দ্বিগু'],
            examType: 'Study Session',
            trackName: 'BCS 10-Day Sprint',
            rawReference: 'AI Mentor Plan',
          ),
          ParsedRoutineItem(
            date: day2,
            examTime: '10:00 PM',
            subject: 'Bangla',
            title: 'Day 2: কারক প্রস্তুতি',
            topics: ['কারক', 'বিভক্তি'],
            examType: 'Study Session',
            trackName: 'BCS 10-Day Sprint',
            rawReference: 'AI Mentor Plan',
          ),
        ];

        // Save via RoutineParserService
        final result1 = await RoutineParserService.instance
            .saveParsedRoutinesToDatabase(
              db,
              items,
              overrideTrack: 'BCS 10-Day Sprint',
            );

        expect(result1.insertedCount, 2);
        expect(result1.skippedCount, 0);

        // Verify database rows
        final savedRows = await db.select(db.examSchedules).get();
        expect(savedRows.length, 2);
        expect(savedRows[0].title, 'Day 1: সমাস প্রস্তুতি');
        expect(savedRows[0].examType, 'Study Session');
        expect(savedRows[0].resourceSummary, 'AI Mentor Plan');

        // Attempt second duplicate insert
        final result2 = await RoutineParserService.instance
            .saveParsedRoutinesToDatabase(
              db,
              items,
              overrideTrack: 'BCS 10-Day Sprint',
            );

        expect(result2.insertedCount, 0);
        expect(result2.skippedCount, 2);
      },
    );

    test('ChatNotifier.executeAction prevents duplicate execution', () async {
      // Seed a chat session and message
      final sessionId = await db
          .into(db.chatSessions)
          .insert(ChatSessionsCompanion.insert(title: 'Test Routine Session'));

      final action = ChatAction(
        type: ChatActionType.routinePlan,
        title: '৩ দিনের প্ল্যান (৩ দিন)',
        subject: 'General BCS',
        trackName: 'Test Track',
        routineJson: jsonEncode({
          'items': [
            {
              'date': day1.toIso8601String().substring(0, 10),
              'title': 'Day 1 Task',
              'subject': 'General BCS',
              'topics': ['Topic 1'],
              'exam_type': 'Study Session',
            },
          ],
        }),
      );

      final messageId = await db
          .into(db.chatMessages)
          .insert(
            ChatMessagesCompanion.insert(
              sessionId: Value(sessionId),
              role: 'model',
              textContent: 'Here is your routine',
              suggestedAction: Value(ChatAction.encodeList([action])),
            ),
          );

      final message = (await (db.select(
        db.chatMessages,
      )..where((t) => t.id.equals(messageId))).getSingle());

      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(chatNotifierProvider.notifier);

      // First execution succeeds
      final ok1 = await notifier.executeAction(
        action: action,
        message: message,
      );
      expect(ok1, isTrue);

      // Verify executed flag written to DB
      final updatedMsg = (await (db.select(
        db.chatMessages,
      )..where((t) => t.id.equals(messageId))).getSingle());
      final updatedActions = ChatAction.decodeList(updatedMsg.suggestedAction);
      expect(updatedActions.first.isExecuted, isTrue);

      // Second execution on already-executed action must return false
      final ok2 = await notifier.executeAction(
        action: updatedActions.first,
        message: updatedMsg,
      );
      expect(ok2, isFalse);
    });

    test(
      'E-{id} exam resolution provides accurate data for plan generation',
      () async {
        final examId = await db
            .into(db.examSchedules)
            .insert(
              ExamSchedulesCompanion.insert(
                examDate: day3,
                examTime: const Value('10:00 PM'),
                subject: const Value('Bangladesh Affairs'),
                title: '৪৭তম বিসিএস মডেল টেস্ট ০১',
                topicsCovered: 'বাংলাদেশের সংবিধান, মুক্তিযুদ্ধ, নদ-নদী',
                trackName: const Value('47th BCS'),
              ),
            );

        // Resolve E-{id}
        final tag = EntityRef(EntityKind.exam, examId).tag;
        final desc = await EntityRefResolver.describe(
          db,
          'এই $tag পরীক্ষার জন্য রুটিন বানাও',
        );

        expect(desc, isNotNull);
        expect(desc!.contains(tag), isTrue);
        expect(desc.contains('৪৭তম বিসিএস মডেল টেস্ট ০১'), isTrue);
        expect(desc.contains('বাংলাদেশের সংবিধান'), isTrue);
        expect(desc.contains('47th BCS'), isTrue);
      },
    );
  });

  group('Widget Action Card & RoutinePreviewSheet Integration Tests', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.delete(db.examSchedules).go();
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets('renders Routine Plan card and opens preview sheet', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final defaultSession = await db.getOrCreateDefaultSession();
      final sessionId = defaultSession.id;

      final planAction = ChatAction(
        type: ChatActionType.routinePlan,
        title: '৫ দিনের স্পেশাল রিভিশন (৫ দিন)',
        subject: 'Bangla',
        trackName: 'Bangla Sprint',
        routineJson: jsonEncode({
          'items': [
            {
              'date': day1.toIso8601String().substring(0, 10),
              'title': 'Day 1: সমাস প্রস্তুতি',
              'subject': 'Bangla',
              'topics': ['সমাস'],
              'exam_type': 'Study Session',
            },
            {
              'date': day2.toIso8601String().substring(0, 10),
              'title': 'Day 2: কারক প্রস্তুতি',
              'subject': 'Bangla',
              'topics': ['কারক'],
              'exam_type': 'Study Session',
            },
          ],
        }),
      );

      final messagesController =
          StreamController<List<ChatMessage>>.broadcast();
      addTearDown(messagesController.close);

      final message = ChatMessage(
        id: 1,
        sessionId: sessionId,
        role: 'model',
        textContent: 'আপনার জন্য ৫ দিনের রিভিশন রুটিন প্রস্তুত:',
        suggestedAction: ChatAction.encodeList([planAction]),
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            chatSessionsStreamProvider.overrideWith(
              (ref) => Stream.value([defaultSession]),
            ),
            chatMessagesStreamProvider.overrideWith(
              (ref) => messagesController.stream,
            ),
          ],
          child: const MaterialApp(home: AiChatScreen()),
        ),
      );

      messagesController.add([message]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify the action card is rendered with title and preview button
      expect(find.text('৫ দিনের স্পেশাল রিভিশন (৫ দিন)'), findsOneWidget);
      expect(find.text('রুটিন প্রিভিউ'), findsOneWidget);
      expect(find.byIcon(Icons.calendar_month), findsOneWidget);

      // Tap on 'রুটিন প্রিভিউ'
      await tester.tap(find.text('রুটিন প্রিভিউ'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify RoutinePreviewSheet opened with items
      expect(find.text('Day 1: সমাস প্রস্তুতি'), findsOneWidget);
      expect(find.text('Day 2: কারক প্রস্তুতি'), findsOneWidget);
      expect(find.text('২টি সেশন যোগ করুন'), findsOneWidget);

      // Confirm by tapping '২টি সেশন যোগ করুন'
      await tester.tap(find.text('২টি সেশন যোগ করুন'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify saved in DB
      final savedExams = await db.select(db.examSchedules).get();
      expect(savedExams.length, 2);
      expect(savedExams[0].title, 'Day 1: সমাস প্রস্তুতি');
      expect(savedExams[0].examType, 'Study Session');

      // Update stream with executed message
      messagesController.add([
        message.copyWith(
          suggestedAction: Value(
            ChatAction.encodeList([planAction.copyWith(isExecuted: true)]),
          ),
        ),
      ]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify card reflects updated state 'সংরক্ষিত'
      expect(find.text('সংরক্ষিত'), findsOneWidget);

      // Settle SnackBar timer so no timers remain pending
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets(
      'renders studyTask action card with quiz button and opens quiz modal',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final defaultSession = await db.getOrCreateDefaultSession();
        final sessionId = defaultSession.id;

        const taskAction = ChatAction(
          type: ChatActionType.studyTask,
          title: '১৫টি সমাস প্র্যাকটিস MCQ',
          subject: 'বাংলা ব্যাকরণ',
          topic: 'সমাস',
          minutes: 15,
        );

        final messagesController =
            StreamController<List<ChatMessage>>.broadcast();
        addTearDown(messagesController.close);

        final message = ChatMessage(
          id: 1,
          sessionId: sessionId,
          role: 'model',
          textContent: 'আপনার জন্য কুইজ প্র্যাকটিস প্রস্তুত:',
          suggestedAction: ChatAction.encodeList([taskAction]),
          timestamp: DateTime.now(),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              chatSessionsStreamProvider.overrideWith(
                (ref) => Stream.value([defaultSession]),
              ),
              chatMessagesStreamProvider.overrideWith(
                (ref) => messagesController.stream,
              ),
            ],
            child: const MaterialApp(home: AiChatScreen()),
          ),
        );

        messagesController.add([message]);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Verify action card renders with 'কুইজ শুরু' and quiz icon
        expect(find.text('১৫টি সমাস প্র্যাকটিস MCQ'), findsOneWidget);
        expect(find.text('কুইজ শুরু'), findsOneWidget);
        expect(find.byIcon(Icons.quiz_outlined), findsOneWidget);

        // Tap on 'কুইজ শুরু'
        await tester.tap(find.text('কুইজ শুরু'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Clean up widget tree
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 100));
      },
    );
  });
}
