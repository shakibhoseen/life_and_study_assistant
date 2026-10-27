import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../chat/presentation/screens/ai_chat_screen.dart';
import '../../../quiz/presentation/widgets/quiz_drill_modal.dart';
import '../../../study_planner/presentation/providers/adaptive_planner_provider.dart';
import '../../../study_planner/presentation/widgets/focus_timer_dialog.dart';

class StudyPlanCard extends ConsumerWidget {
  const StudyPlanCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plannerAsync = ref.watch(adaptivePlannerProvider);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: plannerAsync.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text(
                    'Gemini AI tailoring adaptive study plan...',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          error: (err, stack) => Column(
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.redAccent,
                size: 36,
              ),
              const SizedBox(height: 8),
              Text(
                'Could not load plan: $err',
                style: const TextStyle(fontSize: 12),
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
            final isDark = Theme.of(context).brightness == Brightness.dark;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.purple.withValues(alpha: 0.2)
                            : Colors.purple.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.auto_awesome,
                        color: isDark ? Colors.purpleAccent : Colors.deepPurple,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Tonight’s Adaptive AI Routine',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
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
                const SizedBox(height: 8),
                // Motivational Quote in Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1E1B4B)
                        : Colors.deepPurple.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF3730A3)
                          : Colors.deepPurple.shade100,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('💡', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          plan.motivationalQuote,
                          style: TextStyle(
                            fontStyle: FontStyle.italic,
                            color: isDark
                                ? const Color(0xFFE9D5FF)
                                : Colors.deepPurple.shade900,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Time allocation badges
                Row(
                  children: [
                    Expanded(
                      child: _buildTimeBadge(
                        icon: Icons.menu_book,
                        label: '${plan.recommendedStudyMinutes}m Study',
                        color: isLowEnergy
                            ? Colors.amber.shade800
                            : (isDark ? Colors.indigoAccent : Colors.indigo),
                        bgColor: isDark
                            ? (isLowEnergy
                                  ? Colors.amber.withValues(alpha: 0.15)
                                  : Colors.indigo.withValues(alpha: 0.15))
                            : (isLowEnergy
                                  ? Colors.amber.shade50
                                  : Colors.indigo.shade50),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildTimeBadge(
                        icon: Icons.favorite,
                        label: '${plan.recommendedFamilyMinutes}m Rest',
                        color: isDark
                            ? Colors.tealAccent
                            : Colors.teal.shade800,
                        bgColor: isDark
                            ? Colors.teal.withValues(alpha: 0.15)
                            : Colors.teal.shade50,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  plan.summary,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                if (plan.burnoutWarning != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.red.withValues(alpha: 0.15)
                          : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDark
                            ? Colors.red.withValues(alpha: 0.3)
                            : Colors.red.shade200,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning, color: Colors.red, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            plan.burnoutWarning!,
                            style: TextStyle(
                              color: isDark
                                  ? Colors.red.shade200
                                  : Colors.red.shade900,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  'Micro-Commitment Tasks:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                // Tasks checklist
                ...plan.tasks.map((task) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1E293B)
                          : (task.isCompleted
                                ? Colors.grey.shade50
                                : Colors.white),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark
                            ? Colors.white12
                            : (task.isCompleted
                                  ? Colors.grey.shade300
                                  : Colors.indigo.shade100),
                      ),
                    ),
                    child: CheckboxListTile(
                      dense: true,
                      value: task.isCompleted,
                      activeColor: Colors.teal,
                      title: Text(
                        task.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          decoration: task.isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                          color: task.isCompleted
                              ? Colors.grey
                              : (isDark ? Colors.white : Colors.black87),
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.actionablePrompt,
                            style: TextStyle(
                              fontSize: 12,
                              color: task.isCompleted
                                  ? Colors.grey
                                  : (isDark ? Colors.white70 : Colors.black54),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white12
                                      : Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  task.subject,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                              Text(
                                '⏱ ${task.estimatedMinutes}m',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? Colors.white60
                                      : Colors.black54,
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
                                    horizontal: 7,
                                    vertical: 2.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF312E81)
                                        : Colors.indigo.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.timer,
                                        size: 12,
                                        color: isDark
                                            ? const Color(0xFFA5B4FC)
                                            : Colors.indigo.shade800,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        'Focus',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: isDark
                                              ? const Color(0xFFA5B4FC)
                                              : Colors.indigo.shade800,
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
                                        .read(adaptivePlannerProvider.notifier)
                                        .toggleTaskCompletion(task.id);
                                  },
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF2E1065)
                                        : Colors.purple.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.psychology,
                                        size: 12,
                                        color: isDark
                                            ? const Color(0xFFD8B4FE)
                                            : Colors.deepPurple.shade800,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        'Quiz',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: isDark
                                              ? const Color(0xFFD8B4FE)
                                              : Colors.deepPurple.shade800,
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
                  );
                }),
                const SizedBox(height: 12),
                // Family & Wellbeing advice box
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.nightlife,
                        color: Colors.green,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Guilt-Free Recharge Advice',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: Colors.green,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              plan.familyAndWellbeingAdvice,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green.shade900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.psychology, size: 18),
                    label: const Text('Discuss & Clarify with AI Mentor'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.deepPurple,
                      side: BorderSide(color: Colors.deepPurple.shade200),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
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
