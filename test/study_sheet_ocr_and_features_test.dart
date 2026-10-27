import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/services/ai/models/study_sheet_result.dart';
import 'package:life_and_study_assistant/core/services/ai/study_sheet_ocr_service.dart';
import 'package:life_and_study_assistant/core/services/calendar/calendar_sync_service.dart';
import 'package:life_and_study_assistant/core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Study Sheet OCR & Vision Models Tests', () {
    test('StudySheetResult JSON serialization and deserialization', () {
      final json = {
        'title': 'বাংলা ব্যাকরণ - সমাস',
        'subject': 'Bangla Grammar',
        'summary': 'সমাসের বিভিন্ন প্রকারভেদ ও তাদের নির্ণয় পদ্ধতি।',
        'high_yield_points': [
          'পরপদ প্রধান হলে তৎপুরুষ সমাস',
          'পূর্বপদ প্রধান হলে অব্যয়ীভাব সমাস',
        ],
        'key_rules': ['ব্যাসবাক্যে যে বা যিনি থাকলে কর্মধারয়'],
        'questions': [
          {
            'question': 'কোন সমাসে পরপদের অর্থ প্রধান থাকে?',
            'options': [
              'তৎপুরুষ সমাস',
              'দ্বন্দ্ব সমাস',
              'অব্যয়ীভাব সমাস',
              'বহুব্রীহি সমাস',
            ],
            'correct_index': 0,
            'explanation':
                'তৎপুরুষ ও কর্মধারয় সমাসে পরপদের অর্থ প্রাধান্য পায়।',
          },
        ],
      };

      final result = StudySheetResult.fromJson(json, rawRef: 'test_book.jpg');
      expect(result.title, 'বাংলা ব্যাকরণ - সমাস');
      expect(result.subject, 'Bangla Grammar');
      expect(result.highYieldPoints.length, 2);
      expect(result.keyRules.length, 1);
      expect(result.questions.length, 1);
      expect(
        result.questions.first.questionText,
        'কোন সমাসে পরপদের অর্থ প্রধান থাকে?',
      );
      expect(result.questions.first.correctIndex, 0);

      final encoded = result.toJson();
      expect(encoded['title'], 'বাংলা ব্যাকরণ - সমাস');
      expect((encoded['questions'] as List).length, 1);
    });

    test('StudySheetOcrService generates valid 5-MCQ drill offline without Gemini API Key', () async {
      final dummyFile = File('test_page.png');
      final result = await StudySheetOcrService.instance.analyzeStudySheet(
        dummyFile,
        subjectHint: 'Bangla Grammar',
      );

      expect(result.title.isNotEmpty, true);
      expect(result.subject, 'Bangla Grammar');
      expect(result.questions.length, 5);
      expect(result.keyRules.isNotEmpty, true);
      expect(result.highYieldPoints.isNotEmpty, true);

      // Verify each question has 4 options and valid correct index
      for (final q in result.questions) {
        expect(q.options.length, 4);
        expect(q.correctIndex >= 0 && q.correctIndex < 4, true);
        expect(q.explanation.isNotEmpty, true);
      }
    });
  });

  group('Calendar Sync & iCalendar (.ics) Generation Tests', () {
    test('generateIcsFile produces RFC 5545 compliant calendar file with 30m alerts', () async {
      final exam = ExamSchedule(
        id: 101,
        title: '52nd BCS Mega Model Test 01',
        subject: 'General BCS Syllabus',
        examDate: DateTime(2026, 11, 15),
        examTime: '10:00 PM',
        topicsCovered: 'Bangla, English, Math, General Science',
        examType: 'Model Test',
        trackName: '52nd BCS 135-Day',
        completedStatus: false,
        createdAt: DateTime.now(),
      );

      final file = await CalendarSyncService.instance.generateIcsFile(
        [exam],
        trackName: '52nd BCS',
        targetDirectory: Directory.systemTemp,
      );
      expect(file.existsSync(), true);

      final content = await file.readAsString();
      expect(content.contains('BEGIN:VCALENDAR'), true);
      expect(content.contains('VERSION:2.0'), true);
      expect(content.contains('X-WR-CALNAME:LiveMCQ - 52nd BCS'), true);
      expect(content.contains('BEGIN:VEVENT'), true);
      expect(
        content.contains(
          'SUMMARY:[LiveMCQ] 52nd BCS Mega Model Test 01 (General BCS Syllabus)',
        ),
        true,
      );
      expect(content.contains('BEGIN:VALARM'), true);
      expect(content.contains('TRIGGER:-PT30M'), true);
      expect(content.contains('END:VCALENDAR'), true);
    });
  });

  group('OLED True Dark Theme & Light Theme Tests', () {
    test(
      'AppTheme darkTheme uses true OLED obsidian black (#090D1A) background',
      () {
        final darkTheme = AppTheme.darkTheme;
        expect(darkTheme.brightness, Brightness.dark);
        expect(darkTheme.scaffoldBackgroundColor, const Color(0xFF090D1A));
        expect(darkTheme.colorScheme.primary, const Color(0xFF6366F1));
        expect(darkTheme.colorScheme.surface, const Color(0xFF111827));
      },
    );

    test('AppTheme lightTheme uses clean slate (#F8FAFC) background and deep indigo', () {
      final lightTheme = AppTheme.lightTheme;
      expect(lightTheme.brightness, Brightness.light);
      expect(lightTheme.scaffoldBackgroundColor, const Color(0xFFF8FAFC));
      expect(lightTheme.colorScheme.primary, const Color(0xFF1E3A8A));
    });
  });
}
