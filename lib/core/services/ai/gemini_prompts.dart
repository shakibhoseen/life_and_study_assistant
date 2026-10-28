import 'dart:convert';

import 'package:google_generative_ai/google_generative_ai.dart';

import 'chat_context_resolver.dart';

/// Shape of an adaptive study plan.
///
/// Field names must match what AdaptiveStudyPlan.fromJson and StudyTask read.
/// This lived in the prompt as example JSON; the API enforces it from here,
/// which also stops the model inventing fields or dropping required ones.
final studyPlanSchema = Schema.object(
  properties: {
    'date': Schema.string(description: 'Today, YYYY-MM-DD'),
    'energyLevel': Schema.string(),
    'fatigueScore': Schema.integer(),
    'motivationalQuote': Schema.string(
      description: 'Short, empathetic, non-cliche; English or Bengali',
    ),
    'summary': Schema.string(
      description: "1-2 sentences on tonight's realistic goal",
    ),
    'recommendedStudyMinutes': Schema.integer(
      description: 'Total study minutes, typically 10-45 on a work day',
    ),
    'recommendedFamilyMinutes': Schema.integer(description: 'Typically 45-120'),
    'familyAndWellbeingAdvice': Schema.string(
      description: 'Winding down with family and sleep hygiene',
    ),
    'burnoutWarning': Schema.string(
      description: 'Only when fatigue is high, otherwise null',
      nullable: true,
    ),
    'tasks': Schema.array(
      items: Schema.object(
        properties: {
          'id': Schema.string(description: 'task_1, task_2, ...'),
          'title': Schema.string(),
          'subject': Schema.string(),
          'estimatedMinutes': Schema.integer(),
          'taskType': Schema.string(description: 'e.g. micro_mcq, revision'),
          'actionablePrompt': Schema.string(
            description: 'The specific action to take in LiveMCQ or notes',
          ),
        },
        requiredProperties: [
          'id',
          'title',
          'subject',
          'estimatedMinutes',
          'taskType',
          'actionablePrompt',
        ],
      ),
    ),
  },
  requiredProperties: [
    'date',
    'energyLevel',
    'fatigueScore',
    'motivationalQuote',
    'summary',
    'recommendedStudyMinutes',
    'recommendedFamilyMinutes',
    'familyAndWellbeingAdvice',
    'tasks',
  ],
);

class GeminiPrompts {
  /// Upper bound on study-sheet text handed to the model.
  static const int maxStudySheetChars = 6000;

  /// Shared instruction for the non-chat services.
  ///
  /// Two things used to live here and no longer do. The typography rules are
  /// enforced deterministically by [BengaliMathSanitizer] after the fact, so
  /// spelling them out cost ~200 tokens a call for a second safety net. And
  /// the "respond only in JSON" tenet was simply wrong for half the callers:
  /// explainMistake and getExamQuickRevision want prose, and were being told
  /// the opposite. Output shape is now set per call via GenerationConfig.
  static const String systemInstruction = '''
You are "Life & Study Companion", a compassionate and highly strategic personal AI mentor for a full-time Software Engineer preparing for competitive government examinations (such as BCS) alongside grueling office hours.

Key Tenets:
1. PREVENT BURNOUT AT ALL COSTS. The user writes code all day and has mental exhaustion. Never assign unrealistic 3-4 hour study blocks.
2. MICRO-COMMITMENTS: When energy is LOW or office fatigue is high (>=7/10), prescribe ultra-short micro-tasks (5-15 mins maximum). Explicitly tell them to spend the rest of the evening relaxing with spouse/family guilt-free.
3. WEAK TOPIC PRIORITY: Target the user's specific weak points (Bangla grammar, Math, Science, etc.) tied to their upcoming LiveMCQ exams.
4. ACTIONABLE & PRECISE: Tasks must specify exactly what to do and time in minutes.
5. Write maths and science in native Unicode (১৮০°, →, ×, a² + b², √, π), never LaTeX or \$...\$ delimiters.
''';

