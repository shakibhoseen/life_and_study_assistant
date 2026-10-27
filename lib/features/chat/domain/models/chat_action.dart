import 'dart:convert';

enum ChatActionType { addTopic, studyTask, unknown }

class ChatAction {
  final ChatActionType type;
  final String title;
  final String subject;
  final String? topic;
  final String? proficiency;
  final int? minutes;
  final bool isExecuted;

  const ChatAction({
    required this.type,
    required this.title,
    required this.subject,
    this.topic,
    this.proficiency,
    this.minutes,
    this.isExecuted = false,
  });

  ChatAction copyWith({bool? isExecuted}) {
    return ChatAction(
      type: type,
      title: title,
      subject: subject,
      topic: topic,
      proficiency: proficiency,
      minutes: minutes,
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

    return actions;
  }

  /// Strips out action tags so clean markdown is displayed to the user
  static String cleanActionTags(String rawText) {
    var cleaned = rawText.replaceAll(
      RegExp(r'\[\[ACTION:[^\]]+\]\]', caseSensitive: false),
      '',
    );
    return cleaned.trim();
  }
}
