import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/utils/bengali_math_sanitizer.dart';
import '../../data/services/backup_status_store.dart';
import '../../data/services/exam_vault_service.dart';
import '../providers/exam_vault_provider.dart';

/// Backup & restore, laid out the way WhatsApp lays out Chat Backup:
/// one headline that says when the last backup happened, one big button that
/// makes a new one, the account it goes to, and everything else demoted.
class VaultBackupScreen extends ConsumerWidget {
  const VaultBackupScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
        builder: (_) => const VaultBackupScreen(),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(examVaultProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ব্যাকআপ ও রিস্টোর'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          FluentSpacing.l,
          FluentSpacing.l,
          FluentSpacing.l,
          FluentSpacing.xxl * 2,
        ),
        children: [
          _LastBackupHero(status: state.backupStatus),
          const SizedBox(height: FluentSpacing.xl),
          _BackupNowButton(
            isBusy: state.isSyncingDrive,
            isSignedIn: state.isGoogleSignedIn,
            onBackup: () => _backupNow(context, ref),
            onSignIn: () => _signIn(context, ref),
          ),
          const SizedBox(height: FluentSpacing.xxl),
          _SectionLabel('গুগল অ্যাকাউন্ট'),
          _AccountTile(
            state: state,
            onSignIn: () => _signIn(context, ref),
            onSignOut: () => _signOut(context, ref),
          ),
          const SizedBox(height: FluentSpacing.xxl),
          _SectionLabel('রিস্টোর'),
          _ActionTile(
            icon: Icons.cloud_download_rounded,
            tint: const Color(0xFF10B981),
            title: 'গুগল ড্রাইভ থেকে ফিরিয়ে আনুন',
            subtitle: 'সর্বশেষ ব্যাকআপ — সাধারণত এটাই লাগবে',
            enabled: state.isGoogleSignedIn && !state.isSyncingDrive,
            onTap: () => _restore(context, ref, usePrevious: false),
          ),
          _ActionTile(
            icon: Icons.history_rounded,
            tint: Colors.orange,
            title: 'পূর্ববর্তী সেফটি কপি',
            subtitle: 'সর্বশেষটিতে কিছু মিসিং থাকলে এটা দেখুন',
            enabled: state.isGoogleSignedIn && !state.isSyncingDrive,
            onTap: () => _restore(context, ref, usePrevious: true),
          ),
          const SizedBox(height: FluentSpacing.xxl),
          _SectionLabel('ফাইল দিয়ে (ইন্টারনেট ছাড়া)'),
          _ActionTile(
            icon: Icons.archive_outlined,
            tint: Colors.blueGrey,
            title: 'ZIP ফাইল হিসেবে এক্সপোর্ট',
            subtitle: 'ডাটা ও সকল PDF এক ফাইলে — শেয়ার করে রাখতে পারেন',
            enabled: !state.isSyncingDrive,
            onTap: () => _exportZip(context, ref),
          ),
          _ActionTile(
            icon: Icons.folder_open_outlined,
            tint: Colors.blueGrey,
            title: 'ফাইল থেকে রিস্টোর',
            subtitle: 'ফোনে রাখা .zip বা .json ব্যাকআপ ফাইল বেছে নিন',
            enabled: !state.isSyncingDrive,
            onTap: () => _importFile(context, ref),
          ),
          const SizedBox(height: FluentSpacing.xxl),
          _DriveLocationNote(theme: theme),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- actions

  Future<void> _signIn(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final user = await ref.read(examVaultProvider.notifier).signInGoogle();
      if (user == null) return;
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF10B981),
          content: Text('${user.email} দিয়ে সাইন ইন হয়েছে।'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 6),
          content: Text('সাইন ইন করা যায়নি: $e'),
        ),
      );
    }
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(examVaultProvider.notifier).signOutGoogle();
    messenger.showSnackBar(
      const SnackBar(content: Text('সাইন আউট হয়েছে। ডিভাইসের ডাটা মুছে যায়নি।')),
    );
  }

  Future<void> _backupNow(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result =
          await ref.read(examVaultProvider.notifier).syncToGoogleDrive();
      if (!result.success) {
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: Colors.orange.shade800,
            content: const Text('ব্যাকআপ সম্পূর্ণ হয়নি। আবার চেষ্টা করুন।'),
          ),
        );
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF10B981),
          content: Text(
            result.pdfCount > 0
                ? 'ব্যাকআপ সম্পন্ন — ${_bn(result.pdfCount)}টি PDF সহ।'
                : 'ব্যাকআপ সম্পন্ন।',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 6),
          content: Text('ব্যাকআপ ব্যর্থ: $e'),
        ),
      );
    }
  }

  Future<void> _restore(
    BuildContext context,
    WidgetRef ref, {
    required bool usePrevious,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(usePrevious ? 'পূর্ববর্তী কপি ফেরাবেন?' : 'রিস্টোর করবেন?'),
        content: const Text(
          'ড্রাইভের ব্যাকআপ ফোনের বর্তমান তালিকার সাথে মিলিয়ে দেওয়া হবে। '
          'ফোনে থাকা কোনো আবেদন মুছে যাবে না।',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('বাতিল'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('রিস্টোর'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final count = await ref
          .read(examVaultProvider.notifier)
          .restoreFromGoogleDrive(usePrevious: usePrevious);
      messenger.showSnackBar(
        SnackBar(
          backgroundColor:
              count > 0 ? const Color(0xFF10B981) : Colors.orange.shade800,
          content: Text(
            count > 0
                ? '${_bn(count)}টি আবেদন ফিরে এসেছে।'
                : 'ড্রাইভে এই ব্যাকআপটি পাওয়া যায়নি।',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 6),
          content: Text('রিস্টোর ব্যর্থ: $e'),
        ),
      );
    }
  }

  Future<void> _exportZip(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final zip =
          await ref.read(examVaultProvider.notifier).exportFullBackupZip();
      if (zip == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('ফাইল তৈরি করা যায়নি।')),
        );
        return;
      }
      await ExamVaultService.instance.shareBackupToDrive(zip);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('এক্সপোর্ট ব্যর্থ: $e')),
      );
    }
  }

  Future<void> _importFile(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'zip'],
      );
      if (picked.isEmpty || picked.first.path == null) return;

      final count = await ref
          .read(examVaultProvider.notifier)
          .importBackupFromFile(File(picked.first.path!));
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF10B981),
          content: Text('${_bn(count)}টি আবেদন রিস্টোর হয়েছে।'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          content: Text('রিস্টোর ব্যর্থ: $e'),
        ),
      );
    }
  }
}

