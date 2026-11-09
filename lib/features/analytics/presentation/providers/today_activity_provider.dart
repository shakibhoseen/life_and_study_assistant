import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_provider.dart';

/// How many questions have been answered today.
///
/// The activity table already holds this, keyed by day, for the heatmap — but
/// the heatmap only ever looked backwards, so nothing on the dashboard could
/// say what had been done today. This reads the one day out of it.
final questionsAnsweredTodayProvider = FutureProvider<int>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  // A fortnight, not the heatmap's month: the cost is in the rows scanned and
  // only one day of them is wanted.
  final data = await db.getActivityHeatmapData(daysBack: 14);

  final details = data['details'];
  if (details is! Map) return 0;

  final now = DateTime.now();
  final key =
      '${now.year}-${now.month.toString().padLeft(2, '0')}'
      '-${now.day.toString().padLeft(2, '0')}';

  final today = details[key];
  if (today is! Map) return 0;
  return (today['questions'] as int?) ?? 0;
});
