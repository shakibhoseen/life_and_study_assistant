import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_provider.dart';
import '../../../../core/theme/fluent_tokens.dart';
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final isDark = brightness == Brightness.dark;
    return tracksAsync.when(
      loading: () => const SizedBox(height: 48),
      error: (_, _) => const SizedBox.shrink(),
      data: (tracks) {
        final allTracks = ['All', ...tracks];
        return Container(
          height: 48,
          padding: const EdgeInsets.symmetric(vertical: FluentSpacing.xs),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(
              bottom: BorderSide(
                color: FluentStroke.card(brightness),
                width: FluentStroke.width,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: FluentSpacing.l,
                  ),
                  itemCount: allTracks.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: FluentSpacing.s),
                  itemBuilder: (context, index) {
                    final track = allTracks[index];
                    final isSelected = selectedTrack == track;
                    final isAll = track == 'All';

                    return ChoiceChip(
                      showCheckmark: false,
                      shape: RoundedRectangleBorder(
                        borderRadius: FluentRadius.controlBorder,
                        side: BorderSide(
                          color: isSelected
                              ? (isAll ? scheme.primary : _getTrackColor(track))
                              : FluentStroke.card(brightness),
                          width: FluentStroke.width,
                        ),
                      ),
                      avatar: isAll
                          ? Icon(
                              Icons.layers,
                              size: 14,
                              color: isSelected
                                  ? scheme.onPrimary
                                  : scheme.primary,
                            )
                          : Icon(
                              Icons.bookmark,
                              size: 14,
                              color: isSelected
                                  ? _getTrackColor(track)
                                  : scheme.onSurface.withValues(alpha: 0.65),
                            ),
                      selected: isSelected,
                      label: Text(
                        isAll ? 'All Programs' : track,
                        style: FluentType.caption.copyWith(
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: isSelected
                              ? (isAll
                                    ? scheme.onPrimary
                                    : (isDark
                                          ? scheme.onSurface
                                          : _getTrackColor(track)))
                              : scheme.onSurface,
                        ),
                      ),
                      selectedColor: isAll
                          ? scheme.primary
                          : _getTrackBackgroundColor(track, isDark),
                      backgroundColor: scheme.onSurface.withValues(
                        alpha: isDark ? 0.08 : 0.04,
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
                  padding: const EdgeInsets.only(right: FluentSpacing.m),
                  child: Tooltip(
                    message: '“$selectedTrack” ট্র্যাকের সব পরীক্ষা মুছুন',
                    child: InkWell(
                      borderRadius: FluentRadius.controlBorder,
                      onTap: () =>
                          _confirmDeleteTrack(context, ref, selectedTrack),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: FluentSpacing.s,
                          vertical: FluentSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: FluentLayer.subtle(scheme.error, brightness),
                          borderRadius: FluentRadius.controlBorder,
                          border: Border.all(
                            color: scheme.error.withValues(alpha: 0.3),
                            width: FluentStroke.width,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.delete_outline,
                              size: 14,
                              color: scheme.error,
                            ),
                            const SizedBox(width: FluentSpacing.xs),
                            Flexible(
                              child: Text(
                                'ট্র্যাক মুছুন',
                                style: FluentType.caption.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: scheme.error,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
        shape: RoundedRectangleBorder(borderRadius: FluentRadius.cardBorder),
        title: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Theme.of(ctx).colorScheme.error,
              size: 24,
            ),
            const SizedBox(width: FluentSpacing.s),
            Expanded(
              child: Text(
                'ট্র্যাকের সব পরীক্ষা মুছবেন?',
                style: FluentType.bodyStrong.copyWith(
                  fontSize: 16,
                  color: Theme.of(ctx).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: FluentSpacing.m,
                vertical: FluentSpacing.s,
              ),
              decoration: BoxDecoration(
                color: FluentLayer.subtle(
                  Theme.of(ctx).colorScheme.error,
                  Theme.of(ctx).brightness,
                ),
                borderRadius: FluentRadius.controlBorder,
                border: Border.all(
                  color: Theme.of(ctx).colorScheme.error.withValues(alpha: 0.2),
                  width: FluentStroke.width,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.bookmark,
                    color: Theme.of(ctx).colorScheme.error,
                    size: 18,
                  ),
                  const SizedBox(width: FluentSpacing.s),
                  Expanded(
                    child: Text(
                      trackName,
                      style: FluentType.bodyStrong.copyWith(
                        color: Theme.of(ctx).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: FluentSpacing.m),
            Text(
              'এই ট্র্যাকে মোট $countটি পরীক্ষা রয়েছে।\n\n'
              'ডিলিট করলে এই ট্র্যাকের সবগুলো পরীক্ষা একবারে মুছে যাবে। অন্য কোনো ট্র্যাক বা পরীক্ষা অক্ষত থাকবে।\n\n'
              'আপনি কি নিশ্চিতভাবে এই ট্র্যাকের সব পরীক্ষা মুছে ফেলতে চান?',
              style: FluentType.body.copyWith(
                color: Theme.of(ctx).colorScheme.onSurface,
              ),
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
              elevation: 0,
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
              shape: RoundedRectangleBorder(
                borderRadius: FluentRadius.controlBorder,
              ),
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
