import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../database/app_database.dart';

class FlashcardItem {
  final String subject;
  final String topic;
  final String title;
  final String content;
  final String? mnemonic;
  final String tag;

  const FlashcardItem({
    required this.subject,
    required this.topic,
    required this.title,
    required this.content,
    this.mnemonic,
    required this.tag,
  });
}

class FlashcardService {
  FlashcardService._();
  static final FlashcardService instance = FlashcardService._();

  static const List<FlashcardItem> curatedFlashcards = [
    FlashcardItem(
      subject: 'English Vocabulary',
      topic: 'High Frequency BCS Words',
      title: 'Ephemeral',
      content: 'অর্থ: ক্ষণস্থায়ী, অল্পস্থায়ী (Short-lived, Fleeting)\nSynonym: Transient, Evanescent, Momentary\nAntonym: Eternal, Perpetual, Permanent',
      mnemonic: 'E-phe-meral sounds like "effervescent" (বুদবুদ যা মুহূর্তেই মিলিয়ে যায়)',
      tag: 'Vocab',
    ),
    FlashcardItem(
      subject: 'English Vocabulary',
      topic: 'High Frequency BCS Words',
      title: 'Ubiquitous',
      content: 'অর্থ: সর্বত্র বিদ্যমান (Omnipresent, Existing everywhere)\nSynonym: Pervasive, Universal\nAntonym: Rare, Scarce',
      mnemonic: 'Ubi (সব জায়গায়) + quitous: যেমন স্মার্টফোন ও ইন্টারনেট সর্বত্র বিদ্যমান',
      tag: 'Vocab',
    ),
    FlashcardItem(
      subject: 'English Vocabulary',
      topic: 'High Frequency BCS Words',
      title: 'Pragmatic',
      content: 'অর্থ: বাস্তবমুখী, প্রায়োগিক (Dealing with things practically)\nSynonym: Practical, Realistic, Utilitarian\nAntonym: Idealistic, Impractical',
      mnemonic:
          'Pragmatic = Programmatic / Practical (তত্ত্ব নয়, বাস্তব সমাধান)',
      tag: 'Vocab',
    ),
    FlashcardItem(
      subject: 'Bangla Grammar',
      topic: 'কারক ও বিভক্তি',
      title: 'অপাদান বনাম অধিকরণ কারক',
      content: 'অপাদান: যা থেকে কোনো কিছু বিচ্যুত, উৎপন্ন, জাত, ভীত, স্খলিত হয়।\n• "তিলে তৈল হয়" (উৎপন্ন = অপাদান)\n• "তিলে তৈল আছে" (স্থান/ব্যাপ্তি = অধিকরণ)\n• "পাপে বিরত হও" (বিচ্যুত = অপাদান)',
      mnemonic: 'উৎপন্ন/ভীত/মুক্ত হলে অপাদান, স্থান/আধার হলে অধিকরণ',
      tag: 'Grammar',
    ),
    FlashcardItem(
      subject: 'Bangla Grammar',
      topic: 'সমাস ও প্রকারভেদ',
      title: 'বহুব্রীহি সমাস চেনার টেকনিক',
      content: 'পূর্বপদ বা পরপদ কোনোটির অর্থ প্রাধান্য না পেয়ে তৃতীয় কোনো ব্যক্তিকে বোঝায়।\n• পীতাম্বর: পীত অম্বর যার = শ্রীকৃষ্ণ\n• নীলকণ্ঠ: নীল কণ্ঠ যার = শিব\n• দশানন: দশ আনন যার = রাবণ',
      mnemonic: 'তৃতীয় ভিন্ন অর্থ বের হলেই বহুব্রীহি',
      tag: 'Grammar',
    ),
    FlashcardItem(
      subject: 'Bangla Grammar',
      topic: 'ণ-ত্ব ও ষ-ত্ব বিধান',
      title: 'ণ-ত্ব বিধানের কমন ফাঁদ',
      content: '১. ঋ, র, ষ এর পর তৎসম শব্দে মূর্ধন্য (ণ) হয় (যেমন: ঋণ, বর্ণ, কারণ, কৃষ্ণ)।\n২. ত-বর্গীয় বর্ণের সাথে যুক্ত বর্ণে সর্বদা দন্ত্য-ন হয় (যেমন: বৃন্ত, কান্ত, গ্রন্থ)।\n৩. খাটি বাংলা ও বিদেশী শব্দে কখনো মূর্ধন্য (ণ) হবে না (যেমন: কোরআন, কর্নার, স্টেশন)।',
      mnemonic: 'ত-বর্গের সাথে সর্বদা দন্ত্য-ন, বিদেশী শব্দে ণ নিষিদ্ধ',
      tag: 'Grammar',
    ),
    FlashcardItem(
      subject: 'Mathematics',
      topic: 'শতকরা ও লাভ-ক্ষতি',
      title: 'ক্রয়মূল্য ও বিক্রয়মূল্যের শর্টকাট',
      content: '• r% লাভে: ক্রয়মূল্য = (বিক্রয়মূল্য × ১০০) ÷ (১০০ + r)\n• r% ক্ষতিতে: ক্রয়মূল্য = (বিক্রয়মূল্য × ১০০) ÷ (১০০ - r)\nউদাহরণ: ১০% লাভে বিক্রয়মূল্য ১১০ হলে ক্রয়মূল্য = (১১০ × ১০০)/১১০ = ১০০ টাকা।',
      mnemonic: 'লাভ হলে নিচে যোগ, ক্ষতি হলে নিচে বিয়োগ',
      tag: 'Math',
    ),
    FlashcardItem(
      subject: 'Mathematics',
      topic: 'গুণোত্তর ও সমান্তর ধারা',
      title: 'ধারার পদ নির্ণয়ের শর্টকাট',
      content: '• সমান্তর ধারা: n-তম পদ = a + (n - 1)d\n• সমান্তর ধারার সমষ্টি = n/2 [2a + (n - 1)d]\n• গুণোত্তর ধারা: n-তম পদ = a × r^(n - 1)',
      mnemonic: 'অন্তর যোগ হলে সমান্তর, অনুপাত গুণ হলে গুণোত্তর',
      tag: 'Math',
    ),
    FlashcardItem(
      subject: 'General Science',
      topic: 'আলো ও আলোকীয় যন্ত্রপাতি',
      title: 'পূর্ণ অভ্যন্তরীণ প্রতিফলন',
      content: 'শর্ত: ১. আলো ঘন মাধ্যম থেকে লঘু মাধ্যমে যাবে। ২. আপতন কোণ সংকট কোণের চেয়ে বড় হবে।\nবাস্তব প্রয়োগ: অপটিক্যাল ফাইবার, হীরকের উজ্জ্বলতা, মরুভূমির মরিচিকা ও এন্ডোস্কোপি।',
      mnemonic: 'ঘন থেকে লঘু + সংকট কোণের চেয়ে বড় = পূর্ণ প্রতিফলন',
      tag: 'Science',
    ),
    FlashcardItem(
      subject: 'General Science',
      topic: 'মানবদেহ ও রক্তের গ্রুপ',
      title: 'রক্তের গ্রুপ ও অ্যান্টিজেন',
      content: '• O নেগেটিভ (O-): সর্বজনীন দাতা (Universal Donor) - এতে কোনো অ্যান্টিজেন নেই।\n• AB পজিটিভ (AB+): সর্বজনীন গ্রহীতা (Universal Recipient) - এতে কোনো অ্যান্টিবডি নেই।',
      mnemonic: 'O দেয় সবাইকে, AB নেয় সবার থেকে',
      tag: 'Science',
    ),
    FlashcardItem(
      subject: 'Bangladesh Affairs',
      topic: 'সংবিধানের গুরুত্বপূর্ণ অনুচ্ছেদ',
      title: 'মৌলিক অধিকারের অনুচ্ছেদসমূহ',
      content: '• অনুচ্ছেদ ২৭: আইনের দৃষ্টিতে সমতা\n• অনুচ্ছেদ ২৮: ধর্ম প্রভৃতি কারণে বৈষম্য নিষিদ্ধ\n• অনুচ্ছেদ ৩২: জীবন ও ব্যক্তিস্বাধীনতার অধিকার\n• অনুচ্ছেদ ৩৬-৩৯: চলাফেরা, সমাবেশ, সংগঠন ও বাক-স্বাধীনতা',
      mnemonic: 'সংবিধানের ৩য় ভাগ (অনুচ্ছেদ ২৭ থেকে ৪৪) হলো মৌলিক অধিকার',
      tag: 'Constitution',
    ),
    FlashcardItem(
      subject: 'Bangladesh Affairs',
      topic: 'মুক্তিযুদ্ধের ১১টি সেক্টর',
      title: 'কমন সেক্টর কমান্ডার শর্টকাট',
      content: '• সেক্টর ১: চট্টগ্রাম ও পার্বত্য অঞ্চল (মেজর জিয়াউর রহমান, পরে রফিকুল ইসলাম)\n• সেক্টর ২: ঢাকা ও কুমিল্লা (মেজর খালেদ মোশাররফ, পরে এটিএম হায়দার)\n• সেক্টর ১০: নৌ সেক্টর (কোনো স্থায়ী কমান্ডার ছিল না, যখন যে অফিসার)',
      mnemonic: '১০ নম্বর নৌ-সেক্টরে কোনো নিয়মিত কমান্ডার ছিল না',
      tag: 'LiberationWar',
    ),
    FlashcardItem(
      subject: 'English Literature',
      topic: 'Idioms & Phrases',
      title: 'A bolt from the blue',
      content: 'Meaning: সম্পূর্ণ অপ্রত্যাশিত বা আকস্মিক কোনো বিপদ (A sudden, unexpected catastrophic event or shock).\nSentence: The sudden layoff notice came as a bolt from the blue.',
      mnemonic: 'মেঘহীন নীল আকাশ থেকে হঠাৎ বজ্রপাত পড়ার মতো অপ্রত্যাশিত',
      tag: 'Idioms',
    ),
  ];

  /// Gets a flashcard item either from curated bank or dynamically from user's weak topics / mistakes
  Future<FlashcardItem> getFlashcard({
    AppDatabase? db,
    String? preferredSubject,
  }) async {
    // 1. Try to get from user's due spaced review if available
    if (db != null) {
      try {
        final dueReviews = await db.getDueSpacedReviewItems();
        if (dueReviews.isNotEmpty) {
          final review = dueReviews.first;
          return FlashcardItem(
            subject: review.subject,
            topic: review.topic,
            title: review.title,
            content: review.keyRule,
            tag: 'SpacedReview',
          );
        }
      } catch (e) {
        debugPrint('Error getting due review for flashcard: $e');
      }
    }

    // 2. Otherwise pick from curated deck matching preference
    final list = preferredSubject != null && preferredSubject.isNotEmpty
        ? curatedFlashcards
              .where(
                (f) => f.subject.toLowerCase().contains(
                  preferredSubject.toLowerCase(),
                ),
              )
              .toList()
        : curatedFlashcards;

    final pool = list.isNotEmpty ? list : curatedFlashcards;
    final random = Random();
    return pool[random.nextInt(pool.length)];
  }
}
