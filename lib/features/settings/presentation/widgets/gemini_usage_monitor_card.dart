import 'package:flutter/material.dart';

import '../../../../core/services/ai/gemini_usage_tracker.dart';
import '../../../../core/theme/fluent_tokens.dart';

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

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final isQuotaExceeded = stats.lastStatus == 'QuotaExceeded';
    final isError = stats.lastStatus == 'Error';
    // Status colour, which Fluent keeps: error, warning, success.
    final statusColor = isQuotaExceeded || isError
        ? scheme.error
        : (stats.usagePercent > 0.7
              ? const Color(0xFFF59E0B)
              : const Color(0xFF10B981));

    final statusText = isQuotaExceeded
        ? 'Quota limit reached (local fallback active)'
        : isError
        ? 'Last call failed (local fallback active)'
        : 'Healthy — ${stats.dailyRequestLimit} req/day budget';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: FluentRadius.cardBorder,
        side: FluentStroke.side(brightness),
      ),
      child: Padding(
        padding: const EdgeInsets.all(FluentSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.speed, color: scheme.primary, size: 20),
                const SizedBox(width: FluentSpacing.s),
                Expanded(
                  child: Text(
                    'Gemini API Quota & Usage',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FluentType.bodyStrong.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: FluentSpacing.s),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FluentSpacing.s,
                    vertical: FluentSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: FluentLayer.subtle(statusColor, brightness),
                    borderRadius: FluentRadius.controlBorder,
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.5),
                      width: FluentStroke.width,
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
                      const SizedBox(width: FluentSpacing.xs),
                      Text(
                        isQuotaExceeded ? 'Exceeded' : 'Active',
                        style: FluentType.caption.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: FluentSpacing.m),
            Text(
              statusText,
              style: FluentType.caption.copyWith(
                color: statusColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: FluentSpacing.m),
            // Progress Bar
            ClipRRect(
              borderRadius: FluentRadius.controlBorder,
              child: LinearProgressIndicator(
                value: stats.usagePercent,
                minHeight: 8,
                backgroundColor: FluentStroke.card(brightness),
                color: statusColor,
              ),
            ),
            const SizedBox(height: FluentSpacing.s),
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FluentType.caption.copyWith(
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: FluentSpacing.xs),
                        Icon(
                          Icons.edit_outlined,
                          size: 14,
                          color: scheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ],
                    ),
                  ),
                ),
                Text(
                  '${stats.remainingRequests} left',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FluentType.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
            Divider(
              height: FluentSpacing.xxl,
              color: FluentStroke.divider(brightness),
            ),
            Row(
              children: [
                Expanded(
                  child: _buildMetricTile(
                    label: 'Tokens Used Today',
                    value: '${stats.todayTokens}',
                    icon: Icons.token,
                    context: context,
                  ),
                ),
                const SizedBox(width: FluentSpacing.m),
                Expanded(
                  child: _buildMetricTile(
                    label: 'Avg Tokens / Call',
                    value: '${stats.averageTokensPerRequest}',
                    icon: Icons.straighten,
                    context: context,
                  ),
                ),
              ],
            ),
            const SizedBox(height: FluentSpacing.s),
            Row(
              children: [
                Expanded(
                  child: _buildMetricTile(
                    label: 'Provider Actual Tokens',
                    value: '${stats.todayActualTotalTokens}',
                    icon: Icons.verified_outlined,
                    context: context,
                  ),
                ),
                const SizedBox(width: FluentSpacing.m),
                Expanded(
                  child: _buildMetricTile(
                    label: 'Cache Hits (Zero Cost)',
                    value: '${stats.todayCacheHits} hits',
                    icon: Icons.offline_bolt_outlined,
                    context: context,
                  ),
                ),
              ],
            ),
            _buildBreakdown(stats, context),
            const SizedBox(height: FluentSpacing.m),
            Container(
              padding: const EdgeInsets.all(FluentSpacing.m),
              decoration: BoxDecoration(
                color: FluentLayer.subtle(scheme.primary, brightness),
                borderRadius: FluentRadius.controlBorder,
                border: Border.all(
                  color: FluentStroke.card(brightness),
                  width: FluentStroke.width,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.shield_outlined, color: scheme.primary, size: 18),
                  const SizedBox(width: FluentSpacing.s),
                  Expanded(
                    child: Text(
                      'Free-tier limits are set per project, so check yours in Google AI Studio and tap the counter above to match it. The breakdown shows where today\'s tokens actually went.',
                      style: FluentType.caption.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.65),
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
  Widget _buildBreakdown(GeminiUsageStats stats, BuildContext context) {
    final rows = stats.operationsByCost;
    if (rows.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: FluentSpacing.l),
        Text(
          'Today by operation',
          style: FluentType.caption.copyWith(
            fontWeight: FontWeight.w600,
            color: scheme.onSurface.withValues(alpha: 0.65),
          ),
        ),
        const SizedBox(height: FluentSpacing.s),
        ...rows.map((entry) {
          final share = stats.todayTokens == 0
              ? 0.0
              : entry.value.tokens / stats.todayTokens;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: FluentSpacing.xxs),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Text(
                    entry.key,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FluentType.caption.copyWith(color: scheme.onSurface),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: ClipRRect(
                    borderRadius: FluentRadius.controlBorder,
                    child: LinearProgressIndicator(
                      value: share,
                      minHeight: 6,
                      backgroundColor: FluentStroke.card(brightness),
                      color: scheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: FluentSpacing.s),
                Text(
                  '${entry.value.requests}× · ${entry.value.tokens}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FluentType.caption.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.65),
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
            Text(
              'Google sets free-tier limits per project. Enter the requests/day '
              'your AI Studio project actually allows.',
              style: FluentType.caption,
            ),
            const SizedBox(height: FluentSpacing.m),
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
    // The dialog is gone by here, so the controller it was reading has no
    // more readers. Left undisposed it kept its listeners alive for the rest
    // of the session, one more set every time the dialog was opened.
    controller.dispose();

    if (value != null && value > 0) {
      await GeminiUsageTracker.instance.setDailyRequestLimit(value);
      await _loadStats();
    }
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required IconData icon,
    required BuildContext context,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FluentSpacing.m,
        vertical: FluentSpacing.s,
      ),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: FluentRadius.controlBorder,
        border: Border.all(
          color: FluentStroke.card(theme.brightness),
          width: FluentStroke.width,
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
                color: scheme.onSurface.withValues(alpha: 0.65),
              ),
              const SizedBox(width: FluentSpacing.xs),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FluentType.caption.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: FluentSpacing.xs),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FluentType.bodyStrong.copyWith(color: scheme.onSurface),
          ),
        ],
      ),
    );
  }
}
