import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/tables/daily_energy_logs_table.dart';
import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/widgets/premium_ui_kit.dart';
import '../../../energy_log/presentation/providers/energy_log_provider.dart';
import '../../../study_planner/presentation/providers/adaptive_planner_provider.dart';

class EnergyTrackerCard extends ConsumerStatefulWidget {
  const EnergyTrackerCard({super.key});

  @override
  ConsumerState<EnergyTrackerCard> createState() => _EnergyTrackerCardState();
}

class _EnergyTrackerCardState extends ConsumerState<EnergyTrackerCard> {
  EnergyLevel _selectedEnergy = EnergyLevel.medium;
  double _fatigueScore = 5.0;
  bool _isInitialized = false;

  @override
  Widget build(BuildContext context) {
    final todayLogAsync = ref.watch(todayEnergyLogStreamProvider);

    todayLogAsync.whenData((log) {
      if (log != null && !_isInitialized) {
        _selectedEnergy = log.energyLevel;
        _fatigueScore = log.officeFatigueScore.toDouble();
        _isInitialized = true;
      }
    });

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final onSurface = scheme.onSurface;
    // Red / amber / green, kept because here they carry status meaning.
    final Color fatigueColor = _fatigueScore >= 7
        ? scheme.error
        : (_fatigueScore >= 4
              ? const Color(0xFFF59E0B)
              : const Color(0xFF10B981));

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: FluentRadius.cardBorder,
        side: FluentStroke.side(theme.brightness),
      ),
      child: Padding(
        padding: const EdgeInsets.all(FluentSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bolt, color: scheme.primary, size: 22),
                const SizedBox(width: FluentSpacing.s),
                // Takes the free space like the Spacer it replaces, but also
                // gives it back when the title and the chip together exceed
                // the row. Scaling down beats ellipsising a four-pixel
                // overflow into "Post-Work Energy & Moo…".
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Post-Work Energy & Mood',
                      style: FluentType.bodyStrong.copyWith(
                        fontSize: 16,
                        color: onSurface,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: FluentSpacing.s),
                Flexible(
                  child: PremiumTag(
                    label: 'Fatigue: ${_fatigueScore.toInt()}/10',
                    color: fatigueColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: FluentSpacing.m),
            Text(
              'How mentally drained are you feeling after today’s code/office hours?',
              style: FluentType.body.copyWith(
                color: onSurface.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: FluentSpacing.m),
            // Energy selection segment
            Row(
              children: [
                _buildEnergyOption(
                  level: EnergyLevel.low,
                  label: 'Exhausted',
                  icon: Icons.battery_1_bar,
                  color: scheme.error,
                  isDark: isDark,
                ),
                const SizedBox(width: FluentSpacing.s),
                _buildEnergyOption(
                  level: EnergyLevel.medium,
                  label: 'Moderate',
                  icon: Icons.battery_4_bar,
                  color: const Color(0xFFF59E0B),
                  isDark: isDark,
                ),
                const SizedBox(width: FluentSpacing.s),
                _buildEnergyOption(
                  level: EnergyLevel.high,
                  label: 'Energized',
                  icon: Icons.battery_full,
                  color: const Color(0xFF10B981),
                  isDark: isDark,
                ),
              ],
            ),
            const SizedBox(height: FluentSpacing.l),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    'Office Fatigue Slider:',
                    style: FluentType.body.copyWith(color: onSurface),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: FluentSpacing.s),
                // "⚠️ High burnout risk" is the longest of the three and the
                // one that matters most, so it gets the room it needs.
                Flexible(
                  child: Text(
                    _fatigueScore >= 7
                        ? '⚠️ High burnout risk'
                        : (_fatigueScore >= 4 ? 'Normal tiredness' : 'Fresh'),
                    style: FluentType.caption.copyWith(
                      color: fatigueColor,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            Slider(
              value: _fatigueScore,
              min: 1,
              max: 10,
              divisions: 9,
              activeColor: fatigueColor,
              label: '${_fatigueScore.toInt()}',
              onChanged: (val) {
                setState(() {
                  _fatigueScore = val;
                  if (val >= 7) {
                    _selectedEnergy = EnergyLevel.low;
                  }
                });
              },
            ),
            const SizedBox(height: FluentSpacing.s),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    vertical: FluentSpacing.m,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: FluentRadius.controlBorder,
                  ),
                ),
                icon: const Icon(Icons.sync, size: 18),
                label: Text(
                  'Log Energy & Adapt Study Plan',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FluentType.bodyStrong,
                ),
                onPressed: () async {
                  await ref
                      .read(energyLogNotifierProvider.notifier)
                      .saveLog(
                        energyLevel: _selectedEnergy,
                        officeFatigueScore: _fatigueScore.toInt(),
                      );
                  await ref
                      .read(adaptivePlannerProvider.notifier)
                      .generatePlan(
                        overrideEnergy: _selectedEnergy,
                        overrideFatigue: _fatigueScore.toInt(),
                      );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Energy logged! Adaptive study routine updated.',
                        ),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnergyOption({
    required EnergyLevel level,
    required String label,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final onSurface = theme.colorScheme.onSurface;
    final isSelected = _selectedEnergy == level;

    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedEnergy = level;
            if (level == EnergyLevel.low && _fatigueScore < 7) {
              _fatigueScore = 8;
            } else if (level == EnergyLevel.high && _fatigueScore > 4) {
              _fatigueScore = 2;
            }
          });
        },
        borderRadius: FluentRadius.controlBorder,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: FluentSpacing.s),
          decoration: BoxDecoration(
            color: isSelected
                ? FluentLayer.subtle(color, brightness)
                : FluentLayer.subtle(onSurface, brightness),
            borderRadius: FluentRadius.controlBorder,
            border: Border.all(
              color: isSelected ? color : FluentStroke.card(brightness),
              width: FluentStroke.width,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? color : onSurface.withValues(alpha: 0.65),
                size: 20,
              ),
              const SizedBox(height: FluentSpacing.xs),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FluentType.caption.copyWith(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? color : onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
