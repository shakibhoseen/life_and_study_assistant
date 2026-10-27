import '../../../../core/database/app_database.dart';
import '../../../../core/database/tables/daily_energy_logs_table.dart';

abstract class EnergyLogRepository {
  Stream<DailyEnergyLog?> watchTodayLog();
  Future<DailyEnergyLog?> getTodayLog();
  Stream<List<DailyEnergyLog>> watchRecentLogs({int limit = 7});
  Future<int> logDailyEnergy({
    required DateTime date,
    required EnergyLevel energyLevel,
    required int officeFatigueScore,
    String? completedTasksJson,
    String? notes,
  });
}
