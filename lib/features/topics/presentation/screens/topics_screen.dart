import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/database/tables/weak_topics_table.dart';
import 'package:life_and_study_assistant/core/services/ai/models/quiz_question.dart';
import 'package:life_and_study_assistant/core/utils/bengali_math_sanitizer.dart';
import 'package:life_and_study_assistant/features/quiz/presentation/providers/drill_history_provider.dart';
import 'package:life_and_study_assistant/features/quiz/presentation/widgets/quiz_drill_modal.dart';
import 'package:life_and_study_assistant/features/quiz/presentation/widgets/study_sheet_camera_modal.dart';

import 'package:life_and_study_assistant/core/services/overlay/bubble_handoff_provider.dart';

import '../providers/topics_provider.dart';
import '../widgets/mistake_bank_and_hub_tab.dart';
import '../widgets/topic_card.dart';
import '../../../../core/widgets/animated_premium_background.dart';

class TopicsScreen extends ConsumerStatefulWidget {
  const TopicsScreen({super.key});

  @override
  ConsumerState<TopicsScreen> createState() => _TopicsScreenState();
}

class _TopicsScreenState extends ConsumerState<TopicsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String _selectedFilter = 'All';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  QuizQuestion _convertDrillQuestionToQuiz(DrillQuestion dq) {
    List<String> options = [];
    try {
      final decoded = jsonDecode(dq.optionsJson);
      if (decoded is List) {
        options = decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {}

    return QuizQuestion(
      questionText: BengaliMathSanitizer.sanitize(dq.questionText),
      options: options.map((e) => BengaliMathSanitizer.sanitize(e)).toList(),
      correctIndex: dq.correctIndex,
      explanation: BengaliMathSanitizer.sanitize(dq.explanation),
    );
  }

  void _startMistakeBankDrill(List<DrillQuestion> wrongQuestions) {
    if (wrongQuestions.isEmpty) return;
    final quizQuestions = wrongQuestions
        .map(_convertDrillQuestionToQuiz)
        .toList();
    QuizDrillModal.show(
      context,
      topic: 'Mistake Bank Practice',
      subject: 'Review & Mastery',
      customQuestions: quizQuestions,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Arriving from the floating bubble, which lands on the Mistake Bank
    // rather than the tab the user happened to leave open. This screen is
    // built once inside an IndexedStack, so initState never runs again and
    // cannot carry the request.
    ref.listen<int>(mistakeBankTabRequestProvider, (_, _) {
      if (mounted) _tabController.animateTo(1);
    });

    final wrongQuestions = ref.watch(wrongQuestionsStreamProvider).value ?? [];
    final isTab0 = _tabController.index == 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Weak Topics & Drill Hub',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.camera_alt_outlined),
            tooltip: 'Snap Study Sheet to Drill',
            onPressed: () => StudySheetCameraModal.show(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          // Colours come from tabBarTheme. The old explicit
          // `Theme.of(context).primaryColor` here was the dark-mode bug:
          // on a dark ThemeData that getter resolves to colorScheme.surface
          // (the card background), so the selected tab was painted in almost
          // the same colour as the AppBar behind it.
          tabs: [
            const Tab(icon: Icon(Icons.bookmark_border), text: 'Weak Topics'),
            Tab(
              icon: Badge(
                isLabelVisible: wrongQuestions.isNotEmpty,
                backgroundColor: Colors.redAccent,
                label: Text('${wrongQuestions.length}'),
                child: const Icon(Icons.assignment_late_outlined),
              ),
              text: 'Mistake Bank & Hub',
            ),
          ],
        ),
      ),
      floatingActionButton: isTab0
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Add Weak Topic'),
              onPressed: () => _showAddTopicBottomSheet(context),
            )
          : (wrongQuestions.isNotEmpty
                ? FloatingActionButton.extended(
                    backgroundColor: Colors.indigo,
                    icon: const Icon(Icons.flash_on, color: Colors.white),
                    label: Text(
                      'Re-drill Mistakes (${wrongQuestions.length})',
                      style: const TextStyle(color: Colors.white),
                    ),
                    onPressed: () => _startMistakeBankDrill(wrongQuestions),
                  )
                : null),
      body: Stack(
        children: [
          const Positioned.fill(
            child: AnimatedGradientBackground(child: SizedBox.expand()),
          ),
          const FloatingOrb(top: 40, left: -40, size: 250, opacity: 0.15),
          const FloatingOrb(bottom: 80, right: -40, size: 220, opacity: 0.13),
          TabBarView(
            controller: _tabController,
            children: [
              _buildWeakTopicsTab(),
              _buildMistakeBankAndHubTab(wrongQuestions),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 1: WEAK TOPICS & PROFICIENCY RADAR
  // ==========================================
  Widget _buildWeakTopicsTab() {
    final topicsAsync = ref.watch(weakTopicsStreamProvider);

    return Column(
      children: [
        // Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              _buildFilterChip('All'),
              const SizedBox(width: 8),
              _buildFilterChip('Weak'),
              const SizedBox(width: 8),
              _buildFilterChip('Moderate'),
              const SizedBox(width: 8),
              _buildFilterChip('Strong'),
            ],
          ),
        ),
        Expanded(
          child: topicsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Center(child: Text('Error: $err')),
            data: (topics) {
              final filtered = topics.where((t) {
                if (_selectedFilter == 'Weak') {
                  return t.proficiencyLevel == ProficiencyLevel.weak;
                }
                if (_selectedFilter == 'Moderate') {
                  return t.proficiencyLevel == ProficiencyLevel.moderate;
                }
                if (_selectedFilter == 'Strong') {
                  return t.proficiencyLevel == ProficiencyLevel.strong;
                }
                return true;
              }).toList();

              if (filtered.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.checklist,
                        size: 64,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'No topics found',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final item = filtered[index];
                  return _buildTopicCard(item);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _selectedFilter == label;
    final scheme = Theme.of(context).colorScheme;

    return FilterChip(
      label: Text(label),
      selected: isSelected,
      showCheckmark: true,
      checkmarkColor: scheme.primary,
      // Spelled out rather than left to the chip theme: the shared dark
      // chipTheme paints every chip on `inputFill`, which left the selected
      // one indistinguishable from the rest.
      selectedColor: scheme.primary.withValues(alpha: 0.22),
      labelStyle: TextStyle(
        fontSize: 12.5,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        color: isSelected ? scheme.primary : scheme.onSurface,
      ),
      side: BorderSide(
        color: isSelected
            ? scheme.primary
            : scheme.onSurface.withValues(alpha: 0.22),
        width: isSelected ? 1.4 : 1,
      ),
      onSelected: (val) {
        setState(() {
          _selectedFilter = label;
        });
      },
    );
  }

  Widget _buildTopicCard(dynamic topic) {
    return TopicCard(topic: topic);
  }

  void _showAddTopicBottomSheet(BuildContext context) {
    final subjectController = TextEditingController();
    final topicNameController = TextEditingController();
    final notesController = TextEditingController();
    ProficiencyLevel level = ProficiencyLevel.weak;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add Weak Topic',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: subjectController,
                decoration: const InputDecoration(
                  labelText: 'Subject (e.g. Bangla Grammar, Math, Science)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: topicNameController,
                decoration: const InputDecoration(
                  labelText: 'Topic Name (e.g. কারক ও বিভক্তি)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notesController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes / LiveMCQ references',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Proficiency: ', style: TextStyle(fontSize: 13)),
                  DropdownButton<ProficiencyLevel>(
                    value: level,
                    items: const [
                      DropdownMenuItem(
                        value: ProficiencyLevel.weak,
                        child: Text(
                          'Weak',
                          style: TextStyle(color: Colors.redAccent),
                        ),
                      ),
                      DropdownMenuItem(
                        value: ProficiencyLevel.moderate,
                        child: Text(
                          'Moderate',
                          style: TextStyle(color: Colors.orangeAccent),
                        ),
                      ),
                      DropdownMenuItem(
                        value: ProficiencyLevel.strong,
                        child: Text(
                          'Strong',
                          style: TextStyle(color: Colors.green),
                        ),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setModalState(() {
                          level = val;
                        });
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () {
                    final subject = subjectController.text.trim();
                    final topic = topicNameController.text.trim();
                    if (subject.isNotEmpty && topic.isNotEmpty) {
                      ref
                          .read(topicsNotifierProvider.notifier)
                          .addTopic(
                            subject: subject,
                            topicName: topic,
                            proficiencyLevel: level,
                            notes: notesController.text.trim(),
                          );
                      Navigator.pop(ctx);
                    }
                  },
                  child: const Text('Save Topic'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // TAB 2: MISTAKE BANK & DRILL HUB
  // ==========================================
  Widget _buildMistakeBankAndHubTab(List<DrillQuestion> wrongQuestions) {
    return MistakeBankAndHubTab(
      wrongQuestions: wrongQuestions,
      onStartMistakeBankDrill: _startMistakeBankDrill,
    );
  }
}
