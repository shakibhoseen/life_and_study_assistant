import 'package:flutter/material.dart';

import '../../../../core/services/ai/gemini_usage_tracker.dart';

class GeminiUsageMonitorCard extends StatefulWidget {
  const GeminiUsageMonitorCard({super.key});

  @override
  State<GeminiUsageMonitorCard> createState() => _GeminiUsageMonitorCardState();
}

class _GeminiUsageMonitorCardState extends State<GeminiUsageMonitorCard> {
  GeminiUsageStats? _stats;

  @override
  void initState() {
    super.initState();
    _loadStats();
    GeminiUsageTracker.instance.statsStream.listen((stats) {
      if (mounted) {
        setState(() {
          _stats = stats;
        });
      }
    });
  }

  Future<void> _loadStats() async {
    final stats = await GeminiUsageTracker.instance.getStats();
    if (mounted) {
      setState(() {
        _stats = stats;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats =
        _stats ??
        GeminiUsageStats(
          todayRequests: 0,
          todayTokens: 0,
          lastStatus: 'Healthy',
        );

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isQuotaExceeded = stats.lastStatus == 'QuotaExceeded';
    final isError = stats.lastStatus == 'Error';
    final statusColor = isQuotaExceeded || isError
        ? Colors.redAccent
        : (stats.usagePercent > 0.7 ? Colors.amber : Colors.green);

    final statusText = isQuotaExceeded
        ? 'Quota limit reached (local fallback active)'
        : isError
        ? 'Last call failed (local fallback active)'
        : 'Healthy — ${stats.dailyRequestLimit} req/day budget';

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.speed,
                  color: isDark ? Colors.indigo.shade200 : Colors.indigo,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Gemini API Quota & Usage',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: isDark ? 0.25 : 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isQuotaExceeded ? 'Exceeded' : 'Active',
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              statusText,
              style: TextStyle(
                fontSize: 12,
                color: statusColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            // Progress Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: stats.usagePercent,
                minHeight: 8,
                backgroundColor: isDark ? Colors.white12 : Colors.grey.shade200,
                color: statusColor,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _editDailyLimit(stats.dailyRequestLimit),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${stats.todayRequests} / ${stats.dailyRequestLimit} calls today',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.edit_outlined,
                          size: 13,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ],
                    ),
                  ),
                ),
                Text(
                  '${stats.remainingRequests} left',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white60 : Colors.grey.shade700,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildMetricTile(
                    label: 'Tokens Used Today',
                    value: '${stats.todayTokens}',
                    icon: Icons.token,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricTile(
                    label: 'Avg Tokens / Call',
                    value: '${stats.averageTokensPerRequest}',
                    icon: Icons.straighten,
                    isDark: isDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildMetricTile(
                    label: 'Provider Actual Tokens',
                    value: '${stats.todayActualTotalTokens}',
                    icon: Icons.verified_outlined,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricTile(
                    label: 'Cache Hits (Zero Cost)',
                    value: '${stats.todayCacheHits} hits',
                    icon: Icons.offline_bolt_outlined,
                    isDark: isDark,
                  ),
                ),
              ],
            ),
            _buildBreakdown(stats, isDark),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.blue.withValues(alpha: 0.15)
                    : Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark
                      ? Colors.blue.withValues(alpha: 0.3)
                      : Colors.blue.shade100,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    color: isDark ? Colors.lightBlueAccent : Colors.blue,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Free-tier limits are set per project, so check yours in Google AI Studio and tap the counter above to match it. The breakdown shows where today\'s tokens actually went.',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Where today's tokens actually went.
  ///
  /// This is the point of recording an operation label per call: it is what
  /// answers questions like "is the context router pulling tools too often?"
  /// or "how much is thread summarising costing me?".
  Widget _buildBreakdown(GeminiUsageStats stats, bool isDark) {
    final rows = stats.operationsByCost;
    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Text(
          'Today by operation',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white60 : Colors.black54,
          ),
        ),
        const SizedBox(height: 6),
        ...rows.map((entry) {
          final share = stats.todayTokens == 0
              ? 0.0
              : entry.value.tokens / stats.todayTokens;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Text(
                    entry.key,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: share,
                      minHeight: 5,
                      backgroundColor: isDark
                          ? Colors.white12
                          : Colors.grey.shade200,
                      color: isDark ? Colors.indigo.shade200 : Colors.indigo,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${entry.value.requests}× · ${entry.value.tokens}',
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Future<void> _editDailyLimit(int current) async {
    final controller = TextEditingController(text: '$current');
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Daily request budget'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Google sets free-tier limits per project. Enter the requests/day '
              'your AI Studio project actually allows.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Requests per day',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, int.tryParse(controller.text.trim())),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (value != null && value > 0) {
      await GeminiUsageTracker.instance.setDailyRequestLimit(value);
      await _loadStats();
    }
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required IconData icon,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 14,
                color: isDark ? Colors.blueGrey.shade200 : Colors.blueGrey,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
