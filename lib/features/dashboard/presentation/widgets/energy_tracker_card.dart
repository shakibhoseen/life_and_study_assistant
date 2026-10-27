import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/tables/daily_energy_logs_table.dart';
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

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color fatigueColor = _fatigueScore >= 7
        ? Colors.redAccent
        : (_fatigueScore >= 4 ? Colors.amberAccent : Colors.greenAccent);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bolt, color: Colors.amber, size: 22),
                const SizedBox(width: 8),
                // Takes the free space like the Spacer it replaces, but also
                // gives it back when the title and the chip together exceed
                // the row. Scaling down beats ellipsising a four-pixel
                // overflow into "Post-Work Energy & Moo…".
                const Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Post-Work Energy & Mood',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: fatigueColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Fatigue: ${_fatigueScore.toInt()}/10',
                    style: TextStyle(
                      color: fatigueColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'How mentally drained are you feeling after today’s code/office hours?',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            const SizedBox(height: 12),
            // Energy selection segment
            Row(
              children: [
                _buildEnergyOption(
                  level: EnergyLevel.low,
                  label: 'Exhausted',
                  icon: Icons.battery_1_bar,
                  color: Colors.redAccent,
                  isDark: isDark,
                ),
                const SizedBox(width: 8),
                _buildEnergyOption(
                  level: EnergyLevel.medium,
                  label: 'Moderate',
                  icon: Icons.battery_4_bar,
                  color: Colors.orangeAccent,
                  isDark: isDark,
                ),
                const SizedBox(width: 8),
                _buildEnergyOption(
                  level: EnergyLevel.high,
                  label: 'Energized',
                  icon: Icons.battery_full,
                  color: Colors.green,
                  isDark: isDark,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Flexible(
                  child: Text(
                    'Office Fatigue Slider:',
                    style: TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                // "⚠️ High burnout risk" is the longest of the three and the
                // one that matters most, so it gets the room it needs.
                Flexible(
                  child: Text(
                    _fatigueScore >= 7
                        ? '⚠️ High burnout risk'
                        : (_fatigueScore >= 4 ? 'Normal tiredness' : 'Fresh'),
                    style: TextStyle(
                      fontSize: 12,
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
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.sync, size: 18),
                label: const Text('Log Energy & Adapt Study Plan'),
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
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withValues(alpha: 0.2)
                : (isDark ? const Color(0xFF1E293B) : Colors.grey.shade100),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? color
                  : (isDark ? Colors.white12 : Colors.grey.shade300),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected
                    ? color
                    : (isDark ? Colors.white70 : Colors.grey.shade600),
                size: 20,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected
                      ? color
                      : (isDark ? Colors.white : Colors.black87),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
