import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/services/flashcards/flashcard_service.dart';

void main() {
  const card = FlashcardItem(
    subject: 'বাংলা ব্যাকরণ',
    topic: 'কারক',
    title: 'কারক ও বিভক্তি চেনার সম্পূর্ণ কৌশল এবং পরীক্ষায় আসা ফাঁদসমূহ',
    content: 'ক্রিয়ার সাথে বিশেষ্যের সম্পর্ক দেখে কারক নির্ণয় করতে হয়।',
    mnemonic: 'কে/কাকে প্রশ্ন করলেই কর্ম কারক',
    tag: 'SpacedReview',
    reviewItemId: 7,
  );

  group('Flashcard payload', () {
    test('a card survives the trip through a notification', () {
      final restored = FlashcardItem.tryFromPayload(
        jsonEncode(card.toPayload()),
      );

      expect(restored, isNotNull);
      // The long title is the whole point: the notification truncates it.
      expect(restored!.title, card.title);
      expect(restored.content, card.content);
      expect(restored.mnemonic, card.mnemonic);
      expect(restored.subject, card.subject);
      expect(restored.topic, card.topic);
      expect(restored.reviewItemId, 7);
    });

    test('a card without a mnemonic round-trips too', () {
      const plain = FlashcardItem(
        subject: 'গণিত',
        topic: 'জ্যামিতি',
        title: 'বৃত্তের ক্ষেত্রফল',
        content: 'πr²',
        tag: 'Curated',
      );

      final restored = FlashcardItem.tryFromPayload(
        jsonEncode(plain.toPayload()),
      );

      expect(restored!.mnemonic, anyOf(isNull, isEmpty));
      expect(restored.reviewItemId, isNull);
      expect(restored.content, 'πr²');
    });

    test('a curated card carries no review id to advance', () {
      const plain = FlashcardItem(
        subject: 'গণিত',
        topic: 'জ্যামিতি',
        title: 'ত্রিভুজ',
        content: 'তিন বাহু',
        tag: 'Curated',
      );

      expect(plain.toPayload().containsKey('r'), isFalse);
    });

    test('rubbish payloads are rejected rather than half-read', () {
      expect(FlashcardItem.tryFromPayload(null), isNull);
      expect(FlashcardItem.tryFromPayload(''), isNull);
      expect(FlashcardItem.tryFromPayload('not json'), isNull);
      expect(FlashcardItem.tryFromPayload('[1,2]'), isNull);
      expect(FlashcardItem.tryFromPayload('{}'), isNull);
    });

    test('a payload with only a title is still usable', () {
      expect(
        FlashcardItem.tryFromPayload(jsonEncode({'t': 'শুধু শিরোনাম'})),
        isNotNull,
      );
    });

    test('unicode maths and Bengali survive encoding', () {
      const tricky = FlashcardItem(
        subject: 'গণিত',
        topic: 'ত্রিকোণমিতি',
        title: 'd = √2 × a',
        content: 'ক্ষেত্রফল = a² = d²/2, যেখানে ∠A = ১৮০° - ৬০°',
        tag: 'Curated',
      );

      final restored = FlashcardItem.tryFromPayload(
        jsonEncode(tricky.toPayload()),
      );

      expect(restored!.content, contains('a²'));
      expect(restored.content, contains('১৮০°'));
      expect(restored.title, 'd = √2 × a');
    });
  });
}
