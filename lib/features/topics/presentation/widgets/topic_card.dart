import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/tables/weak_topics_table.dart';
import '../../../chat/presentation/providers/chat_provider.dart';
import '../../../chat/presentation/screens/ai_chat_screen.dart';
import '../../../quiz/presentation/widgets/quiz_drill_modal.dart';
import '../providers/topics_provider.dart';

class TopicCard extends ConsumerWidget {
  final dynamic topic;

  const TopicCard({super.key, required this.topic});

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'today';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                            .updateProficiency(
                              topic.id,
                              ProficiencyLevel.strong,
                            );
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
                          MaterialPageRoute(
                            builder: (_) => const AiChatScreen(),
                          ),
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
}
