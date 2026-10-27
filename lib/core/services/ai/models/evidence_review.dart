import '../claim_math_checker.dart';

/// What the app concluded after the user argued their case.
enum EvidenceVerdict {
  /// The reviewer landed somewhere other than the stored answer.
  storedLooksWrong,

  /// The reviewer landed on the stored answer after all.
  storedHolds,

  /// Neither settled it.
  stillUnclear;

  String get headline => switch (this) {
    EvidenceVerdict.storedLooksWrong => 'সংরক্ষিত উত্তরটি ভুল মনে হচ্ছে',
    EvidenceVerdict.storedHolds => 'সংরক্ষিত উত্তরই ঠিক মনে হচ্ছে',
    EvidenceVerdict.stillUnclear => 'এখনো নিষ্পত্তি হয়নি',
  };

  /// True where the result is a standoff rather than an answer.
  bool get isUnsettled => this == EvidenceVerdict.stillUnclear;
}

/// Something wrong with the question itself, rather than with its answer.
///
/// A question whose options repeat the same value cannot be fixed by picking
/// a different one, so this is tracked apart from the answer.
enum QuestionFlaw {
  none,
  duplicateOptions,
  noCorrectOption,
  unclearWording;

  static QuestionFlaw parse(String? raw) =>
      switch ((raw ?? '').trim().toLowerCase()) {
        'duplicate_options' => QuestionFlaw.duplicateOptions,
        'no_correct_option' => QuestionFlaw.noCorrectOption,
        'unclear_wording' => QuestionFlaw.unclearWording,
        _ => QuestionFlaw.none,
      };

  String get label => switch (this) {
    QuestionFlaw.none => '',
    QuestionFlaw.duplicateOptions => 'দুটি অপশন আসলে একই উত্তর',
    QuestionFlaw.noCorrectOption => 'সঠিক উত্তরটি অপশনে নেই',
    QuestionFlaw.unclearWording => 'প্রশ্নের ভাষা অস্পষ্ট',
  };

  /// What the user has to change to put it right.
  String get guidance => switch (this) {
    QuestionFlaw.none => '',
    QuestionFlaw.duplicateOptions => 'একই মানের অপশন দুটির একটি বদলে ভিন্ন একটি বিকল্প দিন, তারপর সঠিক উত্তর বেছে নিন।',
    QuestionFlaw.noCorrectOption => 'কোনো একটি অপশনের জায়গায় সঠিক উত্তরটি বসান, তারপর সেটিকে সঠিক হিসেবে চিহ্নিত করুন।',
    QuestionFlaw.unclearWording =>
      'প্রশ্নের ভাষা স্পষ্ট করে লিখুন, যাতে একটিমাত্র উত্তর খাটে।',
  };
}

/// The reviewer's reply, written without being told which answer is stored.
///
/// Telling a model what is already saved invites it to agree, so this call is
/// answer-blind like the independent solve. The user's argument may of course
/// name the stored answer — that is the user's choice — but the app does not
/// add that nudge itself.
class EvidenceOpinion {
  /// Whether the user's argument holds up when examined on its own.
  final bool userReasoningSound;

  /// Which option the reviewer settled on, or -1 if it would not commit.
  final int reviewerIndex;

  final String reasoning;
  final QuestionFlaw flaw;
  final String? suggestedQuestionText;
  final List<String>? suggestedOptions;

  const EvidenceOpinion({
    required this.userReasoningSound,
    required this.reviewerIndex,
    required this.reasoning,
    required this.flaw,
    this.suggestedQuestionText,
    this.suggestedOptions,
  });

  static EvidenceOpinion? tryFromJson(
    Map<String, Object?> json, {
    required int optionCount,
  }) {
    final reasoning = (json['reasoning'] ?? '').toString().trim();
    if (reasoning.isEmpty) return null;

    final rawIndex = json['reviewer_index'];
    var index = rawIndex is num ? rawIndex.toInt() : -1;
    if (index < 0 || index >= optionCount) index = -1;

    final rawOptions = json['suggested_options'];
    List<String>? options;
    if (rawOptions is List && rawOptions.length >= 2) {
      options = rawOptions.map((e) => e.toString().trim()).toList();
      if (options.any((o) => o.isEmpty)) options = null;
    }

    final rawText = (json['suggested_question_text'] ?? '').toString().trim();

    return EvidenceOpinion(
      userReasoningSound: json['user_reasoning_sound'] == true,
      reviewerIndex: index,
      reasoning: reasoning,
      flaw: QuestionFlaw.parse(json['question_flaw']?.toString()),
      suggestedQuestionText: rawText.isEmpty ? null : rawText,
      suggestedOptions: options,
    );
  }
}