// ------------------------------------------------------------------ widgets

class _LastBackupHero extends StatelessWidget {
  const _LastBackupHero({required this.status});

  final VaultBackupStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: FluentSpacing.xxl,
        horizontal: FluentSpacing.l,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF14241F) : const Color(0xFFECFDF5),
        borderRadius: FluentRadius.largeBorder,
        border: Border.all(
          color: const Color(0xFF10B981).withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        children: [
          Icon(
            status.hasBackup
                ? Icons.cloud_done_rounded
                : Icons.cloud_off_rounded,
            size: 48,
            color: status.hasBackup
                ? const Color(0xFF10B981)
                : theme.colorScheme.onSurface.withValues(alpha: 0.35),
          ),
          const SizedBox(height: FluentSpacing.m),
          Text(
            'সর্বশেষ ব্যাকআপ',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: FluentSpacing.xs),
          Text(
            status.hasBackup ? _formatWhen(status.at!) : 'এখনো হয়নি',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: FluentSpacing.s),
          Text(
            status.hasBackup
                ? '${_bn(status.applications)}টি আবেদন  ·  '
                    '${_bn(status.pdfs)}টি PDF  ·  ${_formatBytes(status.bytes)}'
                : 'ড্রাইভে এখনো কিছু পাঠানো হয়নি',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackupNowButton extends StatelessWidget {
  const _BackupNowButton({
    required this.isBusy,
    required this.isSignedIn,
    required this.onBackup,
    required this.onSignIn,
  });

  final bool isBusy;
  final bool isSignedIn;
  final VoidCallback onBackup;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    if (isBusy) {
      return const SizedBox(
        height: 52,
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: FluentSpacing.m),
              Text('ড্রাইভে কাজ চলছে…'),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 52,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF10B981),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: FluentRadius.largeBorder,
          ),
        ),
        icon: Icon(isSignedIn ? Icons.backup_rounded : Icons.login_rounded),
        label: Text(
          isSignedIn ? 'এখনই ব্যাকআপ করুন' : 'গুগল দিয়ে সাইন ইন করুন',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        onPressed: isSignedIn ? onBackup : onSignIn,
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.state,
    required this.onSignIn,
    required this.onSignOut,
  });

  final ExamVaultState state;
  final VoidCallback onSignIn;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = state.googleUser;
    final photo = user?.photoUrl;

    return Container(
      padding: const EdgeInsets.all(FluentSpacing.m),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? const Color(0xFF1E202E)
            : const Color(0xFFF8FAFC),
        borderRadius: FluentRadius.cardBorder,
        border: Border.all(color: FluentStroke.card(theme.brightness)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: Colors.blue.shade100,
            backgroundImage: photo != null ? NetworkImage(photo) : null,
            child: photo == null
                ? const Icon(Icons.person, color: Colors.blue, size: 22)
                : null,
          ),
          const SizedBox(width: FluentSpacing.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user?.displayName ?? 'সাইন ইন করা নেই',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  user?.email ?? 'ব্যাকআপ আপনার নিজের ড্রাইভেই থাকবে',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
          if (state.isGoogleSignedIn)
            TextButton(
              onPressed: onSignOut,
              child: const Text(
                'সাইন আউট',
                style: TextStyle(color: Colors.red, fontSize: 12),
              ),
            )
          else
            TextButton(
              onPressed: onSignIn,
              child: const Text('সাইন ইন', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        left: FluentSpacing.xs,
        bottom: FluentSpacing.s,
      ),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.tint,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fade = enabled ? 1.0 : 0.4;

    return Opacity(
      opacity: fade,
      child: Padding(
        padding: const EdgeInsets.only(bottom: FluentSpacing.s),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: FluentRadius.cardBorder,
            onTap: enabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: FluentSpacing.m,
                horizontal: FluentSpacing.s,
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: 0.12),
                      borderRadius: FluentRadius.cardBorder,
                    ),
                    child: Icon(icon, color: tint, size: 20),
                  ),
                  const SizedBox(width: FluentSpacing.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DriveLocationNote extends StatelessWidget {
  const _DriveLocationNote({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.55);
    return Container(
      padding: const EdgeInsets.all(FluentSpacing.m),
      decoration: BoxDecoration(
        borderRadius: FluentRadius.cardBorder,
        border: Border.all(color: FluentStroke.card(theme.brightness)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 15, color: muted),
              const SizedBox(width: FluentSpacing.s),
              Text(
                'ড্রাইভে কোথায় থাকে',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: FluentSpacing.s),
          Text(
            'আপনার ড্রাইভে ExamVault ফোল্ডারটি অ্যাপ নিজেই তৈরি করে নেয়। '
            'ডাটা থাকে ExamVault_Latest_Backup.json ফাইলে, তার আগের কপিটি '
            'ExamVault_Previous_Backup.json নামে রাখা হয়, আর সব PDF যায় '
            'ExamVault/Documents ফোল্ডারে। অ্যাপ শুধু নিজের তৈরি ফাইলগুলোই '
            'দেখতে পারে — আপনার ড্রাইভের বাকি কিছু নয়।',
            style: TextStyle(fontSize: 11.5, height: 1.5, color: muted),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ helpers

String _bn(int value) => BengaliMathSanitizer.toBengaliDigits('$value');

String _formatBytes(int bytes) {
  if (bytes < 1024) return '${_bn(bytes)} B';
  if (bytes < 1024 * 1024) return '${_bn((bytes / 1024).round())} KB';
  final mb = bytes / (1024 * 1024);
  return '${BengaliMathSanitizer.toBengaliDigits(mb.toStringAsFixed(1))} MB';
}

String _formatWhen(DateTime at) {
  final now = DateTime.now();
  final day = DateTime(at.year, at.month, at.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;

  final hour12 = at.hour % 12 == 0 ? 12 : at.hour % 12;
  final minute = at.minute.toString().padLeft(2, '0');
  final meridiem = at.hour < 12 ? 'AM' : 'PM';
  final clock = BengaliMathSanitizer.toBengaliDigits('$hour12:$minute');

  if (diff == 0) return 'আজ, $clock $meridiem';
  if (diff == 1) return 'গতকাল, $clock $meridiem';

  const months = [
    'জানু', 'ফেব', 'মার্চ', 'এপ্রিল', 'মে', 'জুন',
    'জুলাই', 'আগস্ট', 'সেপ্ট', 'অক্টো', 'নভে', 'ডিসে',
  ];
  final date = '${_bn(at.day)} ${months[at.month - 1]}';
  return '$date, $clock $meridiem';
}
