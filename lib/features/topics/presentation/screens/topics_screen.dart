import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:life_and_study_assistant/core/database/app_database.dart';
import 'package:life_and_study_assistant/core/database/tables/weak_topics_table.dart';
import 'package:life_and_study_assistant/core/services/ai/models/quiz_question.dart';
import 'package:life_and_study_assistant/core/utils/bengali_math_sanitizer.dart';
import 'package:life_and_study_assistant/features/chat/presentation/providers/chat_provider.dart';
import 'package:life_and_study_assistant/features/chat/presentation/screens/ai_chat_screen.dart';
import 'package:life_and_study_assistant/features/mistake_notebook/presentation/screens/mistake_notebook_screen.dart';
import 'package:life_and_study_assistant/features/mistake_notebook/presentation/widgets/ai_mistake_explainer_sheet.dart';
import 'package:life_and_study_assistant/features/quiz/presentation/providers/drill_history_provider.dart';
import 'package:life_and_study_assistant/features/quiz/presentation/widgets/quiz_drill_modal.dart';
import 'package:life_and_study_assistant/features/quiz/presentation/widgets/study_sheet_camera_modal.dart';

import '../providers/topics_provider.dart';

class TopicsScreen extends ConsumerStatefulWidget {
  const TopicsScreen({super.key});

  @override
  ConsumerState<TopicsScreen> createState() => _TopicsScreenState();
}

