import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/tables/daily_energy_logs_table.dart';
import '../../domain/repositories/energy_log_repository.dart';

class EnergyLogRepositoryImpl implements EnergyLogRepository {
  final AppDatabase _db;

  EnergyLogRepositoryImpl(this._db);

  @override
  Stream<DailyEnergyLog?> watchTodayLog() {
    return _db.watchTodayLog(DateTime.now());
  }

  @override
  Future<DailyEnergyLog?> getTodayLog() {
    return _db.getTodayLog(DateTime.now());
  }

  @override
  Stream<List<DailyEnergyLog>> watchRecentLogs({int limit = 7}) {
    return _db.watchRecentDailyLogs(limit: limit);
  }

  @override
  Future<int> logDailyEnergy({
    required DateTime date,
    required EnergyLevel energyLevel,
    required int officeFatigueScore,
    String? completedTasksJson,
    String? notes,
  }) {
    return _db.insertOrUpdateDailyLog(
      DailyEnergyLogsCompanion.insert(
        date: date,
        energyLevel: energyLevel,
        officeFatigueScore: Value(officeFatigueScore),
        completedTasks: Value(completedTasksJson ?? '[]'),
        notes: Value(notes),
      ),
    );
  }
}
