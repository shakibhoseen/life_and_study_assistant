import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/utils/bengali_math_sanitizer.dart';
import '../providers/spaced_repetition_provider.dart';
import '../widgets/ai_flashcard_generator_modal.dart';

class SpacedRepetitionScreen extends ConsumerStatefulWidget {
  const SpacedRepetitionScreen({super.key});

  @override
  ConsumerState<SpacedRepetitionScreen> createState() =>
      _SpacedRepetitionScreenState();
}

class _SpacedRepetitionScreenState
    extends ConsumerState<SpacedRepetitionScreen> {
  int _tabFilterIndex = 0; // 0 = Due Today, 1 = All Tracked
  final Set<int> _revealedCardIds = {};
  bool _revealAllByDefault = false;
  String _selectedSubjectFilter = 'All';

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final isToday =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    if (isToday) return 'আজ';
    final diff = dt.difference(now).inDays;
    if (diff == 1) return 'আগামীকাল';
    if (diff > 1) return '$diff দিন পর';
    if (diff < 0) return '${-diff} দিন পার';
    return '${dt.day}/${dt.month}';
  }

  @override
  Widget build(BuildContext context) {
    final dueItems = ref.watch(dueSpacedReviewsStreamProvider).value ?? [];
    final allItems = ref.watch(allSpacedReviewsStreamProvider).value ?? [];

    if (_selectedSubjectFilter != 'All' &&
        !allItems.any((i) => i.subject.trim() == _selectedSubjectFilter)) {
      _selectedSubjectFilter = 'All';
    }

    final filteredDueItems = _selectedSubjectFilter == 'All'
        ? dueItems
        : dueItems
              .where((i) => i.subject.trim() == _selectedSubjectFilter)
              .toList();
    final filteredAllItems = _selectedSubjectFilter == 'All'
        ? allItems
        : allItems
              .where((i) => i.subject.trim() == _selectedSubjectFilter)
              .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'রিভিশন ও ফ্ল্যাশকার্ড',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome, color: Color(0xFF6366F1)),
            tooltip: 'AI দিয়ে ফ্ল্যাশ কার্ড ও সূত্র তৈরি',
            onPressed: () => AiFlashcardGeneratorModal.show(context),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'ম্যানুয়ালি সূত্র যোগ করুন',
            onPressed: () => _showAddRuleDialog(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Ebbinghaus Forgetting Curve Science Card
            _buildForgettingCurveCard(allItems.length, dueItems.length),
            const SizedBox(height: 14),

            // 2. Office Micro-Flashcard 5s Trigger Bar
            _buildOfficeFlashcardNudgeBar(),
            const SizedBox(height: 16),

            // 3. Segmented Filter: Due Today vs All Rules
            SegmentedButton<int>(
              segments: [
                ButtonSegment<int>(
                  value: 0,
                  icon: const Icon(Icons.alarm, size: 16),
                  label: Text('আজ দেখার (${dueItems.length})'),
                ),
                ButtonSegment<int>(
                  value: 1,
                  icon: const Icon(Icons.layers_outlined, size: 16),
                  label: Text('সব সূত্র (${allItems.length})'),
                ),
              ],
              selected: {_tabFilterIndex},
              onSelectionChanged: (set) {
                setState(() {
                  _tabFilterIndex = set.first;
                });
              },
            ),
            const SizedBox(height: 12),

            // Subject Filter Chip Row
            _buildSubjectFilterChips(allItems),
            const SizedBox(height: 4),

            // 4. Content List
            if (_tabFilterIndex == 0)
              _buildDueItemsList(filteredDueItems)
            else
              _buildAllItemsList(filteredAllItems),
          ],
        ),
      ),
    );
  }

  Widget _buildSubjectFilterChips(List<SpacedReviewItem> allItems) {
    final Map<String, int> counts = {'All': allItems.length};
    for (final item in allItems) {
      final s = item.subject.trim();
      if (s.isNotEmpty) {
        counts[s] = (counts[s] ?? 0) + 1;
      }
    }

    if (counts.length <= 1) return const SizedBox.shrink();

    final subjects = counts.keys.toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: subjects.map((subj) {
            final count = counts[subj] ?? 0;
            final isSelected = _selectedSubjectFilter == subj;
            final label = subj == 'All'
                ? 'সকল বিষয় ($count)'
                : '$subj ($count)';
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _buildSubjectFilterBadge(
                label: label,
                isSelected: isSelected,
                onTap: () {
                  setState(() {
                    _selectedSubjectFilter = subj;
                  });
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSubjectFilterBadge({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF6366F1).withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF6366F1)
                : (isDark ? Colors.white24 : Colors.grey.shade400),
            width: isSelected ? 1.4 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected
                ? const Color(0xFF6366F1)
                : (isDark ? Colors.white70 : Colors.black87),
          ),
        ),
      ),
    );
  }

  Widget _buildForgettingCurveCard(int totalTracked, int dueCount) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo.shade800, Colors.deepPurple.shade900],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.psychology,
                  color: Colors.amber,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ebbinghaus Forgetting Curve',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14.5,
                      ),
                    ),
                    Text(
                      '১ দিন, ৩ দিন, ৭ দিন ও ১৪ দিনে রিভিশন = পার্মানেন্ট মেমরি',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'মানুষ যেকোনো নতুন তথ্য শেখার ২৪ ঘণ্টার মধ্যে প্রায় ৬০% ভুলে যায়। বিজ্ঞানসম্মত ব্যবধানে পুশ নোটিফিকেশন আপনাকে ভুলে যাওয়ার ঠিক আগেই নিয়মটি মনে করিয়ে দেয়।',
            style: TextStyle(color: Colors.white, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildIntervalPill('1 Day', 'Lvl 1'),
              const Icon(
                Icons.arrow_right_alt,
                color: Colors.white54,
                size: 16,
              ),
              _buildIntervalPill('3 Days', 'Lvl 2'),
              const Icon(
                Icons.arrow_right_alt,
                color: Colors.white54,
                size: 16,
              ),
              _buildIntervalPill('7 Days', 'Lvl 3'),
              const Icon(
                Icons.arrow_right_alt,
                color: Colors.white54,
                size: 16,
              ),
              _buildIntervalPill('14 Days', 'Lvl 4'),
              const Icon(
                Icons.arrow_right_alt,
                color: Colors.white54,
                size: 16,
              ),
              _buildIntervalPill('30 Days', 'Mastered', isMastered: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIntervalPill(
    String interval,
    String level, {
    bool isMastered = false,
  }) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: isMastered
              ? Colors.amber.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isMastered ? Colors.amber : Colors.white24,
            width: 0.8,
          ),
        ),
        child: Column(
          children: [
            Text(
              interval,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.bold,
                color: isMastered ? Colors.amber : Colors.white,
              ),
            ),
            Text(
              level,
              style: const TextStyle(fontSize: 8, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfficeFlashcardNudgeBar() {
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.flash_on, color: Colors.amber, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Office 5-Second Flashcard',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                    ),
                  ),
                  Text(
                    'Test your memory while coding with a background push',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white70
                          : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () async {
                await ref
                    .read(spacedRepetitionNotifierProvider.notifier)
                    .triggerOfficeFlashcardNotification();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        '⚡ 5-Second Flashcard notification sent! Check your notification shade.',
                      ),
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
              },
              child: const Text(
                'Push Now',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // DUE ITEMS LIST
  // ==========================================
  Widget _buildDueItemsList(List<SpacedReviewItem> dueItems) {
    if (dueItems.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 60,
                color: Colors.green.shade400,
              ),
              const SizedBox(height: 12),
              const Text(
                'All Caught Up for Today!',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'None of your tracked rules are due for review right now.\nKeep taking drills or add more rules to strengthen memory.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10, left: 2, right: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Active Recall মেমোরি টেস্ট',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white70
                      : Colors.black54,
                ),
              ),
              InkWell(
                onTap: () {
                  setState(() {
                    _revealAllByDefault = !_revealAllByDefault;
                  });
                },
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _revealAllByDefault
                            ? Icons.visibility
                            : Icons.visibility_off_outlined,
                        size: 14,
                        color: const Color(0xFF6366F1),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _revealAllByDefault
                            ? 'সব উত্তর দৃশ্যমান'
                            : 'উত্তর লুকানো 🔒',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF6366F1),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: dueItems.length,
          itemBuilder: (context, index) {
            final item = dueItems[index];
            return _buildDueItemCard(item);
          },
        ),
      ],
    );
  }

  Widget _buildDueItemCard(SpacedReviewItem item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isRevealed =
        _revealAllByDefault || _revealedCardIds.contains(item.id);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Subject & Repetition Stage Badge
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.indigo.withValues(alpha: 0.2)
                        : Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    item.subject,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? Colors.indigo.shade200
                          : Colors.indigo.shade800,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '• ${item.topic}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.orange.withValues(alpha: 0.2)
                        : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isDark
                          ? Colors.orange.withValues(alpha: 0.4)
                          : Colors.orange.shade200,
                    ),
                  ),
                  child: Text(
                    'Lvl ${item.repetitionLevel} (${item.intervalDays}d)',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? Colors.orange.shade200
                          : Colors.orange.shade800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Title (Front of Flashcard)
            Text(
              BengaliMathSanitizer.sanitize(item.title),
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),

            if (!isRevealed) ...[
              // Active Recall: Tap to Reveal Button
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  setState(() {
                    _revealedCardIds.add(item.id);
                  });
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1E293B)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFCBD5E1),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.visibility_outlined,
                        size: 18,
                        color: isDark
                            ? const Color(0xFFA5B4FC)
                            : const Color(0xFF4F46E5),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'উত্তর দেখুন (Tap to Reveal Answer)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? const Color(0xFFA5B4FC)
                              : const Color(0xFF4F46E5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              // Key Rule / Flashcard Content Container (Back of Flashcard)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? Colors.white12 : Colors.grey.shade200,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'উত্তর ও নিয়ম:',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            setState(() {
                              _revealedCardIds.remove(item.id);
                            });
                          },
                          child: Text(
                            'ঢাকুন 🙈',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white38 : Colors.grey,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      BengaliMathSanitizer.sanitize(item.keyRule),
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Actions: [ Forgot (Reset to 1d) ] vs [ Remembered (+Interval) ]
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text(
                        'মনে নেই',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: () async {
                        setState(() {
                          _revealedCardIds.remove(item.id);
                        });
                        await ref
                            .read(spacedRepetitionNotifierProvider.notifier)
                            .resetReview(item.id);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '"${item.title}" কালই আবার দেখাবে।',
                              ),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.done_all, size: 16),
                      label: const Text(
                        'মনে আছে',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: () async {
                        setState(() {
                          _revealedCardIds.remove(item.id);
                        });
                        await ref
                            .read(spacedRepetitionNotifierProvider.notifier)
                            .advanceReview(item.id);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '🎉 পাকা হলো! পরেরবার ${item.intervalDays * 2} দিন পর।',
                              ),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ==========================================
  // ALL ITEMS LIST
  // ==========================================
  Widget _buildAllItemsList(List<SpacedReviewItem> allItems) {
    if (allItems.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              Icon(Icons.layers_clear, size: 60, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              const Text(
                'No Rules Tracked Yet',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Add difficult rules you just learned using the + button.',
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
      itemCount: allItems.length,
      itemBuilder: (context, index) {
        final item = allItems[index];

        return Card(
          elevation: 1,
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 6,
            ),
            onTap: () => _showRuleDetailModal(context, item),
            leading: CircleAvatar(
              backgroundColor: item.isMastered
                  ? (Theme.of(context).brightness == Brightness.dark
                        ? Colors.green.withValues(alpha: 0.25)
                        : Colors.green.shade100)
                  : (Theme.of(context).brightness == Brightness.dark
                        ? Colors.indigo.withValues(alpha: 0.25)
                        : Colors.indigo.shade50),
              child: Icon(
                item.isMastered ? Icons.verified : Icons.alarm,
                color: item.isMastered
                    ? (Theme.of(context).brightness == Brightness.dark
                          ? Colors.greenAccent
                          : Colors.green.shade800)
                    : (Theme.of(context).brightness == Brightness.dark
                          ? Colors.indigoAccent
                          : Colors.indigo.shade700),
                size: 20,
              ),
            ),
            title: Text(
              item.title,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 3),
                Text(
                  '${item.subject} • ${item.topic}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white70
                        : Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Next review: ${_formatDate(item.nextReviewDate)} (Level ${item.repetitionLevel})',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: item.isMastered
                        ? (Theme.of(context).brightness == Brightness.dark
                              ? Colors.greenAccent
                              : Colors.green.shade700)
                        : (Theme.of(context).brightness == Brightness.dark
                              ? Colors.indigoAccent
                              : Colors.indigo.shade700),
                  ),
                ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(
                Icons.delete_outline,
                size: 18,
                color: Colors.red,
              ),
              onPressed: () {
                ref
                    .read(spacedRepetitionNotifierProvider.notifier)
                    .deleteRule(item.id);
              },
            ),
          ),
        );
      },
    );
  }

  void _showRuleDetailModal(BuildContext context, SpacedReviewItem item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.indigo.withValues(alpha: 0.25)
                        : Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    item.subject,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? Colors.indigo.shade200
                          : Colors.indigo.shade800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.topic,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (item.isMastered)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.green.withValues(alpha: 0.2)
                          : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '✓ Mastered',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'প্রশ্ন / সূত্র (Front):',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              BengaliMathSanitizer.sanitize(item.title),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'উত্তর ও নিয়ম (Back):',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF0F172A)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.grey.shade300,
                ),
              ),
              child: Text(
                BengaliMathSanitizer.sanitize(item.keyRule),
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 14,
                  color: Colors.grey.shade500,
                ),
                const SizedBox(width: 6),
                Text(
                  'পরবর্তী রিভিশন: ${_formatDate(item.nextReviewDate)} (লেভেল ${item.repetitionLevel}, ব্যবধান: ${item.intervalDays} দিন)',
                  style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('বন্ধ করুন'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddRuleDialog(BuildContext context) {
    final subjectController = TextEditingController();
    final topicController = TextEditingController();
    final titleController = TextEditingController();
    final ruleController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Rule to Spaced Repetition'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: const Color(0xFF6366F1),
                  side: const BorderSide(color: Color(0xFF6366F1)),
                ),
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: const Text('বা AI দিয়ে স্বয়ংক্রিয় তৈরি করুন 🪄'),
                onPressed: () {
                  Navigator.pop(ctx);
                  AiFlashcardGeneratorModal.show(context);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: subjectController,
                decoration: const InputDecoration(
                  labelText: 'Subject (e.g. Bangla Grammar)',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: topicController,
                decoration: const InputDecoration(
                  labelText: 'Topic Name (e.g. সমাস)',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'Rule Title / Keyword',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: ruleController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'The Rule, Mnemonic, or Trap to remember',
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final sub = subjectController.text.trim();
              final top = topicController.text.trim();
              final title = titleController.text.trim();
              final rule = ruleController.text.trim();

              if (sub.isNotEmpty && title.isNotEmpty && rule.isNotEmpty) {
                await ref
                    .read(spacedRepetitionNotifierProvider.notifier)
                    .addRule(
                      subject: sub,
                      topic: top.isNotEmpty ? top : sub,
                      title: title,
                      keyRule: rule,
                    );
                if (context.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Added "$title" to Spaced Repetition curve!',
                      ),
                    ),
                  );
                }
              }
            },
            child: const Text('Save & Track'),
          ),
        ],
      ),
    );
  }
}