class _TopicsScreenState extends ConsumerState<TopicsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String _selectedFilter = 'All';
  int _hubSubViewIndex = 0; // 0 = Mistake Bank, 1 = Drill History

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

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final isToday =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    final timeStr = '$hour:$minute $period';
    if (isToday) return 'Today at $timeStr';
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${dt.day} ${months[dt.month - 1]}, $timeStr';
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
    final wrongQuestions = ref.watch(wrongQuestionsStreamProvider).value ?? [];
    final isTab0 = _tabController.index == 0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
          labelColor: Theme.of(context).primaryColor,
          unselectedLabelColor: isDark ? Colors.white60 : Colors.black54,
          indicatorWeight: 3,
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
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildWeakTopicsTab(),
          _buildMistakeBankAndHubTab(wrongQuestions),
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
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (val) {
        setState(() {
          _selectedFilter = label;
        });
      },
    );
  }

  Widget _buildTopicCard(dynamic topic) {
    Color badgeColor = Colors.redAccent;
    String badgeText = 'Weak';
    switch (topic.proficiencyLevel) {
      case ProficiencyLevel.weak:
        badgeColor = Colors.redAccent;
        badgeText = 'Weak';
        break;
      case ProficiencyLevel.moderate:
        badgeColor = Colors.orangeAccent;
        badgeText = 'Moderate';
        break;
      case ProficiencyLevel.strong:
        badgeColor = Colors.green;
        badgeText = 'Strong';
        break;
      default:
        badgeColor = Colors.redAccent;
        badgeText = 'Weak';
    }

    final reviewedText = topic.lastReviewedAt != null
        ? 'Reviewed ${_formatDateTime(topic.lastReviewedAt)}'
        : 'Not reviewed yet';

    return Card(
      elevation: 1.5,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.indigo.withValues(alpha: 0.2)
                            : Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        topic.subject,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.indigo.shade200
                              : Colors.indigo.shade800,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: badgeColor,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      Icons.more_vert,
                      size: 18,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white70
                          : Colors.grey.shade700,
                    ),
                    tooltip: 'Options',
                    onSelected: (val) {
                    if (val == 'weak') {
                      ref
                          .read(topicsNotifierProvider.notifier)
                          .updateProficiency(topic.id, ProficiencyLevel.weak);
                    } else if (val == 'moderate') {
                      ref
                          .read(topicsNotifierProvider.notifier)
                          .updateProficiency(
                            topic.id,
                            ProficiencyLevel.moderate,
                          );
                    } else if (val == 'strong') {
                      ref
                          .read(topicsNotifierProvider.notifier)
                          .updateProficiency(topic.id, ProficiencyLevel.strong);
                    } else if (val == 'ask_ai') {
                      ref
                          .read(chatNotifierProvider.notifier)
                          .openOrCreateTopicSession(
                            subject: topic.subject,
                            topic: topic.topicName,
                            initialPrompt:
                                'আমাকে "${topic.subject}" বিষয়ের "${topic.topicName}" টপিকটি সহজে বুঝিয়ে দাও এবং BCS পরীক্ষার কমন ফাঁদ ও বিগত বছরের প্রশ্নগুলো বলো।',
                          );
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AiChatScreen()),
                      );
                    } else if (val == 'drill') {
                      QuizDrillModal.show(
                        context,
                        topic: topic.topicName,
                        subject: topic.subject,
                      );
                    } else if (val == 'delete') {
                      ref
                          .read(topicsNotifierProvider.notifier)
                          .deleteTopic(topic.id);
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'drill',
                      child: Row(
                        children: [
                          Icon(
                            Icons.psychology,
                            size: 16,
                            color: Colors.indigo,
                          ),
                          SizedBox(width: 8),
                          Text('Drill 5 MCQs (AI Quiz)'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'ask_ai',
                      child: Row(
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            size: 16,
                            color: Colors.indigo,
                          ),
                          SizedBox(width: 8),
                          Text('Explain with AI Mentor'),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'weak',
                      child: Text('Mark as Weak'),
                    ),
                    const PopupMenuItem(
                      value: 'moderate',
                      child: Text('Mark as Moderate'),
                    ),
                    const PopupMenuItem(
                      value: 'strong',
                      child: Text('Mark as Strong'),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        'Delete',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
            Text(
              topic.topicName,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            if (topic.notes != null && topic.notes.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                topic.notes,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white70
                      : Colors.black54,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    reviewedText,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white60
                          : Colors.grey.shade600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(
                        Icons.psychology,
                        size: 14,
                        color: Colors.indigo,
                      ),
                      label: const Text(
                        'Drill',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                        ),
                      ),
                      onPressed: () {
                        QuizDrillModal.show(
                          context,
                          topic: topic.topicName,
                          subject: topic.subject,
                        );
                      },
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        minimumSize: const Size(40, 26),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.check, size: 13),
                      label: const Text(
                        'Reviewed',
                        style: TextStyle(fontSize: 11),
                      ),
                      onPressed: () {
                        ref
                            .read(topicsNotifierProvider.notifier)
                            .markReviewed(topic.id);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
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
    final statsAsync = ref.watch(drillStatsStreamProvider);
    final historyAsync = ref.watch(drillHistoryStreamProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Overall Performance Dashboard Card
          statsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (err, stack) => const SizedBox.shrink(),
            data: (stats) => _buildStatsCard(stats),
          ),
          const SizedBox(height: 14),

          // 2. Prominent Re-drill Action Banner (if active mistakes exist)
          if (wrongQuestions.isNotEmpty) ...[
            _buildMistakeBanner(wrongQuestions),
            const SizedBox(height: 14),
          ],

          // 3. Sub-segment Selector: Mistake Bank vs Drill History
          historyAsync.when(
            loading: () => _buildSubViewSelector(wrongQuestions.length, 0),
            error: (err, stack) =>
                _buildSubViewSelector(wrongQuestions.length, 0),
            data: (history) =>
                _buildSubViewSelector(wrongQuestions.length, history.length),
          ),
          const SizedBox(height: 14),

          // 4. Sub-view Content
          if (_hubSubViewIndex == 0)
            _buildMistakeBankList(wrongQuestions)
          else
            historyAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (err, _) =>
                  Center(child: Text('Error loading history: $err')),
              data: (history) => _buildDrillHistoryList(history),
            ),
        ],
      ),
    );
  }

  Widget _buildStatsCard(Map<String, dynamic> stats) {
    final totalDrills = stats['total_drills'] ?? 0;
    final totalAnswered = stats['total_answered'] ?? 0;
    final totalCorrect = stats['total_correct'] ?? 0;
    final activeMistakes = stats['active_wrong_count'] ?? 0;
    final accuracy = (stats['accuracy_percentage'] as num?)?.toDouble() ?? 0.0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.analytics_outlined,
                  color: Colors.indigo,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Drill Performance Summary',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: accuracy >= 70
                        ? Colors.green.shade50
                        : (accuracy >= 40
                              ? Colors.orange.shade50
                              : Colors.red.shade50),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: accuracy >= 70
                          ? Colors.green.shade200
                          : (accuracy >= 40
                                ? Colors.orange.shade200
                                : Colors.red.shade200),
                    ),
                  ),
                  child: Text(
                    '${accuracy.toStringAsFixed(1)}% Accuracy',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: accuracy >= 70
                          ? Colors.green.shade800
                          : (accuracy >= 40
                                ? Colors.orange.shade800
                                : Colors.red.shade800),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _buildStatPill('Total Drills', '$totalDrills', Colors.indigo),
                const SizedBox(width: 8),
                _buildStatPill('Questions', '$totalAnswered', Colors.blueGrey),
                const SizedBox(width: 8),
                _buildStatPill('Correct', '$totalCorrect', Colors.green),
                const SizedBox(width: 8),
                _buildStatPill('Mistakes', '$activeMistakes', Colors.redAccent),
              ],
            ),
            if (totalAnswered > 0) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (accuracy / 100).clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: Colors.red.shade100,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    accuracy >= 70
                        ? Colors.green
                        : (accuracy >= 50 ? Colors.orange : Colors.redAccent),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatPill(String title, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMistakeBanner(List<DrillQuestion> wrongQuestions) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo.shade700, Colors.indigo.shade900],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.flash_on, color: Colors.amber, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${wrongQuestions.length} Mistakes to Master',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Practice your exact wrong questions until you get 100%!',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => _startMistakeBankDrill(wrongQuestions),
                child: const Text(
                  'Drill Now',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                ),
              ),
              const SizedBox(height: 4),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white70),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MistakeNotebookScreen(),
                  ),
                ),
                child: const Text(
                  'Notebook 📓',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSubViewSelector(int mistakesCount, int historyCount) {
    return SegmentedButton<int>(
      segments: [
        ButtonSegment<int>(
          value: 0,
          icon: const Icon(Icons.highlight_off, size: 16),
          label: Text('Mistake Bank ($mistakesCount)'),
        ),
        ButtonSegment<int>(
          value: 1,
          icon: const Icon(Icons.history, size: 16),
          label: Text('Past Sessions ($historyCount)'),
        ),
      ],
      selected: {_hubSubViewIndex},
      onSelectionChanged: (set) {
        setState(() {
          _hubSubViewIndex = set.first;
        });
      },
    );
  }

  // ==========================================
  // MISTAKE BANK CARDS
  // ==========================================
  Widget _buildMistakeBankList(List<DrillQuestion> wrongQuestions) {
    if (wrongQuestions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              Icon(Icons.verified, size: 64, color: Colors.green.shade400),
              const SizedBox(height: 12),
              const Text(
                'No Active Mistakes!',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'You have mastered all previous wrong questions.\nTake more drills to challenge yourself!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: wrongQuestions.length,
      itemBuilder: (context, index) {
        final dq = wrongQuestions[index];
        return _buildWrongQuestionCard(dq);
      },
    );
  }

  Widget _buildWrongQuestionCard(DrillQuestion dq) {
    List<String> options = [];
    try {
      final decoded = jsonDecode(dq.optionsJson);
      if (decoded is List) {
        options = decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {}

    final userAns = (dq.selectedIndex >= 0 && dq.selectedIndex < options.length)
        ? options[dq.selectedIndex]
        : 'Not Answered / Invalid';

    final correctAns =
        (dq.correctIndex >= 0 && dq.correctIndex < options.length)
        ? options[dq.correctIndex]
        : 'Unknown';

    return Card(
      elevation: 1.5,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => AiMistakeExplainerSheet.show(context, dq),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Subject & Topic Badge + Time + Menu
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? Colors.indigo.withValues(alpha: 0.2)
                                  : Colors.indigo.shade50,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              dq.subject,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? Colors.indigo.shade200
                                    : Colors.indigo.shade800,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '• ${dq.topic}',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? Colors.white
                                  : Colors.black87,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatDateTime(dq.attemptedAt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white60
                          : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        Icons.more_vert,
                        size: 18,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white70
                            : Colors.grey.shade700,
                      ),
                      tooltip: 'Options',
                      onSelected: (val) {
                      if (val == 'details') {
                        AiMistakeExplainerSheet.show(context, dq);
                      } else if (val == 'delete') {
                        ref
                            .read(drillHistoryNotifierProvider.notifier)
                            .deleteQuestion(dq.id);
                      } else if (val == 'ask_ai') {
                        ref
                            .read(chatNotifierProvider.notifier)
                            .openOrCreateTopicSession(
                              subject: dq.subject,
                              topic: dq.topic,
                              initialPrompt:
                                  'প্রশ্ন: "${dq.questionText}"\nসঠিক উত্তর: "$correctAns"\nএই প্রশ্নটি কেন সঠিক এবং এর পেছনের কনসেপ্টটি বিস্তারিত বুঝিয়ে দাও।',
                            );
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AiChatScreen()),
                        );
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'details',
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 16,
                              color: Colors.blue,
                            ),
                            SizedBox(width: 8),
                            Text('বিস্তারিত দেখুন (Details)'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'ask_ai',
                        child: Row(
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 16,
                              color: Colors.indigo,
                            ),
                            SizedBox(width: 8),
                            Text('Ask AI to Explain'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline,
                              size: 16,
                              color: Colors.red,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Delete from Bank',
                              style: TextStyle(color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
              const SizedBox(height: 10),

            // Question Text
            Text(
              BengaliMathSanitizer.sanitize(dq.questionText),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),

            // Your Answer (Red)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.red.withValues(alpha: 0.18)
                    : Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.red.withValues(alpha: 0.4)
                      : Colors.red.shade200,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.close, color: Colors.red, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Your answer: $userAns',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.red.shade200
                            : Colors.red.shade900,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),

            // Correct Answer (Green)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.green.withValues(alpha: 0.18)
                    : Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.green.withValues(alpha: 0.4)
                      : Colors.green.shade200,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check, color: Colors.green, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Correct answer: $correctAns',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.greenAccent
                            : Colors.green.shade900,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Explanation (if present)
            if (dq.explanation.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF1E293B)
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white12
                        : Colors.grey.shade200,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.lightbulb_outline,
                      size: 16,
                      color: Colors.amber,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        BengaliMathSanitizer.sanitize(dq.explanation),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white70
                              : Colors.black87,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Action Buttons: [ Practice This ] & [ ✓ Mastered (বুঝেছি) ]
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(
                    Icons.psychology,
                    size: 14,
                    color: Colors.indigo,
                  ),
                  label: const Text(
                    'Practice This',
                    style: TextStyle(fontSize: 11.5, color: Colors.indigo),
                  ),
                  onPressed: () {
                    final quizQ = _convertDrillQuestionToQuiz(dq);
                    QuizDrillModal.show(
                      context,
                      topic: dq.topic,
                      subject: dq.subject,
                      customQuestions: [quizQ],
                    );
                  },
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.done_all, size: 14),
                  label: const Text(
                    'Mastered (বুঝেছি)',
                    style: TextStyle(fontSize: 11.5),
                  ),
                  onPressed: () async {
                    await ref
                        .read(drillHistoryNotifierProvider.notifier)
                        .markQuestionMastered(dq.id, true);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Marked as mastered! 🎉'),
                          duration: const Duration(seconds: 4),
                          action: SnackBarAction(
                            label: 'Undo',
                            onPressed: () {
                              ref
                                  .read(drillHistoryNotifierProvider.notifier)
                                  .markQuestionMastered(dq.id, false);
                            },
                          ),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

  // ==========================================
  // DRILL HISTORY LIST
  // ==========================================
  Widget _buildDrillHistoryList(List<DrillRecord> history) {
    if (history.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              Icon(
                Icons.history_toggle_off,
                size: 64,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 12),
              const Text(
                'No Past Drill Sessions',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Start a drill from Weak Topics or AI Mentor to test your skills!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: history.length,
      itemBuilder: (context, index) {
        final r = history[index];
        final score = r.scorePercentage;
        Color badgeColor = Colors.green;
        if (score < 50) {
          badgeColor = Colors.redAccent;
        } else if (score < 75) {
          badgeColor = Colors.orangeAccent;
        }

        return Card(
          elevation: 1.5,
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Score Circle / Badge
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: badgeColor.withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${r.correctCount}/${r.totalQuestions}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: badgeColor,
                          ),
                        ),
                        Text(
                          '${score.toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: badgeColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Details: Subject, Topic, Date
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.indigo.withValues(alpha: 0.2)
                                  : Colors.indigo.shade50,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              r.subject,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.indigo.shade200
                                    : Colors.indigo.shade800,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _formatDateTime(r.createdAt),
                            style: TextStyle(
                              fontSize: 10.5,
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.white60
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        r.topic,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Correct: ${r.correctCount}  •  Mistakes: ${r.incorrectCount}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white70
                              : Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Re-drill Topic button
                IconButton(
                  tooltip: 'Drill again',
                  icon: const Icon(
                    Icons.refresh,
                    size: 20,
                    color: Colors.indigo,
                  ),
                  onPressed: () {
                    QuizDrillModal.show(
                      context,
                      topic: r.topic,
                      subject: r.subject,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
