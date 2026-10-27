import 'package:drift/drift.dart';

enum EnergyLevel { low, medium, high }

class DailyEnergyLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get date => dateTime()();
  TextColumn get energyLevel => textEnum<EnergyLevel>()();
  IntColumn get officeFatigueScore =>
      integer().withDefault(const Constant(5))();
  TextColumn get completedTasks => text().withDefault(const Constant('[]'))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
