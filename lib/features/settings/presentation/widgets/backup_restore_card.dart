import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_provider.dart';
import '../../../../core/services/export/app_export_service.dart';
import '../../../../core/services/export/preference_backup.dart';

class BackupRestoreCard extends ConsumerWidget {
  const BackupRestoreCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          'Offline Data Backup & Restore',
          Icons.cloud_sync_rounded,
          Colors.teal.shade700,
        ),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.teal.withValues(alpha: 0.2)
                          : Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.download_rounded,
                      color: isDark ? Colors.tealAccent : Colors.teal.shade700,
                    ),
                  ),
                  title: const Text(
                    'Export Study Backup (JSON)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: const Text(
                    'Save all Weak Topics, LiveMCQ routines & daily logs',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: () => _handleExportBackup(context, ref),
                ),
                const Divider(height: 1, indent: 64),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.indigo.withValues(alpha: 0.2)
                          : const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.upload_rounded,
                      color: isDark
                          ? const Color(0xFFA5B4FC)
                          : const Color(0xFF4338CA),
                    ),
                  ),
                  title: const Text(
                    'Restore Study Data from Backup',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: const Text(
                    'Paste JSON or select a backup file to merge',
                    style: TextStyle(fontSize: 12),
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

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
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
      final isDark = Theme.of(context).brightness == Brightness.dark;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF111827) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.teal.withValues(alpha: 0.2)
                          : Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.cloud_done_rounded,
                      color: isDark ? Colors.tealAccent : Colors.teal.shade700,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Export Study Data Backup',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'Zero-loss offline JSON format',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E293B)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Column(
                  children: [
                    _buildBackupStatRow(
                      'Weak Topics & Syllabus',
                      '$topicsCount items',
                      Icons.playlist_add_check,
                      isDark,
                    ),
                    const Divider(height: 12),
                    _buildBackupStatRow(
                      'LiveMCQ Exam Schedules',
                      '$examsCount exams',
                      Icons.calendar_today_outlined,
                      isDark,
                    ),
                    const Divider(height: 12),
                    _buildBackupStatRow(
                      'Energy & Fatigue Logs',
                      '$logsCount logs',
                      Icons.bolt_outlined,
                      isDark,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Option 1: Save directly to Download folder (Recommended)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.download_rounded, size: 20),
                  label: const Text(
                    'Download ফোল্ডারে সেভ করুন',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
              const SizedBox(height: 10),
              // Option 2 & 3: Save As (Custom Folder) & Copy JSON
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(
                        Icons.create_new_folder_outlined,
                        size: 16,
                      ),
                      label: const Text(
                        'অন্য ফোল্ডার',
                        style: TextStyle(fontSize: 12.5),
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
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text(
                        'Copy JSON',
                        style: TextStyle(fontSize: 12.5),
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
              const SizedBox(height: 10),
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
    IconData icon, [
    bool isDark = false,
  ]) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: isDark ? Colors.blueGrey.shade200 : Colors.blueGrey,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white70 : const Color(0xFF334155),
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  Future<void> _handleRestoreBackup(BuildContext context, WidgetRef ref) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF111827) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.indigo.withValues(alpha: 0.2)
                        : Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.settings_backup_restore_rounded,
                    color: isDark
                        ? Colors.indigoAccent
                        : Colors.indigo.shade700,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Restore from Backup',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Import without losing existing data',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isDark ? Colors.white12 : Colors.grey.shade200,
                ),
              ),
              leading: CircleAvatar(
                backgroundColor: isDark
                    ? Colors.indigo.withValues(alpha: 0.3)
                    : const Color(0xFFEEF2FF),
                child: Icon(
                  Icons.paste_rounded,
                  color: isDark ? Colors.indigoAccent : Colors.indigo,
                ),
              ),
              title: const Text(
                'Paste JSON from Clipboard',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              subtitle: const Text(
                'Directly read from clipboard',
                style: TextStyle(fontSize: 12),
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
            const SizedBox(height: 10),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isDark ? Colors.white12 : Colors.grey.shade200,
                ),
              ),
              leading: CircleAvatar(
                backgroundColor: isDark
                    ? Colors.green.withValues(alpha: 0.25)
                    : const Color(0xFFF0FDF4),
                child: Icon(
                  Icons.file_open_rounded,
                  color: isDark ? Colors.greenAccent : Colors.green,
                ),
              ),
              title: const Text(
                'Pick JSON Backup File',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              subtitle: const Text(
                'Select a .json file from phone storage',
                style: TextStyle(fontSize: 12),
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
            const SizedBox(height: 12),
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
      final isDark = Theme.of(context).brightness == Brightness.dark;

      showDialog(
        context: context,
        builder: (dCtx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 28),
              SizedBox(width: 10),
              Text('Restore Complete!'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'আপনার ব্যাকআপ সফলভাবে রিস্টোর হয়েছে:',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
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
              if (restoredPrefs > 0)
                Text('• $restoredPrefs টি সেটিংস ফিরেছে'),
              const SizedBox(height: 8),
              // Said every time: it is the one thing a restore cannot do for
              // you, and finding out later costs a failed scan.
              const Text(
                'API key ব্যাকআপ ফাইলে রাখা হয় না — সেটি আবার বসাতে হবে।',
                style: TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo.shade700,
                foregroundColor: Colors.white,
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