  static String buildStudyPlanPrompt({
    required String energyLevel,
    required int fatigueScore,
    required List<Map<String, dynamic>> weakTopics,
    required List<Map<String, dynamic>> upcomingExams,
    bool isOffDay = false,
  }) {
    final scheduleContext = isOffDay
        ? 'SPECIAL SCHEDULE: TODAY IS AN OFF-DAY / WEEKEND (NO OFFICE WORK)! The user has Thursday/Friday off. This is their prime BCS acceleration day! Schedule deeper focus study blocks (e.g. 60-120 mins total), model tests on LiveMCQ, and thorough weak topic drills, while reserving ample quality time for family/spouse.'
        : 'SCHEDULE: Regular office day with coding hours. Office fatigue is $fatigueScore/10. Emphasize micro-commitments (5-20 mins) and burnout prevention.';

    return '''
Generate a personalized, adaptive daily study plan for today based on the user's status:

$scheduleContext
User Energy Level: $energyLevel
Office Fatigue Score: $fatigueScore / 10
Identified Weak Topics (JSON):
${jsonEncode(weakTopics)}

Upcoming LiveMCQ Exams & Multi-Track Schedule (JSON):
${jsonEncode(upcomingExams)}

NOTE ON MULTI-TRACK ROUTINES:
The user attends multiple concurrent LiveMCQ tracks (e.g. Daily Vocabulary Booster, 52nd BCS 135-Day Syllabus Routine, Friday Full-Syllabus Mega Model Test, Primary Teacher Exam).
- On office/work days: Favor quick micro-drills from daily tracks like Vocabulary Booster or single-topic syllabus revision (5-20 min).
- On off-days (Thursday/Friday): Schedule deep preparation or review for Full Syllabus Model Tests and upcoming 135-day major exams.

Fill every field of the required schema. Echo back today's date, the energy level and the fatigue score you were given.
''';
  }

  static String buildStudySheetSummaryPrompt({
    required String rawContent,
    String? subject,
  }) {
    // A pasted sheet or OCR dump can be arbitrarily long; past this much the
    // extra text stops adding exam value and only adds cost.
    final content = rawContent.length > maxStudySheetChars
        ? '${rawContent.substring(0, maxStudySheetChars)}…'
        : rawContent;

    return '''
Analyze the following study sheet / topic summary text for a BCS / Competitive Exam candidate${subject != null ? ' in subject $subject' : ''}:

--- STUDY CONTENT ---
$content
---------------------

Synthesize this into a high-yield exam preparation card.
Return a JSON object with this exact structure:
{
  "title": "Concise topic title",
  "highYieldPoints": [
    "High yield point 1 (crisp and exam-focused)",
    "High yield point 2",
    "High yield point 3",
    "High yield point 4",
    "High yield point 5"
  ],
  "recurringPastQuestions": [
    "Frequent past question pattern or examiner trap 1",
    "Frequent past question pattern or examiner trap 2"
  ],
  "mnemonics": [
    "Helpful memory trick or shortcut rule"
  ],
  "quickCheck": [
    {
      "question": "Quick self-check question",
      "answer": "Accurate answer"
    }
  ]
}
''';
  }

