import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:life_and_study_assistant/core/database/database_provider.dart';
import 'package:life_and_study_assistant/core/services/sharing/sharing_intent_service.dart';
import 'package:life_and_study_assistant/features/chat/presentation/screens/ai_chat_screen.dart';
import 'package:life_and_study_assistant/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:life_and_study_assistant/features/live_mcq/presentation/providers/exam_schedule_provider.dart';
import 'package:life_and_study_assistant/features/live_mcq/presentation/screens/live_mcq_screen.dart';
import 'package:life_and_study_assistant/features/live_mcq/presentation/widgets/routine_preview_sheet.dart';
import 'package:life_and_study_assistant/features/settings/presentation/screens/settings_screen.dart';
import 'package:life_and_study_assistant/core/services/notification/notification_service.dart';
import 'package:life_and_study_assistant/core/services/flashcards/flashcard_service.dart';
import 'package:life_and_study_assistant/features/spaced_repetition/presentation/widgets/flashcard_detail_sheet.dart';
import 'package:life_and_study_assistant/features/spaced_repetition/presentation/providers/spaced_repetition_provider.dart';
import 'package:life_and_study_assistant/features/topics/presentation/providers/topics_provider.dart';
import 'package:life_and_study_assistant/features/topics/presentation/screens/topics_screen.dart';

class HomeShellScreen extends ConsumerStatefulWidget {
  const HomeShellScreen({super.key});

  @override
  ConsumerState<HomeShellScreen> createState() => _HomeShellScreenState();
}

class _HomeShellScreenState extends ConsumerState<HomeShellScreen>
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  StreamSubscription<SharingImportState>? _sharingSubscription;
  StreamSubscription<FlashcardItem>? _flashcardTapSubscription;

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
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initSharingIntent();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The queue holds a finite run of cards, so topping it up only on a cold
    // start meant it quietly ran dry for anyone who leaves the app open in
    // the background for days.
    if (state == AppLifecycleState.resumed) {
      final notifier = ref.read(spacedRepetitionNotifierProvider.notifier);
      notifier.applyPendingReviewAdvances().then(
        (_) => notifier.refreshFlashcardSchedule(),
      );
    }
  }

  void _initSharingIntent() {
    final db = ref.read(appDatabaseProvider);
    SharingIntentService.instance.init(db);

    // The push queue holds a finite run of cards, so it is topped up every
    // time the app is opened rather than relying on a background worker.
    Future.microtask(() async {
      final notifier = ref.read(spacedRepetitionNotifierProvider.notifier);
      await notifier.applyPendingReviewAdvances();
      await notifier.refreshFlashcardSchedule();

      // A tap that started the app from cold arrives before anything is
      // listening, so it is collected here rather than lost.
      final launched = await NotificationService.instance.takeLaunchFlashcard();
      if (launched != null && mounted) {
        await FlashcardDetailSheet.show(context, launched);
      }
    });

    _flashcardTapSubscription = NotificationService.instance.tappedFlashcards
        .listen((card) {
          if (mounted) FlashcardDetailSheet.show(context, card);
        });

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
    WidgetsBinding.instance.removeObserver(this);
    _sharingSubscription?.cancel();
    _flashcardTapSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    const activeColor = Color(0xFF6366F1);
    final navBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF1E293B)
        : const Color(0xFFE2E8F0);
    final indicatorBg = isDark
        ? const Color(0xFF1E293B)
        : const Color(0xFFEEF2FF);

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: navBg,
          border: Border(top: BorderSide(color: borderColor, width: 1.2)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            height: 66,
            backgroundColor: navBg,
            indicatorColor: indicatorBg,
            indicatorShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              final isSelected = states.contains(WidgetState.selected);
              return TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected
                    ? (isDark
                          ? const Color(0xFFA5B4FC)
                          : const Color(0xFF4338CA))
                    : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                letterSpacing: 0.1,
              );
            }),
            iconTheme: WidgetStateProperty.resolveWith((states) {
              final isSelected = states.contains(WidgetState.selected);
              return IconThemeData(
                size: 22,
                color: isSelected
                    ? activeColor
                    : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
              );
            }),
          ),
          child: NavigationBar(
            selectedIndex: _currentIndex,
            elevation: 0,
            onDestinationSelected: (index) {
              if (_currentIndex != index) {
                HapticFeedback.selectionClick();
                setState(() {
                  _currentIndex = index;
                });
              }
            },
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.space_dashboard_outlined),
                selectedIcon: Icon(Icons.space_dashboard_rounded),
                label: 'Dashboard',
                tooltip: 'ড্যাশবোর্ড',
              ),
              const NavigationDestination(
                icon: Icon(Icons.auto_awesome_outlined),
                selectedIcon: Icon(Icons.auto_awesome),
                label: 'AI Mentor',
                tooltip: 'এআই মেন্টর চ্যাট',
              ),
              NavigationDestination(
                icon: Consumer(
                  builder: (context, ref, _) {
                    final count = ref.watch(
                      weakTopicsStreamProvider.select(
                        (s) => s.value?.length ?? 0,
                      ),
                    );
                    return Badge.count(
                      count: count,
                      isLabelVisible: count > 0,
                      backgroundColor: const Color(0xFFEF4444),
                      child: const Icon(Icons.radar_outlined),
                    );
                  },
                ),
                selectedIcon: Consumer(
                  builder: (context, ref, _) {
                    final count = ref.watch(
                      weakTopicsStreamProvider.select(
                        (s) => s.value?.length ?? 0,
                      ),
                    );
                    return Badge.count(
                      count: count,
                      isLabelVisible: count > 0,
                      backgroundColor: const Color(0xFFEF4444),
                      child: const Icon(Icons.radar_rounded),
                    );
                  },
                ),
                label: 'Weak Topics',
                tooltip: 'দুর্বল টপিক তালিকা',
              ),
              NavigationDestination(
                icon: Consumer(
                  builder: (context, ref, _) {
                    final count = ref.watch(
                      upcomingExamsStreamProvider.select(
                        (s) => s.value?.length ?? 0,
                      ),
                    );
                    return Badge.count(
                      count: count,
                      isLabelVisible: count > 0,
                      backgroundColor: const Color(0xFF10B981),
                      child: const Icon(Icons.event_note_outlined),
                    );
                  },
                ),
                selectedIcon: Consumer(
                  builder: (context, ref, _) {
                    final count = ref.watch(
                      upcomingExamsStreamProvider.select(
                        (s) => s.value?.length ?? 0,
                      ),
                    );
                    return Badge.count(
                      count: count,
                      isLabelVisible: count > 0,
                      backgroundColor: const Color(0xFF10B981),
                      child: const Icon(Icons.event_note_rounded),
                    );
                  },
                ),
                label: 'LiveMCQ',
                tooltip: 'লাইভ এমসিকিউ হাব',
              ),
              const NavigationDestination(
                icon: Icon(Icons.tune_outlined),
                selectedIcon: Icon(Icons.tune_rounded),
                label: 'Settings',
                tooltip: 'অ্যাপ সেটিংস',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
