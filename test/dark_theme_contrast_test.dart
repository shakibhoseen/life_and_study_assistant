import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/theme/app_theme.dart';
import 'package:life_and_study_assistant/features/chat/presentation/providers/chat_provider.dart';
import 'package:life_and_study_assistant/features/chat/presentation/screens/ai_chat_screen.dart';
import 'package:life_and_study_assistant/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:life_and_study_assistant/features/live_mcq/presentation/providers/exam_schedule_provider.dart';
import 'package:life_and_study_assistant/features/live_mcq/presentation/screens/live_mcq_screen.dart';
import 'package:life_and_study_assistant/features/settings/presentation/providers/settings_provider.dart';
import 'package:life_and_study_assistant/features/settings/presentation/screens/settings_screen.dart';

class _MockSettingsNotifier extends SettingsNotifier {
  final SettingsState _initial;
  _MockSettingsNotifier(this._initial);

  @override
  Future<SettingsState> build() async => _initial;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Dark Theme Contrast & Typography Tests', () {
    test('AppTheme.darkTheme defines bright readable typography and dark card surfaces', () {
      final darkTheme = AppTheme.darkTheme;

      expect(darkTheme.brightness, Brightness.dark);
      expect(darkTheme.scaffoldBackgroundColor, const Color(0xFF090D1A));
      expect(darkTheme.cardTheme.color, const Color(0xFF111827));

      final textTheme = darkTheme.textTheme;
      expect(textTheme.bodyLarge?.color, const Color(0xFFF1F5F9));
      expect(textTheme.bodyMedium?.color, const Color(0xFFF1F5F9));
      expect(textTheme.bodySmall?.color, const Color(0xFF94A3B8));
      expect(textTheme.titleMedium?.color, const Color(0xFFF1F5F9));
      expect(textTheme.titleSmall?.color, const Color(0xFF94A3B8));
    });

    testWidgets(
      'DashboardScreen renders in Dark Mode without crashing or contrast errors',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: ThemeMode.dark,
              home: const DashboardScreen(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.byType(DashboardScreen), findsOneWidget);
      },
    );

    testWidgets(
      'SettingsScreen renders in Dark Mode without crashing or contrast errors',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final mockSettings = SettingsState(
          officeWifiSsid: 'Zavisoft',
          dinnerHour: 16,
          dinnerMinute: 0,
          geminiApiKey: 'test-api-key',
          lastCheckInStatus: 'Pending',
          lastMealResponse: 'None',
          isWifiMonitoringActive: true,
          isWeaknessHealingEnabled: true,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              settingsNotifierProvider.overrideWith(
                () => _MockSettingsNotifier(mockSettings),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: ThemeMode.dark,
              home: const SettingsScreen(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.byType(SettingsScreen), findsOneWidget);
        expect(find.text('Automation & Settings'), findsOneWidget);
        expect(find.text('Office Attendance & Schedule'), findsOneWidget);
      },
    );

    testWidgets(
      'AiChatScreen suggestion chips & input bar adopt dark theme styling in Dark Mode',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              chatSessionsStreamProvider.overrideWith(
                (ref) => Stream.value([]),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: ThemeMode.dark,
              home: const AiChatScreen(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.byType(AiChatScreen), findsOneWidget);

        // Verify quick prompt chips are present with dark background
        final actionChips = tester.widgetList<ActionChip>(
          find.byType(ActionChip),
        );
        expect(actionChips.isNotEmpty, isTrue);
        expect(actionChips.first.backgroundColor, const Color(0xFF1E293B));

        // Verify TextField has dark fill color
        final textFields = tester.widgetList<TextField>(find.byType(TextField));
        expect(textFields.isNotEmpty, isTrue);
        final decoration = textFields.first.decoration;
        expect(decoration?.fillColor, const Color(0xFF1E293B));
      },
    );

    testWidgets(
      'LiveMcqScreen timeline bar & track chips adopt dark theme styling in Dark Mode',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final sampleExam = ExamSchedule(
          id: 1,
          examDate: DateTime.now().add(const Duration(days: 1)),
          examTime: '10:00 PM',
          subject: 'Bangla',
          title: 'Day-12: Bangla Grammar',
          topicsCovered: 'কারক ও বিভক্তি',
          examType: 'Daily',
          trackName: '47th BCS',
          resourceSummary: null,
          rawReference: null,
          completedStatus: false,
          score: null,
          createdAt: DateTime.now(),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              distinctTracksStreamProvider.overrideWith(
                (ref) => Stream.value(['47th BCS', 'Primary Track']),
              ),
              filteredExamsStreamProvider.overrideWith(
                (ref) => Stream.value([sampleExam]),
              ),
              upcomingExamsStreamProvider.overrideWith(
                (ref) => Stream.value([sampleExam]),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: ThemeMode.dark,
              home: const LiveMcqScreen(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.byType(LiveMcqScreen), findsOneWidget);

        // Search field is present with dark theme text styling
        expect(find.byType(TextField), findsOneWidget);
        final searchField = tester.widget<TextField>(find.byType(TextField));
        expect(searchField.style?.color, Colors.white);

        // ChoiceChips in track bar have dark styling
        final choiceChips = tester.widgetList<ChoiceChip>(
          find.byType(ChoiceChip),
        );
        expect(choiceChips.isNotEmpty, isTrue);
        expect(choiceChips.first.backgroundColor, const Color(0xFF1E293B));
      },
    );
  });
}