  /// Static half of the chat system instruction.
  ///
  /// Deliberately held byte-identical across every request so that it forms a
  /// stable prompt prefix. All volatile context is appended *after* this block
  /// by [buildChatSystemInstruction] rather than interleaved into it, so
  /// changing context never invalidates the shared prefix.
  ///
  /// The typography rules are intentionally terse: [BengaliMathSanitizer]
  /// already rewrites LaTeX, dollar delimiters, fractions, roots, Greek
  /// letters and digit harmonisation deterministically after the fact, so
  /// spelling every rule out here was paying ~400 tokens a message for a
  /// second safety net behind one that never misses.
  static const String chatStaticInstruction = '''
You are "Life & Study Companion", a personal AI mentor and BCS study partner for a full-time Software Engineer.
The user writes code during the day and prepares for Bangladesh Civil Service (BCS) & government competitive exams alongside their job and family life.

Your Personality & Communication Style:
- Warm, empathetic, intellectually sharp, and highly practical.
- Communicate naturally in conversational Bengali (বাংলা) blended smoothly with English technical / exam terms (e.g. "MCQ", "revision", "routine", "shortcut").
- Never give overwhelming lectures. Break hard concepts into digestible bullet points, real-life analogies, and mnemonic tricks.
- Answer what was actually asked; do not cover the whole topic unless asked to.

INTERACTIVE ACTION TAGS — you can trigger app database actions by appending these exact tags at the bottom of a reply:
[[ACTION:ADD_TOPIC|SubjectName|TopicName|weak]]   e.g. [[ACTION:ADD_TOPIC|বাংলা ব্যাকরণ|সমাস|weak]]
[[ACTION:STUDY_TASK|Task Title|SubjectName|Minutes]]   e.g. [[ACTION:STUDY_TASK|১০টি সমাস প্র্যাকটিস MCQ|বাংলা ব্যাকরণ|10]]
[[ACTION:ADD_EXAM|YYYY-MM-DD|Exam Title|SubjectName|Topics|Track|HH:MM AM/PM]]   e.g. [[ACTION:ADD_EXAM|2026-11-12|বাংলা ব্যাকরণ কুইজ|বাংলা ব্যাকরণ|কারক, সমাস|Self Test|10:00 PM]]
Multi-day routine:
[[ACTION:ROUTINE_PLAN_BEGIN]]
{"title":"১০ দিনের প্ল্যান","subject":"Subject","track":"Self Study","items":[{"date":"YYYY-MM-DD","exam_time":"10:00 PM","subject":"Subject","title":"Day 1: Title","topics":["Topic"],"exam_type":"Study Session"}]}
[[ACTION:ROUTINE_PLAN_END]]

Tag rules:
- Tags are proposals the user taps to apply; never claim you already saved anything.
- Priority: When asked to add/schedule an exam, quiz or self-test, emit ADD_EXAM (or ROUTINE_PLAN); do NOT emit ADD_TOPIC. Use ADD_TOPIC only when discussing weak topics.
- ADD_EXAM: single exam with a real date. Never invent dates.
- Track selection: Track names create category tabs in LiveMCQ Hub. Use "Self Test" for self-tests, "Self Study" for custom exams/study routines, or user-specified track name. NEVER assign AI items to imported official PDF tracks (e.g. "১০০ দিনে বিসিএস", "১৩৫ দিনে বিসিএস") unless explicitly asked. Default: "Self Study".
- ROUTINE_PLAN: multi-day study schedule anchored from tomorrow using CURRENT DATE ANCHOR. Default track "Self Study". For E-{id}, use syllabus & date from REFERENCED ITEMS (ask if missing). Use exam_type "Study Session" / "Revision" ("Mock Test" on final day). Do not misrepresent study sessions as real exams. Append block at the bottom.

OUTPUT FORMAT:
- Write maths and science directly in Unicode (১৮০°, →, ×, ÷, a² + b², √(a²+b²), π, ∠, ½). Never output LaTeX commands or \$...\$ delimiters.
- In Bengali sentences use Bengali digits (১৮০° - ৬০° = ১২০°).
- Use markdown bolding, bullets and short headers so replies scan easily on a phone.
''';

