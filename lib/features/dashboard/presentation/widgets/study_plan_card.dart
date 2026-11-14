import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/widgets/premium_glass_card.dart';
import '../../../chat/presentation/screens/ai_chat_screen.dart';
import '../../../quiz/presentation/widgets/quiz_drill_modal.dart';
import '../../../study_planner/presentation/providers/adaptive_planner_provider.dart';
import '../../../study_planner/presentation/widgets/focus_timer_dialog.dart';

class StudyPlanCard extends ConsumerWidget {
  const StudyPlanCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plannerAsync = ref.watch(adaptivePlannerProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final onSurface = scheme.onSurface;
    final onSurfaceMuted = onSurface.withValues(alpha: 0.65);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: FluentRadius.cardBorder,
        side: FluentStroke.side(brightness),
      ),
      child: Padding(
        padding: const EdgeInsets.all(FluentSpacing.l),
        child: plannerAsync.when(
          loading: () => Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: FluentSpacing.xxl),
              child: Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: FluentSpacing.m),
                  Text(
                    'Gemini AI tailoring adaptive study plan...',
                    textAlign: TextAlign.center,
                    style: FluentType.body.copyWith(color: onSurfaceMuted),
                  ),
                ],
              ),
            ),
          ),
          error: (err, stack) => Column(
            children: [
              Icon(Icons.error_outline, color: scheme.error, size: 36),
              const SizedBox(height: FluentSpacing.s),
              Text(
                'Could not load plan: $err',
                style: FluentType.caption.copyWith(color: onSurfaceMuted),
              ),
              TextButton(
                onPressed: () =>
                    ref.read(adaptivePlannerProvider.notifier).generatePlan(),
                child: const Text('Retry'),
              ),
            ],
          ),
          data: (plan) {
            if (plan == null) {
              return const Center(child: Text('No plan generated yet.'));
            }

            final isLowEnergy =
                plan.energyLevel.toLowerCase() == 'low' ||
                plan.fatigueScore >= 7;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const PremiumIconBadge(
                      icon: Icons.auto_awesome,
                      size: 32,
                      iconSize: 20,
                    ),
                    const SizedBox(width: FluentSpacing.s),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tonight’s Adaptive AI Routine',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: FluentType.bodyStrong.copyWith(
                              fontSize: 16,
                              color: onSurface,
                            ),
                          ),
                          // The plan is drawn from real weak topics and exams
                          // either way, but a plan the model never saw should
                          // not be presented under its name.
                          if (plan.isLocallyBuilt)
                            Text(
                              'ফোনেই সাজানো — AI-তে পৌঁছানো যায়নি',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: FluentType.caption.copyWith(
                                color: const Color(0xFFF59E0B),
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      tooltip: 'Regenerate Plan',
                      onPressed: () => ref
                          .read(adaptivePlannerProvider.notifier)
                          .generatePlan(),
                    ),
                  ],
                ),
                const SizedBox(height: FluentSpacing.s),
                // Motivational Quote in Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(FluentSpacing.m),
                  decoration: BoxDecoration(
                    color: FluentLayer.subtle(scheme.primary, brightness),
                    borderRadius: FluentRadius.controlBorder,
                    border: Border.all(
                      color: FluentStroke.card(brightness),
                      width: FluentStroke.width,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('💡', style: FluentType.body),
                      const SizedBox(width: FluentSpacing.s),
                      Expanded(
                        child: Text(
                          plan.motivationalQuote,
                          style: FluentType.body.copyWith(
                            fontStyle: FontStyle.italic,
                            color: onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: FluentSpacing.m),
                // Time allocation badges
                Row(
                  children: [
                    Expanded(
                      child: _buildTimeBadge(
                        icon: Icons.menu_book,
                        label: '${plan.recommendedStudyMinutes}m Study',
                        // Amber only when the plan is flagging low energy.
                        color: isLowEnergy
                            ? const Color(0xFFF59E0B)
                            : scheme.primary,
                        bgColor: FluentLayer.subtle(
                          isLowEnergy
                              ? const Color(0xFFF59E0B)
                              : scheme.primary,
                          brightness,
                        ),
                      ),
                    ),
                    const SizedBox(width: FluentSpacing.s),
                    Expanded(
                      child: _buildTimeBadge(
                        icon: Icons.favorite,
                        label: '${plan.recommendedFamilyMinutes}m Rest',
                        color: onSurface.withValues(alpha: 0.75),
                        bgColor: FluentLayer.subtle(onSurface, brightness),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: FluentSpacing.m),
                Text(
                  plan.summary,
                  style: FluentType.body.copyWith(color: onSurface),
                ),
                if (plan.burnoutWarning != null) ...[
                  const SizedBox(height: FluentSpacing.s),
                  Container(
                    padding: const EdgeInsets.all(FluentSpacing.m),
                    decoration: BoxDecoration(
                      color: FluentLayer.subtle(scheme.error, brightness),
                      borderRadius: FluentRadius.controlBorder,
                      border: Border.all(
                        color: scheme.error.withValues(alpha: 0.3),
                        width: FluentStroke.width,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning, color: scheme.error, size: 18),
                        const SizedBox(width: FluentSpacing.s),
                        Expanded(
                          child: Text(
                            plan.burnoutWarning!,
                            style: FluentType.caption.copyWith(
                              color: onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: FluentSpacing.l),
                Text(
                  'Micro-Commitment Tasks:',
                  style: FluentType.bodyStrong.copyWith(color: onSurface),
                ),
                const SizedBox(height: FluentSpacing.s),
                // Tasks checklist
                ...plan.tasks.map((task) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: FluentSpacing.s),
                    decoration: BoxDecoration(
                      color: task.isCompleted
                          ? FluentLayer.subtle(onSurface, brightness)
                          : (theme.cardTheme.color ?? theme.cardColor),
                      borderRadius: FluentRadius.controlBorder,
                      border: Border.all(
                        color: FluentStroke.card(brightness),
                        width: FluentStroke.width,
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: CheckboxListTile(
                        dense: true,
                        value: task.isCompleted,
                        activeColor: scheme.primary,
                        checkboxShape: RoundedRectangleBorder(
                          borderRadius: FluentRadius.controlBorder,
                        ),
                        title: Text(
                          task.title,
                          style: FluentType.bodyStrong.copyWith(
                            decoration: task.isCompleted
                                ? TextDecoration.lineThrough
                                : null,
                            color: task.isCompleted
                                ? onSurfaceMuted
                                : onSurface,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              task.actionablePrompt,
                              style: FluentType.caption.copyWith(
                                color: onSurfaceMuted,
                              ),
                            ),
                            const SizedBox(height: FluentSpacing.xs + 2),
                            Wrap(
                              spacing: FluentSpacing.xs + 2,
                              runSpacing: FluentSpacing.xs,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: FluentSpacing.s,
                                    vertical: FluentSpacing.xxs,
                                  ),
                                  decoration: BoxDecoration(
                                    color: FluentLayer.subtle(
                                      onSurface,
                                      brightness,
                                    ),
                                    borderRadius: FluentRadius.controlBorder,
                                  ),
                                  child: Text(
                                    task.subject,
                                    style: FluentType.caption.copyWith(
                                      color: onSurface,
                                    ),
                                  ),
                                ),
                                Text(
                                  '⏱ ${task.estimatedMinutes}m',
                                  style: FluentType.caption.copyWith(
                                    color: onSurfaceMuted,
                                  ),
                                ),
                                InkWell(
                                  onTap: () => FocusTimerDialog.show(
                                    context,
                                    taskId: task.id,
                                    taskTitle: task.title,
                                    subject: task.subject,
                                    initialMinutes: task.estimatedMinutes,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: FluentSpacing.s,
                                      vertical: FluentSpacing.xxs,
                                    ),
                                    decoration: BoxDecoration(
                                      color: FluentLayer.subtle(
                                        scheme.primary,
                                        brightness,
                                      ),
                                      borderRadius: FluentRadius.controlBorder,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.timer,
                                          size: 12,
                                          color: scheme.primary,
                                        ),
                                        const SizedBox(width: FluentSpacing.xs),
                                        Text(
                                          'Focus',
                                          style: FluentType.caption.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: scheme.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                InkWell(
                                  onTap: () => QuizDrillModal.show(
                                    context,
                                    topic: task.title,
                                    subject: task.subject,
                                    onCompleted: () {
                                      ref
                                          .read(
                                            adaptivePlannerProvider.notifier,
                                          )
                                          .toggleTaskCompletion(task.id);
                                    },
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: FluentSpacing.s,
                                      vertical: FluentSpacing.xxs,
                                    ),
                                    decoration: BoxDecoration(
                                      color: FluentLayer.subtle(
                                        onSurface,
                                        brightness,
                                      ),
                                      borderRadius: FluentRadius.controlBorder,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.psychology,
                                          size: 12,
                                          color: onSurface.withValues(
                                            alpha: 0.75,
                                          ),
                                        ),
                                        const SizedBox(width: FluentSpacing.xs),
                                        Text(
                                          'Quiz',
                                          style: FluentType.caption.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: onSurface.withValues(
                                              alpha: 0.75,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        onChanged: (val) {
                          ref
                              .read(adaptivePlannerProvider.notifier)
                              .toggleTaskCompletion(task.id);
                        },
                      ),
                    ),
                  );
                }),
                const SizedBox(height: FluentSpacing.m),
                // Family & Wellbeing advice box
                Container(
                  padding: const EdgeInsets.all(FluentSpacing.m),
                  decoration: BoxDecoration(
                    color: FluentLayer.subtle(onSurface, brightness),
                    borderRadius: FluentRadius.controlBorder,
                    border: Border.all(
                      color: FluentStroke.card(brightness),
                      width: FluentStroke.width,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.nightlife, color: scheme.primary, size: 20),
                      const SizedBox(width: FluentSpacing.s),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Guilt-Free Recharge Advice',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: FluentType.caption.copyWith(
                                fontWeight: FontWeight.w600,
                                color: onSurface,
                              ),
                            ),
                            const SizedBox(height: FluentSpacing.xxs),
                            Text(
                              plan.familyAndWellbeingAdvice,
                              style: FluentType.caption.copyWith(
                                color: onSurfaceMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: FluentSpacing.m),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.psychology, size: 18),
                    label: Text(
                      'Discuss & Clarify with AI Mentor',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FluentType.bodyStrong,
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.primary,
                      side: BorderSide(
                        color: FluentStroke.card(brightness),
                        width: FluentStroke.width,
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: FluentSpacing.m,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: FluentRadius.controlBorder,
                      ),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AiChatScreen()),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTimeBadge({
    required IconData icon,
    required String label,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FluentSpacing.s,
        vertical: FluentSpacing.xs + 2,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: FluentRadius.controlBorder,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: FluentSpacing.xs),
          Expanded(
            child: Text(
              label,
              style: FluentType.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}
