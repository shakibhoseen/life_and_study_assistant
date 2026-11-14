import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:life_and_study_assistant/core/database/database_provider.dart';
import 'package:life_and_study_assistant/core/theme/fluent_tokens.dart';
import 'package:life_and_study_assistant/core/services/overlay/bubble_handoff_provider.dart';
import 'package:life_and_study_assistant/core/services/overlay/bubble_handoff_service.dart';
import 'package:life_and_study_assistant/core/services/sharing/sharing_intent_service.dart';
import 'package:life_and_study_assistant/features/quiz/presentation/providers/drill_history_provider.dart';
import 'package:life_and_study_assistant/features/chat/presentation/screens/ai_chat_screen.dart';
import 'package:life_and_study_assistant/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:life_and_study_assistant/features/live_mcq/presentation/providers/exam_schedule_provider.dart';
import 'package:life_and_study_assistant/features/live_mcq/presentation/screens/live_mcq_screen.dart';
import 'package:life_and_study_assistant/features/live_mcq/presentation/widgets/routine_preview_sheet.dart';
import 'package:life_and_study_assistant/features/live_mcq/presentation/widgets/voice_mistake_bottom_sheet.dart';
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
      // The cold-start path: the app was not running when the bubble opened it.
      unawaited(_showWhatTheBubbleAdded());
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
      // This is the usual way in from the bubble: it opens the app, and the
      // app resumes with something waiting to be shown.
      unawaited(_showWhatTheBubbleAdded());
    }
  }

  /// Picks up where the floating bubble left off.
  ///
  /// The bubble is a small copy of the app's own voice sheet, made to be
  /// reachable while the user is inside someone else's app. So coming back
  /// from it lands on that sheet — the real one, with the whole screen and
  /// the keyboard — carrying whatever was written out there, finished or not.
  /// Whether the user got as far as saving makes no difference to where they
  /// arrive; it is the same piece of work either way.
  ///
  /// Opening the app from the launcher is a different thing entirely. Nobody
  /// who came to start a timer wants a sheet over the screen about a question
  /// they dictated hours ago, so that case only mentions it.
  ///
  /// The reload matters as much as the destination. The bubble writes through
  /// a database connection of its own, in its own Flutter engine, and drift
  /// only tells a connection about its own writes — so the Mistake Bank would
  /// otherwise be exactly as it was before the user spoke, and what they saved
  /// would appear only after a restart.
  Future<void> _showWhatTheBubbleAdded() async {
    // Read first, and whatever else happens below. The bubble can open the app
    // with nothing saved and nothing written, and a flag left set then would
    // make the next arrival, days later, look like it came from the bubble.
    final cameFromBubble = await BubbleHandoffService.instance
        .takeOpenedFromBubble();
    final draft = await BubbleHandoffService.instance.takeDraft();
    final added = await BubbleHandoffService.instance.pending();
    if (!mounted) return;

    if (added.isNotEmpty) {
      await BubbleHandoffService.instance.clear();
      if (!mounted) return;
      ref.invalidate(wrongQuestionsStreamProvider);
      ref.invalidate(allMistakesStreamProvider);
      ref.invalidate(allDrillQuestionsStreamProvider);
      ref.invalidate(drillHistoryStreamProvider);
      ref.invalidate(drillStatsStreamProvider);
    }

    if (cameFromBubble) {
      VoiceMistakeBottomSheet.show(context, initialText: draft);
      return;
    }

    if (added.isEmpty) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF10B981),
        duration: const Duration(seconds: 6),
        content: Text(
          added.length == 1
              ? 'বাবল থেকে যোগ হয়েছে: ${added.first}'
              : 'বাবল থেকে ${added.length}টি প্রশ্ন যোগ হয়েছে',
        ),
        // Offered, never taken: the user came here for something else.
        action: SnackBarAction(
          label: 'দেখুন',
          textColor: Colors.white,
          onPressed: _goToMistakeBank,
        ),
      ),
    );
  }

  /// Puts the Topics screen up with its Mistake Bank tab showing.
  void _goToMistakeBank() {
    if (!mounted) return;
    setState(() => _currentIndex = 2);
    ref.read(mistakeBankTabRequestProvider.notifier).request();
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
                  const SizedBox(width: FluentSpacing.m),
                  Expanded(
                    child: Text(
                      state.message ?? 'Analyzing routine with Gemini...',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      // Sits on a saturated snackbar fill.
                      style: FluentType.body.copyWith(color: Colors.white),
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
        shape: RoundedRectangleBorder(borderRadius: FluentRadius.cardBorder),
        title: Row(
          children: [
            // Green here is status: the import succeeded.
            const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 24),
            const SizedBox(width: FluentSpacing.s),
            Flexible(
              child: Text(
                'Routine Imported!',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: FluentType.subtitle.copyWith(
                  fontSize: 18,
                  color: Theme.of(ctx).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Gemini successfully parsed and added ${state.parsedItems.length} exam schedules to your calendar:',
              style: FluentType.body.copyWith(
                color: Theme.of(ctx).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: FluentSpacing.m),
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
                    leading: Icon(
                      Icons.event,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(
                      '${item.subject} (${item.examType})',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: FluentType.bodyStrong.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    subtitle: Text(
                      '📅 ${item.date.toIso8601String().substring(0, 10)} at ${item.examTime}\nTopics: ${item.topics.join(", ")}',
                      style: FluentType.caption.copyWith(
                        color: Theme.of(context).colorScheme.onSurface
                            .withValues(alpha: 0.65),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: FluentRadius.controlBorder,
              ),
            ),
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

  /// Windows 11 marks the selected navigation item with a short rounded
  /// accent bar. The filled indicator plate alone is a Material idiom; this
  /// adds the Fluent selection mark above the icon.
  static Widget _selectedNavIcon(BuildContext context, Widget icon) {
    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 3,
          decoration: BoxDecoration(
            color: primary,
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
        const SizedBox(height: FluentSpacing.xs),
        icon,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;

    final navBg = scheme.surface;

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: navBg,
          // Fluent defines the window chrome with a stroke, not a glow.
          border: Border(top: FluentStroke.side(brightness)),
        ),
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            height: 72,
            backgroundColor: navBg,
            indicatorColor: FluentLayer.subtle(scheme.primary, brightness),
            indicatorShape: RoundedRectangleBorder(
              borderRadius: FluentRadius.controlBorder,
            ),
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              final isSelected = states.contains(WidgetState.selected);
              return FluentType.caption.copyWith(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected
                    ? scheme.primary
                    : scheme.onSurface.withValues(alpha: 0.65),
              );
            }),
            iconTheme: WidgetStateProperty.resolveWith((states) {
              final isSelected = states.contains(WidgetState.selected);
              return IconThemeData(
                size: 22,
                color: isSelected
                    ? scheme.primary
                    : scheme.onSurface.withValues(alpha: 0.65),
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
              NavigationDestination(
                icon: const Icon(Icons.space_dashboard_outlined),
                selectedIcon: _selectedNavIcon(
                  context,
                  const Icon(Icons.space_dashboard_rounded),
                ),
                label: 'Dashboard',
                tooltip: 'ড্যাশবোর্ড',
              ),
              NavigationDestination(
                icon: const Icon(Icons.auto_awesome_outlined),
                selectedIcon: _selectedNavIcon(
                  context,
                  const Icon(Icons.auto_awesome),
                ),
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
                    return _selectedNavIcon(
                      context,
                      Badge.count(
                        count: count,
                        isLabelVisible: count > 0,
                        backgroundColor: const Color(0xFFEF4444),
                        child: const Icon(Icons.radar_rounded),
                      ),
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
                    return _selectedNavIcon(
                      context,
                      Badge.count(
                        count: count,
                        isLabelVisible: count > 0,
                        backgroundColor: const Color(0xFF10B981),
                        child: const Icon(Icons.event_note_rounded),
                      ),
                    );
                  },
                ),
                label: 'LiveMCQ',
                tooltip: 'লাইভ এমসিকিউ হাব',
              ),
              NavigationDestination(
                icon: const Icon(Icons.tune_outlined),
                selectedIcon: _selectedNavIcon(
                  context,
                  const Icon(Icons.tune_rounded),
                ),
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
