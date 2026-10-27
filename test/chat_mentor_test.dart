import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/services/ai/chat_context_resolver.dart';
import 'package:life_and_study_assistant/core/services/ai/chat_context_tools.dart';
import 'package:life_and_study_assistant/core/services/ai/gemini_prompts.dart';
import 'package:life_and_study_assistant/core/services/ai/gemini_chat_service.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:life_and_study_assistant/core/database/tables/weak_topics_table.dart';
import 'package:life_and_study_assistant/features/chat/domain/models/chat_action.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('ChatAction Model & Tag Extraction Tests', () {
    test('Extracts ADD_TOPIC and STUDY_TASK action tags properly', () {
      const rawResponse = '''
এখানে সমাস বিষয়ে বিশদ ব্যাখ্যা দেওয়া হলো:
* দ্বন্দ্ব সমাস: মা-বাবা
* কর্মধারয় সমাস: নীলপদ্ম

[[ACTION:ADD_TOPIC|বাংলা ব্যাকরণ|সমাস|weak]]
[[ACTION:STUDY_TASK|১০টি সমাস MCQ প্র্যাকটিস|বাংলা ব্যাকরণ|10]]
''';

      final actions = ChatAction.extractActions(rawResponse);
      expect(actions.length, 2);

      expect(actions[0].type, ChatActionType.addTopic);
      expect(actions[0].subject, 'বাংলা ব্যাকরণ');
      expect(actions[0].topic, 'সমাস');
      expect(actions[0].proficiency, 'weak');

      expect(actions[1].type, ChatActionType.studyTask);
      expect(actions[1].title, '১০টি সমাস MCQ প্র্যাকটিস');
      expect(actions[1].minutes, 10);

      final cleanText = ChatAction.cleanActionTags(rawResponse);
      expect(cleanText.contains('[[ACTION:'), isFalse);
      expect(cleanText.contains('নীলপদ্ম'), isTrue);
    });

    test('Serializes and deserializes ChatAction list to JSON', () {
      final actions = [
        const ChatAction(
          type: ChatActionType.addTopic,
          title: 'Add "কারক ও বিভক্তি"',
          subject: 'Bangla Grammar',
          topic: 'কারক ও বিভক্তি',
          proficiency: 'weak',
        ),
      ];

      final jsonStr = ChatAction.encodeList(actions);
      expect(jsonStr, isNotNull);

      final decoded = ChatAction.decodeList(jsonStr);
      expect(decoded.length, 1);
      expect(decoded.first.topic, 'কারক ও বিভক্তি');
      expect(decoded.first.isExecuted, isFalse);
    });
  });

  group('Gemini Chat Prompts & Context Builder Tests', () {
    test('buildChatSystemInstruction embeds user fatigue and weak topics', () {
      final prompt = GeminiPrompts.buildChatSystemInstruction(
        energyLevel: 'Low',
        fatigueScore: 8,
        weakTopics: [
          {'subject': 'গণিত', 'topic': 'শতকরা', 'proficiency': 'weak'},
        ],
        upcomingExams: [
          {
            'title': '47th BCS Final',
            'examDate': '2026-11-01',
            'topics': 'বাংলা ও সাধারণ জ্ঞান',
          },
        ],
      );

      expect(prompt.contains('Energy Level: Low'), isTrue);
      expect(prompt.contains('Fatigue Score: 8/10'), isTrue);
      expect(prompt.contains('শতকরা'), isTrue);
      expect(prompt.contains('47th BCS Final'), isTrue);
      expect(prompt.contains('[[ACTION:ADD_TOPIC'), isTrue);
    });

    test(
      'GeminiChatService local fallback returns empathetic advice on fatigue',
      () {
        final response = GeminiChatService.instance.sendMessage(
          userMessage: 'আজকে অফিস শেষে অনেক ক্লান্ত, কী পড়া যায়?',
          history: [],
          energyLevel: 'Low',
          fatigueScore: 9,
        );

        expect(response, completes);
      },
    );
  });

  group('Prompt Prefix Stability Tests', () {
    test('static instruction comes first and volatile context comes last', () {
      String build(String energy, List<Map<String, dynamic>> topics) =>
          GeminiPrompts.buildChatSystemInstruction(
            energyLevel: energy,
            fatigueScore: 4,
            weakTopics: topics,
          );

      final a = build('High', [
        {'subject': 'গণিত', 'topic': 'শতকরা', 'proficiency': 'weak'},
      ]);
      final b = build('Low', [
        {'subject': 'বাংলা', 'topic': 'সমাস', 'proficiency': 'moderate'},
      ]);

      // Everything before the context marker must be byte-identical, so a
      // change in context cannot invalidate the shared prompt prefix.
      final prefixA = a.substring(0, a.indexOf('--- CURRENT USER CONTEXT ---'));
      final prefixB = b.substring(0, b.indexOf('--- CURRENT USER CONTEXT ---'));
      expect(prefixA, prefixB);
      expect(prefixA, GeminiPrompts.chatStaticInstruction);

      // The expensive static rules must sit inside that stable prefix.
      expect(prefixA.contains('[[ACTION:ADD_TOPIC'), isTrue);
      expect(prefixA.contains('OUTPUT FORMAT'), isTrue);

      // Volatile values must only appear after the marker.
      expect(
        a.indexOf('শতকরা'),
        greaterThan(a.indexOf('--- CURRENT USER CONTEXT ---')),
      );
    });
  });

  group('Chat History Window Tests', () {
    ChatMessage msg(int id, String role, String text) => ChatMessage(
      id: id,
      sessionId: 1,
      role: role,
      textContent: text,
      timestamp: DateTime(2026, 1, 1).add(Duration(minutes: id)),
    );

    String textOf(Content c) => (c.parts.first as TextPart).text;

    test('alternating history passes through untouched', () {
      final (contents, carried) = GeminiChatService.instance
          .buildHistoryContents([
            msg(1, 'user', 'প্রশ্ন ১'),
            msg(2, 'model', 'উত্তর ১'),
          ]);

      expect(carried, isNull);
      expect(contents.length, 2);
      expect(contents.first.role, 'user');
      expect(textOf(contents.last), 'উত্তর ১');
    });

    test('orphan trailing user message is carried over, not dropped', () {
      // Happens when a send fails after the user message was persisted.
      final (contents, carried) = GeminiChatService.instance
          .buildHistoryContents([
            msg(1, 'user', 'প্রশ্ন ১'),
            msg(2, 'model', 'উত্তর ১'),
            msg(3, 'user', 'হারিয়ে যাওয়া প্রশ্ন'),
          ]);

      expect(contents.length, 2);
      expect(contents.last.role, 'model');
      expect(carried, 'হারিয়ে যাওয়া প্রশ্ন');
    });

    test('consecutive same-role messages are merged rather than discarded', () {
      final (contents, carried) = GeminiChatService.instance
          .buildHistoryContents([
            msg(1, 'user', 'প্রথম অংশ'),
            msg(2, 'user', 'দ্বিতীয় অংশ'),
            msg(3, 'model', 'উত্তর'),
          ]);

      expect(carried, isNull);
      expect(contents.length, 2);
      expect(textOf(contents.first).contains('প্রথম অংশ'), isTrue);
      expect(textOf(contents.first).contains('দ্বিতীয় অংশ'), isTrue);
    });

    test('leading model turn is dropped so history starts with user', () {
      final (contents, _) = GeminiChatService.instance.buildHistoryContents([
        msg(1, 'model', 'অনাথ উত্তর'),
        msg(2, 'user', 'প্রশ্ন'),
        msg(3, 'model', 'উত্তর'),
      ]);

      expect(contents.first.role, 'user');
      expect(contents.length, 2);
    });

    test('older model replies are condensed, recent ones kept verbatim', () {
      final longReply = 'ক' * 2000;
      final messages = <ChatMessage>[];
      for (var i = 0; i < 10; i++) {
        messages.add(msg(i * 2 + 1, 'user', 'প্রশ্ন $i'));
        messages.add(msg(i * 2 + 2, 'model', longReply));
      }

      final (contents, _) = GeminiChatService.instance.buildHistoryContents(
        messages,
      );

      final modelTexts = contents
          .where((c) => c.role == 'model')
          .map((c) => (c.parts.first as TextPart).text)
          .toList();

      // The newest model reply survives intact...
      expect(modelTexts.last.length, 2000);
      // ...older ones are reduced.
      expect(
        modelTexts.first.length,
        lessThan(GeminiChatService.olderModelTurnCharLimit + 50),
      );
      expect(modelTexts.first.contains('সংক্ষেপিত'), isTrue);
    });

    test('history is capped at maxHistoryMessages', () {
      final many = List.generate(
        40,
        (i) => msg(i + 1, i.isEven ? 'user' : 'model', 'বার্তা $i'),
      );

      final (contents, _) = GeminiChatService.instance.buildHistoryContents(
        many,
      );

      expect(
        contents.length,
        lessThanOrEqualTo(GeminiChatService.maxHistoryMessages),
      );
    });
  });

  group('AI Context Cap Tests', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('getContextUpcomingExams caps a bulk-imported routine', () async {
      await db.delete(db.examSchedules).go();

      // Simulate a 135-day routine import.
      for (var i = 1; i <= 120; i++) {
        await db
            .into(db.examSchedules)
            .insert(
              ExamSchedulesCompanion.insert(
                title: 'Day $i Exam',
                examDate: DateTime.now().add(Duration(days: i)),
                topicsCovered: 'Topic set $i with a fairly long description',
                trackName: const Value('135-Day Routine'),
              ),
            );
      }

      final capped = await db.getContextUpcomingExams();
      expect(capped.length, lessThanOrEqualTo(5));

      // And all of them are actually imminent.
      final horizon = DateTime.now().add(const Duration(days: 21));
      expect(capped.every((e) => e.examDate.isBefore(horizon)), isTrue);
    });

    test(
      'getContextWeakTopics excludes mastered topics and caps the list',
      () async {
        for (var i = 0; i < 20; i++) {
          await db.insertWeakTopic(
            WeakTopicsCompanion.insert(
              subject: 'বাংলা',
              topicName: 'দুর্বল টপিক $i',
              proficiencyLevel: ProficiencyLevel.weak,
            ),
          );
        }
        await db.insertWeakTopic(
          WeakTopicsCompanion.insert(
            subject: 'বাংলা',
            topicName: 'মাস্টার করা টপিক',
            proficiencyLevel: ProficiencyLevel.strong,
          ),
        );

        final context = await db.getContextWeakTopics();

        expect(context.length, lessThanOrEqualTo(10));
        expect(
          context.any((t) => t.proficiencyLevel == ProficiencyLevel.strong),
          isFalse,
        );
      },
    );
  });

  group('Context Relevance Gating Tests', () {
    test('a plain teaching question needs no stored context at all', () {
      final needs = ChatContextResolver.resolve(
        userMessage: 'সমাস কাকে বলে একটু বুঝিয়ে দাও',
      );

      expect(needs.isEmpty, isTrue);
    });

    test('a planning question needs every slice', () {
      final needs = ChatContextResolver.resolve(
        userMessage: 'আজকে কী পড়ব একটু প্ল্যান করে দাও',
      );

      expect(needs.energy, isTrue);
      expect(needs.weakTopics, isTrue);
      expect(needs.exams, isTrue);
    });

    test('an exam question pulls exams but not the weak topic list', () {
      final needs = ChatContextResolver.resolve(
        userMessage: 'আমার পরবর্তী পরীক্ষা কবে?',
      );

      expect(needs.exams, isTrue);
      expect(needs.weakTopics, isFalse);
    });

    test('high fatigue forces energy context into a teaching question', () {
      final needs = ChatContextResolver.resolve(
        userMessage: 'সমাস বুঝিয়ে দাও',
        fatigueScore: 9,
      );

      expect(needs.energy, isTrue);
      expect(needs.forcedBySafety, isTrue);
    });

    test('an imminent exam forces exam context in whatever was asked', () {
      final needs = ChatContextResolver.resolve(
        userMessage: 'সমাস বুঝিয়ে দাও',
        daysToNextExam: 2,
      );

      expect(needs.exams, isTrue);
      expect(needs.forcedBySafety, isTrue);
    });

    test('a distant exam does not force exam context', () {
      final needs = ChatContextResolver.resolve(
        userMessage: 'সমাস বুঝিয়ে দাও',
        daysToNextExam: 40,
      );

      expect(needs.exams, isFalse);
    });

    test('the first message of a session gets the full baseline', () {
      final needs = ChatContextResolver.resolve(
        userMessage: 'সমাস বুঝিয়ে দাও',
        isFirstMessageInSession: true,
      );

      expect(needs.energy, isTrue);
      expect(needs.weakTopics, isTrue);
      expect(needs.exams, isTrue);
    });

    test('naming a stored subject narrows weak topics to that subject', () {
      final needs = ChatContextResolver.resolve(
        userMessage: 'আমার বাংলা ব্যাকরণ কেমন চলছে, দুর্বল কোথায়?',
        knownSubjects: const ['বাংলা ব্যাকরণ', 'গণিত', 'English'],
      );

      expect(needs.weakTopics, isTrue);
      expect(needs.subjectFilter, 'বাংলা ব্যাকরণ');
    });
  });

  group('Prompt Size Tests', () {
    List<Map<String, dynamic>> bulkExams(int n) => List.generate(
      n,
      (i) => {
        'title': 'Day ${i + 1} Daily Vocabulary Booster Exam',
        'track': '52nd BCS 135-Day Syllabus Routine',
        'examDate': '2026-11-01',
        'daysAway': i + 1,
        'topics':
            'Synonyms, Antonyms, Prepositions, Idioms and Phrases, One word substitution, Spelling corrections for unit ${i + 1}',
      },
    );

    List<Map<String, dynamic>> bulkTopics(int n) => List.generate(
      n,
      (i) => {
        'subject': 'বাংলা ব্যাকরণ',
        'topic': 'দুর্বল টপিক ${i + 1}',
        'proficiency': 'weak',
      },
    );

    test('a teaching question sends only the stable static prefix', () {
      final prompt = GeminiPrompts.buildChatSystemInstruction(
        energyLevel: 'Moderate',
        fatigueScore: 4,
        weakTopics: bulkTopics(10),
        upcomingExams: bulkExams(5),
        needs: const ChatContextNeeds(),
      );

      expect(prompt, GeminiPrompts.chatStaticInstruction);
    });

    test('gating and capping shrink a realistic worst-case prompt', () {
      // What the mentor used to carry on *every* message once a 135-day
      // routine had been imported.
      final ungated = GeminiPrompts.buildChatSystemInstruction(
        energyLevel: 'Low',
        fatigueScore: 6,
        weakTopics: bulkTopics(25),
        upcomingExams: bulkExams(120),
      );

      // What a plain teaching question carries now.
      final gated = GeminiPrompts.buildChatSystemInstruction(
        energyLevel: 'Low',
        fatigueScore: 6,
        weakTopics: bulkTopics(10),
        upcomingExams: bulkExams(5),
        needs: const ChatContextNeeds(),
      );

      // And what a planning question — the heaviest legitimate case — carries.
      final planning = GeminiPrompts.buildChatSystemInstruction(
        energyLevel: 'Low',
        fatigueScore: 6,
        weakTopics: bulkTopics(10),
        upcomingExams: bulkExams(5),
        needs: const ChatContextNeeds(
          energy: true,
          weakTopics: true,
          exams: true,
        ),
      );

      // ignore: avoid_print
      print(
        'prompt chars — ungated: ${ungated.length}, '
        'planning: ${planning.length}, teaching: ${gated.length}',
      );

      expect(gated.length, lessThan(ungated.length ~/ 8));
      expect(planning.length, lessThan(ungated.length ~/ 3));
    });

    test('long exam topic strings are truncated, not pasted whole', () {
      final prompt = GeminiPrompts.buildChatSystemInstruction(
        upcomingExams: [
          {
            'title': 'Mega Model Test',
            'examDate': '2026-11-01',
            'daysAway': 2,
            'topics': 'অধ্যায় ' * 200,
          },
        ],
        needs: const ChatContextNeeds(exams: true),
      );

      expect(prompt.contains('…'), isTrue);
      expect(
        prompt.length,
        lessThan(GeminiPrompts.chatStaticInstruction.length + 400),
      );
    });

    test('relative exam timing replaces raw dates', () {
      final prompt = GeminiPrompts.buildChatSystemInstruction(
        upcomingExams: [
          {
            'title': 'Prelim',
            'examDate': '2026-11-01',
            'daysAway': 1,
            'topics': '',
          },
        ],
        needs: const ChatContextNeeds(exams: true),
      );

      expect(prompt.contains('tomorrow'), isTrue);
      expect(prompt.contains('2026-11-01'), isFalse);
    });
  });

  group('On-Demand Context Tool Tests', () {
    final data = ChatContextData(
      weakTopics: const [
        {'subject': 'বাংলা ব্যাকরণ', 'topic': 'সমাস', 'proficiency': 'weak'},
        {'subject': 'গণিত', 'topic': 'শতকরা', 'proficiency': 'moderate'},
      ],
      exams: const [
        {
          'title': 'Vocabulary Booster',
          'track': 'Daily',
          'daysAway': 2,
          'topics': 'Synonyms, Antonyms',
        },
        {
          'title': 'Mega Model Test',
          'track': 'Friday',
          'daysAway': 45,
          'topics':
              'Full syllabus coverage across every single subject '
              'including Bangla, English, Maths, Science, ICT and more detail '
              'than any prompt should ever carry inline at once',
        },
      ],
      energyLevel: 'Low',
      fatigueScore: 8,
      isOffDay: false,
    );

    test('nothing is declared when every slice is already in the prompt', () {
      final tool = ChatContextToolset.declarationsFor(
        const ChatContextNeeds(energy: true, weakTopics: true, exams: true),
        data,
      );

      expect(tool, isNull);
    });

    test('only the omitted slices are declared', () {
      final tool = ChatContextToolset.declarationsFor(
        const ChatContextNeeds(energy: true),
        data,
      );

      final names = tool!.functionDeclarations!.map((d) => d.name).toSet();
      expect(names, {
        ChatContextToolset.getWeakTopics,
        ChatContextToolset.getUpcomingExams,
      });
      expect(names.contains(ChatContextToolset.getEnergyStatus), isFalse);
    });

    test('a slice with no data behind it is not declared', () {
      final tool = ChatContextToolset.declarationsFor(
        const ChatContextNeeds(energy: true),
        const ChatContextData(),
      );

      expect(tool, isNull);
    });

    test('get_weak_topics narrows to the requested subject', () {
      final result = ChatContextToolset.resolve(
        FunctionCall(ChatContextToolset.getWeakTopics, {'subject': 'গণিত'}),
        data,
      );

      expect(result['count'], 1);
      final topics = result['topics'] as List;
      expect((topics.first as Map)['topic'], 'শতকরা');
    });

    test('get_weak_topics returns everything when no subject is given', () {
      final result = ChatContextToolset.resolve(
        FunctionCall(ChatContextToolset.getWeakTopics, const {}),
        data,
      );

      expect(result['count'], 2);
    });

    test('get_upcoming_exams honours within_days and truncates topics', () {
      final near = ChatContextToolset.resolve(
        FunctionCall(ChatContextToolset.getUpcomingExams, {'within_days': 7}),
        data,
      );
      expect(near['count'], 1);

      final all = ChatContextToolset.resolve(
        FunctionCall(ChatContextToolset.getUpcomingExams, {'within_days': 90}),
        data,
      );
      expect(all['count'], 2);

      final exams = all['exams'] as List;
      final longOne = exams.last as Map;
      expect(
        (longOne['topics'] as String).length,
        lessThanOrEqualTo(ChatContextToolset.topicsCharLimit + 1),
      );
    });

    test('get_energy_status reports the stored figures', () {
      final result = ChatContextToolset.resolve(
        FunctionCall(ChatContextToolset.getEnergyStatus, const {}),
        data,
      );

      expect(result['energyLevel'], 'Low');
      expect(result['officeFatigueScore'], 8);
      expect(result['isOffDay'], false);
    });

    test('an unknown function name returns an error rather than throwing', () {
      final result = ChatContextToolset.resolve(
        FunctionCall('delete_everything', const {}),
        data,
      );

      expect(result['error'], contains('delete_everything'));
    });
  });

  group('Thread Memory Tests', () {
    test('the summary rides along even when every slice is gated off', () {
      final prompt = GeminiPrompts.buildChatSystemInstruction(
        threadSummary:
            '- সমাস-এর ৬ প্রকার আলোচনা হয়েছে\n- user উপপদ তৎপুরুষে আটকায়',
        needs: const ChatContextNeeds(),
      );

      // Not gated: without it a long thread has no memory at all.
      expect(prompt.contains('EARLIER IN THIS THREAD'), isTrue);
      expect(prompt.contains('উপপদ তৎপুরুষে আটকায়'), isTrue);
    });

    test('no summary means no wasted header', () {
      final prompt = GeminiPrompts.buildChatSystemInstruction(
        needs: const ChatContextNeeds(),
      );

      expect(prompt, GeminiPrompts.chatStaticInstruction);
    });

    test('the summary sits after the stable prefix, not inside it', () {
      final prompt = GeminiPrompts.buildChatSystemInstruction(
        threadSummary: 'MEMORY-MARKER',
        needs: const ChatContextNeeds(),
      );

      expect(
        prompt.indexOf('MEMORY-MARKER'),
        greaterThan(prompt.indexOf('--- CURRENT USER CONTEXT ---')),
      );
    });

    group('persistence', () {
      late AppDatabase db;

      setUp(() {
        db = AppDatabase(NativeDatabase.memory());
      });

      tearDown(() async {
        await db.close();
      });

      test('a summary persists against its session with a watermark', () async {
        final session = await db.createChatSession(title: 'সমাস thread');

        await db.updateChatSessionSummary(
          session,
          summary: '- সমাস নিয়ে আলোচনা',
          upToId: 42,
        );

        final loaded = await db.getChatSessionById(session);
        expect(loaded!.summary, '- সমাস নিয়ে আলোচনা');
        expect(loaded.summarizedUpToId, 42);
      });

      test('clearing a thread also clears its memory', () async {
        final session = await db.createChatSession(title: 'সমাস thread');
        await db.insertChatMessage(
          ChatMessagesCompanion.insert(
            sessionId: Value(session),
            role: 'user',
            textContent: 'প্রশ্ন',
          ),
        );
        await db.updateChatSessionSummary(
          session,
          summary: '- পুরনো স্মৃতি',
          upToId: 7,
        );

        await db.clearSessionMessages(session);

        final loaded = await db.getChatSessionById(session);
        expect(loaded!.summary, isNull);
        expect(loaded.summarizedUpToId, isNull);
      });

      test(
        'getAllChatMessagesForSession returns the thread oldest first',
        () async {
          final session = await db.createChatSession(title: 'thread');
          for (var i = 0; i < 5; i++) {
            await db.insertChatMessage(
              ChatMessagesCompanion.insert(
                sessionId: Value(session),
                role: i.isEven ? 'user' : 'model',
                textContent: 'বার্তা $i',
              ),
            );
          }

          final all = await db.getAllChatMessagesForSession(session);
          expect(all.length, 5);
          expect(all.first.textContent, 'বার্তা 0');
          expect(all.last.textContent, 'বার্তা 4');
        },
      );
    });
  });

  group('Streaming Placeholder Tests', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'a placeholder fills in as the reply streams, then finalises',
      () async {
        final session = await db.createChatSession(title: 'thread');
        final id = await db.insertChatMessage(
          ChatMessagesCompanion.insert(
            sessionId: Value(session),
            role: 'model',
            textContent: '',
          ),
        );

        await db.updateChatMessageText(id, 'সমাস হলো');
        await db.updateChatMessageText(id, 'সমাস হলো একাধিক পদের');

        var rows = await db.getAllChatMessagesForSession(session);
        expect(rows.single.textContent, 'সমাস হলো একাধিক পদের');
        expect(rows.single.suggestedAction, isNull);

        await db.finalizeChatMessage(
          id,
          text: 'সমাস হলো একাধিক পদের মিলন।',
          suggestedAction: '[]',
        );

        rows = await db.getAllChatMessagesForSession(session);
        expect(rows.single.textContent, 'সমাস হলো একাধিক পদের মিলন।');
        expect(rows.single.suggestedAction, '[]');
        // Still one row: the placeholder was replaced, not duplicated.
        expect(rows.length, 1);
      },
    );

    test('a failed send leaves no empty bubble behind', () async {
      final session = await db.createChatSession(title: 'thread');
      final id = await db.insertChatMessage(
        ChatMessagesCompanion.insert(
          sessionId: Value(session),
          role: 'model',
          textContent: '',
        ),
      );

      await db.deleteChatMessage(id);

      expect(await db.getAllChatMessagesForSession(session), isEmpty);
    });

    test('an empty placeholder never reaches the model as history', () {
      final (contents, _) = GeminiChatService.instance.buildHistoryContents([
        ChatMessage(
          id: 1,
          sessionId: 1,
          role: 'user',
          textContent: 'প্রশ্ন',
          timestamp: DateTime(2026, 1, 1),
        ),
        ChatMessage(
          id: 2,
          sessionId: 1,
          role: 'model',
          textContent: '',
          timestamp: DateTime(2026, 1, 1, 0, 1),
        ),
      ]);

      // The orphan placeholder is skipped, so the trailing user turn is
      // carried over rather than paired with an empty reply.
      expect(contents, isEmpty);
    });
  });

  group('Shared Prompt Hygiene Tests', () {
    test('the shared instruction no longer forces JSON on prose callers', () {
      final shared = GeminiPrompts.systemInstruction;

      // explainMistake and getExamQuickRevision want prose; telling every
      // caller "respond only in JSON" contradicted half of them.
      expect(shared.toUpperCase().contains('JSON'), isFalse);
    });

    test('the burnout tenets survive the trim', () {
      final shared = GeminiPrompts.systemInstruction;

      expect(shared.contains('PREVENT BURNOUT'), isTrue);
      expect(shared.contains('MICRO-COMMITMENTS'), isTrue);
      expect(shared.contains('WEAK TOPIC PRIORITY'), isTrue);
    });

    test('typography detail is gone now the sanitizer owns it', () {
      // One short line survives; the old rule-by-rule block does not.
      expect(GeminiPrompts.systemInstruction.length, lessThan(1200));
      expect(GeminiPrompts.systemInstruction.contains('Unicode'), isTrue);
    });

    test(
      'an oversized study sheet is truncated before it reaches the model',
      () {
        final huge = 'অধ্যায় ' * 5000;
        final prompt = GeminiPrompts.buildStudySheetSummaryPrompt(
          rawContent: huge,
          subject: 'বাংলা',
        );

        expect(huge.length, greaterThan(GeminiPrompts.maxStudySheetChars));
        expect(
          prompt.length,
          lessThan(GeminiPrompts.maxStudySheetChars + 2000),
        );
        expect(prompt.contains('…'), isTrue);
      },
    );

    test('a normal study sheet passes through untouched', () {
      const normal = 'সমাস হলো একাধিক পদের মিলন।';
      final prompt = GeminiPrompts.buildStudySheetSummaryPrompt(
        rawContent: normal,
      );

      expect(prompt.contains(normal), isTrue);
    });
  });

  group('Drift ChatMessages Persistence Tests', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'Can insert and retrieve chat messages in chronological order',
      () async {
        await db.insertChatMessage(
          ChatMessagesCompanion.insert(
            role: 'user',
            textContent: 'সমাস সহজে মনে রাখার উপায় কী?',
          ),
        );

        await db.insertChatMessage(
          ChatMessagesCompanion.insert(
            role: 'model',
            textContent: 'সমাস ৬ প্রকার। নিচে নিয়ম দেওয়া হলো...',
          ),
        );

        final messages = await db.getRecentChatMessages(limit: 10);
        expect(messages.length, 2);
        expect(messages[0].role, 'user');
        expect(messages[0].textContent, 'সমাস সহজে মনে রাখার উপায় কী?');
        expect(messages[1].role, 'model');

        // Clear history
        await db.clearChatHistory();
        final afterClear = await db.getRecentChatMessages();
        expect(afterClear.isEmpty, isTrue);
      },
    );

    test('Topic-wise sessions isolate conversation history and prevent context mixing', () async {
      // 1. Create two separate topic sessions
      final sessionBangla = await db.getOrCreateTopicSession(
        subject: 'Bangla Grammar',
        topic: 'কারক ও বিভক্তি',
      );
      final sessionMath = await db.getOrCreateTopicSession(
        subject: 'Mathematics',
        topic: 'শতকরা ও লাভ-ক্ষতি',
      );

      expect(sessionBangla.id, isNot(equals(sessionMath.id)));
      expect(sessionBangla.title, equals('Bangla Grammar: কারক ও বিভক্তি'));
      expect(sessionMath.title, equals('Mathematics: শতকরা ও লাভ-ক্ষতি'));

      // 2. Insert messages into Bangla session
      await db.insertChatMessage(
        ChatMessagesCompanion.insert(
          sessionId: Value(sessionBangla.id),
          role: 'user',
          textContent: 'পাপে বিরত হও কোন কারক?',
        ),
      );
      await db.insertChatMessage(
        ChatMessagesCompanion.insert(
          sessionId: Value(sessionBangla.id),
          role: 'model',
          textContent: 'এটি অপাদান কারক।',
        ),
      );

      // 3. Insert message into Math session
      await db.insertChatMessage(
        ChatMessagesCompanion.insert(
          sessionId: Value(sessionMath.id),
          role: 'user',
          textContent: '১০% লাভে বিক্রয়মূল্য ১১০ হলে ক্রয়মূল্য কত?',
        ),
      );

      // 4. Verify Bangla session history contains ONLY Bangla messages
      final banglaHistory = await db.getRecentChatMessagesForSession(
        sessionBangla.id,
      );
      expect(banglaHistory.length, equals(2));
      expect(banglaHistory[0].textContent, contains('পাপে বিরত হও'));
      expect(banglaHistory[1].textContent, contains('অপাদান কারক'));
      expect(
        banglaHistory.any((m) => m.textContent.contains('বিক্রয়মূল্য')),
        isFalse,
      );

      // 5. Verify Math session history contains ONLY Math message (no context pollution)
      final mathHistory = await db.getRecentChatMessagesForSession(
        sessionMath.id,
      );
      expect(mathHistory.length, equals(1));
      expect(mathHistory[0].textContent, contains('বিক্রয়মূল্য'));
      expect(mathHistory.any((m) => m.textContent.contains('কারক')), isFalse);

      // 6. Test re-accessing existing topic session doesn't create duplicate
      final sameBangla = await db.getOrCreateTopicSession(
        subject: 'Bangla Grammar',
        topic: 'কারক ও বিভক্তি',
      );
      expect(sameBangla.id, equals(sessionBangla.id));

      // 7. Test rename session
      final renamed = await db.updateChatSessionTitle(
        sessionBangla.id,
        'বাংলা ব্যাকরণ: কারক স্পেশাল',
      );
      expect(renamed, isTrue);
      final updated = await db.getChatSessionById(sessionBangla.id);
      expect(updated?.title, equals('বাংলা ব্যাকরণ: কারক স্পেশাল'));

      // 8. Test delete session also deletes its messages
      await db.deleteChatSession(sessionBangla.id);
      final checkDeletedSession = await db.getChatSessionById(sessionBangla.id);
      expect(checkDeletedSession, isNull);
      final banglaRemaining = await db.getRecentChatMessagesForSession(
        sessionBangla.id,
      );
      expect(banglaRemaining.isEmpty, isTrue);

      // Math session is still completely untouched
      final mathRemaining = await db.getRecentChatMessagesForSession(
        sessionMath.id,
      );
      expect(mathRemaining.length, equals(1));
    });
  });
}
