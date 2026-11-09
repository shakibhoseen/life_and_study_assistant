import 'package:flutter/material.dart';

import '../../../../core/services/ai/gemini_result_cache.dart';

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
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(sheetContext).size.height * 0.7,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'সংরক্ষিত AI উত্তর',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
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
                                style: const TextStyle(fontSize: 12.5),
                              ),
                              subtitle: Text(
                                '${entry.operation} · '
                                '${_whenever(entry.createdAt)} · '
                                '${_size(entry.sizeBytes)}',
                                style: const TextStyle(fontSize: 10.5),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final stats = _stats;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.save_outlined,
                size: 18,
                color: isDark ? Colors.tealAccent : Colors.teal.shade700,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'AI ক্যাশ',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
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
          const SizedBox(height: 6),
          Text(
            stats == null
                ? 'দেখা হচ্ছে…'
                : stats.isEmpty
                ? 'কিছু সংরক্ষিত নেই — প্রতিটি স্ক্যান নতুন করে পড়া হবে'
                : '${stats.entries} টি উত্তর · ${_size(stats.bytes)} · '
                      '৭ দিন পর নিজেই মুছে যায়',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.35,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'একই ছবি বা লেখা আবার দিলে সংরক্ষিত উত্তরই আসে, টোকেন খরচ ছাড়াই। '
            'একটিবার নতুন করে পড়াতে চাইলে স্ক্যানারে "আবার নতুন করে পড়ো" দিন।',
            style: TextStyle(
              fontSize: 10.5,
              height: 1.35,
              color: isDark ? Colors.white38 : Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: (stats == null || stats.isEmpty)
                      ? null
                      : _showEntries,
                  icon: const Icon(Icons.list_alt, size: 16),
                  label: const Text(
                    'দেখুন',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: (_busy || stats == null || stats.isEmpty)
                      ? null
                      : _clearAll,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                  ),
                  icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                  label: const Text(
                    'সব মুছুন',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
