import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/tables/weak_topics_table.dart';
import '../../../quiz/presentation/providers/drill_history_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../topics/presentation/providers/topics_provider.dart';
import '../../domain/models/weakness_healing_model.dart';
import 'weakness_healing_drill_modal.dart';

class WeaknessHealingCard extends ConsumerStatefulWidget {
  const WeaknessHealingCard({super.key});

  @override
  ConsumerState<WeaknessHealingCard> createState() =>
      _WeaknessHealingCardState();
}

class _WeaknessHealingCardState extends ConsumerState<WeaknessHealingCard> {
  int? _overrideTopicId;

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsNotifierProvider);
    final settings = settingsAsync.value;

    // 1. If feature is disabled by the user in settings, render nothing!
    if (settings != null && !settings.isWeaknessHealingEnabled) {
      return const SizedBox.shrink();
    }

    final weakTopics = ref.watch(weakTopicsStreamProvider).value ?? [];
    final unmasteredMistakes =
        ref.watch(wrongQuestionsStreamProvider).value ?? [];

    if (weakTopics.isEmpty) {
      return const SizedBox.shrink();
    }

    final summary = calculateWeaknessHealth(
      topics: weakTopics,
      unmasteredMistakes: unmasteredMistakes,
    );

    // Pick focus topic (either user override or calculated primary focus)
    WeakTopic? focusTopic;
    if (_overrideTopicId != null) {
      focusTopic = weakTopics.firstWhere(
        (t) => t.id == _overrideTopicId,
        orElse: () => summary.primaryFocusTopic ?? weakTopics.first,
      );
    } else {
      focusTopic = summary.primaryFocusTopic ?? weakTopics.first;
    }

    // Matching mistakes for this specific focus topic
    final focusSubjectLower = focusTopic.subject.toLowerCase();
    final focusTopicLower = focusTopic.topicName.toLowerCase();
    final matchingMistakes = unmasteredMistakes.where((m) {
      return m.subject.toLowerCase().contains(focusSubjectLower) ||
          m.topic.toLowerCase().contains(focusTopicLower) ||
          focusTopicLower.contains(m.topic.toLowerCase());
    }).toList();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      elevation: 2.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: isDark
                ? [const Color(0xFF064E3B), const Color(0xFF0F172A)]
                : [const Color(0xFFECFDF5), Colors.white],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: const Color(0xFF10B981)
                .withValues(alpha: isDark ? 0.3 : 0.25),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Healer Badge, Health % Pill, Toggle Menu
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.healing_rounded,
                    color: Color(0xFF10B981),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Flexible(
                            child: Text(
                              'অটো-উইকনেস হিলিং',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14.5,
                              ),
                            ),
                          ),
                          SizedBox(width: 6),
                          Text(
                            '৩মিনিট ড্রিল',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF10B981),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${summary.healedCount}/${summary.totalTopics}টি টপিক স্ট্রং জোনে হিল হয়েছে',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF10B981).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    '${summary.healthPercentage.toStringAsFixed(0)}% Health',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF10B981),
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18),
                  tooltip: 'হিলিং কন্ট্রোল',
                  onSelected: (val) {
                    if (val == 'disable') {
                      ref
                          .read(settingsNotifierProvider.notifier)
                          .setWeaknessHealingEnabled(false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'অটো-উইকনেস হিলিং বন্ধ করা হয়েছে। সেটিংস থেকে পুনরায় চালু করতে পারবেন।',
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'disable',
                      child: Row(
                        children: [
                          Icon(
                            Icons.pause_circle_outline,
                            size: 16,
                            color: Colors.amber,
                          ),
                          SizedBox(width: 8),
                          Text('হিলিং ইঞ্জিন সাময়িক বন্ধ রাখুন'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Health Progress Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (summary.healthPercentage / 100).clamp(0.0, 1.0),
                minHeight: 5,
                backgroundColor: isDark ? Colors.white12 : Colors.grey.shade300,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF10B981),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Target Weak Topic Spotlight Box
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.indigo.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            focusTopic.subject,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _getLevelBadgeColor(
                            focusTopic.proficiencyLevel,
                          ).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _getLevelBadgeText(focusTopic.proficiencyLevel),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: _getLevelBadgeColor(
                              focusTopic.proficiencyLevel,
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (matchingMistakes.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${matchingMistakes.length}টি ভুল সংরক্ষিত',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.redAccent,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '🎯 আজকের ফোকাস: ${focusTopic.topicName}',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (focusTopic.notes != null &&
                      focusTopic.notes!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      focusTopic.notes!,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Action Buttons: Start 3-Min Drill & Switch Topic
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () {
                      WeaknessHealingDrillModal.show(
                        context,
                        topic: focusTopic!,
                        relatedMistakes: matchingMistakes,
                      );
                    },
                    icon: const Icon(Icons.flash_on, size: 16),
                    label: const Text(
                      '৩ মিনিটের হিলিং ড্রিল 🩺',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                if (weakTopics.length > 1) ...[
                  const SizedBox(width: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => _showTopicPickerBottomSheet(weakTopics),
                    child: const Text(
                      'অন্য টপিক',
                      style: TextStyle(fontSize: 11.5),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showTopicPickerBottomSheet(List<WeakTopic> topics) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 16, 18, 8),
                child: Text(
                  'হিলিং ড্রিলের জন্য টপিক বেছে নিন',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: topics.length,
                  itemBuilder: (context, index) {
                    final t = topics[index];
                    return ListTile(
                      leading: Icon(
                        Icons.bookmark_outline,
                        color: _getLevelBadgeColor(t.proficiencyLevel),
                      ),
                      title: Text(
                        t.topicName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        t.subject,
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: Text(
                        _getLevelBadgeText(t.proficiencyLevel),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _getLevelBadgeColor(t.proficiencyLevel),
                        ),
                      ),
                      onTap: () {
                        setState(() {
                          _overrideTopicId = t.id;
                        });
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _getLevelBadgeColor(ProficiencyLevel level) {
    switch (level) {
      case ProficiencyLevel.strong:
        return Colors.green;
      case ProficiencyLevel.moderate:
        return Colors.orange;
      case ProficiencyLevel.weak:
        return Colors.redAccent;
    }
  }

  String _getLevelBadgeText(ProficiencyLevel level) {
    switch (level) {
      case ProficiencyLevel.strong:
        return 'Strong (Healed)';
      case ProficiencyLevel.moderate:
        return 'Moderate';
      case ProficiencyLevel.weak:
        return 'Weak';
    }
  }
}
