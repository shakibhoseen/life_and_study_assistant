import 'dart:convert';

import '../../../../core/services/ai/models/parsed_routine_item.dart';

enum ChatActionType {
  addTopic,
  studyTask,
  addExam,
  routinePlan,
  fixExam,
  addFlashcard,
  unknown,
}

class ChatAction {
  final ChatActionType type;
  final String title;
  final String subject;
  final String? topic;
  final String? proficiency;
  final int? minutes;

  /// Set only for [ChatActionType.addExam]: the exam this reply offers to put
  /// in the routine.
  final String? examDate;
  final String? examTime;
  final String? trackName;

  /// Set for [ChatActionType.routinePlan]: JSON payload containing the routine items.
  final String? routineJson;

  /// Set for [ChatActionType.fixExam]: target exam ID and corrections JSON.
  final int? examId;
  final String? correctionsJson;

  /// Set for [ChatActionType.addFlashcard]: the formula, key rule, or explanation on the back of the card.
  final String? keyRule;

  final bool isExecuted;

  const ChatAction({
    required this.type,
    required this.title,
    required this.subject,
    this.topic,
    this.proficiency,
    this.minutes,
    this.examDate,
    this.examTime,
    this.trackName,
    this.routineJson,
    this.examId,
    this.correctionsJson,
    this.keyRule,
    this.isExecuted = false,
  });

  /// Returns a display/persistence-ready track name, defaulting intelligently
  /// to 'Self Test' for self tests or 'Self Study' for custom mentor exams
  /// so they never accidentally pollute official PDF tracks.
  String get effectiveTrackName {
    if (trackName != null && trackName!.trim().isNotEmpty) {
      return trackName!.trim();
    }
    final lower = title.toLowerCase();
    if (lower.contains('self test') || title.contains('সেলফ টেস্ট')) {
      return 'Self Test';
    }
    return 'Self Study';
  }

