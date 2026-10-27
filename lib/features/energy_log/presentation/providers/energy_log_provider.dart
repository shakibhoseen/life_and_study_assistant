import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/database/tables/daily_energy_logs_table.dart';
import '../../data/repositories/energy_log_repository_impl.dart';
import '../../domain/repositories/energy_log_repository.dart';

final energyLogRepositoryProvider = Provider<EnergyLogRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return EnergyLogRepositoryImpl(db);
});

final todayEnergyLogStreamProvider = StreamProvider<DailyEnergyLog?>((ref) {
  final repo = ref.watch(energyLogRepositoryProvider);
  return repo.watchTodayLog();
});

final recentEnergyLogsStreamProvider = StreamProvider<List<DailyEnergyLog>>((
  ref,
) {
  final repo = ref.watch(energyLogRepositoryProvider);
  return repo.watchRecentLogs(limit: 7);
});

class EnergyLogNotifier extends Notifier<void> {
  @override
  void build() {}

  Future<void> saveLog({
    required EnergyLevel energyLevel,
    required int officeFatigueScore,
    String? notes,
  }) async {
    final repo = ref.read(energyLogRepositoryProvider);
    await repo.logDailyEnergy(
      date: DateTime.now(),
      energyLevel: energyLevel,
      officeFatigueScore: officeFatigueScore,
      notes: notes,
    );
  }
}

final energyLogNotifierProvider = NotifierProvider<EnergyLogNotifier, void>(() {
  return EnergyLogNotifier();
});
