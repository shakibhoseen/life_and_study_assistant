/// Decides which slices of the user's stored context a given chat message
/// actually needs.
///
/// The mentor prompt used to carry every slice on every message: energy,
/// fatigue, the whole weak-topic list and every upcoming exam. For a plain
/// teaching question ("সমাস বুঝিয়ে দাও") none of that changes the answer, so
/// it was paid for on every turn and bought nothing.
///
/// The rule here is: send context when it can change the reply, otherwise
/// leave it out. Detection is local keyword matching -- free and instant, as
/// opposed to asking the model what it needs, which costs an extra round trip
/// every turn to save part of one.
///
/// The matcher errs towards *including* context: a missed slice degrades the
/// answer, an extra one only costs a few tokens.
library;

/// Which context slices a message needs.
class ChatContextNeeds {
  /// Today's energy level / office fatigue and the workday-vs-off-day line.
  final bool energy;

  /// The user's registered weak topics.
  final bool weakTopics;

  /// Upcoming LiveMCQ exams.
  final bool exams;

  /// When set, weak topics are narrowed to this subject.
  final String? subjectFilter;

  /// True when a slice was forced in by a safety rule rather than by intent
  /// (imminent exam, or exhaustion high enough to matter regardless).
  final bool forcedBySafety;

  const ChatContextNeeds({
    this.energy = false,
    this.weakTopics = false,
    this.exams = false,
    this.subjectFilter,
    this.forcedBySafety = false,
  });

  bool get isEmpty => !energy && !weakTopics && !exams;

  ChatContextNeeds copyWith({
    bool? energy,
    bool? weakTopics,
    bool? exams,
    String? subjectFilter,
    bool? forcedBySafety,
  }) {
    return ChatContextNeeds(
      energy: energy ?? this.energy,
      weakTopics: weakTopics ?? this.weakTopics,
      exams: exams ?? this.exams,
      subjectFilter: subjectFilter ?? this.subjectFilter,
      forcedBySafety: forcedBySafety ?? this.forcedBySafety,
    );
  }

  @override
  String toString() =>
      'ChatContextNeeds(energy: $energy, weakTopics: $weakTopics, '
      'exams: $exams, subject: $subjectFilter)';
}

class ChatContextResolver {
  ChatContextResolver._();

  /// Fatigue at or above this is relevant to *any* answer, because it changes
  /// how much work the mentor is allowed to prescribe.
  static const int fatigueAlwaysRelevantThreshold = 7;

  /// An exam this close is relevant whatever the user asked about.
  static const int imminentExamDays = 3;

  /// "What should I study / plan my time" -- needs the full picture.
  static const List<String> planningKeywords = [
    'পড়ব',
    'পড়বো',
    'পড়ি',
    'কী পড়',
    'কি পড়',
    'কোথা থেকে',
    'শুরু',
    'প্ল্যান',
    'পরিকল্পনা',
    'রুটিন',
    'সময়',
    'শিডিউল',
    'কতক্ষণ',
    'টাস্ক',
    'পরামর্শ',
    'প্রস্তুতি',
    'আজকে কি',
    'আজ কি',
    'আজকে কী',
    'আজ কী',
    'plan',
    'routine',
    'schedule',
    'today',
    'time',
    'task',
    'advice',
    'suggest',
    'prepare',
    'preparation',
    'start',
    'study what',
    'what should',
    'porbo',
    'porum',
    'ki pori',
    'ki porbo',
    'plan koro',
  ];

  /// Tiredness / wellbeing.
  static const List<String> energyKeywords = [
    'ক্লান্ত',
    'ক্লান্তি',
    'টায়ার্ড',
    'এনার্জি',
    'ঘুম',
    'বিশ্রাম',
    'রেস্ট',
    'মুড',
    'অফিস',
    'চাপ',
    'স্ট্রেস',
    'বার্নআউট',
    'মাথা ধরে',
    'পারছি না',
    'tired',
    'fatigue',
    'energy',
    'sleep',
    'rest',
    'mood',
    'office',
    'stress',
    'burnout',
    'exhaust',
    'break',
    'klanto',
    'tired lagche',
    'energy nai',
  ];

