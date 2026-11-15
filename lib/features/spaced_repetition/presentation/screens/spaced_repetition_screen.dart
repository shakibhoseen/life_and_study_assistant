import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/theme/fluent_tokens.dart';
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
        padding: const EdgeInsets.fromLTRB(
          FluentSpacing.l,
          FluentSpacing.s,
          FluentSpacing.l,
          40,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Ebbinghaus Forgetting Curve Science Card
            _buildForgettingCurveCard(allItems.length, dueItems.length),
            const SizedBox(height: FluentSpacing.m),

            // 2. Office Micro-Flashcard 5s Trigger Bar
            _buildOfficeFlashcardNudgeBar(),
            const SizedBox(height: FluentSpacing.m),

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
            const SizedBox(height: FluentSpacing.s),

            // Subject Filter Chip Row
            _buildSubjectFilterChips(allItems),
            const SizedBox(height: FluentSpacing.xxs),

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

  Future<void> _showEditRuleDialog(SpacedReviewItem item) async {
    final titleController = TextEditingController(text: item.title);
    final ruleController = TextEditingController(text: item.keyRule);

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: FluentRadius.cardBorder,
          side: FluentStroke.side(Theme.of(dialogContext).brightness),
        ),
        title: const Text('কার্ড সম্পাদনা', style: TextStyle(fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'সামনের দিক (প্রশ্ন বা নাম)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                maxLines: 2,
                minLines: 1,
              ),
              const SizedBox(height: FluentSpacing.m),
              TextField(
                controller: ruleController,
                decoration: const InputDecoration(
                  labelText: 'পেছনের দিক (উত্তর বা নিয়ম)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                maxLines: 8,
                minLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('বাতিল'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('সেভ করুন'),
          ),
        ],
      ),
    );

    final title = titleController.text.trim();
    final rule = ruleController.text.trim();
    titleController.dispose();
    ruleController.dispose();

    // An empty card is worse than the one it would replace.
    if (saved != true || title.isEmpty || rule.isEmpty) return;

    // The schedule is left alone: editing the wording is not the same as
    // having forgotten the card.
    await ref
        .read(spacedRepetitionNotifierProvider.notifier)
        .editItem(id: item.id, title: title, keyRule: rule);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('কার্ডটি বদলানো হলো')));
    }
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
      padding: const EdgeInsets.only(bottom: FluentSpacing.xs),
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
              padding: const EdgeInsets.only(right: FluentSpacing.s),
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    return InkWell(
      onTap: onTap,
      borderRadius: FluentRadius.controlBorder,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: FluentSpacing.m,
          vertical: FluentSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? FluentLayer.subtle(scheme.primary, brightness)
              : Colors.transparent,
          borderRadius: FluentRadius.controlBorder,
          border: Border.all(
            color: isSelected
                ? scheme.primary
                : FluentStroke.card(brightness),
            width: isSelected ? 1.4 : FluentStroke.width,
          ),
        ),
        child: Text(
          label,
          style: FluentType.caption.copyWith(
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? scheme.primary : scheme.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _buildForgettingCurveCard(int totalTracked, int dueCount) {
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: const EdgeInsets.all(FluentSpacing.l),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo.shade800, Colors.deepPurple.shade900],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: FluentRadius.cardBorder,
        border: Border.all(
          color: FluentStroke.card(brightness),
          width: FluentStroke.width,
        ),
        boxShadow: FluentElevation.card(brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(FluentSpacing.s),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: FluentRadius.controlBorder,
                ),
                child: const Icon(
                  Icons.psychology,
                  color: Colors.amber,
                  size: 22,
                ),
              ),
              const SizedBox(width: FluentSpacing.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ebbinghaus Forgetting Curve',
                      style: FluentType.bodyStrong.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '১ দিন, ৩ দিন, ৭ দিন ও ১৪ দিনে রিভিশন = পার্মানেন্ট মেমরি',
                      style: FluentType.caption.copyWith(
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: FluentSpacing.m),
          Text(
            'মানুষ যেকোনো নতুন তথ্য শেখার ২৪ ঘণ্টার মধ্যে প্রায় ৬০% ভুলে যায়। বিজ্ঞানসম্মত ব্যবধানে পুশ নোটিফিকেশন আপনাকে ভুলে যাওয়ার ঠিক আগেই নিয়মটি মনে করিয়ে দেয়।',
            style: FluentType.caption.copyWith(color: Colors.white),
          ),
          const SizedBox(height: FluentSpacing.m),
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
        margin: const EdgeInsets.symmetric(horizontal: FluentSpacing.xxs),
        padding: const EdgeInsets.symmetric(vertical: FluentSpacing.xs),
        decoration: BoxDecoration(
          color: isMastered
              ? Colors.amber.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.12),
          borderRadius: FluentRadius.controlBorder,
          border: Border.all(
            color: isMastered ? Colors.amber : Colors.white24,
            width: FluentStroke.width,
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: FluentRadius.cardBorder,
        side: FluentStroke.side(brightness),
      ),
      child: Padding(
        padding: const EdgeInsets.all(FluentSpacing.m),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(FluentSpacing.s),
              decoration: BoxDecoration(
                color: FluentLayer.subtle(Colors.amber, brightness),
                borderRadius: FluentRadius.controlBorder,
              ),
              child: const Icon(Icons.flash_on, color: Colors.amber, size: 24),
            ),
            const SizedBox(width: FluentSpacing.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Office 5-Second Flashcard',
                    style: FluentType.bodyStrong.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
                  Text(
                    'Test your memory while coding with a background push',
                    style: FluentType.caption.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: FluentSpacing.m,
                  vertical: FluentSpacing.s,
                ),
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(
                  borderRadius: FluentRadius.controlBorder,
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
              child: Text(
                'Push Now',
                style: FluentType.caption.copyWith(
                  fontWeight: FontWeight.w600,
                ),
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
              const SizedBox(height: FluentSpacing.m),
              const Text(
                'All Caught Up for Today!',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: FluentSpacing.s),
              Text(
                'None of your tracked rules are due for review right now.\nKeep taking drills or add more rules to strengthen memory.',
                textAlign: TextAlign.center,
                style: FluentType.caption.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(height: FluentSpacing.l),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: FluentStroke.width,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: FluentSpacing.l,
                    vertical: FluentSpacing.s,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: FluentRadius.controlBorder,
                  ),
                ),
                onPressed: () {
                  setState(() {
                    _tabFilterIndex = 1;
                  });
                },
                icon: const Icon(Icons.style_outlined, size: 16),
                label: Text(
                  'সকল সংরক্ষিত ফ্ল্যাশকার্ড দেখুন',
                  style: FluentType.caption.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
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
          padding: const EdgeInsets.only(
            bottom: FluentSpacing.s,
            left: FluentSpacing.xxs,
            right: FluentSpacing.xxs,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Active Recall মেমোরি টেস্ট',
                  style: FluentType.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Flexible(
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _revealAllByDefault = !_revealAllByDefault;
                    });
                  },
                  borderRadius: FluentRadius.controlBorder,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FluentSpacing.s,
                      vertical: FluentSpacing.xxs,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _revealAllByDefault
                              ? Icons.visibility
                              : Icons.visibility_off_outlined,
                          size: 14,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: FluentSpacing.xs),
                        Flexible(
                          child: Text(
                            _revealAllByDefault
                                ? 'সব উত্তর দৃশ্যমান'
                                : 'উত্তর লুকানো 🔒',
                            style: FluentType.caption.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final isDark = brightness == Brightness.dark;
    final isRevealed =
        _revealAllByDefault || _revealedCardIds.contains(item.id);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: FluentSpacing.m),
      shape: RoundedRectangleBorder(
        borderRadius: FluentRadius.cardBorder,
        side: FluentStroke.side(brightness),
      ),
      child: Padding(
        padding: const EdgeInsets.all(FluentSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Subject & Repetition Stage Badge
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FluentSpacing.s,
                    vertical: FluentSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.indigo.withValues(alpha: 0.2)
                        : Colors.indigo.shade50,
                    borderRadius: FluentRadius.controlBorder,
                  ),
                  child: Text(
                    item.subject,
                    style: FluentType.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? Colors.indigo.shade200
                          : Colors.indigo.shade800,
                    ),
                  ),
                ),
                const SizedBox(width: FluentSpacing.s),
                Expanded(
                  child: Text(
                    '• ${item.topic}',
                    style: FluentType.caption.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FluentSpacing.s,
                    vertical: FluentSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.orange.withValues(alpha: 0.2)
                        : Colors.orange.shade50,
                    borderRadius: FluentRadius.controlBorder,
                    border: Border.all(
                      color: isDark
                          ? Colors.orange.withValues(alpha: 0.4)
                          : Colors.orange.shade200,
                      width: FluentStroke.width,
                    ),
                  ),
                  child: Text(
                    'Lvl ${item.repetitionLevel} (${item.intervalDays}d)',
                    style: FluentType.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? Colors.orange.shade200
                          : Colors.orange.shade800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: FluentSpacing.s),

            // Title (Front of Flashcard)
            Text(
              BengaliMathSanitizer.sanitize(item.title),
              style: FluentType.bodyStrong.copyWith(color: scheme.onSurface),
            ),
            const SizedBox(height: FluentSpacing.s),

            if (!isRevealed) ...[
              // Active Recall: Tap to Reveal Button
              InkWell(
                borderRadius: FluentRadius.controlBorder,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _revealedCardIds.add(item.id);
                  });
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: FluentSpacing.m,
                    horizontal: FluentSpacing.l,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1E293B)
                        : const Color(0xFFF1F5F9),
                    borderRadius: FluentRadius.controlBorder,
                    border: Border.all(
                      color: FluentStroke.card(brightness),
                      width: FluentStroke.width,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.visibility_outlined,
                        size: 18,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: FluentSpacing.s),
                      Flexible(
                        child: Text(
                          'উত্তর দেখুন (Tap to Reveal Answer)',
                          style: FluentType.bodyStrong.copyWith(
                            color: scheme.primary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                padding: const EdgeInsets.all(FluentSpacing.m),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E293B)
                      : const Color(0xFFFAFAFA),
                  borderRadius: FluentRadius.cardBorder,
                  border: Border.all(
                    color: FluentStroke.card(brightness),
                    width: FluentStroke.width,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            'উত্তর ও নিয়ম:',
                            style: FluentType.caption.copyWith(
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface.withValues(alpha: 0.65),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Flexible(
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _revealedCardIds.remove(item.id);
                              });
                            },
                            child: Text(
                              'ঢাকুন 🙈',
                              style: FluentType.caption.copyWith(
                                color: scheme.onSurface.withValues(alpha: 0.65),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: FluentSpacing.s),
                    Text(
                      BengaliMathSanitizer.sanitize(item.keyRule),
                      style: FluentType.body.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: FluentSpacing.m),

              // Actions: [ Forgot (Reset to 1d) ] vs [ Remembered (+Interval) ]
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(
                          color: Colors.red.shade300,
                          width: FluentStroke.width,
                        ),
                        padding: const EdgeInsets.symmetric(
                          vertical: FluentSpacing.s,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: FluentRadius.controlBorder,
                        ),
                      ),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: Text(
                        'মনে নেই',
                        style: FluentType.caption.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: () async {
                        HapticFeedback.lightImpact();
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
                  const SizedBox(width: FluentSpacing.m),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          vertical: FluentSpacing.s,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: FluentRadius.controlBorder,
                        ),
                      ),
                      icon: const Icon(Icons.done_all, size: 16),
                      label: Text(
                        'মনে আছে',
                        style: FluentType.caption.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: () async {
                        HapticFeedback.mediumImpact();
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
              Icon(
                Icons.layers_clear,
                size: 60,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.35),
              ),
              const SizedBox(height: FluentSpacing.m),
              const Text(
                'No Rules Tracked Yet',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: FluentSpacing.s),
              Text(
                'Add difficult rules you just learned using the + button.',
                style: FluentType.caption.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.65),
                ),
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
          elevation: 0,
          margin: const EdgeInsets.only(bottom: FluentSpacing.m),
          shape: RoundedRectangleBorder(
            borderRadius: FluentRadius.cardBorder,
            side: FluentStroke.side(Theme.of(context).brightness),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: FluentSpacing.l,
              vertical: FluentSpacing.s,
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
              style: FluentType.bodyStrong.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: FluentSpacing.xs),
                Text(
                  '${item.subject} • ${item.topic}',
                  style: FluentType.caption.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
                const SizedBox(height: FluentSpacing.xxs),
                Text(
                  'Next review: ${_formatDate(item.nextReviewDate)} (Level ${item.repetitionLevel})',
                  style: FluentType.caption.copyWith(
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
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // A card with a typo or a wrong fact used to leave only one
                // option: delete it and start over, losing its schedule with
                // it, and for a scanned card meaning another scan.
                IconButton(
                  tooltip: 'সম্পাদনা করুন',
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: () => _showEditRuleDialog(item),
                ),
                IconButton(
                  tooltip: 'মুছে ফেলুন',
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
              ],
            ),
          ),
        );
      },
    );
  }

  void _showRuleDetailModal(BuildContext context, SpacedReviewItem item) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final isDark = brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(
          FluentSpacing.xl,
          FluentSpacing.l,
          FluentSpacing.xl,
          FluentSpacing.xxl,
        ),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(FluentRadius.large),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: FluentSpacing.l),
                decoration: BoxDecoration(
                  color: scheme.onSurface.withValues(alpha: 0.3),
                  borderRadius: FluentRadius.controlBorder,
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FluentSpacing.s,
                    vertical: FluentSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.indigo.withValues(alpha: 0.25)
                        : Colors.indigo.shade50,
                    borderRadius: FluentRadius.controlBorder,
                  ),
                  child: Text(
                    item.subject,
                    style: FluentType.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? Colors.indigo.shade200
                          : Colors.indigo.shade800,
                    ),
                  ),
                ),
                const SizedBox(width: FluentSpacing.s),
                Expanded(
                  child: Text(
                    item.topic,
                    style: FluentType.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (item.isMastered)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FluentSpacing.s,
                      vertical: FluentSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.green.withValues(alpha: 0.2)
                          : Colors.green.shade50,
                      borderRadius: FluentRadius.controlBorder,
                    ),
                    child: Text(
                      '✓ Mastered',
                      style: FluentType.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Colors.green,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: FluentSpacing.l),
            Text(
              'প্রশ্ন / সূত্র (Front):',
              style: FluentType.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: scheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: FluentSpacing.xs),
            Text(
              BengaliMathSanitizer.sanitize(item.title),
              style: FluentType.bodyStrong.copyWith(color: scheme.onSurface),
            ),
            const SizedBox(height: FluentSpacing.l),
            Text(
              'উত্তর ও নিয়ম (Back):',
              style: FluentType.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: scheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: FluentSpacing.s),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(FluentSpacing.m),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF0F172A)
                    : const Color(0xFFF8FAFC),
                borderRadius: FluentRadius.cardBorder,
                border: Border.all(
                  color: FluentStroke.card(brightness),
                  width: FluentStroke.width,
                ),
              ),
              child: Text(
                BengaliMathSanitizer.sanitize(item.keyRule),
                style: FluentType.body.copyWith(color: scheme.onSurface),
              ),
            ),
            const SizedBox(height: FluentSpacing.l),
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 14,
                  color: scheme.onSurface.withValues(alpha: 0.5),
                ),
                const SizedBox(width: FluentSpacing.s),
                Expanded(
                  child: Text(
                    'পরবর্তী রিভিশন: ${_formatDate(item.nextReviewDate)} (লেভেল ${item.repetitionLevel}, ব্যবধান: ${item.intervalDays} দিন)',
                    style: FluentType.caption.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.65),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: FluentSpacing.l),
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
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: FluentRadius.cardBorder,
          side: FluentStroke.side(Theme.of(ctx).brightness),
        ),
        title: const Text('Add Rule to Spaced Repetition'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: Theme.of(ctx).colorScheme.primary,
                  side: BorderSide(
                    color: Theme.of(ctx).colorScheme.primary,
                    width: FluentStroke.width,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: FluentRadius.controlBorder,
                  ),
                ),
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: const Text('বা AI দিয়ে স্বয়ংক্রিয় তৈরি করুন 🪄'),
                onPressed: () {
                  Navigator.pop(ctx);
                  AiFlashcardGeneratorModal.show(context);
                },
              ),
              const SizedBox(height: FluentSpacing.m),
              TextField(
                controller: subjectController,
                decoration: const InputDecoration(
                  labelText: 'Subject (e.g. Bangla Grammar)',
                  isDense: true,
                ),
              ),
              const SizedBox(height: FluentSpacing.m),
              TextField(
                controller: topicController,
                decoration: const InputDecoration(
                  labelText: 'Topic Name (e.g. সমাস)',
                  isDense: true,
                ),
              ),
              const SizedBox(height: FluentSpacing.m),
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'Rule Title / Keyword',
                  isDense: true,
                ),
              ),
              const SizedBox(height: FluentSpacing.m),
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
      // Four controllers a time, kept alive for the rest of the session
      // otherwise. The dialog above it disposes its two; this one was missed.
    ).whenComplete(() {
      subjectController.dispose();
      topicController.dispose();
      titleController.dispose();
      ruleController.dispose();
    });
  }
}
