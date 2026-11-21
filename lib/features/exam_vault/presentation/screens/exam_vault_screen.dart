import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/fluent_tokens.dart';
import '../providers/exam_vault_provider.dart';
import '../widgets/exam_credential_card.dart';
import 'exam_application_edit_screen.dart';
import 'vault_backup_screen.dart';

class ExamVaultScreen extends ConsumerWidget {
  const ExamVaultScreen({super.key});

  void _openBackupScreen(BuildContext context) {
    Navigator.push(context, VaultBackupScreen.route());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(examVaultProvider);
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final isDark = brightness == Brightness.dark;

    final apps = state.filteredApplications;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Exam & Job Vault'),
        actions: [
          IconButton(
            icon: Icon(
              state.isGoogleSignedIn
                  ? Icons.cloud_done_rounded
                  : Icons.cloud_sync_outlined,
              color: state.isGoogleSignedIn ? const Color(0xFF10B981) : null,
            ),
            tooltip: 'ব্যাকআপ ও রিস্টোর',
            onPressed: () => _openBackupScreen(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        icon: const Icon(Icons.add),
        label: const Text('নতুন আবেদন'),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => const ExamApplicationEditScreen(),
            ),
          );
        },
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(examVaultProvider.notifier).loadApplications(),
        child: ListView(
          padding: const EdgeInsets.all(FluentSpacing.l),
          children: [
            // Google Drive Sync Banner
            Container(
              margin: const EdgeInsets.only(bottom: FluentSpacing.m),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: state.isGoogleSignedIn
                    ? (isDark
                        ? const Color(0xFF132F21)
                        : const Color(0xFFECFDF5))
                    : (isDark
                        ? const Color(0xFF1E202E)
                        : const Color(0xFFF8FAFC)),
                borderRadius: FluentRadius.cardBorder,
                border: Border.all(
                  color: state.isGoogleSignedIn
                      ? const Color(0xFF10B981).withValues(alpha: 0.4)
                      : FluentStroke.card(brightness),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    state.isGoogleSignedIn
                        ? Icons.cloud_done_rounded
                        : Icons.cloud_queue_rounded,
                    size: 20,
                    color: state.isGoogleSignedIn
                        ? const Color(0xFF10B981)
                        : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.isGoogleSignedIn
                          ? 'ড্রাইভ সিঙ্ক: ${state.googleUser?.email}'
                          : 'গুগল ড্রাইভ সিঙ্ক সক্রিয় করুন',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: state.isGoogleSignedIn
                            ? (isDark
                                ? const Color(0xFF34D399)
                                : const Color(0xFF047857))
                            : theme.colorScheme.onSurface
                                .withValues(alpha: 0.7),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: () => _openBackupScreen(context),
                    icon: Icon(
                      state.isGoogleSignedIn
                          ? Icons.backup_rounded
                          : Icons.login_rounded,
                      size: 16,
                    ),
                    label: Text(
                      state.isGoogleSignedIn ? 'ব্যাকআপ' : 'কানেক্ট',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),

            // Top Overview Stats Row
            Row(
              children: [
                Expanded(
                  child: _buildStatTile(
                    title: 'মোট আবেদন',
                    count: '${state.applications.length}',
                    icon: Icons.assignment_rounded,
                    color: Colors.blue,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: FluentSpacing.m),
                Expanded(
                  child: _buildStatTile(
                    title: 'সামনে পরীক্ষা',
                    count: '${state.upcomingExamsCount}',
                    icon: Icons.event_available_rounded,
                    color: const Color(0xFFF59E0B),
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: FluentSpacing.m),
                Expanded(
                  child: _buildStatTile(
                    title: 'অ্যাডমিট রেডি',
                    count: '${state.admitCardAvailableCount}',
                    icon: Icons.badge_rounded,
                    color: const Color(0xFF10B981),
                    isDark: isDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: FluentSpacing.l),

            // Search Bar
            TextField(
              decoration: InputDecoration(
                hintText: 'পরীক্ষা, প্রতিষ্ঠান, User ID বা রোল দিয়ে খুঁজুন...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                filled: true,
                fillColor: isDark ? const Color(0xFF1E202E) : Colors.white,
                border: OutlineInputBorder(
                  borderRadius: FluentRadius.cardBorder,
                  borderSide: BorderSide(
                    color: FluentStroke.card(brightness),
                    width: FluentStroke.width,
                  ),
                ),
              ),
              onChanged: (val) =>
                  ref.read(examVaultProvider.notifier).setSearchQuery(val),
            ),
            const SizedBox(height: FluentSpacing.m),

            // Filter Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip(
                    label: 'সবগুলো (${state.applications.length})',
                    filter: 'all',
                    selected: state.selectedFilter == 'all',
                    onSelected: () => ref
                        .read(examVaultProvider.notifier)
                        .setSelectedFilter('all'),
                  ),
                  const SizedBox(width: FluentSpacing.s),
                  _buildFilterChip(
                    label: '🎟️ অ্যাডমিট এসেছে (${state.admitCardAvailableCount})',
                    filter: 'admit_issued',
                    selected: state.selectedFilter == 'admit_issued',
                    onSelected: () => ref
                        .read(examVaultProvider.notifier)
                        .setSelectedFilter('admit_issued'),
                  ),
                  const SizedBox(width: FluentSpacing.s),
                  _buildFilterChip(
                    label: '⏳ তারিখ নির্ধারিত (${state.upcomingExamsCount})',
                    filter: 'upcoming',
                    selected: state.selectedFilter == 'upcoming',
                    onSelected: () => ref
                        .read(examVaultProvider.notifier)
                        .setSelectedFilter('upcoming'),
                  ),
                  const SizedBox(width: FluentSpacing.s),
                  _buildFilterChip(
                    label: '✓ সম্পন্ন',
                    filter: 'completed',
                    selected: state.selectedFilter == 'completed',
                    onSelected: () => ref
                        .read(examVaultProvider.notifier)
                        .setSelectedFilter('completed'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: FluentSpacing.l),

            // Content List or Empty State
            if (state.isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(FluentSpacing.xxl),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (apps.isEmpty)
              _buildEmptyState(context, state.applications.isEmpty)
            else
              ...apps.map((app) {
                return ExamCredentialCard(
                  key: ValueKey(app.id),
                  application: app,
                  onEdit: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (ctx) => ExamApplicationEditScreen(
                          existingApplication: app,
                        ),
                      ),
                    );
                  },
                  onDelete: () {
                    ref.read(examVaultProvider.notifier).deleteApplication(app.id);
                  },
                  onStatusChanged: (newStatus) {
                    ref
                        .read(examVaultProvider.notifier)
                        .updateStatus(app.id, newStatus);
                  },
                );
              }),
            const SizedBox(height: 80), // Fab spacing
          ],
        ),
      ),
    );
  }

  Widget _buildStatTile({
    required String title,
    required String count,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FluentSpacing.m,
        vertical: FluentSpacing.m,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: FluentRadius.cardBorder,
        border: Border.all(
          color: color.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: FluentSpacing.xs),
          Text(
            count,
            style: FluentType.bodyStrong.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: FluentType.caption.copyWith(
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required String filter,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isTotalEmpty) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: FluentSpacing.xxl),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.folder_shared_rounded,
                size: 54,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: FluentSpacing.l),
            Text(
              isTotalEmpty
                  ? 'কোনো পরীক্ষা বা আবেদন যোগ করা নেই'
                  : 'সার্চে কোনো আবেদন পাওয়া যায়নি',
              style: FluentType.bodyStrong.copyWith(fontSize: 16),
            ),
            const SizedBox(height: FluentSpacing.s),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: FluentSpacing.l),
              child: Text(
                isTotalEmpty
                    ? 'আপনার চাকরির পরীক্ষা ও আবেদনের User ID, Password, SMS ও Admit Card PDF এখানে সুরক্ষিত রাখুন।'
                    : 'অন্য কোনো নাম, রোল নম্বর বা ইউজার আইডি দিয়ে খুঁজে দেখুন।',
                textAlign: TextAlign.center,
                style: FluentType.caption,
              ),
            ),
            if (isTotalEmpty) ...[
              const SizedBox(height: FluentSpacing.l),
              ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('প্রথম আবেদন যুক্ত করুন'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (ctx) => const ExamApplicationEditScreen(),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
