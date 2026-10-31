import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/services/ai/models/quiz_question.dart';
import '../../../quiz/presentation/providers/drill_history_provider.dart';
import '../../../quiz/presentation/widgets/quiz_batch_correction_sheet.dart';
import '../../../quiz/presentation/widgets/quiz_drill_modal.dart';
import '../../domain/models/mistake_folder.dart';
import '../widgets/mastery_overview_card.dart';
import '../widgets/mistake_question_card.dart';
import '../widgets/nightly_review_modal.dart';
import '../../../../core/utils/option_label.dart';

class MistakeNotebookScreen extends ConsumerStatefulWidget {
  final String? initialSubjectFolder;

  const MistakeNotebookScreen({super.key, this.initialSubjectFolder});

  @override
  ConsumerState<MistakeNotebookScreen> createState() =>
      _MistakeNotebookScreenState();
}

class _MistakeNotebookScreenState extends ConsumerState<MistakeNotebookScreen> {
  String _selectedFolderId = 'all';
  String _statusFilter = 'all'; // 'all', 'pending', 'mastered'
  String _sourceFilter = 'all'; // 'all', 'voice', 'book', 'drill'
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    if (widget.initialSubjectFolder != null) {
      _selectedFolderId = widget.initialSubjectFolder!;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> _decodeOptions(String optionsJson) {
    try {
      final decoded = jsonDecode(optionsJson);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {}
    return const [];
  }

  void _startQuizDrill(List<DrillQuestion> questions) {
    if (questions.isEmpty) return;

    final quizQuestions = questions.map((dq) {
      final options = _decodeOptions(dq.optionsJson);
      return QuizQuestion(
        questionText: dq.questionText,
        options: options,
        correctIndex: dq.correctIndex,
        explanation: dq.explanation,
      );
    }).toList();

    QuizDrillModal.show(
      context,
      topic: 'Mistake Notebook Practice',
      subject: _selectedFolderId == 'all' ? 'All Mistakes' : _selectedFolderId,
      mistakeQuestions: questions,
      customQuestions: quizQuestions,
    );
  }

  void _copyFilteredMistakesToClipboard(List<DrillQuestion> questions) {
    if (questions.isEmpty) return;

    final buffer = StringBuffer();
    final folderLabel = _selectedFolderId == 'all'
        ? 'সব বিষয়'
        : _selectedFolderId;
    buffer.writeln(
      '[স্মার্ট মিস্টেক নোটবুক: $folderLabel (${questions.length}টি প্রশ্ন)]\n',
    );

    for (int i = 0; i < questions.length; i++) {
      final dq = questions[i];
      final options = _decodeOptions(dq.optionsJson);
      buffer.writeln('প্রশ্ন ${i + 1}: ${dq.questionText} [Q-${dq.id}]');
      for (int j = 0; j < options.length; j++) {
        buffer.writeln(
          '  ${optionLabelChar(j)}) ${stripOptionLabel(options[j])}',
        );
      }
      final correctOpt =
          (dq.correctIndex >= 0 && dq.correctIndex < options.length)
          ? '${optionLabelChar(dq.correctIndex)}) '
                '${stripOptionLabel(options[dq.correctIndex])}'
          : '(অজানা)';
      final userOpt =
          (dq.selectedIndex >= 0 && dq.selectedIndex < options.length)
          ? '${optionLabelChar(dq.selectedIndex)}) '
                '${stripOptionLabel(options[dq.selectedIndex])}'
          : '(দাগানো হয়নি)';
      buffer.writeln('  চিহ্নিত সঠিক উত্তর: $correctOpt');
      buffer.writeln('  ব্যবহারকারীর ভুল উত্তর: $userOpt');
      if (dq.explanation.isNotEmpty) {
        buffer.writeln('  ব্যাখ্যা: ${dq.explanation}');
      }
      buffer.writeln();
    }
    buffer.writeln('==============================');
    buffer.writeln(
      'নির্দেশনা: অনুগ্রহ করে উপরের প্রতিটি ভুল প্রশ্নের উত্তর ও ব্যাখ্যা নিরপেক্ষভাবে যাচাই করুন। কোনো প্রশ্নে অসঙ্গতি থাকলে সঠিক উত্তরটি জানিয়ে দিন।',
    );

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF4F46E5),
        content: Text(
          '${questions.length}টি ভুল প্রশ্ন কপি হয়েছে — ChatGPT বা Claude-এ পেস্ট করতে পারেন!',
        ),
      ),
    );
  }

  Future<void> _batchFixFilteredMistakes(List<DrillQuestion> questions) async {
    if (questions.isEmpty) return;

    final quizQuestions = questions.map((dq) {
      final options = _decodeOptions(dq.optionsJson);
      return QuizQuestion(
        questionText: dq.questionText,
        options: options,
        correctIndex: dq.correctIndex,
        explanation: dq.explanation,
      );
    }).toList();

    await QuizBatchCorrectionSheet.show(
      context,
      ref: ref,
      questions: quizQuestions,
      mistakeQuestions: questions,
      topic: _selectedFolderId == 'all'
          ? 'স্মার্ট মিস্টেক নোটবুক'
          : _selectedFolderId,
      subject: 'Mistake Notebook',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allMistakesAsync = ref.watch(allMistakesStreamProvider);

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0F172A)
          : const Color(0xFFF8FAFC),
      appBar: AppBar(
        titleSpacing: 0,
        title: const Row(
          children: [
            Icon(Icons.menu_book_rounded, color: Colors.indigo, size: 24),
            SizedBox(width: 8),
            Text(
              'স্মার্ট মিস্টেক নোটবুক',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'রাতের ৫ মিনিটের রিভিশন',
            icon: const Icon(Icons.nightlight_round, color: Colors.amber),
            onPressed: () {
              final unmastered = (allMistakesAsync.value ?? [])
                  .where((q) => !q.isMastered)
                  .toList();
              NightlyReviewModal.show(context, unmastered);
            },
          ),
        ],
      ),
      body: allMistakesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error loading mistakes: $err')),
        data: (allMistakes) {
          return _buildContent(context, allMistakes, isDark);
        },
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    List<DrillQuestion> allMistakes,
    bool isDark,
  ) {
    final folders = groupMistakesIntoFolders(allMistakes);
    final totalMistakes = allMistakes.length;
    final masteredCount = allMistakes.where((q) => q.isMastered).length;
    final pendingCount = totalMistakes - masteredCount;
    final overallMasteryRate = totalMistakes == 0
        ? 0.0
        : (masteredCount / totalMistakes) * 100.0;

    // Filter questions based on selected folder
    List<DrillQuestion> folderQuestions = allMistakes;
    if (_selectedFolderId != 'all') {
      final folder = folders.firstWhere(
        (f) => f.id == _selectedFolderId,
        orElse: () => MistakeSubjectFolder(
          id: 'unknown',
          displayName: 'Unknown',
          icon: Icons.folder,
          color: Colors.grey,
          questions: [],
        ),
      );
      folderQuestions = folder.questions;
    }

    // Apply status filter
    var filtered = folderQuestions.where((q) {
      if (_statusFilter == 'pending') return !q.isMastered;
      if (_statusFilter == 'mastered') return q.isMastered;
      return true;
    }).toList();

    // Apply source filter
    if (_sourceFilter != 'all') {
      filtered = filtered.where((q) {
        final src = detectMistakeSource(q);
        if (_sourceFilter == 'voice') return src == MistakeSource.liveMcqVoice;
        if (_sourceFilter == 'book') return src == MistakeSource.bookScan;
        if (_sourceFilter == 'drill') return src == MistakeSource.modelTest;
        return true;
      }).toList();
    }

    // Apply search query
    if (_searchQuery.trim().isNotEmpty) {
      final qLower = _searchQuery.toLowerCase().trim();
      filtered = filtered.where((q) {
        return q.questionText.toLowerCase().contains(qLower) ||
            q.subject.toLowerCase().contains(qLower) ||
            q.topic.toLowerCase().contains(qLower) ||
            q.explanation.toLowerCase().contains(qLower);
      }).toList();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Mastery Overview Card
          MasteryOverviewCard(
            total: totalMistakes,
            pending: pendingCount,
            mastered: masteredCount,
            rate: overallMasteryRate,
            isDark: isDark,
            onNightlyReview: () {
              final unmastered = allMistakes
                  .where((q) => !q.isMastered)
                  .toList();
              NightlyReviewModal.show(context, unmastered);
            },
            onReDrill: () => _startQuizDrill(filtered),
          ),
          const SizedBox(height: 14),

          // 2. Subject Folders Horizontal Carousel
          _buildSubjectFoldersCarousel(folders, totalMistakes, isDark),
          const SizedBox(height: 14),

          // 3. Search & Filter Bar
          _buildSearchAndFilters(isDark),
          const SizedBox(height: 14),

          // 4. Questions Counter and Quick Action Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'সংরক্ষিত ভুলসমূহ (${filtered.length}টি)',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              if (filtered.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        foregroundColor: isDark
                            ? const Color(0xFFA5B4FC)
                            : const Color(0xFF4F46E5),
                        side: BorderSide(
                          color: isDark
                              ? const Color(0xFF6366F1)
                              : const Color(0xFF4F46E5),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () =>
                          _copyFilteredMistakesToClipboard(filtered),
                      icon: const Icon(Icons.copy_rounded, size: 13),
                      label: const Text(
                        'কপি',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () => _batchFixFilteredMistakes(filtered),
                      icon: const Icon(Icons.auto_fix_high_rounded, size: 13),
                      label: const Text(
                        'AI ফিক্স',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'এই তালিকা ড্রিল করুন',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _startQuizDrill(filtered),
                      icon: const Icon(
                        Icons.flash_on,
                        size: 19,
                        color: Colors.amber,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),

          // 5. Mistakes List or Empty State
          if (filtered.isEmpty)
            _buildEmptyState(isDark)
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              itemBuilder: (ctx, index) {
                final dq = filtered[index];
                return MistakeQuestionCard(dq: dq, isDark: isDark);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildSubjectFoldersCarousel(
    List<MistakeSubjectFolder> folders,
    int totalCount,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'বিষয়ভিত্তিক ফোল্ডারসমূহ',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // "All Mistakes" Folder Tab
              _buildFolderChip(
                id: 'all',
                title: 'সকল ভুল',
                icon: Icons.all_inclusive_rounded,
                color: Colors.indigo,
                totalCount: totalCount,
                isSelected: _selectedFolderId == 'all',
                isDark: isDark,
              ),
              const SizedBox(width: 8),

              // Each Category Folder
              ...folders.map((f) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _buildFolderChip(
                    id: f.id,
                    title: f.displayName,
                    icon: f.icon,
                    color: f.color,
                    totalCount: f.totalCount,
                    pendingCount: f.pendingCount,
                    isSelected: _selectedFolderId == f.id,
                    isDark: isDark,
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFolderChip({
    required String id,
    required String title,
    required IconData icon,
    required Color color,
    required int totalCount,
    int? pendingCount,
    required bool isSelected,
    required bool isDark,
  }) {
    final chipBg = isSelected
        ? color
        : (isDark ? const Color(0xFF1E293B) : Colors.white);
    final textColor = isSelected
        ? Colors.white
        : (isDark ? Colors.white : Colors.black87);
    final borderColor = isSelected
        ? color
        : (isDark ? Colors.white12 : Colors.grey.shade300);

    return InkWell(
      onTap: () {
        setState(() {
          _selectedFolderId = id;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: chipBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : color),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: textColor,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.25)
                    : color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$totalCount',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAndFilters(bool isDark) {
    return Column(
      children: [
        // Search text field
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'প্রশ্ন বা টপিক দিয়ে খুঁজুন...',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
            filled: true,
            fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark ? Colors.white12 : Colors.grey.shade300,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark ? Colors.white12 : Colors.grey.shade300,
              ),
            ),
          ),
          onChanged: (val) {
            setState(() => _searchQuery = val);
          },
        ),
        const SizedBox(height: 8),

        // Filter chips row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // Status filters
              _buildFilterBadge(
                'সব ভুল',
                'all',
                _statusFilter,
                (v) => setState(() => _statusFilter = v),
              ),
              const SizedBox(width: 6),
              _buildFilterBadge(
                'বাকি ভুল',
                'pending',
                _statusFilter,
                (v) => setState(() => _statusFilter = v),
                color: Colors.redAccent,
              ),
              const SizedBox(width: 6),
              _buildFilterBadge(
                'আয়ত্তে এসেছে',
                'mastered',
                _statusFilter,
                (v) => setState(() => _statusFilter = v),
                color: Colors.green,
              ),
              const SizedBox(width: 12),
              Container(width: 1, height: 20, color: Colors.grey.shade400),
              const SizedBox(width: 12),

              // Source filters
              _buildFilterBadge(
                'সকল উৎস',
                'all',
                _sourceFilter,
                (v) => setState(() => _sourceFilter = v),
              ),
              const SizedBox(width: 6),
              _buildFilterBadge(
                '🎙️ LiveMCQ',
                'voice',
                _sourceFilter,
                (v) => setState(() => _sourceFilter = v),
                color: const Color(0xFF8B5CF6),
              ),
              const SizedBox(width: 6),
              _buildFilterBadge(
                '📷 বই স্ক্যান',
                'book',
                _sourceFilter,
                (v) => setState(() => _sourceFilter = v),
                color: const Color(0xFF6366F1),
              ),
              const SizedBox(width: 6),
              _buildFilterBadge(
                '📝 ড্রিল',
                'drill',
                _sourceFilter,
                (v) => setState(() => _sourceFilter = v),
                color: const Color(0xFF0EA5E9),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterBadge(
    String label,
    String value,
    String current,
    ValueChanged<String> onSelected, {
    Color color = Colors.indigo,
  }) {
    final isSelected = value == current;
    return InkWell(
      onTap: () => onSelected(value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade400,
            width: isSelected ? 1.4 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? color : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Icon(Icons.verified, size: 64, color: Colors.green.shade400),
            const SizedBox(height: 12),
            const Text(
              'কোনো অমীমাংসিত ভুল নেই!',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              _searchQuery.isNotEmpty
                  ? 'আপনার খোঁজার সাথে কোনো ভুল প্রশ্ন মিলেনি।'
                  : 'লাইভ এমসিকিউ বা প্র্যাকটিস করার সময় ভুল হলে তা স্বয়ংক্রিয়ভাবে এখানে ফোল্ডার আকারে জমা হবে।',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
            if (_searchQuery.isEmpty) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () {
                  QuizDrillModal.show(
                    context,
                    topic: 'Quick Practice',
                    subject: 'General Knowledge',
                  );
                },
                icon: const Icon(Icons.flash_on, size: 16),
                label: const Text(
                  'কুইজ ড্রিল শুরু করুন ⚡',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
