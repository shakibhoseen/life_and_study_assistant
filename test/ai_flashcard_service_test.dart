import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/services/ai/ai_flashcard_service.dart';
import 'package:life_and_study_assistant/features/chat/domain/models/chat_action.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('AiFlashcardItem & BengaliMathSanitizer', () {
    test('Correctly maps and sanitizes Bengali math symbols and LaTeX', () {
      final item = AiFlashcardItem.fromJson({
        'subject': 'গণিত',
        'topic': 'জ্যামিতি',
        'front': r'বর্গক্ষেত্রের কর্ণ $d$',
        'back': r'সূত্র: $d = \sqrt{2} \times a$ এবং ক্ষেত্রফল $A = a^2$',
      });

      expect(item.subject, equals('গণিত'));
      expect(item.topic, equals('জ্যামিতি'));
      expect(item.front.contains(r'$'), isFalse);
      expect(item.back.contains(r'$'), isFalse);
      expect(item.isSelected, isTrue);
    });
  });

  group('AiFlashcardService Offline Generation', () {
    test('Generates geometry formulas for square query', () async {
      final cards = await AiFlashcardService.instance.generateFromPrompt(
        'বর্গক্ষেত্রের কর্ণের দৈর্ঘ্য',
      );

      expect(cards.isNotEmpty, isTrue);
      expect(cards.any((c) => c.front.contains('বর্গক্ষেত্র')), isTrue);
      expect(cards.any((c) => c.back.contains('√2')), isTrue);
    });

    test('Generates formulas for right-angled triangle query', () async {
      final cards = await AiFlashcardService.instance.generateFromPrompt(
        'সমকোণী ত্রিভুজ সূত্র',
      );

      expect(cards.isNotEmpty, isTrue);
      expect(cards.any((c) => c.back.contains('অতিভুজ')), isTrue);
    });

    test('Generates grammar rules for ণ-ত্ব বিধান query', () async {
      final cards = await AiFlashcardService.instance.generateFromPrompt(
        'ণ-ত্ব বিধান',
      );

      expect(cards.isNotEmpty, isTrue);
      expect(cards.any((c) => c.front.contains('ণ-ত্ব বিধান')), isTrue);
    });
  });

  group('AiFlashcardService External AI Text Parsing', () {
    test('Parses JSON generated from ChatGPT or Claude', () async {
      const jsonSnippet = '''
```json
{
  "subject": "পরিমিতি",
  "topic": "বৃত্ত",
  "cards": [
    {
      "front": "বৃত্তের পরিধি",
      "back": "2πr (যেখানে r হলো ব্যাসার্ধ)"
    },
    {
      "front": "বৃত্তের ক্ষেত্রফল",
      "back": "πr²"
    }
  ]
}
```
''';

      final cards = await AiFlashcardService.instance.parseFromExternalText(
        jsonSnippet,
      );

      expect(cards.length, equals(2));
      expect(cards[0].front, equals('বৃত্তের পরিধি'));
      expect(cards[0].back.contains('2πr'), isTrue);
      expect(cards[1].front, equals('বৃত্তের ক্ষেত্রফল'));
      expect(cards[1].back.contains('πr²'), isTrue);
    });

    test('Parses bullet points or colon-separated text from external AI', () async {
      const bulletText = '''
• রম্বসের ক্ষেত্রফল: ½ × d1 × d2
• সামান্তরিকের ক্ষেত্রফল = ভূমি × উচ্চতা
• ট্রাপিজিয়ামের ক্ষেত্রফল -> ½ × (সমান্তরাল বাহুদ্বয়ের যোগফল) × উচ্চতা
''';

      final cards = await AiFlashcardService.instance.parseFromExternalText(
        bulletText,
      );

      expect(cards.length, equals(3));
      expect(cards[0].front, contains('রম্বসের ক্ষেত্রফল'));
      expect(cards[0].back, contains('½ × d1 × d2'));
      expect(cards[1].front, contains('সামান্তরিকের ক্ষেত্রফল'));
      expect(cards[2].front, contains('ট্রাপিজিয়ামের ক্ষেত্রফল'));
    });
  });

  group('AiFlashcardService Database Batch Persistence', () {
    test('Saves selected cards into SpacedReviewItems table', () async {
      final cards = [
        AiFlashcardItem(
          subject: 'গণিত',
          topic: 'পরিমিতি',
          front: 'বর্গক্ষেত্রের কর্ণ',
          back: 'd = √2 × a',
          isSelected: true,
        ),
        AiFlashcardItem(
          subject: 'গণিত',
          topic: 'পরিমিতি',
          front: 'বর্গক্ষেত্রের পরিসীমা',
          back: 'P = 4a',
          isSelected: false, // Should NOT be saved
        ),
        AiFlashcardItem(
          subject: 'বাংলা',
          topic: 'ব্যাকরণ',
          front: 'ণ-ত্ব বিধানের ব্যতিক্রম',
          back: 'স্বভাবতই ণ হয়: চাণক্য মাণিক্য গণ...',
          isSelected: true,
        ),
      ];

      final initialCount = (await db.watchAllSpacedReviewItems().first).length;

      final savedCount = await AiFlashcardService.instance.saveToSpacedRepetition(
        db,
        cards,
      );

      expect(savedCount, equals(2));

      final allItems = await db.watchAllSpacedReviewItems().first;
      expect(allItems.length, equals(initialCount + 2));
      expect(allItems.any((it) => it.title == 'বর্গক্ষেত্রের কর্ণ'), isTrue);
      expect(
        allItems.any((it) => it.title == 'ণ-ত্ব বিধানের ব্যতিক্রম'),
        isTrue,
      );
      expect(
        allItems.any((it) => it.title == 'বর্গক্ষেত্রের পরিসীমা'),
        isFalse,
      );
    });
  });

  group('ChatAction Flashcard Integration', () {
    test('extractActions parses single tag [[ACTION:ADD_FLASHCARD]]', () {
      const response = '''
এখানে বর্গক্ষেত্রের কর্ণের সূত্রটি দেওয়া হলো:
[[ACTION:ADD_FLASHCARD|গণিত|জ্যামিতি|বর্গক্ষেত্রের কর্ণের দৈর্ঘ্য|d = √2 × a]]
ভালো করে রিভিশন দিন!
''';

      final actions = ChatAction.extractActions(response);
      expect(actions.length, equals(1));
      expect(actions.first.type, equals(ChatActionType.addFlashcard));
      expect(actions.first.subject, equals('গণিত'));
      expect(actions.first.topic, equals('জ্যামিতি'));
      expect(actions.first.title, equals('বর্গক্ষেত্রের কর্ণের দৈর্ঘ্য'));
      expect(actions.first.keyRule, equals('d = √2 × a'));

      final cleaned = ChatAction.cleanActionTags(response);
      expect(cleaned.contains('[[ACTION:'), isFalse);
      expect(cleaned.contains('ভালো করে রিভিশন দিন!'), isTrue);
    });

    test('extractActions parses block tag [[ACTION:ADD_FLASHCARD_BEGIN]]', () {
      const response = '''
[[ACTION:ADD_FLASHCARD_BEGIN|গণিত|ত্রিকোণমিতি|পিথাগোরাসের উপপাদ্য]]
অতিভুজ² = লম্ব² + ভূমি²
[[ACTION:ADD_FLASHCARD_END]]
''';

      final actions = ChatAction.extractActions(response);
      expect(actions.length, equals(1));
      expect(actions.first.type, equals(ChatActionType.addFlashcard));
      expect(actions.first.subject, equals('গণিত'));
      expect(actions.first.topic, equals('ত্রিকোণমিতি'));
      expect(actions.first.title, equals('পিথাগোরাসের উপপাদ্য'));
      expect(actions.first.keyRule?.contains('অতিভুজ² = লম্ব² + ভূমি²'), isTrue);

      final cleaned = ChatAction.cleanActionTags(response);
      expect(cleaned.trim(), isEmpty);
    });

    test('Serializes and deserializes ChatAction with keyRule', () {
      const action = ChatAction(
        type: ChatActionType.addFlashcard,
        title: 'রম্বসের ক্ষেত্রফল',
        subject: 'গণিত',
        topic: 'পরিমিতি',
        keyRule: 'A = ½ × d1 × d2',
      );

      final json = action.toJson();
      expect(json['type'], equals('addFlashcard'));
      expect(json['keyRule'], equals('A = ½ × d1 × d2'));

      final restored = ChatAction.fromJson(json);
      expect(restored.type, equals(ChatActionType.addFlashcard));
      expect(restored.title, equals('রম্বসের ক্ষেত্রফল'));
      expect(restored.keyRule, equals('A = ½ × d1 × d2'));
    });
  });
}