  /// Builds the full chat system instruction: the stable
  /// [chatStaticInstruction] followed by only the context slices that
  /// [needs] says this particular message actually requires.
  ///
  /// When nothing volatile is required the static block is returned on its
  /// own — byte-identical to every other such request, and the cheapest
  /// prompt the mentor can run on.
  static String buildChatSystemInstruction({
    String? energyLevel,
    int? fatigueScore,
    List<Map<String, dynamic>>? weakTopics,
    List<Map<String, dynamic>>? upcomingExams,
    bool isOffDay = false,
    String? sessionSubject,
    String? sessionTopic,
    String? threadSummary,
    String? referencedItems,
    ChatContextNeeds needs = const ChatContextNeeds(
      energy: true,
      weakTopics: true,
      exams: true,
    ),
  }) {
    final context = StringBuffer();

    if (sessionSubject != null &&
        sessionTopic != null &&
        sessionSubject.isNotEmpty &&
        sessionTopic.isNotEmpty) {
      context.writeln(
        'ACTIVE THREAD: dedicated to "$sessionSubject" / "$sessionTopic". Keep strict continuity, build on the conversation so far, and tailor every explanation, mnemonic, trap and MCQ to mastering this topic for BCS.',
      );
    }

    // Never gated: once a thread is long enough to have one, this *is* the
    // conversation as far as the model can see.
    if (threadSummary != null && threadSummary.trim().isNotEmpty) {
      context.writeln(
        'EARLIER IN THIS THREAD (summary of messages no longer replayed):',
      );
      context.writeln(threadSummary.trim());
    }

    // Never gated either: the user pasted these tags to be acted on, so the
    // rows they name are the subject of the message.
    if (referencedItems != null && referencedItems.trim().isNotEmpty) {
      context.writeln(referencedItems.trim());
      context.writeln(
        'Act on these rows when the user asks you to. To propose a change, '
        'emit the matching ACTION tag; never claim you have already changed '
        'anything.',
      );
    }

    if (needs.energy) {
      context.writeln(
        isOffDay
            ? 'Schedule: OFF-DAY today (no office). Deep prep, revision or relaxed family time are all available.'
            : 'Schedule: regular office workday.',
      );

      if (energyLevel != null || fatigueScore != null) {
        context.writeln(
          'Today\'s Energy Level: ${energyLevel ?? "Moderate"} | Office Fatigue Score: ${fatigueScore ?? 5}/10',
        );
        if (!isOffDay && (fatigueScore ?? 0) >= 7) {
          context.writeln(
            'NOTE: exhausted from office today — keep any study advice to 5-15 minute micro-sessions and prioritise rest.',
          );
        }
      }
    }

    if (needs.weakTopics && weakTopics != null && weakTopics.isNotEmpty) {
      context.writeln('Weak topics (weakest first):');
      for (final t in weakTopics) {
        context.writeln(
          '- ${t['subject']} / ${t['topic']} (${t['proficiency']})',
        );
      }
    }

    if (needs.exams && upcomingExams != null && upcomingExams.isNotEmpty) {
      context.writeln('Nearest exams:');
      for (final e in upcomingExams) {
        final track = e['track'] != null ? ' [${e['track']}]' : '';
        final days = e['daysAway'];
        final whenStr = days is int
            ? (days <= 0
                  ? 'today'
                  : days == 1
                  ? 'tomorrow'
                  : 'in $days days')
            : '${e['examDate']}';
        final topics = _shorten(e['topics']?.toString(), 80);
        final topicsStr = topics.isEmpty ? '' : ' — $topics';
        context.writeln('- ${e['title']}$track, $whenStr$topicsStr');
      }
    }

    if (context.isEmpty) return chatStaticInstruction;

    final todayStr = DateTime.now().toIso8601String().substring(0, 10);
    return '$chatStaticInstruction'
        '--- CURRENT USER CONTEXT ---\n'
        'CURRENT DATE ANCHOR: Today is $todayStr.\n'
        '$context'
        '----------------------------\n';
  }

  /// Trims a context value to [max] characters on a word boundary.
  static String _shorten(String? value, int max) {
    final v = value?.trim() ?? '';
    if (v.length <= max) return v;
    final cut = v.substring(0, max);
    final lastSpace = cut.lastIndexOf(' ');
    return '${lastSpace > max ~/ 2 ? cut.substring(0, lastSpace) : cut}…';
  }
}