  /// Deserializes [routineJson] into structured [ParsedRoutineItem] rows.
  List<ParsedRoutineItem> get routineItems {
    if (routineJson == null || routineJson!.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(routineJson!);
      List<dynamic> itemsList;
      String? defaultTrack = trackName;
      if (decoded is Map<String, dynamic>) {
        defaultTrack = decoded['track']?.toString() ?? defaultTrack;
        itemsList = decoded['items'] as List<dynamic>? ?? const [];
      } else if (decoded is List) {
        itemsList = decoded;
      } else {
        return const [];
      }
      return itemsList
          .whereType<Map<String, dynamic>>()
          .map(
            (m) => ParsedRoutineItem.fromJson(
              m,
              defaultTrack: defaultTrack,
              rawRef: 'AI Mentor Plan',
            ),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  ChatAction copyWith({
    bool? isExecuted,
    String? routineJson,
    int? examId,
    String? correctionsJson,
    String? keyRule,
  }) {
    return ChatAction(
      type: type,
      title: title,
      subject: subject,
      topic: topic,
      proficiency: proficiency,
      minutes: minutes,
      examDate: examDate,
      examTime: examTime,
      trackName: trackName,
      routineJson: routineJson ?? this.routineJson,
      examId: examId ?? this.examId,
      correctionsJson: correctionsJson ?? this.correctionsJson,
      keyRule: keyRule ?? this.keyRule,
      isExecuted: isExecuted ?? this.isExecuted,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'title': title,
    'subject': subject,
    'topic': topic,
    'proficiency': proficiency,
    'minutes': minutes,
    'examDate': examDate,
    'examTime': examTime,
    'trackName': trackName,
    'routineJson': routineJson,
    'examId': examId,
    'correctionsJson': correctionsJson,
    'keyRule': keyRule,
    'isExecuted': isExecuted,
  };

  factory ChatAction.fromJson(Map<String, dynamic> json) {
    ChatActionType type;
    switch (json['type']) {
      case 'addTopic':
        type = ChatActionType.addTopic;
        break;
      case 'studyTask':
        type = ChatActionType.studyTask;
        break;
      case 'addExam':
        type = ChatActionType.addExam;
        break;
      case 'routinePlan':
        type = ChatActionType.routinePlan;
        break;
      case 'fixExam':
        type = ChatActionType.fixExam;
        break;
      case 'addFlashcard':
        type = ChatActionType.addFlashcard;
        break;
      default:
        type = ChatActionType.unknown;
    }
    return ChatAction(
      type: type,
      title: json['title'] as String? ?? '',
      subject: json['subject'] as String? ?? 'General',
      topic: json['topic'] as String?,
      proficiency: json['proficiency'] as String?,
      minutes: json['minutes'] as int?,
      examDate: json['examDate'] as String?,
      examTime: json['examTime'] as String?,
      trackName: json['trackName'] as String?,
      routineJson: json['routineJson'] as String?,
      examId: (json['examId'] as num?)?.toInt(),
      correctionsJson: json['correctionsJson'] as String?,
      keyRule: json['keyRule'] as String?,
      isExecuted: json['isExecuted'] as bool? ?? false,
    );
  }

  static String? encodeList(List<ChatAction> actions) {
    if (actions.isEmpty) return null;
    return jsonEncode(actions.map((a) => a.toJson()).toList());
  }

  static List<ChatAction> decodeList(String? jsonStr) {
    if (jsonStr == null || jsonStr.trim().isEmpty) return [];
    try {
      final List<dynamic> decoded = jsonDecode(jsonStr);
      return decoded
          .map((e) => ChatAction.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Parses custom action tags from Gemini text response:
  /// [[ACTION:ADD_TOPIC|Subject|TopicName|weak]]
  /// [[ACTION:STUDY_TASK|Title|Subject|Minutes]]
  /// [[ACTION:ADD_EXAM|YYYY-MM-DD|Title|Subject|Topics|Track|HH:MM AM/PM]]
  static List<ChatAction> extractActions(String rawText) {
    final actions = <ChatAction>[];

    // Regex for ADD_TOPIC: [[ACTION:ADD_TOPIC|Subject|TopicName|proficiency]]
    final addTopicRegex = RegExp(
      r'\[\[ACTION:ADD_TOPIC\|([^|\]]+)\|([^|\]]+)(?:\|([^|\]]+))?\]\]',
      caseSensitive: false,
    );
    for (final match in addTopicRegex.allMatches(rawText)) {
      final subject = match.group(1)?.trim() ?? 'General';
      final topic = match.group(2)?.trim() ?? '';
      final prof = match.group(3)?.trim().toLowerCase() ?? 'weak';
      if (topic.isNotEmpty) {
        actions.add(
          ChatAction(
            type: ChatActionType.addTopic,
            title: 'Add "$topic" to Weak Topics',
            subject: subject,
            topic: topic,
            proficiency: prof,
          ),
        );
      }
    }

    // Regex for STUDY_TASK: [[ACTION:STUDY_TASK|Title|Subject|Minutes]]
    final studyTaskRegex = RegExp(
      r'\[\[ACTION:STUDY_TASK\|([^|\]]+)\|([^|\]]+)(?:\|(\d+))?\]\]',
      caseSensitive: false,
    );
    for (final match in studyTaskRegex.allMatches(rawText)) {
      final title = match.group(1)?.trim() ?? 'Study Task';
      final subject = match.group(2)?.trim() ?? 'General';
      final mins = int.tryParse(match.group(3)?.trim() ?? '10') ?? 10;
      actions.add(
        ChatAction(
          type: ChatActionType.studyTask,
          title: title,
          subject: subject,
          minutes: mins,
        ),
      );
    }

    // ADD_EXAM: [[ACTION:ADD_EXAM|date|title|subject|topics|track|time]]
    // Only the first three fields are required; a reply that cannot name a
    // date is not offering to schedule anything.
    final addExamRegex = RegExp(
      r'\[\[ACTION:ADD_EXAM\|([^|\]]+)\|([^|\]]+)\|([^|\]]+)'
      r'(?:\|([^|\]]*))?(?:\|([^|\]]*))?(?:\|([^|\]]*))?\]\]',
      caseSensitive: false,
    );
    for (final match in addExamRegex.allMatches(rawText)) {
      final dateStr = match.group(1)?.trim() ?? '';
      final parsedDate = DateTime.tryParse(dateStr);
      if (parsedDate == null) continue;

      final title = match.group(2)?.trim() ?? '';
      final subject = match.group(3)?.trim() ?? 'General';
      if (title.isEmpty) continue;

      final topics = match.group(4)?.trim() ?? '';
      String track = match.group(5)?.trim() ?? '';
      final time = match.group(6)?.trim() ?? '';

      // Normalize track for self-tests and custom AI exams
      final lowerTitle = title.toLowerCase();
      if (lowerTitle.contains('self test') || title.contains('সেলফ টেস্ট')) {
        if (track.isEmpty ||
            track == 'General BCS' ||
            track == '১০০ দিনে বিসিএস') {
          track = 'Self Test';
        }
      } else if (lowerTitle.contains('self study') ||
          title.contains('সেলফ স্টাডি')) {
        if (track.isEmpty ||
            track == 'General BCS' ||
            track == '১০০ দিনে বিসিএস') {
          track = 'Self Study';
        }
      }

      actions.add(
        ChatAction(
          type: ChatActionType.addExam,
          title: title,
          subject: subject,
          topic: topics.isEmpty ? null : topics,
          examDate: dateStr,
          examTime: time.isEmpty ? null : time,
          trackName: track.isEmpty ? null : track,
        ),
      );
    }

    // 1. ROUTINE_PLAN: [[ACTION:ROUTINE_PLAN_BEGIN]] ... [[ACTION:ROUTINE_PLAN_END]]
    final routinePlanBlockRegex = RegExp(
      r'\[\[ACTION:ROUTINE_PLAN_BEGIN\]\]([\s\S]*?)\[\[ACTION:ROUTINE_PLAN_END\]\]',
      caseSensitive: false,
    );
    for (final match in routinePlanBlockRegex.allMatches(rawText)) {
      final jsonPayload = match.group(1)?.trim() ?? '';
      if (jsonPayload.isNotEmpty) {
        _parseRoutinePlanPayload(jsonPayload, actions);
      }
    }

    // 2. Fallback single tag: [[ACTION:ROUTINE_PLAN|...]]
    // Only if not already extracted from the block format
    if (!actions.any((a) => a.type == ChatActionType.routinePlan)) {
      final routinePlanSingleRegex = RegExp(
        r'\[\[ACTION:ROUTINE_PLAN\|([\s\S]*?)\]\]',
        caseSensitive: false,
      );
      for (final match in routinePlanSingleRegex.allMatches(rawText)) {
        final payload = match.group(1)?.trim() ?? '';
        if (payload.isNotEmpty) {
          _parseRoutinePlanPayload(payload, actions);
          break;
        }
      }
    }

    // 3. FIX_EXAM: [[ACTION:FIX_EXAM_BEGIN|examId|title]] ... [[ACTION:FIX_EXAM_END]]
    final fixExamBlockRegex = RegExp(
      r'\[\[ACTION:FIX_EXAM_BEGIN\|(\d+)\|([^\]]*)\]\]([\s\S]*?)\[\[ACTION:FIX_EXAM_END\]\]',
      caseSensitive: false,
    );
    for (final match in fixExamBlockRegex.allMatches(rawText)) {
      final examId = int.tryParse(match.group(1) ?? '');
      final title = match.group(2)?.trim() ?? 'পরীক্ষার প্রশ্ন সংশোধন';
      final jsonPayload = match.group(3)?.trim() ?? '';
      if (examId != null && jsonPayload.isNotEmpty) {
        actions.add(
          ChatAction(
            type: ChatActionType.fixExam,
            title: title.isEmpty ? 'E-$examId প্রশ্ন সংশোধন' : title,
            subject: 'Exam Fix',
            examId: examId,
            correctionsJson: jsonPayload,
          ),
        );
      }
    }

    // 4. ADD_FLASHCARD: [[ACTION:ADD_FLASHCARD|Subject|Topic|Title|KeyRule]]
    final addFlashcardRegex = RegExp(
      r'\[\[ACTION:ADD_FLASHCARD\|([^|\]]+)\|([^|\]]+)\|([^|\]]+)\|([^|\]]+)\]\]',
      caseSensitive: false,
    );
    for (final match in addFlashcardRegex.allMatches(rawText)) {
      final subject = match.group(1)?.trim() ?? 'General';
      final topic = match.group(2)?.trim() ?? 'Flashcard';
      final front = match.group(3)?.trim() ?? '';
      final back = match.group(4)?.trim() ?? '';
      if (front.isNotEmpty && back.isNotEmpty) {
        actions.add(
          ChatAction(
            type: ChatActionType.addFlashcard,
            title: front,
            subject: subject,
            topic: topic,
            keyRule: back,
          ),
        );
      }
    }

    // 5. ADD_FLASHCARD_BLOCK: [[ACTION:ADD_FLASHCARD_BEGIN|Subject|Topic|Title]]\n...\n[[ACTION:ADD_FLASHCARD_END]]
    final addFlashcardBlockRegex = RegExp(
      r'\[\[ACTION:ADD_FLASHCARD_BEGIN\|([^|\]]+)\|([^|\]]+)\|([^|\]]+)\]\]([\s\S]*?)\[\[ACTION:ADD_FLASHCARD_END\]\]',
      caseSensitive: false,
    );
    for (final match in addFlashcardBlockRegex.allMatches(rawText)) {
      final subject = match.group(1)?.trim() ?? 'General';
      final topic = match.group(2)?.trim() ?? 'Flashcard';
      final front = match.group(3)?.trim() ?? '';
      final back = match.group(4)?.trim() ?? '';
      if (front.isNotEmpty && back.isNotEmpty) {
        actions.add(
          ChatAction(
            type: ChatActionType.addFlashcard,
            title: front,
            subject: subject,
            topic: topic,
            keyRule: back,
          ),
        );
      }
    }

    return actions;
  }

  static void _parseRoutinePlanPayload(
    String payload,
    List<ChatAction> actions,
  ) {
    try {
      String jsonStr = payload;
      String? explicitTrack;

      if (payload.startsWith('{') || payload.startsWith('[')) {
        jsonStr = payload;
      } else if (payload.contains('|')) {
        final firstPipe = payload.indexOf('|');
        explicitTrack = payload.substring(0, firstPipe).trim();
        jsonStr = payload.substring(firstPipe + 1).trim();
      }

      final dynamic decoded = jsonDecode(jsonStr);
      List<dynamic> itemsList;
      String title = 'স্টাডি রুটিন';
      String subject = 'General BCS';
      String track = explicitTrack ?? 'AI Study Plan';

      if (decoded is Map<String, dynamic>) {
        title = decoded['title']?.toString().trim() ?? title;
        subject = decoded['subject']?.toString().trim() ?? subject;
        track = decoded['track']?.toString().trim() ?? track;
        itemsList = decoded['items'] as List<dynamic>? ?? const [];
      } else if (decoded is List) {
        itemsList = decoded;
      } else {
        return;
      }

      if (itemsList.isEmpty) return;

      final parsedItems = itemsList
          .whereType<Map<String, dynamic>>()
          .map(
            (m) => ParsedRoutineItem.fromJson(
              m,
              defaultTrack: track,
              rawRef: 'AI Mentor Plan',
            ),
          )
          .toList();

      if (parsedItems.isEmpty) return;

      // Date validation: anchored at today, no dates in distant past (>1 day) or >1 year future
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final minAllowed = todayStart.subtract(const Duration(days: 1));
      final maxAllowed = todayStart.add(const Duration(days: 365));

      final validItems = parsedItems.where((it) {
        final itemDate = DateTime(it.date.year, it.date.month, it.date.day);
        return !itemDate.isBefore(minAllowed) && itemDate.isBefore(maxAllowed);
      }).toList();

      if (validItems.isEmpty) return;

      final cleanJson = jsonEncode({
        'title': title,
        'subject': subject,
        'track': track,
        'items': validItems.map((e) => e.toJson()).toList(),
      });

      actions.add(
        ChatAction(
          type: ChatActionType.routinePlan,
          title: '$title (${_toBengaliDigit(validItems.length)} দিন)',
          subject: subject,
          trackName: track,
          routineJson: cleanJson,
        ),
      );
    } catch (_) {
      // Malformed or invalid JSON is safely dropped
    }
  }

  static String _toBengaliDigit(int n) {
    const en = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const bn = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];
    var s = n.toString();
    for (var i = 0; i < en.length; i++) {
      s = s.replaceAll(en[i], bn[i]);
    }
    return s;
  }

  /// Strips out action tags so clean markdown is displayed to the user
  static String cleanActionTags(String rawText) {
    var cleaned = rawText.replaceAll(
      RegExp(
        r'\[\[ACTION:ROUTINE_PLAN_BEGIN\]\][\s\S]*?\[\[ACTION:ROUTINE_PLAN_END\]\]',
        caseSensitive: false,
      ),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(
        r'\[\[ACTION:ADD_FLASHCARD_BEGIN\|[\s\S]*?\]\][\s\S]*?\[\[ACTION:ADD_FLASHCARD_END\]\]',
        caseSensitive: false,
      ),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(
        r'\[\[ACTION:FIX_EXAM_BEGIN\|[\s\S]*?\]\][\s\S]*?\[\[ACTION:FIX_EXAM_END\]\]',
        caseSensitive: false,
      ),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'\[\[ACTION:ROUTINE_PLAN\|[\s\S]*?\]\]', caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'\[\[ACTION:[^\]]+\]\]', caseSensitive: false),
      '',
    );
    return cleaned.trim();
  }
}
