import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:life_and_study_assistant/core/database/database_provider.dart';
import 'package:life_and_study_assistant/core/services/sharing/sharing_intent_service.dart';
import 'package:life_and_study_assistant/features/chat/presentation/screens/ai_chat_screen.dart';
import 'package:life_and_study_assistant/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:life_and_study_assistant/features/live_mcq/presentation/providers/exam_schedule_provider.dart';
import 'package:life_and_study_assistant/features/live_mcq/presentation/screens/live_mcq_screen.dart';
import 'package:life_and_study_assistant/features/live_mcq/presentation/widgets/routine_preview_sheet.dart';
import 'package:life_and_study_assistant/features/settings/presentation/screens/settings_screen.dart';
import 'package:life_and_study_assistant/features/topics/presentation/screens/topics_screen.dart';

class HomeShellScreen extends ConsumerStatefulWidget {
  const HomeShellScreen({super.key});

  @override
  ConsumerState<HomeShellScreen> createState() => _HomeShellScreenState();
}

class _HomeShellScreenState extends ConsumerState<HomeShellScreen> {
  int _currentIndex = 0;
  StreamSubscription<SharingImportState>? _sharingSubscription;

  final List<Widget> _screens = const [
    DashboardScreen(),
    AiChatScreen(),
    TopicsScreen(),
    LiveMcqScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initSharingIntent();
    });
  }

  void _initSharingIntent() {
    final db = ref.read(appDatabaseProvider);
    SharingIntentService.instance.init(db);

    _sharingSubscription = SharingIntentService.instance.stateStream.listen((
      state,
    ) {
      if (!mounted) return;

      switch (state.status) {
        case SharingImportStatus.analyzing:
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 4),
              backgroundColor: Colors.indigo.shade900,
              content: Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      state.message ?? 'Analyzing routine with Gemini...',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          );
          break;

        case SharingImportStatus.needsConfirmation:
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          // Shared routines go through the same preview as every other
          // import: nothing is saved before it has been looked at.
          RoutinePreviewSheet.show(
            context,
            state.parsedItems,
            sourceLabel: state.message ?? 'শেয়ার করা ফাইল',
          ).then((approved) {
            if (approved == null || approved.isEmpty) return;
            SharingIntentService.instance.confirmImport(approved);
          });
          break;

        case SharingImportStatus.success:
          ref.invalidate(upcomingExamsStreamProvider);
          ref.invalidate(allExamsStreamProvider);

          _showImportSuccessDialog(state);
          break;

        case SharingImportStatus.error:
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.red.shade800,
              content: Text(
                state.message ?? 'Failed to parse routine',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          );
          break;

        case SharingImportStatus.idle:
          break;
      }
    });
  }

  void _showImportSuccessDialog(SharingImportState state) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 24),
            const SizedBox(width: 8),
            const Text('Routine Imported!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Gemini successfully parsed and added ${state.parsedItems.length} exam schedules to your calendar:',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: state.parsedItems.length,
                itemBuilder: (context, index) {
                  final item = state.parsedItems[index];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.event,
                      size: 20,
                      color: Colors.indigo,
                    ),
                    title: Text(
                      '${item.subject} (${item.examType})',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: Text(
                      '📅 ${item.date.toIso8601String().substring(0, 10)} at ${item.examTime}\nTopics: ${item.topics.join(", ")}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _currentIndex = 3; // Jump to LiveMCQ Hub to view the exams
              });
            },
            child: const Text('View in LiveMCQ Hub'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _sharingSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.psychology_outlined),
            selectedIcon: Icon(Icons.psychology),
            label: 'AI Mentor',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_border),
            selectedIcon: Icon(Icons.bookmark),
            label: 'Weak Topics',
          ),
          NavigationDestination(
            icon: Icon(Icons.quiz_outlined),
            selectedIcon: Icon(Icons.quiz),
            label: 'LiveMCQ',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Automation',
          ),
        ],
      ),
    );
  }
}