  /// Exams as a *schedule*: when, how soon, what is coming up.
  ///
  /// Deliberately excludes "MCQ", "BCS" and bare "পরীক্ষা". Measured against
  /// real messages, those are everyday vocabulary here -- "BCS পরীক্ষার কমন
  /// ফাঁদ বুঝিয়ে দাও" is a teaching request, not a question about dates -- and
  /// treating them as schedule intent attached the exam list to ordinary
  /// study questions. A genuinely imminent exam still gets through via the
  /// [imminentExamDays] safety override.
  static const List<String> examKeywords = [
    'কবে',
    'কত দিন',
    'কতদিন',
    'কয়দিন',
    'তারিখ',
    'ডেডলাইন',
    'সময়সূচি',
    'পরবর্তী পরীক্ষা',
    'আসন্ন',
    'সামনের পরীক্ষা',
    'পরীক্ষা কবে',
    'রুটিন',
    'সিলেবাস',
    'মডেল টেস্ট',
    'শিডিউল',
    'কাউন্টডাউন',
    'next exam',
    'upcoming',
    'deadline',
    'countdown',
    'when is',
    'exam date',
    'schedule',
    'syllabus',
    'routine',
    'model test',
    'rutine',
    'porikkha kobe',
    'kobe',
  ];

  /// Progress / weakness review.
  static const List<String> weaknessKeywords = [
    'দুর্বল',
    'উন্নতি',
    'অগ্রগতি',
    'কেমন করছি',
    'ভালো করছি',
    'রিভিশন',
    'রিভিউ',
    'ভুল',
    'কাঁচা',
    'আটকে',
    'weak',
    'weakness',
    'progress',
    'improve',
    'improvement',
    'revision',
    'review',
    'mistake',
    'struggling',
    'stuck',
    'durbol',
    'vul',
  ];

  static bool _matchesAny(String haystack, List<String> needles) {
    for (final n in needles) {
      if (haystack.contains(n)) return true;
    }
    return false;
  }

  /// Works out which slices [userMessage] needs.
  ///
  /// [knownSubjects] are the subject names actually stored in the user's
  /// database, so a mention of one narrows the weak-topic list to that
  /// subject rather than sending every subject. [fatigueScore] and
  /// [daysToNextExam] drive the safety overrides.
  static ChatContextNeeds resolve({
    required String userMessage,
    String? sessionSubject,
    String? sessionTopic,
    List<String> knownSubjects = const [],
    int? fatigueScore,
    int? daysToNextExam,
    bool isFirstMessageInSession = false,
  }) {
    final text = userMessage.toLowerCase();

    final planning = _matchesAny(text, planningKeywords);
    final energyAsked = _matchesAny(text, energyKeywords);
    final examAsked = _matchesAny(text, examKeywords);
    final weaknessAsked = _matchesAny(text, weaknessKeywords);

    // Opening a thread: the mentor has no history at all, so give it the
    // baseline picture once instead of answering blind.
    if (isFirstMessageInSession) {
      return ChatContextNeeds(
        energy: true,
        weakTopics: true,
        exams: true,
        subjectFilter: _subjectFor(text, sessionSubject, knownSubjects),
      );
    }

    var needs = ChatContextNeeds(
      energy: planning || energyAsked,
      weakTopics: planning || weaknessAsked,
      exams: planning || examAsked,
      subjectFilter: _subjectFor(text, sessionSubject, knownSubjects),
    );

    // Safety overrides: things the mentor must not answer without, whatever
    // the user happened to ask about.
    var forced = false;
    if (fatigueScore != null &&
        fatigueScore >= fatigueAlwaysRelevantThreshold &&
        !needs.energy) {
      needs = needs.copyWith(energy: true);
      forced = true;
    }
    if (daysToNextExam != null &&
        daysToNextExam <= imminentExamDays &&
        !needs.exams) {
      needs = needs.copyWith(exams: true);
      forced = true;
    }

    // A dedicated topic thread is about one subject; its weak topics are the
    // whole point of the thread, and they are only a line or two once
    // filtered.
    if (sessionSubject != null &&
        sessionSubject.isNotEmpty &&
        !needs.weakTopics) {
      needs = needs.copyWith(weakTopics: true);
    }

    return needs.copyWith(forcedBySafety: forced);
  }

  /// Picks the subject to narrow weak topics to: one the user named in the
  /// message, else the thread's own subject.
  static String? _subjectFor(
    String lowercaseText,
    String? sessionSubject,
    List<String> knownSubjects,
  ) {
    for (final s in knownSubjects) {
      final trimmed = s.trim();
      if (trimmed.isEmpty) continue;
      if (lowercaseText.contains(trimmed.toLowerCase())) return trimmed;
    }
    if (sessionSubject != null && sessionSubject.trim().isNotEmpty) {
      return sessionSubject.trim();
    }
    return null;
  }
}
