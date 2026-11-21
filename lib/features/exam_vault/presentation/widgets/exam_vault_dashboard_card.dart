import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/widgets/premium_glass_card.dart';
import '../../../../core/widgets/premium_ui_kit.dart';
import '../providers/exam_vault_provider.dart';
import '../screens/exam_application_edit_screen.dart';
import '../screens/exam_vault_screen.dart';

class ExamVaultDashboardCard extends ConsumerWidget {
  const ExamVaultDashboardCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(examVaultProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final onSurface = theme.colorScheme.onSurface;
    final onSurfaceMuted = onSurface.withValues(alpha: 0.65);

    final apps = state.applications;
    final upcomingCount = state.upcomingExamsCount;
    final admitCount = state.admitCardAvailableCount;

    // Find next upcoming exam
    final nextExam = apps.where((a) => (a.daysUntilExam ?? -1) >= 0).toList()
      ..sort((a, b) => (a.daysUntilExam ?? 0).compareTo(b.daysUntilExam ?? 0));
    final next = nextExam.isNotEmpty ? nextExam.first : null;

    return PremiumGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.indigo.withValues(alpha: 0.12),
                      borderRadius: FluentRadius.controlBorder,
                    ),
                    child: const Icon(
                      Icons.shield_outlined,
                      color: Colors.indigo,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: FluentSpacing.m),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Exam & Application Vault',
                        style: FluentType.bodyStrong.copyWith(fontSize: 15),
                      ),
                      Text(
                        'রিয়েল পরীক্ষা, User ID ও Admit Card',
                        style: FluentType.caption.copyWith(color: onSurfaceMuted),
                      ),
                    ],
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                tooltip: 'ভল্ট ওপেন করুন',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (ctx) => const ExamVaultScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: FluentSpacing.m),

          if (apps.isEmpty) ...[
            Container(
              padding: const EdgeInsets.all(FluentSpacing.m),
              decoration: BoxDecoration(
                color: isDark ? Colors.black26 : const Color(0xFFF8FAFC),
                borderRadius: FluentRadius.controlBorder,
                border: Border.all(
                  color: FluentStroke.card(theme.brightness),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.lock_person_outlined,
                    color: Colors.indigo,
                    size: 24,
                  ),
                  const SizedBox(width: FluentSpacing.m),
                  Expanded(
                    child: Text(
                      'আবেদনের User ID, Password, SMS ও Admit Card PDF এক জায়গায় নিরাপদ রাখুন।',
                      style: FluentType.caption,
                    ),
                  ),
                  const SizedBox(width: FluentSpacing.s),
                  OutlinedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (ctx) =>
                              const ExamApplicationEditScreen(),
                        ),
                      );
                    },
                    child: const Text('Add First'),
                  ),
                ],
              ),
            ),
          ] else ...[
            // Status Pills Row
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: FluentSpacing.s,
                      horizontal: FluentSpacing.m,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: isDark ? 0.2 : 0.08),
                      borderRadius: FluentRadius.controlBorder,
                    ),
                    child: Text(
                      '📊 ${apps.length}টি আবেদন',
                      style: FluentType.caption.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.blue.shade200 : Colors.blue.shade900,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                const SizedBox(width: FluentSpacing.s),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: FluentSpacing.s,
                      horizontal: FluentSpacing.m,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B)
                          .withValues(alpha: isDark ? 0.2 : 0.08),
                      borderRadius: FluentRadius.controlBorder,
                    ),
                    child: Text(
                      '⏳ $upcomingCountটি সামনে',
                      style: FluentType.caption.copyWith(
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFFF59E0B),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                if (admitCount > 0) ...[
                  const SizedBox(width: FluentSpacing.s),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: FluentSpacing.s,
                        horizontal: FluentSpacing.m,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981)
                            .withValues(alpha: isDark ? 0.2 : 0.08),
                        borderRadius: FluentRadius.controlBorder,
                      ),
                      child: Text(
                        '🎟️ $admitCountটি অ্যাডমিট',
                        style: FluentType.caption.copyWith(
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF10B981),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ],
            ),

            if (next != null) ...[
              const SizedBox(height: FluentSpacing.m),
              Container(
                padding: const EdgeInsets.all(FluentSpacing.s + 2),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black26 : const Color(0xFFF1F5F9),
                  borderRadius: FluentRadius.controlBorder,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.event_available,
                      color: Colors.indigo,
                      size: 18,
                    ),
                    const SizedBox(width: FluentSpacing.s),
                    Expanded(
                      child: Text(
                        'পরবর্তী পরীক্ষা: ${next.postName} (${next.organization})',
                        style: FluentType.caption.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    PremiumTag(
                      label: 'আর ${next.daysUntilExam} দিন',
                      color: Colors.indigo,
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: FluentSpacing.m),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: FluentRadius.controlBorder,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: FluentSpacing.s),
                ),
                icon: const Icon(Icons.lock_open_rounded, size: 16),
                label: const Text('ভল্ট ওপেন করুন (Open Vault)'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (ctx) => const ExamVaultScreen(),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
