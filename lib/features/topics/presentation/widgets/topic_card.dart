import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/tables/weak_topics_table.dart';
import '../../../../core/theme/fluent_tokens.dart';
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

    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final secondaryText = scheme.onSurface.withValues(alpha: 0.65);

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
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: FluentSpacing.s,
                        vertical: FluentSpacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        color: FluentLayer.subtle(scheme.primary, brightness),
                        borderRadius: FluentRadius.controlBorder,
                      ),
                      child: Text(
                        topic.subject,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FluentType.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: FluentSpacing.s),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FluentSpacing.s,
                    vertical: FluentSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: FluentLayer.subtle(badgeColor, brightness),
                    borderRadius: FluentRadius.controlBorder,
                  ),
                  child: Text(
                    badgeText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FluentType.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: badgeColor,
                    ),
                  ),
                ),
                const SizedBox(width: FluentSpacing.xs),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(Icons.more_vert, size: 18, color: secondaryText),
                    shape: RoundedRectangleBorder(
                      borderRadius: FluentRadius.cardBorder,
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
                      PopupMenuItem(
                        value: 'drill',
                        child: Row(
                          children: [
                            Icon(
                              Icons.psychology,
                              size: 16,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: FluentSpacing.s),
                            Text(
                              'Drill 5 MCQs (AI Quiz)',
                              style: FluentType.body,
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'ask_ai',
                        child: Row(
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 16,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: FluentSpacing.s),
                            Text(
                              'Explain with AI Mentor',
                              style: FluentType.body,
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'weak',
                        child: Text('Mark as Weak', style: FluentType.body),
                      ),
                      PopupMenuItem(
                        value: 'moderate',
                        child: Text('Mark as Moderate', style: FluentType.body),
                      ),
                      PopupMenuItem(
                        value: 'strong',
                        child: Text('Mark as Strong', style: FluentType.body),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          'Delete',
                          style: FluentType.body.copyWith(
                            color: scheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: FluentSpacing.s),
            Text(
              topic.topicName,
              style: FluentType.bodyStrong.copyWith(color: scheme.onSurface),
            ),
            if (topic.notes != null && topic.notes.isNotEmpty) ...[
              const SizedBox(height: FluentSpacing.xs),
              Text(
                topic.notes,
                style: FluentType.caption.copyWith(color: secondaryText),
              ),
            ],
            const SizedBox(height: FluentSpacing.s),
            // Reviewed-at and the actions stack instead of sharing a Row: at
            // 320px with large text the two buttons alone fill the width.
            Text(
              reviewedText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FluentType.caption.copyWith(color: secondaryText),
            ),
            const SizedBox(height: FluentSpacing.s),
            Wrap(
              spacing: FluentSpacing.s,
              runSpacing: FluentSpacing.xs,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FluentSpacing.s,
                      vertical: FluentSpacing.xxs,
                    ),
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(color: FluentStroke.card(brightness)),
                    shape: RoundedRectangleBorder(
                      borderRadius: FluentRadius.controlBorder,
                    ),
                  ),
                  icon: Icon(
                    Icons.psychology,
                    size: 14,
                    color: scheme.primary,
                  ),
                  label: Text(
                    'Drill',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FluentType.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
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
                      horizontal: FluentSpacing.s,
                      vertical: FluentSpacing.xxs,
                    ),
                    minimumSize: const Size(40, 26),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: FluentRadius.controlBorder,
                    ),
                  ),
                  icon: const Icon(Icons.check, size: 14),
                  label: Text(
                    'Reviewed',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FluentType.caption.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
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
      ),
    );
  }
}
