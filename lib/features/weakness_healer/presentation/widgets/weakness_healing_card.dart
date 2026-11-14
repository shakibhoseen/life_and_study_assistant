import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/tables/weak_topics_table.dart';
import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/widgets/premium_glass_card.dart';
import '../../../../core/widgets/premium_ui_kit.dart';
import '../../../quiz/presentation/providers/drill_history_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../topics/presentation/providers/topics_provider.dart';
import '../../domain/models/weakness_healing_model.dart';
import 'weakness_healing_drill_modal.dart';

/// Green is the *status* colour in this card — it is a health meter — so it
/// stays, while the decorative gradient and the coloured glow go.
const Color _healthColor = Color(0xFF10B981);

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

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final secondaryText = scheme.onSurface.withValues(alpha: 0.65);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: FluentRadius.cardBorder,
        side: FluentStroke.side(brightness),
      ),
      child: Container(
        padding: const EdgeInsets.all(FluentSpacing.l),
        decoration: BoxDecoration(borderRadius: FluentRadius.cardBorder),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Healer Badge, Health % Pill, Toggle Menu
            Row(
              children: [
                const PremiumIconBadge(
                  icon: Icons.healing_rounded,
                  size: 36,
                  iconSize: 20,
                  color: _healthColor,
                ),
                const SizedBox(width: FluentSpacing.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'অটো-উইকনেস হিলিং',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: FluentType.bodyStrong.copyWith(
                                color: scheme.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: FluentSpacing.s),
                          // Flexible, not a bare Text: this label used to
                          // demand its full width beside the title.
                          Flexible(
                            child: Text(
                              '৩মিনিট ড্রিল',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: FluentType.caption.copyWith(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: _healthColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${summary.healedCount}/${summary.totalTopics}টি টপিক স্ট্রং জোনে হিল হয়েছে',
                        style: FluentType.caption.copyWith(
                          color: secondaryText,
                        ),
                      ),
                    ],
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
                            SizedBox(width: FluentSpacing.s),
                            Text('হিলিং ইঞ্জিন সাময়িক বন্ধ রাখুন'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: FluentSpacing.m),

            // Health Progress Bar, with the health figure beside it. The
            // percentage pill used to sit in the header row, where it and the
            // title fought over the same width.
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: FluentRadius.controlBorder,
                    child: LinearProgressIndicator(
                      value: (summary.healthPercentage / 100).clamp(0.0, 1.0),
                      minHeight: 5,
                      backgroundColor: scheme.onSurface.withValues(alpha: 0.10),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        _healthColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: FluentSpacing.s),
                PremiumTag(
                  label:
                      '${summary.healthPercentage.toStringAsFixed(0)}% Health',
                  color: _healthColor,
                ),
              ],
            ),
            const SizedBox(height: FluentSpacing.m),

            // Target Weak Topic Spotlight Box
            Container(
              padding: const EdgeInsets.all(FluentSpacing.m),
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: 0.04),
                borderRadius: FluentRadius.controlBorder,
                border: Border.all(
                  color: FluentStroke.card(brightness),
                  width: FluentStroke.width,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // A Wrap, not a Row with a Spacer: the three badges
                  // together are wider than the card at 320px / 1.5x text,
                  // and none of them could shrink.
                  Wrap(
                    spacing: FluentSpacing.s,
                    runSpacing: FluentSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      PremiumTag(
                        label: focusTopic.subject,
                        color: scheme.primary,
                      ),
                      PremiumTag(
                        label: _getLevelBadgeText(focusTopic.proficiencyLevel),
                        color: _getLevelBadgeColor(
                          focusTopic.proficiencyLevel,
                        ),
                      ),
                      if (matchingMistakes.isNotEmpty)
                        PremiumTag(
                          label: '${matchingMistakes.length}টি ভুল সংরক্ষিত',
                          color: Colors.redAccent,
                        ),
                    ],
                  ),
                  const SizedBox(height: FluentSpacing.s),
                  Text(
                    '🎯 আজকের ফোকাস: ${focusTopic.topicName}',
                    style: FluentType.bodyStrong.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
                  if (focusTopic.notes != null &&
                      focusTopic.notes!.isNotEmpty) ...[
                    const SizedBox(height: FluentSpacing.xxs),
                    Text(
                      focusTopic.notes!,
                      style: FluentType.caption.copyWith(color: secondaryText),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: FluentSpacing.m),

            // Action Buttons: Start 3-Min Drill & Switch Topic
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _healthColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        vertical: FluentSpacing.s,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: FluentRadius.controlBorder,
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
                    label: Text(
                      '৩ মিনিটের হিলিং ড্রিল 🩺',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FluentType.caption.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                if (weakTopics.length > 1) ...[
                  const SizedBox(width: FluentSpacing.s),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: FluentSpacing.m,
                        vertical: FluentSpacing.s,
                      ),
                      visualDensity: VisualDensity.compact,
                      side: BorderSide(color: FluentStroke.card(brightness)),
                      shape: RoundedRectangleBorder(
                        borderRadius: FluentRadius.controlBorder,
                      ),
                    ),
                    onPressed: () => _showTopicPickerBottomSheet(weakTopics),
                    child: Text(
                      'অন্য টপিক',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FluentType.caption.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
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
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(FluentRadius.large),
        ),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  FluentSpacing.l,
                  FluentSpacing.l,
                  FluentSpacing.l,
                  FluentSpacing.s,
                ),
                child: Text(
                  'হিলিং ড্রিলের জন্য টপিক বেছে নিন',
                  style: FluentType.subtitle.copyWith(fontSize: 16),
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
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: FluentType.bodyStrong,
                      ),
                      subtitle: Text(
                        t.subject,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FluentType.caption.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                      trailing: Text(
                        _getLevelBadgeText(t.proficiencyLevel),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FluentType.caption.copyWith(
                          fontWeight: FontWeight.w600,
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
