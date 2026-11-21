import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/fluent_tokens.dart';
import '../../data/services/exam_vault_service.dart';
import '../providers/exam_vault_provider.dart';
import '../widgets/exam_credential_card.dart';
import 'exam_application_edit_screen.dart';

class ExamVaultScreen extends ConsumerWidget {
  const ExamVaultScreen({super.key});

  Future<void> _handleDirectDriveSync(
      BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('গুগল ড্রাইভে সিঙ্ক হচ্ছে...'),
          duration: Duration(seconds: 2),
        ),
      );
      final result =
          await ref.read(examVaultProvider.notifier).syncToGoogleDrive();
      if (result.success) {
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            content: Text(
              result.pdfCount > 0
                  ? '🎉 গুগল ড্রাইভে ব্যাকআপ সম্পন্ন হয়েছে!\n(ExamVault_Documents ফোল্ডারে ${result.pdfCount}টি PDF ও মাস্টার ডাটা সংরক্ষিত)'
                  : '🎉 গুগল ড্রাইভে ব্যাকআপ সম্পন্ন হয়েছে!\n(ক্রেডেনশিয়াল মাস্টার ব্যাকআপ ও সেফটি কপি আপডেট হয়েছে)',
            ),
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.amber.shade900,
          duration: const Duration(seconds: 6),
          content: Text(
            'ড্রাইভে সরাসরি আপলোড হতে সমস্যা: $e\nআপনি অফলাইন ব্যাকআপ ফাইল তৈরি করে Drive অ্যাপে শেয়ার করতে পারেন।',
          ),
          action: SnackBarAction(
            label: 'শেয়ার করুন',
            textColor: Colors.white,
            onPressed: () => _handleBackup(context, ref),
          ),
        ),
      );
    }
  }

  Future<void> _showDriveRestoreDialog(
      BuildContext context, WidgetRef ref) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Google Drive থেকে রিস্টোর'),
        content: const Text(
          'কোন ব্যাকআপ ফাইলটি আপনি রিস্টোর করতে চান?\n\n'
          '• সর্বশেষ ব্যাকআপ (Latest): সর্বশেষ সিঙ্ক করা ডাটা\n'
          '• পূর্ববর্তী সেফটি কপি (Previous): সর্বশেষ কপিতে কিছু মিসিং থাকলে উদ্ধার করতে',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, 'cancel'),
            child: const Text('বাতিল'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(dialogCtx, 'previous'),
            child: const Text('পূর্ববর্তী (Previous)'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx, 'latest'),
            child: const Text('সর্বশেষ (Latest)'),
          ),
        ],
      ),
    );

    if (choice == null || choice == 'cancel') return;
    final usePrevious = (choice == 'previous');
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            usePrevious
                ? 'ড্রাইভ থেকে পূর্ববর্তী ব্যাকআপ আনা হচ্ছে...'
                : 'ড্রাইভ থেকে সর্বশেষ ব্যাকআপ আনা হচ্ছে...',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      final count = await ref
          .read(examVaultProvider.notifier)
          .restoreFromGoogleDrive(usePrevious: usePrevious);
      if (count > 0) {
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            content: Text(
              '🎉 গুগল ড্রাইভ থেকে $count টি আবেদন সফলভাবে রিস্টোর হয়েছে!',
            ),
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(
            backgroundColor: Colors.orange,
            content: Text('গুগল ড্রাইভে কোনো ব্যাকআপ ফাইল পাওয়া যায়নি।'),
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('ড্রাইভ থেকে রিস্টোর ব্যর্থ: $e'),
        ),
      );
    }
  }

  Future<void> _showCloudBackupSheet(
      BuildContext context, WidgetRef ref) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return Consumer(
          builder: (context, ref, _) {
            final state = ref.watch(examVaultProvider);
            return Padding(
              padding: EdgeInsets.only(
                left: FluentSpacing.l,
                right: FluentSpacing.l,
                top: FluentSpacing.l,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom +
                    FluentSpacing.l,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.cloud_sync_rounded,
                            color: Colors.blue),
                      ),
                      const SizedBox(width: FluentSpacing.m),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Google Drive ও ক্লাউড ব্যাকআপ',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'রোলিং ডুয়েল ব্যাকআপ (Latest ও Previous)',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(sheetContext),
                      ),
                    ],
                  ),
                  const Divider(height: 24),

                  // Account Tile
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1E202E)
                          : const Color(0xFFF8FAFC),
                      borderRadius: FluentRadius.cardBorder,
                      border: Border.all(
                          color: FluentStroke.card(theme.brightness)),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.blue.shade100,
                          backgroundImage: state.googleUser?.photoUrl != null
                              ? NetworkImage(state.googleUser!.photoUrl!)
                              : null,
                          child: state.googleUser?.photoUrl == null
                              ? const Icon(Icons.person,
                                  color: Colors.blue, size: 20)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                state.isGoogleSignedIn
                                    ? (state.googleUser?.displayName ??
                                        'গুগল ব্যবহারকারী')
                                    : 'গুগলে সাইন ইন করা নেই',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              Text(
                                state.isGoogleSignedIn
                                    ? (state.googleUser?.email ?? '')
                                    : 'ড্রাইভে অটো-সিঙ্কের জন্য সাইন ইন করুন',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (state.isGoogleSignedIn)
                          TextButton(
                            onPressed: () async {
                              await ref
                                  .read(examVaultProvider.notifier)
                                  .signOutGoogle();
                            },
                            child: const Text('লগআউট',
                                style: TextStyle(
                                    color: Colors.red, fontSize: 12)),
                          )
                        else
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                            ),
                            icon: const Icon(Icons.login, size: 16),
                            label: const Text('সাইন ইন',
                                style: TextStyle(fontSize: 12)),
                            onPressed: () async {
                              try {
                                await ref
                                    .read(examVaultProvider.notifier)
                                    .signInGoogle();
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text('সাইন ইন ত্রুটি: $e')),
                                  );
                                }
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: FluentSpacing.m),

                  // Action Buttons
                  if (state.isSyncingDrive)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Column(
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 8),
                            Text('গুগল ড্রাইভে কাজ চলছে...'),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    // Sync to Google Drive
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.cloud_upload),
                      label: const Text(
                        '☁️ ড্রাইভে ব্যাকআপ সিঙ্ক (JSON + সকল PDF)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: () async {
                        Navigator.pop(sheetContext);
                        _handleDirectDriveSync(context, ref);
                      },
                    ),
                    const SizedBox(height: 10),

                    // Restore from Google Drive
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.cloud_download_outlined),
                      label: const Text('📥 ড্রাইভ ব্যাকআপ থেকে রিস্টোর'),
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _showDriveRestoreDialog(context, ref);
                      },
                    ),
                    const SizedBox(height: 10),

                    // Native Share / Export
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('📤 লোকাল ফাইল ব্যাকআপ ও শেয়ার'),
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _handleBackup(context, ref);
                      },
                    ),
                    const SizedBox(height: 10),

                    // Local File Restore
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.folder_open_outlined),
                      label: const Text('📂 লোকাল .json ফাইল থেকে রিস্টোর'),
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _handleRestore(context, ref);
                      },
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _handleBackup(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await ref.read(examVaultProvider.notifier).exportBackup();
      if (file != null) {
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 4),
            content: const Text(
              '☁️ মাস্টার ব্যাকআপ তৈরি হয়েছে!\n(ExamVault_Latest_Backup.json ও পূর্ববর্তী সেফটি কপি)',
            ),
            action: SnackBarAction(
              label: 'Drive-এ পাঠান',
              textColor: Colors.white,
              onPressed: () {
                ExamVaultService.instance.shareBackupToDrive(file);
              },
            ),
          ),
        );
        // Automatically open the Drive / System Share sheet
        await ExamVaultService.instance.shareBackupToDrive(file);
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('ব্যাকআপ ব্যর্থ: $e'),
        ),
      );
    }
  }

  Future<void> _handleRestore(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (picked.isNotEmpty && picked.first.path != null) {
        final file = File(picked.first.path!);
        final content = await file.readAsString();
        final count =
            await ref.read(examVaultProvider.notifier).importBackup(content);
        final fileName = file.path.split(Platform.pathSeparator).last;
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            content: Text(
              'সফলভাবে $count টি আবেদন রিস্টোর করা হয়েছে! ($fileName)',
            ),
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('রিস্টোর ব্যর্থ: $e'),
        ),
      );
    }
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
            tooltip: 'Google Drive ও ব্যাকআপ',
            onPressed: () => _showCloudBackupSheet(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.folder_open_outlined),
            tooltip: 'লোকাল ফাইল রিস্টোর',
            onPressed: () => _handleRestore(context, ref),
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
                    onPressed: () => _showCloudBackupSheet(context, ref),
                    icon: Icon(
                      state.isGoogleSignedIn
                          ? Icons.sync_rounded
                          : Icons.login_rounded,
                      size: 16,
                    ),
                    label: Text(
                      state.isGoogleSignedIn ? 'সিঙ্ক মেনু' : 'কানেক্ট',
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
