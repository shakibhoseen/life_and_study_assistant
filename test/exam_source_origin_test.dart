import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/services/ai/models/parsed_routine_item.dart';
import 'package:life_and_study_assistant/features/chat/domain/models/chat_action.dart';
import 'package:life_and_study_assistant/features/live_mcq/data/repositories/exam_schedule_repository_impl.dart';
import 'package:life_and_study_assistant/features/live_mcq/domain/models/exam_source_info.dart';
import 'package:life_and_study_assistant/features/live_mcq/presentation/providers/exam_schedule_provider.dart';
import 'package:life_and_study_assistant/features/live_mcq/presentation/screens/live_mcq_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);

  group('ExamSourceInfo Resolution Tests', () {
    test('resolves PDF / digital routine import sources accurately', () {
      final pdfExam = ExamSchedule(
        id: 1,
        examDate: todayStart.add(const Duration(days: 1)),
        examTime: '10:00 PM',
        subject: 'General BCS',
        title: '47th BCS Preliminary Exam',
        topicsCovered: 'Full syllabus',
        examType: 'Daily',
        trackName: '47th BCS',
        rawReference: 'PDF: 47th_bcs_schedule.pdf',
        resourceSummary: 'Imported routine (47th BCS)',
        completedStatus: false,
        score: null,
        createdAt: now,
      );

      final source = ExamSourceInfo.resolve(pdfExam);
      expect(source, isNotNull);
      expect(source!.kind, ExamSourceKind.pdfImport);
      expect(source.label, 'PDF: 47th_bcs_schedule.pdf');
      expect(source.icon, Icons.description_outlined);

      // Long filenames are cleanly truncated
      final longPdfExam = pdfExam.copyWith(
        rawReference: Value(
          'PDF: very_long_official_routine_filename_2026.pdf',
        ),
      );
      final longSource = ExamSourceInfo.resolve(longPdfExam);
      expect(longSource, isNotNull);
      expect(longSource!.label.length, lessThanOrEqualTo(28));
      expect(longSource.label.endsWith('…'), isTrue);
    });

    test('resolves manual exam additions with or without custom notes', () {
      // Manual exam without custom notes
      final manualExam1 = ExamSchedule(
        id: 2,
        examDate: todayStart.add(const Duration(days: 2)),
        examTime: '10:00 PM',
        subject: 'Bangla',
        title: 'বাংলা ব্যাকরণ পরীক্ষা',
        topicsCovered: 'কারক ও সমাস',
        examType: 'Daily',
        trackName: 'General BCS',
        rawReference: 'manual',
        resourceSummary: 'নিজে যোগ করেছেন',
        completedStatus: false,
        score: null,
        createdAt: now,
      );

      final source1 = ExamSourceInfo.resolve(manualExam1);
      expect(source1, isNotNull);
      expect(source1!.kind, ExamSourceKind.manual);
      expect(source1.label, 'নিজে যোগ করেছেন');
      expect(source1.icon, Icons.person_outline);

      // Manual exam with user custom target notes in resourceSummary
      final manualExam2 = manualExam1.copyWith(
        resourceSummary: const Value('টার্গেট: ৮০+ নম্বর পেতে হবে'),
      );
      final source2 = ExamSourceInfo.resolve(manualExam2);
      expect(source2, isNotNull);
      expect(source2!.kind, ExamSourceKind.manual);
      expect(source2.label, 'নিজে যোগ করেছেন');
    });

    test('resolves AI Mentor ADD_EXAM sources accurately', () {
      final aiExam = ExamSchedule(
        id: 3,
        examDate: todayStart.add(const Duration(days: 3)),
        examTime: '09:00 PM',
        subject: 'Math',
        title: 'AI পাটিগণিত কুইজ',
        topicsCovered: 'শতকরা ও লাভ-ক্ষতি',
        examType: 'Daily',
        trackName: 'General BCS',
        rawReference: 'ai_mentor',
        resourceSummary: 'AI Mentor',
        completedStatus: false,
        score: null,
        createdAt: now,
      );

      final source = ExamSourceInfo.resolve(aiExam);
      expect(source, isNotNull);
      expect(source!.kind, ExamSourceKind.aiMentor);
      expect(source.label, 'AI Mentor');
      expect(source.icon, Icons.smart_toy_outlined);
    });

    test(
      'resolves AI Study Plan (ROUTINE_PLAN) distinct from official exams',
      () {
        final studyPlanExam = ExamSchedule(
          id: 4,
          examDate: todayStart.add(const Duration(days: 4)),
          examTime: '10:00 PM',
          subject: 'General Science',
          title: 'Day 1: পদার্থের অবস্থা ও আলো',
          topicsCovered: 'পদার্থের অবস্থা, আলো',
          examType: 'Study Session',
          trackName: 'General BCS',
          rawReference: 'AI Mentor Plan',
          resourceSummary: 'AI Mentor Plan',
          completedStatus: false,
          score: null,
          createdAt: now,
        );

        final source = ExamSourceInfo.resolve(studyPlanExam);
        expect(source, isNotNull);
        expect(source!.kind, ExamSourceKind.aiStudyPlan);
        expect(source.label, 'AI Study Plan');
        expect(source.icon, Icons.auto_stories);
      },
    );

    test(
      'does not infer legacy records with missing metadata as AI-created',
      () {
        final legacyExam = ExamSchedule(
          id: 5,
          examDate: todayStart.add(const Duration(days: 5)),
          examTime: '10:00 PM',
          subject: 'English',
          title: 'English Vocabulary Quiz',
          topicsCovered: 'Synonyms & Antonyms',
          examType: 'Daily',
          trackName: 'General BCS',
          rawReference: null,
          resourceSummary: null,
          completedStatus: false,
          score: null,
          createdAt: now,
        );

        final source = ExamSourceInfo.resolve(legacyExam);
        // Must NOT guess or invent an AI label
        expect(source, isNull);

        final emptyRefExam = legacyExam.copyWith(
          rawReference: const Value(''),
          resourceSummary: const Value('Old user notes'),
        );
        expect(ExamSourceInfo.resolve(emptyRefExam), isNull);
      },
    );
  });

  group('Database Persistence & Deduplication Tests', () {
    late AppDatabase db;
    late ExamScheduleRepositoryImpl repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = ExamScheduleRepositoryImpl(db);
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'persists manual exam with rawReference manual and custom summary',
      () async {
        final id = await repo.addExam(
          examDate: todayStart.add(const Duration(days: 2)),
          title: 'বাংলাদেশ বিষয়াবলি রিভিশন',
          topicsCovered: 'মুক্তিযুদ্ধ ও সংবিধান',
          resourceSummary: 'টার্গেট ২৫ নম্বর',
          trackName: '47th BCS',
          rawReference: 'manual',
        );

        final fetched = await (db.select(
          db.examSchedules,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        expect(fetched, isNotNull);
        expect(fetched!.rawReference, 'manual');
        expect(fetched.resourceSummary, 'টার্গেট ২৫ নম্বর');

        final source = ExamSourceInfo.resolve(fetched);
        expect(source?.kind, ExamSourceKind.manual);
        expect(source?.label, 'নিজে যোগ করেছেন');
      },
    );

    test('persists AI ADD_EXAM with rawReference ai_mentor', () async {
      final action = ChatAction(
        type: ChatActionType.addExam,
        title: 'AI প্রস্তাবিত বাংলাদেশ ইতিহাস পরীক্ষা',
        subject: 'Bangladesh Affairs',
        topic: 'প্রাচীন বাংলার ইতিহাস',
        examDate: todayStart.add(const Duration(days: 3)).toIso8601String(),
        examTime: '08:00 PM',
        trackName: 'General BCS',
      );

      final examDate = DateTime.parse(action.examDate!);
      await db.insertExamSchedulesDeduplicated([
        ExamSchedulesCompanion.insert(
          examDate: examDate,
          examTime: Value(action.examTime ?? '10:00 PM'),
          subject: Value(action.subject),
          title: action.title,
          topicsCovered: action.topic ?? 'General Syllabus',
          trackName: Value(action.trackName ?? 'General BCS'),
          resourceSummary: const Value('AI Mentor'),
          rawReference: const Value('ai_mentor'),
        ),
      ]);

      final all = await db.select(db.examSchedules).get();
      final added = all.firstWhere((e) => e.title == action.title);
      expect(added.rawReference, 'ai_mentor');
      expect(added.resourceSummary, 'AI Mentor');

      final source = ExamSourceInfo.resolve(added);
      expect(source?.kind, ExamSourceKind.aiMentor);
      expect(source?.label, 'AI Mentor');
    });

    test('persists AI ROUTINE_PLAN study sessions with rawReference AI Mentor Plan', () async {
      final item = ParsedRoutineItem(
        date: todayStart.add(const Duration(days: 1)),
        examTime: '10:00 PM',
        subject: 'Science',
        title: 'Day 1: ভৌত বিজ্ঞান প্রস্তুতি',
        topics: ['পদার্থের অবস্থা'],
        examType: 'Study Session',
        trackName: 'General BCS',
        rawReference: 'AI Mentor Plan',
      );

      await db.insertExamSchedulesDeduplicated([item.toCompanion()]);

      final all = await db.select(db.examSchedules).get();
      final saved = all.firstWhere(
        (e) => e.title == 'Day 1: ভৌত বিজ্ঞান প্রস্তুতি',
      );
      expect(saved.examType, 'Study Session');
      expect(saved.rawReference, 'AI Mentor Plan');

      final source = ExamSourceInfo.resolve(saved);
      expect(source?.kind, ExamSourceKind.aiStudyPlan);
      expect(source?.label, 'AI Study Plan');
    });

    test(
      'deduplication preserves original source and does not clobber it',
      () async {
        // 1. User manually creates an exam
        final examDate = todayStart.add(const Duration(days: 5));
        await db.insertExamSchedule(
          ExamSchedulesCompanion.insert(
            examDate: examDate,
            title: 'বাংলা ব্যাকরণ ফাইনাল',
            topicsCovered: 'কারক, প্রত্যয়',
            trackName: const Value('General BCS'),
            resourceSummary: const Value('টার্গেট ৮০'),
            rawReference: const Value('manual'),
          ),
        );

        // 2. An imported routine attempts to insert a duplicate with same date & title
        final duplicateImport = ParsedRoutineItem(
          date: examDate,
          examTime: '10:00 PM',
          subject: 'Bangla',
          title: 'বাংলা ব্যাকরণ ফাইনাল',
          topics: ['কারক, প্রত্যয়, উপসর্গ'],
          examType: 'Daily',
          trackName: 'General BCS',
          rawReference: 'PDF: routine_2026.pdf',
        );

        final res = await db.insertExamSchedulesDeduplicated([
          duplicateImport.toCompanion(),
        ]);
        expect(
          res.updatedCount,
          1,
        ); // updated topics because incoming has longer topics

        final all = await db.select(db.examSchedules).get();
        final updated = all.firstWhere(
          (e) => e.title == 'বাংলা ব্যাকরণ ফাইনাল',
        );

        // The original source 'manual' must be preserved, not overwritten with 'PDF: ...'!
        expect(updated.rawReference, 'manual');
        expect(updated.resourceSummary, 'টার্গেট ৮০');
        expect(ExamSourceInfo.resolve(updated)?.kind, ExamSourceKind.manual);
      },
    );

    test('deduplication safely populates source on legacy records with null rawReference', () async {
      final examDate = todayStart.add(const Duration(days: 6));
      // Seed legacy record without source metadata
      await db.insertExamSchedule(
        ExamSchedulesCompanion.insert(
          examDate: examDate,
          title: 'Legacy Math Exam',
          topicsCovered: 'Algebra',
          trackName: const Value('General BCS'),
          resourceSummary: const Value.absent(),
          rawReference: const Value.absent(),
        ),
      );

      // Re-importing with PDF source metadata
      final importItem = ParsedRoutineItem(
        date: examDate,
        examTime: '10:00 PM',
        subject: 'Math',
        title: 'Legacy Math Exam',
        topics: ['Algebra, Geometry'],
        examType: 'Daily',
        trackName: 'General BCS',
        rawReference: 'PDF: math_routine.pdf',
      );

      await db.insertExamSchedulesDeduplicated([importItem.toCompanion()]);

      final all = await db.select(db.examSchedules).get();
      final updated = all.firstWhere((e) => e.title == 'Legacy Math Exam');
      expect(updated.rawReference, 'PDF: math_routine.pdf');
      expect(ExamSourceInfo.resolve(updated)?.kind, ExamSourceKind.pdfImport);
    });
  });

  group('LiveMcqScreen Source Badge Rendering Tests', () {
    final sampleExams = [
      ExamSchedule(
        id: 101,
        examDate: todayStart.add(const Duration(days: 1)),
        examTime: '10:00 PM',
        subject: 'PDF Subject',
        title: 'PDF Imported Exam',
        topicsCovered: 'Chapter 1, 2',
        examType: 'Daily',
        trackName: '47th BCS',
        rawReference: 'PDF: 47th_routine.pdf',
        resourceSummary: 'Imported routine (47th BCS)',
        completedStatus: false,
        score: null,
        createdAt: now,
      ),
      ExamSchedule(
        id: 102,
        examDate: todayStart.add(const Duration(days: 2)),
        examTime: '09:00 PM',
        subject: 'Manual Subject',
        title: 'Manually Added Exam',
        topicsCovered: 'Chapter 3, 4',
        examType: 'Daily',
        trackName: '47th BCS',
        rawReference: 'manual',
        resourceSummary: 'নিজে যোগ করেছেন',
        completedStatus: false,
        score: null,
        createdAt: now,
      ),
      ExamSchedule(
        id: 103,
        examDate: todayStart.add(const Duration(days: 3)),
        examTime: '08:00 PM',
        subject: 'AI Subject',
        title: 'AI Mentor Created Exam',
        topicsCovered: 'Chapter 5, 6',
        examType: 'Daily',
        trackName: '47th BCS',
        rawReference: 'ai_mentor',
        resourceSummary: 'AI Mentor',
        completedStatus: false,
        score: null,
        createdAt: now,
      ),
      ExamSchedule(
        id: 104,
        examDate: todayStart.add(const Duration(days: 4)),
        examTime: '07:00 PM',
        subject: 'Study Subject',
        title: 'AI Study Session 01',
        topicsCovered: 'Chapter 7, 8',
        examType: 'Study Session',
        trackName: '47th BCS',
        rawReference: 'AI Mentor Plan',
        resourceSummary: 'AI Mentor Plan',
        completedStatus: false,
        score: null,
        createdAt: now,
      ),
      ExamSchedule(
        id: 105,
        examDate: todayStart.add(const Duration(days: 5)),
        examTime: '06:00 PM',
        subject: 'Legacy Subject',
        title: 'Legacy Exam Without Origin',
        topicsCovered: 'Chapter 9, 10',
        examType: 'Daily',
        trackName: '47th BCS',
        rawReference: null,
        resourceSummary: null,
        completedStatus: false,
        score: null,
        createdAt: now,
      ),
    ];

    Widget buildTestScreen() {
      return ProviderScope(
        overrides: [
          distinctTracksStreamProvider.overrideWith(
            (ref) => Stream.value(['47th BCS']),
          ),
          filteredExamsStreamProvider.overrideWith(
            (ref) => Stream.value(sampleExams),
          ),
        ],
        child: const MaterialApp(home: LiveMcqScreen()),
      );
    }

    testWidgets('renders distinct origin badges on exam cards', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildTestScreen());
      await tester.pumpAndSettle();

      // Check PDF source badge
      expect(find.text('PDF: 47th_routine.pdf'), findsOneWidget);

      // Check Manual source badge
      expect(find.text('নিজে যোগ করেছেন'), findsOneWidget);

      // Check AI Mentor badge
      expect(find.text('AI Mentor'), findsOneWidget);

      // Check AI Study Plan badge
      expect(find.text('AI Study Plan'), findsOneWidget);

      // E-{id} tags are also present on the cards
      expect(find.text('E-101'), findsOneWidget);
      expect(find.text('E-102'), findsOneWidget);
      expect(find.text('E-103'), findsOneWidget);
      expect(find.text('E-104'), findsOneWidget);
      expect(find.text('E-105'), findsOneWidget);
    });

    testWidgets(
      'suppresses redundant system summary boxes but displays user custom notes',
      (tester) async {
        final examsWithNotes = [
          ExamSchedule(
            id: 201,
            examDate: todayStart.add(const Duration(days: 1)),
            examTime: '10:00 PM',
            subject: 'Custom Note Subject',
            title: 'Exam With Custom Note',
            topicsCovered: 'Geometry',
            examType: 'Daily',
            trackName: '47th BCS',
            rawReference: 'manual',
            resourceSummary: 'Custom User Target: 90 marks',
            completedStatus: false,
            score: null,
            createdAt: now,
          ),
        ];

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              distinctTracksStreamProvider.overrideWith(
                (ref) => Stream.value(['47th BCS']),
              ),
              filteredExamsStreamProvider.overrideWith(
                (ref) => Stream.value(examsWithNotes),
              ),
            ],
            child: const MaterialApp(home: LiveMcqScreen()),
          ),
        );
        await tester.pumpAndSettle();

        // The custom note box is rendered
        expect(find.text('Custom User Target: 90 marks'), findsOneWidget);
        // The manual badge is also rendered
        expect(find.text('নিজে যোগ করেছেন'), findsOneWidget);
      },
    );
  });
}
