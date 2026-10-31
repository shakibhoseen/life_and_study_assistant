import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_provider.dart';

/// Provides the user's current consecutive study streak in days.
/// Computes from completed drills, MCQ attempts, and daily logs.
final studyStreakProvider = FutureProvider<int>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final data = await db.getActivityHeatmapData(daysBack: 30);
  return (data['currentStreak'] as int?) ?? 0;
});
