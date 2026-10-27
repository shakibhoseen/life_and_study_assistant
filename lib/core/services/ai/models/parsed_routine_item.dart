import 'package:drift/drift.dart';

import '../../../database/app_database.dart';

class ParsedRoutineItem {
  final DateTime date;
  final String examTime;
  final String subject;
  final List<String> topics;
  final String examType;
  final String trackName;
  final String? rawReference;

  ParsedRoutineItem({
    required this.date,
    required this.examTime,
    required this.subject,
    required this.topics,
    required this.examType,
    this.trackName = 'General BCS',
    this.rawReference,
  });

  factory ParsedRoutineItem.fromJson(
    Map<String, dynamic> json, {
    String? rawRef,
    String? defaultTrack,
  }) {
    DateTime parsedDate;
    final dateStr = json['date']?.toString() ?? '';
    try {
      parsedDate = DateTime.parse(dateStr);
    } catch (_) {
      parsedDate = DateTime.now().add(const Duration(days: 1));
    }

    final rawTopics = json['topics'];
    List<String> parsedTopics = [];
    if (rawTopics is List) {
      parsedTopics = rawTopics.map((e) => e.toString().trim()).toList();
    } else if (rawTopics is String) {
      parsedTopics = rawTopics
          .split(RegExp(r'[,;\n]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    final subject = json['subject']?.toString() ?? 'General';
    final examType = json['exam_type']?.toString() ?? 'Daily';
    final examTime = json['exam_time']?.toString() ?? '10:00 PM';
    final trackName =
        json['track_name']?.toString() ?? defaultTrack ?? 'General BCS';

    return ParsedRoutineItem(
      date: parsedDate,
      examTime: examTime,
      subject: subject,
      topics: parsedTopics,
      examType: examType,
      trackName: trackName,
      rawReference: rawRef ?? json['raw_reference']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String().substring(0, 10),
    'exam_time': examTime,
    'subject': subject,
    'topics': topics,
    'exam_type': examType,
    'track_name': trackName,
    'raw_reference': rawReference,
  };

  ExamSchedulesCompanion toCompanion({String? overrideTrack}) {
    final title = '$subject $examType Exam';
    final topicsStr = topics.join(', ');

    return ExamSchedulesCompanion.insert(
      examDate: date,
      examTime: Value(examTime),
      subject: Value(subject),
      title: title,
      topicsCovered: topicsStr.isNotEmpty ? topicsStr : 'General Syllabus',
      examType: Value(examType),
      trackName: Value(overrideTrack ?? trackName),
      resourceSummary: Value(
        rawReference != null ? 'Imported routine ($trackName)' : null,
      ),
      rawReference: Value(rawReference),
    );
  }
}