/// A second look at a stored question, taken with the user's own argument in
/// hand — and, like every other check here, decided in code.
class EvidenceReview {
  final EvidenceVerdict verdict;
  final EvidenceOpinion opinion;
  final int storedIndex;

  /// Which option to offer as the replacement, where there is one to offer.
  final int? suggestedCorrectIndex;

  /// What the user's own argument came to when it contained arithmetic.
  ///
  /// A user who writes "১০:৬ মানে ৫:৩" has said something that can be checked
  /// without asking anyone, so it is checked.
  final MathCheck userMathCheck;

  const EvidenceReview({
    required this.verdict,
    required this.opinion,
    required this.storedIndex,
    required this.userMathCheck,
    this.suggestedCorrectIndex,
    this.conflictsWithUserMath = false,
  });

  String get reasoning => opinion.reasoning;
  QuestionFlaw get flaw => opinion.flaw;
  String? get suggestedQuestionText => opinion.suggestedQuestionText;
  List<String>? get suggestedOptions => opinion.suggestedOptions;

  bool get suggestsEdit =>
      suggestedCorrectIndex != null ||
      suggestedQuestionText != null ||
      suggestedOptions != null;

  /// True where the user's arithmetic checked out on its own.
  bool get userArithmeticHolds =>
      userMathCheck.outcome == MathCheckOutcome.holds;

  /// The user's arithmetic checked out, yet the reviewer still chose the
  /// stored option.
  ///
  /// One of the two is wrong and the app cannot tell which, so it says so
  /// instead of quietly siding with the model.
  final bool conflictsWithUserMath;

  /// Whether this was settled rather than merely agreed on.
  ///
  /// A model siding with the user is not proof — it is agreeable. Only the
  /// user's own arithmetic holding up makes it more than that, and not even
  /// then while the reviewer is pulling the other way.
  bool get settled => userArithmeticHolds && !conflictsWithUserMath;

  String get limitations {
    if (conflictsWithUserMath) {
      return 'আপনার হিসাব মিলেছে, কিন্তু যাচাইকারী সংরক্ষিত উত্তরেই স্থির '
          '· External sources not checked';
    }
    return settled
        ? 'আপনার হিসাব যাচাই করা হয়েছে · External sources not checked'
        : 'মডেলের মতামত, স্বাধীন প্রমাণ নয় · External sources not checked';
  }

  /// Works out what the reply means for the stored answer.
  ///
  /// The reviewer was never told what that answer is, so the comparison —
  /// and what it is worth — happens here.
  static EvidenceReview decide({
    required EvidenceOpinion opinion,
    required int storedIndex,
    required String userEvidence,
  }) {
    final mathCheck = ClaimMathChecker.check(userEvidence);
    final index = opinion.reviewerIndex;

    // A question whose options are themselves broken is not settled by
    // choosing among them.
    if (index < 0 || opinion.flaw == QuestionFlaw.duplicateOptions) {
      return EvidenceReview(
        verdict: EvidenceVerdict.stillUnclear,
        opinion: opinion,
        storedIndex: storedIndex,
        userMathCheck: mathCheck,
      );
    }

    if (index != storedIndex) {
      return EvidenceReview(
        verdict: EvidenceVerdict.storedLooksWrong,
        opinion: opinion,
        storedIndex: storedIndex,
        suggestedCorrectIndex: index,
        userMathCheck: mathCheck,
      );
    }

    // The reviewer came down on the stored answer. Where the user's own
    // arithmetic checked out in code, that is a standoff between something
    // proved and something recalled -- and recall does not win it.
    final mathHolds = mathCheck.outcome == MathCheckOutcome.holds;
    if (mathHolds) {
      return EvidenceReview(
        verdict: EvidenceVerdict.stillUnclear,
        opinion: opinion,
        storedIndex: storedIndex,
        userMathCheck: mathCheck,
        conflictsWithUserMath: true,
      );
    }

    return EvidenceReview(
      verdict: EvidenceVerdict.storedHolds,
      opinion: opinion,
      storedIndex: storedIndex,
      userMathCheck: mathCheck,
    );
  }
}
