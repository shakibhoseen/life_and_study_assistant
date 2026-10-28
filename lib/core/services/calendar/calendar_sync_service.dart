import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../database/app_database.dart';
import '../export/app_export_service.dart';

class CalendarSyncService {
  CalendarSyncService._();
  static final CalendarSyncService instance = CalendarSyncService._();

  /// Parse exam time string (e.g., "10:00 PM" or "22:00") and combine with exam date
  DateTime _combineDateAndTime(DateTime date, String timeStr) {
    try {
      final trimmed = timeStr.trim().toUpperCase();
      final isPm = trimmed.contains('PM');
      final isAm = trimmed.contains('AM');

      final cleaned = trimmed.replaceAll('AM', '').replaceAll('PM', '').trim();
      final parts = cleaned.split(':');
      if (parts.isNotEmpty) {
        int hour = int.parse(parts[0].trim());
        int minute = parts.length > 1 ? int.parse(parts[1].trim()) : 0;

        if (isPm && hour < 12) hour += 12;
        if (isAm && hour == 12) hour = 0;

        return DateTime(date.year, date.month, date.day, hour, minute);
      }
    } catch (e) {
      debugPrint('Error parsing exam time "$timeStr": $e');
    }
    // Default to 10:00 PM (22:00)
    return DateTime(date.year, date.month, date.day, 22, 0);
  }

  /// Formats DateTime as UTC string for Google Calendar and iCal (YYYYMMDDTHHMMSSZ)
  String _formatToUtcString(DateTime dt) {
    final utc = dt.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}'
        '${utc.month.toString().padLeft(2, '0')}'
        '${utc.day.toString().padLeft(2, '0')}T'
        '${utc.hour.toString().padLeft(2, '0')}'
        '${utc.minute.toString().padLeft(2, '0')}'
        '${utc.second.toString().padLeft(2, '0')}Z';
  }

  /// Direct 1-tap sync: Opens Google Calendar Web / Native app with pre-filled exam details and 30-min reminder
  Future<bool> addToGoogleCalendar(ExamSchedule exam) async {
    final start = _combineDateAndTime(exam.examDate, exam.examTime);
    final end = start.add(
      const Duration(minutes: 60),
    ); // Typical 1-hour LiveMCQ exam window

    final startUtc = _formatToUtcString(start);
    final endUtc = _formatToUtcString(end);

    final title = '[LiveMCQ] ${exam.title} - ${exam.subject}';
    final details =
        'Program/Track: ${exam.trackName}\n'
        'Exam Time: ${exam.examTime}\n'
        'Topics Covered:\n${exam.topicsCovered}\n\n'
        '---\nSynchronized via Life & Study Assistant';

    final url = Uri.parse(
      'https://calendar.google.com/calendar/render?'
      'action=TEMPLATE&'
      'text=${Uri.encodeComponent(title)}&'
      'dates=$startUtc/$endUtc&'
      'details=${Uri.encodeComponent(details)}&'
      'location=${Uri.encodeComponent("LiveMCQ App / web.livemcq.com")}&'
      'sf=true&output=xml',
    );

    try {
      if (await canLaunchUrl(url)) {
        return await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Error launching calendar URL: $e');
    }
    return false;
  }

  /// Generate a standard .ics iCalendar file for an entire batch or list of exams
  Future<File> generateIcsFile(
    List<ExamSchedule> exams, {
    String trackName = 'LiveMCQ',
    Directory? targetDirectory,
  }) async {
    final buffer = StringBuffer();
    final nowUtc = _formatToUtcString(DateTime.now());

    buffer.writeln('BEGIN:VCALENDAR');
    buffer.writeln('VERSION:2.0');
    buffer.writeln('PRODID:-//Life and Study Assistant//LiveMCQ Sync//EN');
    buffer.writeln('CALSCALE:GREGORIAN');
    buffer.writeln('METHOD:PUBLISH');
    buffer.writeln('X-WR-CALNAME:LiveMCQ - $trackName');
    buffer.writeln('X-WR-TIMEZONE:Asia/Dhaka');

    for (final exam in exams) {
      final start = _combineDateAndTime(exam.examDate, exam.examTime);
      final end = start.add(const Duration(minutes: 60));
      final startUtc = _formatToUtcString(start);
      final endUtc = _formatToUtcString(end);

      final uid =
          'livemcq_${exam.id}_${start.millisecondsSinceEpoch}@lifeandstudy.app';
      final summary = '[LiveMCQ] ${exam.title} (${exam.subject})';
      final description =
          'Batch: ${exam.trackName}\\n'
          'Time: ${exam.examTime}\\n'
          'Syllabus: ${exam.topicsCovered.replaceAll('\n', '\\n')}';

      buffer.writeln('BEGIN:VEVENT');
      buffer.writeln('UID:$uid');
      buffer.writeln('DTSTAMP:$nowUtc');
      buffer.writeln('DTSTART:$startUtc');
      buffer.writeln('DTEND:$endUtc');
      buffer.writeln('SUMMARY:$summary');
      buffer.writeln('DESCRIPTION:$description');
      buffer.writeln('LOCATION:LiveMCQ App');
      buffer.writeln('STATUS:CONFIRMED');

      // 30 minutes prior reminder alert
      buffer.writeln('BEGIN:VALARM');
      buffer.writeln('TRIGGER:-PT30M');
      buffer.writeln('ACTION:DISPLAY');
      buffer.writeln('DESCRIPTION:LiveMCQ Exam in 30 minutes: ${exam.title}');
      buffer.writeln('END:VALARM');

      buffer.writeln('END:VEVENT');
    }

    buffer.writeln('END:VCALENDAR');

    Directory dir;
    if (targetDirectory != null) {
      dir = targetDirectory;
    } else {
      try {
        dir = await AppExportService.getExportDirectory();
      } catch (_) {
        dir = await getTemporaryDirectory();
      }
    }
    final sanitizedTrack = trackName
        .replaceAll(RegExp(r'[^\w\s]+'), '_')
        .replaceAll(' ', '_');
    final file = File('${dir.path}/LiveMCQ_${sanitizedTrack}_Schedule.ics');
    await file.writeAsString(buffer.toString());
    return file;
  }
}
