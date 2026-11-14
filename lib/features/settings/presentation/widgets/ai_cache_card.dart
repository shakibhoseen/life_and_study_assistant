import 'package:flutter/material.dart';

import '../../../../core/services/ai/gemini_result_cache.dart';
import '../../../../core/theme/fluent_tokens.dart';

/// Shows what the AI result cache is holding, and lets it be emptied.
///
/// The cache saves a real amount of money — the same page scanned twice costs
/// nothing the second time — but until now there was no way to see into it or
/// clear it. The keys are hashes, so even reading the stored preferences told
/// nobody which entry belonged to which page; `clear()` existed and nothing
/// ever called it. The only way out was to clear the app's data.
class AiCacheCard extends StatefulWidget {
  const AiCacheCard({super.key});

  @override
  State<AiCacheCard> createState() => _AiCacheCardState();
}

class _AiCacheCardState extends State<AiCacheCard> {
  CacheStats? _stats;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stats = await GeminiResultCache.instance.stats();
    if (mounted) setState(() => _stats = stats);
  }

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ক্যাশ মুছে ফেলবেন?'),
        content: const Text(
          'সংরক্ষিত AI উত্তরগুলো মুছে যাবে। কোনো প্রশ্ন বা পরীক্ষা মুছবে না — '
          'শুধু একই ছবি বা লেখা আবার দিলে নতুন করে পড়তে হবে, আর টোকেন খরচ হবে।',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('থাক'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('মুছে ফেলুন'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    await GeminiResultCache.instance.clear();
    await _load();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _showEntries() async {
    final entries = await GeminiResultCache.instance.list();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(FluentRadius.large),
        ),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(sheetContext).size.height * 0.7,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        FluentSpacing.l,
                        FluentSpacing.l,
                        FluentSpacing.s,
                        FluentSpacing.s,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'সংরক্ষিত AI উত্তর',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: FluentType.bodyStrong.copyWith(
                                color: Theme.of(sheetContext)
                                    .colorScheme
                                    .onSurface,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(sheetContext),
                          ),
                        ],
                      ),
                    ),
                    if (entries.isEmpty)
                      const Expanded(
                        child: Center(child: Text('কিছু সংরক্ষিত নেই')),
                      )
                    else
                      Expanded(
                        child: ListView.separated(
                          itemCount: entries.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final entry = entries[i];
                            return ListTile(
                              dense: true,
                              title: Text(
                                entry.label.isEmpty
                                    ? entry.operation
                                    : entry.label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: FluentType.body.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface,
                                ),
                              ),
                              subtitle: Text(
                                '${entry.operation} · '
                                '${_whenever(entry.createdAt)} · '
                                '${_size(entry.sizeBytes)}',
                                style: FluentType.caption.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.65),
                                ),
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 20,
                                ),
                                tooltip: 'এটি মুছুন',
                                onPressed: () async {
                                  await GeminiResultCache.instance.remove(
                                    entry.key,
                                  );
                                  entries.removeAt(i);
                                  setSheetState(() {});
                                  await _load();
                                },
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// How long ago, roughly. The cache only keeps things for a week, so days
  /// and hours are as precise as this needs to be.
  String _whenever(DateTime at) {
    final age = DateTime.now().difference(at);
    if (age.inHours < 1) return '${age.inMinutes} মিনিট আগে';
    if (age.inDays < 1) return '${age.inHours} ঘণ্টা আগে';
    return '${age.inDays} দিন আগে';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final stats = _stats;

    return Container(
      padding: const EdgeInsets.all(FluentSpacing.l),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.cardColor,
        borderRadius: FluentRadius.cardBorder,
        border: Border.all(
          color: FluentStroke.card(theme.brightness),
          width: FluentStroke.width,
        ),
        boxShadow: FluentElevation.card(theme.brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.save_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: FluentSpacing.s),
              Expanded(
                child: Text(
                  'AI ক্যাশ',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FluentType.bodyStrong.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
              ),
              if (_busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: FluentSpacing.s),
          Text(
            stats == null
                ? 'দেখা হচ্ছে…'
                : stats.isEmpty
                ? 'কিছু সংরক্ষিত নেই — প্রতিটি স্ক্যান নতুন করে পড়া হবে'
                : '${stats.entries} টি উত্তর · ${_size(stats.bytes)} · '
                      '৭ দিন পর নিজেই মুছে যায়',
            style: FluentType.caption.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: FluentSpacing.xs),
          Text(
            'একই ছবি বা লেখা আবার দিলে সংরক্ষিত উত্তরই আসে, টোকেন খরচ ছাড়াই। '
            'একটিবার নতুন করে পড়াতে চাইলে স্ক্যানারে "আবার নতুন করে পড়ো" দিন।',
            style: FluentType.caption.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: FluentSpacing.m),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: (stats == null || stats.isEmpty)
                      ? null
                      : _showEntries,
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: FluentRadius.controlBorder,
                    ),
                  ),
                  icon: const Icon(Icons.list_alt, size: 16),
                  label: Text('দেখুন', style: FluentType.caption),
                ),
              ),
              const SizedBox(width: FluentSpacing.s),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: (_busy || stats == null || stats.isEmpty)
                      ? null
                      : _clearAll,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.error,
                    side: BorderSide(color: scheme.error),
                    shape: RoundedRectangleBorder(
                      borderRadius: FluentRadius.controlBorder,
                    ),
                  ),
                  icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                  label: Text('সব মুছুন', style: FluentType.caption),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
