import 'dart:convert';
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

  /// Set when this card came from the user's own spaced review list, so
  /// "মনে থাকবে" can advance that item rather than only noting a date.
  final int? reviewItemId;

  const FlashcardItem({
    required this.subject,
    required this.topic,
    required this.title,
    required this.content,
    this.mnemonic,
    required this.tag,
    this.reviewItemId,
  });

  /// Carried on the notification so a tap can show the whole card.
  ///
  /// A notification title is one truncated line and the body is capped too,
  /// so a long rule or a formula is unreadable there however it is styled.
  /// The full text travels with it and the app renders it properly.
  Map<String, Object?> toPayload() => {
    's': subject,
    'tp': topic,
    't': title,
    'c': content,
    if (mnemonic != null && mnemonic!.isNotEmpty) 'm': mnemonic,
    'g': tag,
    if (reviewItemId != null) 'r': reviewItemId,
  };

  static FlashcardItem? tryFromPayload(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final title = decoded['t']?.toString() ?? '';
      final content = decoded['c']?.toString() ?? '';
      if (title.isEmpty && content.isEmpty) return null;
      return FlashcardItem(
        subject: decoded['s']?.toString() ?? '',
        topic: decoded['tp']?.toString() ?? '',
        title: title,
        content: content,
        mnemonic: decoded['m']?.toString(),
        tag: decoded['g']?.toString() ?? 'Flashcard',
        reviewItemId: (decoded['r'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }
}

class FlashcardService {
  FlashcardService._();
  static final FlashcardService instance = FlashcardService._();

  /// The deck the push falls back on when nothing is due for review.
  ///
  /// Weighted toward formulas and rules rather than trivia, because those are
  /// what repetition actually fixes and what the exam keeps asking. Every
  /// entry here is definitional — a formula, a grammatical rule, a
  /// constitutional article — so none of it depends on anyone's recall being
  /// right. Dates and one-off facts are kept few and only where they are
  /// beyond dispute; the rest of the deck grows from the user's own generated
  /// cards, which flow in through the spaced review list.
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
    // ---- Mensuration: pure definition, nothing to misremember ----------
    FlashcardItem(
      subject: 'Mathematics',
      topic: 'পরিমিতি',
      title: 'বর্গক্ষেত্রের কর্ণ ও ক্ষেত্রফল',
      content: 'কর্ণ, d = √2 × a\nক্ষেত্রফল = a² = d² ÷ 2\nপরিসীমা = 4a',
      mnemonic: 'কর্ণ জানা থাকলে ক্ষেত্রফল বের করতে বাহু লাগে না: d² ÷ 2',
      tag: 'Formula',
    ),
    FlashcardItem(
      subject: 'Mathematics',
      topic: 'পরিমিতি',
      title: 'রম্বস ও ট্রাপিজিয়ামের ক্ষেত্রফল',
      content:
          'রম্বস = ½ × d₁ × d₂ (কর্ণদ্বয়ের গুণফলের অর্ধেক)\n'
          'ট্রাপিজিয়াম = ½ × (সমান্তরাল বাহুদ্বয়ের সমষ্টি) × উচ্চতা',
      mnemonic: 'দুটোতেই ½ আছে — কর্ণ বা সমান্তরাল বাহু, তারপর অর্ধেক',
      tag: 'Formula',
    ),
    FlashcardItem(
      subject: 'Mathematics',
      topic: 'পরিমিতি',
      title: 'বৃত্ত ও গোলকের সূত্র',
      content:
          'বৃত্তের ক্ষেত্রফল = πr², পরিধি = 2πr\n'
          'গোলকের পৃষ্ঠতল = 4πr², আয়তন = ⁴⁄₃ πr³',
      mnemonic: 'গোলকের পৃষ্ঠতল বৃত্তের ক্ষেত্রফলের ঠিক ৪ গুণ',
      tag: 'Formula',
    ),
    FlashcardItem(
      subject: 'Mathematics',
      topic: 'বীজগণিত',
      title: 'অপরিহার্য তিনটি অভেদ',
      content:
          '(a + b)² = a² + 2ab + b²\n'
          '(a − b)² = a² − 2ab + b²\n'
          'a² − b² = (a + b)(a − b)',
      mnemonic: 'a² + b² = (a + b)² − 2ab — পরীক্ষায় এই রূপেই বেশি লাগে',
      tag: 'Formula',
    ),
    FlashcardItem(
      subject: 'Mathematics',
      topic: 'বীজগণিত',
      title: 'দ্বিঘাত সমীকরণের সমাধান',
      content:
          'ax² + bx + c = 0 হলে, x = [−b ± √(b² − 4ac)] ÷ 2a\n'
          'নিশ্চায়ক b² − 4ac > 0 হলে দুটি বাস্তব মূল, = 0 হলে সমান দুটি, < 0 হলে বাস্তব মূল নেই',
      mnemonic: 'মূলদ্বয়ের যোগফল = −b/a, গুণফল = c/a',
      tag: 'Formula',
    ),
    FlashcardItem(
      subject: 'Mathematics',
      topic: 'শতকরা ও মুনাফা',
      title: 'সরল ও চক্রবৃদ্ধি মুনাফা',
      content:
          'সরল মুনাফা, I = (P × r × t) ÷ 100\n'
          'চক্রবৃদ্ধি মূলধন, A = P(1 + r/100)ᵗ\n'
          'চক্রবৃদ্ধি মুনাফা = A − P',
      mnemonic: 'সরলে গুণ, চক্রবৃদ্ধিতে ঘাত — এই একটাই পার্থক্য',
      tag: 'Formula',
    ),
    FlashcardItem(
      subject: 'Mathematics',
      topic: 'গড় ও অনুপাত',
      title: 'অনুপাত লঘিষ্ঠ করার নিয়ম',
      content:
          'উভয় পদকে তাদের গ.সা.গু দিয়ে ভাগ করলে লঘিষ্ঠ আকার পাওয়া যায়।\n'
          'যেমন ১০ : ৬ → গ.সা.গু ২ → ৫ : ৩',
      mnemonic: '১০:৬ কখনোই ৩:২ নয় — পরীক্ষায় এটিই সবচেয়ে কমন ফাঁদ',
      tag: 'Formula',
    ),
    FlashcardItem(
      subject: 'General Science',
      topic: 'পদার্থবিজ্ঞান',
      title: 'নিউটনের তিন সূত্র',
      content:
          '১ম: বাইরের বল না থাকলে বস্তু তার অবস্থা বজায় রাখে (জড়তা)\n'
          '২য়: F = ma, বল = ভর × ত্বরণ\n'
          '৩য়: প্রত্যেক ক্রিয়ার সমান ও বিপরীত প্রতিক্রিয়া আছে',
      mnemonic: 'জড়তা → F = ma → ক্রিয়া-প্রতিক্রিয়া',
      tag: 'Law',
    ),
    FlashcardItem(
      subject: 'General Science',
      topic: 'পদার্থবিজ্ঞান',
      title: 'ওহমের সূত্র ও ক্ষমতা',
      content:
          'V = IR (বিভব = তড়িৎপ্রবাহ × রোধ)\n'
          'ক্ষমতা, P = VI = I²R = V² ÷ R',
      mnemonic: 'V = IR একটাই মনে রাখলে বাকি সব এখান থেকেই বের হয়',
      tag: 'Law',
    ),
    FlashcardItem(
      subject: 'Bangla Grammar',
      topic: 'সমাস',
      title: 'ছয় প্রকার সমাস এক নজরে',
      content:
          'দ্বন্দ্ব: উভয় পদের অর্থ প্রাধান্য\n'
          'দ্বিগু: সংখ্যাবাচক পূর্বপদ, সমাহার বোঝায়\n'
          'কর্মধারয়: বিশেষণ + বিশেষ্য, পরপদের অর্থ প্রাধান্য\n'
          'তৎপুরুষ: পরপদের অর্থ প্রাধান্য, পূর্বপদের বিভক্তি লোপ\n'
          'বহুব্রীহি: কোনো পদেরই অর্থ নয়, তৃতীয় কিছু বোঝায়\n'
          'অব্যয়ীভাব: অব্যয় পূর্বপদ, পূর্বপদের অর্থ প্রাধান্য',
      mnemonic: 'দ্বন্দ্বে দুই, দ্বিগুতে সংখ্যা, বহুব্রীহিতে বাইরের কেউ',
      tag: 'Rule',
    ),
    FlashcardItem(
      subject: 'Bangla Grammar',
      topic: 'কারক',
      title: 'কারক চেনার প্রশ্নসূত্র',
      content:
          'কর্তৃ: কে? কারা?\nকর্ম: কাকে? কী?\nকরণ: কী দিয়ে? কীসের দ্বারা?\n'
          'সম্প্রদান: স্বত্ব ত্যাগ করে কাকে?\nঅপাদান: কোথা থেকে? কী হতে?\n'
          'অধিকরণ: কোথায়? কখন?',
      mnemonic: 'ক্রিয়াকে প্রশ্ন করুন — উত্তরটাই কারক',
      tag: 'Rule',
    ),
    FlashcardItem(
      subject: 'Bangladesh Affairs',
      topic: 'সংবিধান',
      title: 'সংবিধানের মূলনীতি ও গুরুত্বপূর্ণ অনুচ্ছেদ',
      content:
          'রাষ্ট্র পরিচালনার মূলনীতি চারটি: জাতীয়তাবাদ, সমাজতন্ত্র, গণতন্ত্র, ধর্মনিরপেক্ষতা\n'
          'অনুচ্ছেদ ২৭: আইনের দৃষ্টিতে সমতা\n'
          'অনুচ্ছেদ ২৮: বৈষম্য থেকে অব্যাহতি\n'
          'অনুচ্ছেদ ৩৯: চিন্তা ও বিবেকের স্বাধীনতা',
      mnemonic: 'মূলনীতি চারটি — জা-স-গ-ধ',
      tag: 'Fact',
    ),
    FlashcardItem(
      subject: 'Bangla Literature',
      topic: 'সাহিত্যিক পরিচিতি',
      title: 'রবীন্দ্রনাথের নোবেল',
      content:
          'রবীন্দ্রনাথ ঠাকুর ১৯১৩ সালে সাহিত্যে নোবেল পুরস্কার পান, '
          '"গীতাঞ্জলি" কাব্যগ্রন্থের ইংরেজি অনুবাদ Song Offerings-এর জন্য।\n'
          'তিনিই এশিয়ার প্রথম নোবেল বিজয়ী।',
      mnemonic: '১৯১৩ — গীতাঞ্জলি — এশিয়ার প্রথম',
      tag: 'Fact',
    ),
    FlashcardItem(
      subject: 'English Grammar',
      topic: 'Subject-Verb Agreement',
      title: 'Each / Every / None অনুসরণে Verb',
      content:
          'Each, every, everyone, nobody, none, either, neither — '
          'এগুলোর পরে সর্বদা singular verb বসে।\n'
          'Each of the boys WAS present. (were নয়)',
      mnemonic: 'Each/Every দিয়ে শুরু হলেই verb একবচন',
      tag: 'Rule',
    ),
  ];

  /// Gets a flashcard item either from curated bank or dynamically from user's weak topics / mistakes
  /// Picks a batch of distinct cards for the scheduled push series.
  ///
  /// Due spaced-review items come first, because those are the ones the user
  /// actually asked to be reminded of; the curated deck fills the rest. Cards
  /// are not repeated within a batch — the same card arriving three times in
  /// an afternoon is how a useful nudge becomes noise.
  Future<List<FlashcardItem>> getFlashcardBatch({
    AppDatabase? db,
    required int count,
    String? preferredSubject,
  }) async {
    if (count <= 0) return const [];

    final picked = <FlashcardItem>[];
    final seenTitles = <String>{};

    if (db != null) {
      try {
        for (final review in await db.getDueSpacedReviewItems()) {
          if (picked.length >= count) break;
          if (!seenTitles.add(review.title)) continue;
          picked.add(
            FlashcardItem(
              subject: review.subject,
              topic: review.topic,
              title: review.title,
              content: review.keyRule,
              tag: 'SpacedReview',
              reviewItemId: review.id,
            ),
          );
        }
      } catch (e) {
        debugPrint('Error loading due reviews for flashcard batch: $e');
      }
    }

    if (picked.length < count) {
      final pool = [...curatedFlashcards]..shuffle(Random());
      for (final card in pool) {
        if (picked.length >= count) break;
        if (preferredSubject != null &&
            preferredSubject.isNotEmpty &&
            !card.subject.toLowerCase().contains(
              preferredSubject.toLowerCase(),
            )) {
          continue;
        }
        if (!seenTitles.add(card.title)) continue;
        picked.add(card);
      }
    }

    return picked;
  }

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
            reviewItemId: review.id,
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
