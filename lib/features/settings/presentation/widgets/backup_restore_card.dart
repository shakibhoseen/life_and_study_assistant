import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_provider.dart';
import '../../../../core/services/export/app_export_service.dart';
import '../../../../core/services/export/auto_backup_service.dart';
import '../../../../core/services/export/preference_backup.dart';
import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/widgets/premium_glass_card.dart';
import '../../../../core/widgets/premium_ui_kit.dart';

class BackupRestoreCard extends ConsumerWidget {
  const BackupRestoreCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(
            bottom: FluentSpacing.s,
            top: FluentSpacing.xs,
          ),
          child: PremiumSectionHeader(
            icon: Icons.cloud_sync_rounded,
            label: 'Offline Data Backup & Restore',
          ),
        ),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: FluentRadius.cardBorder,
            side: FluentStroke.side(theme.brightness),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: FluentSpacing.s),
            child: Column(
              children: [
                // Where a silent failure becomes visible: the automatic backup
                // never interrupts anything, so this line is the only place
                // anybody would notice it had stopped happening.
                const _AutoBackupStatus(),
                ListTile(
                  leading: const PremiumIconBadge(
                    icon: Icons.download_rounded,
                    size: 40,
                    iconSize: 20,
                  ),
                  title: Text(
                    'Export Study Backup (JSON)',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: FluentType.bodyStrong.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    'Save all Weak Topics, LiveMCQ routines & daily logs',
                    style: FluentType.caption.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: () => _handleExportBackup(context, ref),
                ),
                Divider(
                  height: 1,
                  indent: 64,
                  color: FluentStroke.divider(theme.brightness),
                ),
                ListTile(
                  leading: const PremiumIconBadge(
                    icon: Icons.upload_rounded,
                    size: 40,
                    iconSize: 20,
                  ),
                  title: Text(
                    'Restore Study Data from Backup',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: FluentType.bodyStrong.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    'Paste JSON or select a backup file to merge',
                    style: FluentType.caption.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: () => _handleRestoreBackup(context, ref),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _handleExportBackup(BuildContext context, WidgetRef ref) async {
    try {
      final db = ref.read(appDatabaseProvider);
      // Half of what makes the app yours lives outside the database.
      final jsonString = await db.exportBackupJson(
        extraPreferences: await PreferenceBackup.collect(),
      );
      final Map<String, dynamic> parsed =
          jsonDecode(jsonString) as Map<String, dynamic>;

      final topicsCount = (parsed['weak_topics'] as List?)?.length ?? 0;
      final examsCount = (parsed['exam_schedules'] as List?)?.length ?? 0;
      final logsCount = (parsed['daily_energy_logs'] as List?)?.length ?? 0;

      if (!context.mounted) return;
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final brightness = theme.brightness;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(FluentRadius.large),
            ),
            border: Border(top: FluentStroke.side(brightness)),
          ),
          padding: const EdgeInsets.all(FluentSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: FluentSpacing.l),
                  decoration: BoxDecoration(
                    color: scheme.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  const PremiumIconBadge(
                    icon: Icons.cloud_done_rounded,
                    size: 40,
                    iconSize: 20,
                  ),
                  const SizedBox(width: FluentSpacing.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Export Study Data Backup',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: FluentType.bodyStrong.copyWith(
                            fontSize: 15,
                            color: scheme.onSurface,
                          ),
                        ),
                        Text(
                          'Zero-loss offline JSON format',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: FluentType.caption.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.65),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: FluentSpacing.l),
              Container(
                padding: const EdgeInsets.all(FluentSpacing.m),
                decoration: BoxDecoration(
                  color: scheme.onSurface.withValues(alpha: 0.04),
                  borderRadius: FluentRadius.cardBorder,
                  border: Border.all(
                    color: FluentStroke.card(brightness),
                    width: FluentStroke.width,
                  ),
                ),
                child: Column(
                  children: [
                    _buildBackupStatRow(
                      'Weak Topics & Syllabus',
                      '$topicsCount items',
                      Icons.playlist_add_check,
                      ctx,
                    ),
                    Divider(
                      height: FluentSpacing.m,
                      color: FluentStroke.divider(brightness),
                    ),
                    _buildBackupStatRow(
                      'LiveMCQ Exam Schedules',
                      '$examsCount exams',
                      Icons.calendar_today_outlined,
                      ctx,
                    ),
                    Divider(
                      height: FluentSpacing.m,
                      color: FluentStroke.divider(brightness),
                    ),
                    _buildBackupStatRow(
                      'Energy & Fatigue Logs',
                      '$logsCount logs',
                      Icons.bolt_outlined,
                      ctx,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: FluentSpacing.l),
              // Option 1: Save directly to Download folder (Recommended)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    padding: const EdgeInsets.symmetric(
                      vertical: FluentSpacing.m,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: FluentRadius.controlBorder,
                    ),
                  ),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text(
                    'Download ফোল্ডারে সেভ করুন',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FluentType.bodyStrong,
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final nowStr = DateTime.now().toIso8601String().substring(
                      0,
                      10,
                    );
                    final fileName = 'life_study_backup_$nowStr.json';
                    final result = await AppExportService.saveToDownloads(
                      fileName: fileName,
                      content: jsonString,
                    );
                    if (!context.mounted) return;
                    if (result.success) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: Colors.teal.shade800,
                          duration: const Duration(seconds: 6),
                          content: Text(result.bengaliSummary),
                          action: SnackBarAction(
                            textColor: Colors.tealAccent,
                            label: 'পথ কপি',
                            onPressed: () {
                              if (result.filePath != null) {
                                Clipboard.setData(
                                  ClipboardData(text: result.filePath!),
                                );
                              }
                            },
                          ),
                        ),
                      );
                    } else if (!result.wasCancelled) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: Colors.red.shade800,
                          content: Text(result.bengaliSummary),
                        ),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(height: FluentSpacing.s),
              // Option 2 & 3: Save As (Custom Folder) & Copy JSON
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          vertical: FluentSpacing.m,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: FluentRadius.controlBorder,
                        ),
                      ),
                      icon: const Icon(
                        Icons.create_new_folder_outlined,
                        size: 16,
                      ),
                      label: Text(
                        'অন্য ফোল্ডার',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FluentType.caption,
                      ),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        final nowStr = DateTime.now()
                            .toIso8601String()
                            .substring(0, 10);
                        final fileName = 'life_study_backup_$nowStr.json';
                        final result = await AppExportService.saveWithPicker(
                          fileName: fileName,
                          content: jsonString,
                          dialogTitle: 'ব্যাকআপ ফাইল সেভ করার ফোল্ডার বেছে নিন',
                        );
                        if (!context.mounted) return;
                        if (result.success) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: Colors.indigo.shade800,
                              duration: const Duration(seconds: 6),
                              content: Text(result.bengaliSummary),
                              action: SnackBarAction(
                                textColor: Colors.indigoAccent,
                                label: 'পথ কপি',
                                onPressed: () {
                                  if (result.filePath != null) {
                                    Clipboard.setData(
                                      ClipboardData(text: result.filePath!),
                                    );
                                  }
                                },
                              ),
                            ),
                          );
                        } else if (!result.wasCancelled) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: Colors.red.shade800,
                              content: Text(result.bengaliSummary),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: FluentSpacing.s),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          vertical: FluentSpacing.m,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: FluentRadius.controlBorder,
                        ),
                      ),
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: Text(
                        'Copy JSON',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FluentType.caption,
                      ),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: jsonString));
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Backup JSON copied to clipboard! You can paste and save it anywhere.',
                            ),
                            backgroundColor: Colors.teal,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: FluentSpacing.s),
            ],
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildBackupStatRow(
    String label,
    String value,
    IconData icon,
    BuildContext context,
  ) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(icon, size: 16, color: scheme.onSurface.withValues(alpha: 0.65)),
        const SizedBox(width: FluentSpacing.s),
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: FluentType.caption.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
        ),
        const SizedBox(width: FluentSpacing.s),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: FluentType.caption.copyWith(
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
      ],
    );
  }

  Future<void> _handleRestoreBackup(BuildContext context, WidgetRef ref) async {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(FluentRadius.large),
          ),
          border: Border(top: FluentStroke.side(brightness)),
        ),
        padding: const EdgeInsets.all(FluentSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: FluentSpacing.l),
                decoration: BoxDecoration(
                  color: scheme.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                const PremiumIconBadge(
                  icon: Icons.settings_backup_restore_rounded,
                  size: 40,
                  iconSize: 20,
                ),
                const SizedBox(width: FluentSpacing.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Restore from Backup',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: FluentType.bodyStrong.copyWith(
                          fontSize: 15,
                          color: scheme.onSurface,
                        ),
                      ),
                      Text(
                        'Import without losing existing data',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: FluentType.caption.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: FluentSpacing.l),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: FluentRadius.cardBorder,
                side: FluentStroke.side(brightness),
              ),
              leading: const PremiumIconBadge(
                icon: Icons.paste_rounded,
                size: 40,
                iconSize: 20,
              ),
              title: Text(
                'Paste JSON from Clipboard',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: FluentType.bodyStrong.copyWith(color: scheme.onSurface),
              ),
              subtitle: Text(
                'Directly read from clipboard',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: FluentType.caption.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 14),
              onTap: () async {
                Navigator.pop(ctx);
                final clipData = await Clipboard.getData(Clipboard.kTextPlain);
                final text = clipData?.text?.trim() ?? '';
                if (text.isEmpty) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Clipboard is empty. Please copy the backup JSON first.',
                        ),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  }
                  return;
                }
                if (context.mounted) {
                  _executeRestore(context, ref, text);
                }
              },
            ),
            const SizedBox(height: FluentSpacing.s),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: FluentRadius.cardBorder,
                side: FluentStroke.side(brightness),
              ),
              leading: const PremiumIconBadge(
                icon: Icons.file_open_rounded,
                size: 40,
                iconSize: 20,
              ),
              title: Text(
                'Pick JSON Backup File',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: FluentType.bodyStrong.copyWith(color: scheme.onSurface),
              ),
              subtitle: Text(
                'Select a .json file from phone storage',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: FluentType.caption.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 14),
              onTap: () async {
                Navigator.pop(ctx);
                final picked = await FilePicker.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['json'],
                );
                if (picked.isNotEmpty && picked.first.path != null) {
                  final file = File(picked.first.path!);
                  final content = await file.readAsString();
                  if (context.mounted) {
                    _executeRestore(context, ref, content);
                  }
                }
              },
            ),
            const SizedBox(height: FluentSpacing.m),
          ],
        ),
      ),
    );
  }

  Future<void> _executeRestore(
    BuildContext context,
    WidgetRef ref,
    String jsonString,
  ) async {
    try {
      final db = ref.read(appDatabaseProvider);
      final result = await db.importBackupJson(jsonString);

      // The settings outside the database go back too, except the API key,
      // which is never written to a backup file in the first place.
      var restoredPrefs = 0;
      try {
        final decoded = jsonDecode(jsonString.trim());
        if (decoded is Map) {
          restoredPrefs = await PreferenceBackup.restore(
            decoded['preferences'],
          );
        }
      } catch (_) {
        // A file that will not decode has already failed above; the counts
        // below simply show nothing for it.
      }

      final topicsCount = result['weak_topics'] ?? 0;
      final examsCount = result['exam_schedules'] ?? 0;
      final logsCount = result['daily_energy_logs'] ?? 0;
      final mistakesCount = result['mistakes'] ?? 0;

      if (!context.mounted) return;
      final scheme = Theme.of(context).colorScheme;

      showDialog(
        context: context,
        builder: (dCtx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: FluentRadius.cardBorder),
          title: const Row(
            children: [
              // Green here is status: the restore succeeded.
              Icon(Icons.check_circle, color: Color(0xFF10B981), size: 24),
              SizedBox(width: FluentSpacing.s),
              Flexible(
                child: Text(
                  'Restore Complete!',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'আপনার ব্যাকআপ সফলভাবে রিস্টোর হয়েছে:',
                style: FluentType.body.copyWith(color: scheme.onSurface),
              ),
              const SizedBox(height: FluentSpacing.m),
              Text('• $topicsCount টি Weak Topics যুক্ত বা আপডেট হয়েছে'),
              Text('• $examsCount টি LiveMCQ পরীক্ষার শিডিউল রিস্টোর হয়েছে'),
              Text('• $logsCount টি Daily Energy Logs সিঙ্ক হয়েছে'),
              if (mistakesCount > 0)
                Text(
                  '• $mistakesCount টি Mistake Notebook প্রশ্ন রিস্টোর হয়েছে',
                ),
              if ((result['drill_records'] ?? 0) > 0)
                Text('• ${result['drill_records']} টি ড্রিলের রেকর্ড ফিরেছে'),
              if ((result['spaced_reviews'] ?? 0) > 0)
                Text('• ${result['spaced_reviews']} টি রিভিশন কার্ড ফিরেছে'),
              if (restoredPrefs > 0) Text('• $restoredPrefs টি সেটিংস ফিরেছে'),
              const SizedBox(height: FluentSpacing.s),
              // Said every time: it is the one thing a restore cannot do for
              // you, and finding out later costs a failed scan.
              Text(
                'API key ব্যাকআপ ফাইলে রাখা হয় না — সেটি আবার বসাতে হবে।',
                style: FluentType.caption.copyWith(
                  fontStyle: FontStyle.italic,
                  color: scheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: FluentRadius.controlBorder,
                ),
              ),
              onPressed: () => Navigator.pop(dCtx),
              child: const Text('ঠিক আছে'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (dCtx) => AlertDialog(
            title: const Text('Restore Failed'),
            content: Text('Invalid backup JSON format:\n$e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dCtx),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    }
  }
}

/// When the app last wrote a backup on its own, and where those go.
class _AutoBackupStatus extends StatelessWidget {
  const _AutoBackupStatus();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return FutureBuilder<DateTime?>(
      future: AutoBackupService.lastRunAt(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        final at = snap.data;
        final text = at == null
            ? 'স্বয়ংক্রিয় ব্যাকআপ এখনো হয়নি — অ্যাপ খুললেই প্রথমটি হবে'
            : 'সর্বশেষ স্বয়ংক্রিয় ব্যাকআপ: '
                  '${at.day}/${at.month}/${at.year} '
                  '${at.hour.toString().padLeft(2, '0')}:'
                  '${at.minute.toString().padLeft(2, '0')}';

        return Padding(
          padding: const EdgeInsets.fromLTRB(
            FluentSpacing.l,
            FluentSpacing.s,
            FluentSpacing.l,
            FluentSpacing.xs,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                at == null ? Icons.schedule : Icons.verified_outlined,
                size: 16,
                // Amber warns no backup has run yet; green confirms one has.
                color: at == null
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFF10B981),
              ),
              const SizedBox(width: FluentSpacing.s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text,
                      style: FluentType.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    Text(
                      'Download/${AppExportService.defaultSubfolder} ফোল্ডারে, '
                      'দিনে একবার, শেষ ${AutoBackupService.keepCount}টি রাখা হয়',
                      style: FluentType.caption.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
