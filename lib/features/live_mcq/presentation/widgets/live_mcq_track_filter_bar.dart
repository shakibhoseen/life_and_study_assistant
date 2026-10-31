import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_provider.dart';
import '../providers/exam_schedule_provider.dart';

class LiveMcqTrackFilterBar extends ConsumerWidget {
  final AsyncValue<List<String>> tracksAsync;
  final String selectedTrack;

  const LiveMcqTrackFilterBar({
    super.key,
    required this.tracksAsync,
    required this.selectedTrack,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return tracksAsync.when(
      loading: () => const SizedBox(height: 48),
      error: (_, _) => const SizedBox.shrink(),
      data: (tracks) {
        final allTracks = ['All', ...tracks];
        return Container(
          height: 48,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF111827) : Colors.white,
            border: Border(
              bottom: BorderSide(
                color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade200,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: allTracks.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final track = allTracks[index];
                    final isSelected = selectedTrack == track;
                    final isAll = track == 'All';

                    return ChoiceChip(
                      showCheckmark: false,
                      avatar: isAll
                          ? Icon(
                              Icons.layers,
                              size: 14,
                              color: isSelected ? Colors.white : Colors.indigo,
                            )
                          : Icon(
                              Icons.bookmark,
                              size: 14,
                              color: isSelected
                                  ? _getTrackColor(track)
                                  : Colors.grey,
                            ),
                      selected: isSelected,
                      label: Text(
                        isAll ? 'All Programs' : track,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: isSelected
                              ? (isAll
                                    ? Colors.white
                                    : (isDark
                                          ? Colors.white
                                          : _getTrackColor(track)))
                              : (isDark ? Colors.white70 : Colors.black87),
                        ),
                      ),
                      selectedColor: isAll
                          ? Colors.indigo
                          : _getTrackBackgroundColor(track, isDark),
                      backgroundColor: isDark
                          ? const Color(0xFF1E293B)
                          : Colors.grey.shade50,
                      side: BorderSide(
                        color: isSelected
                            ? (isAll ? Colors.indigo : _getTrackColor(track))
                            : (isDark
                                  ? const Color(0xFF334155)
                                  : Colors.grey.shade300),
                        width: isSelected ? 1.5 : 1,
                      ),
                      onSelected: (_) {
                        ref
                            .read(selectedTrackProvider.notifier)
                            .setTrack(track);
                      },
                    );
                  },
                ),
              ),
              if (selectedTrack != 'All') ...[
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Tooltip(
                    message: '“$selectedTrack” ট্র্যাকের সব পরীক্ষা মুছুন',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () =>
                          _confirmDeleteTrack(context, ref, selectedTrack),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.red.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.delete_outline,
                              size: 14,
                              color: Colors.red,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'ট্র্যাক মুছুন',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteTrack(
    BuildContext context,
    WidgetRef ref,
    String trackName,
  ) async {
    final db = ref.read(appDatabaseProvider);
    final count =
        await (db.select(db.examSchedules)
              ..where((t) => t.trackName.equals(trackName)))
            .get()
            .then((list) => list.length);

    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'ট্র্যাকের সব পরীক্ষা মুছবেন?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bookmark, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      trackName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'এই ট্র্যাকে মোট $countটি পরীক্ষা রয়েছে।\n\n'
              'ডিলিট করলে এই ট্র্যাকের সবগুলো পরীক্ষা একবারে মুছে যাবে। অন্য কোনো ট্র্যাক বা পরীক্ষা অক্ষত থাকবে।\n\n'
              'আপনি কি নিশ্চিতভাবে এই ট্র্যাকের সব পরীক্ষা মুছে ফেলতে চান?',
              style: const TextStyle(fontSize: 12.5, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('বাতিল'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.delete_forever, size: 16),
            label: Text('হ্যাঁ, $countটি পরীক্ষা মুছুন'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final deletedCount = await ref
          .read(examScheduleNotifierProvider.notifier)
          .deleteExamsByTrack(trackName);

      // Reset filter to All Programs
      ref.read(selectedTrackProvider.notifier).setTrack('All');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            behavior: SnackBarBehavior.floating,
            content: Text(
              '“$trackName” ট্র্যাকের $deletedCountটি পরীক্ষা সফলভাবে মুছে ফেলা হয়েছে।',
            ),
          ),
        );
      }
    }
  }

  static Color getTrackColor(String track) {
    final lower = track.toLowerCase();
    if (lower.contains('vocab')) return Colors.orange.shade800;
    if (lower.contains('friday') ||
        lower.contains('mega') ||
        lower.contains('model')) {
      return Colors.teal.shade800;
    }
    if (lower.contains('135') ||
        lower.contains('140') ||
        lower.contains('200') ||
        lower.contains('bcs')) {
      return Colors.deepPurple.shade700;
    }
    if (lower.contains('primary')) return Colors.blue.shade800;
    return Colors.indigo.shade800;
  }

  static Color getTrackBackgroundColor(String track, [bool isDark = false]) {
    final lower = track.toLowerCase();
    if (lower.contains('vocab')) {
      return isDark
          ? Colors.orange.withValues(alpha: 0.2)
          : Colors.orange.shade50;
    }
    if (lower.contains('friday') ||
        lower.contains('mega') ||
        lower.contains('model')) {
      return isDark ? Colors.teal.withValues(alpha: 0.2) : Colors.teal.shade50;
    }
    if (lower.contains('135') ||
        lower.contains('140') ||
        lower.contains('200') ||
        lower.contains('bcs')) {
      return isDark
          ? Colors.deepPurple.withValues(alpha: 0.2)
          : Colors.deepPurple.shade50;
    }
    if (lower.contains('primary')) {
      return isDark ? Colors.blue.withValues(alpha: 0.2) : Colors.blue.shade50;
    }
    return isDark
        ? Colors.indigo.withValues(alpha: 0.2)
        : Colors.indigo.shade50;
  }

  Color _getTrackColor(String track) => getTrackColor(track);
  Color _getTrackBackgroundColor(String track, [bool isDark = false]) =>
      getTrackBackgroundColor(track, isDark);
}
