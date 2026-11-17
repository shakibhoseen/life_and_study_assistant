import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/data/confusable_pairs.dart';
import '../../../../core/data/mistake_kind.dart';
import '../../../../core/database/database_provider.dart';

/// Bumped whenever a tag is set or cleared, so the pattern refetches.
class MistakePatternRevisionNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final mistakePatternRevisionProvider =
    NotifierProvider<MistakePatternRevisionNotifier, int>(
      MistakePatternRevisionNotifier.new,
    );

/// What kinds of mistake the user actually makes, over the last three months.
///
/// Three months rather than everything: a habit fixed in March should stop
/// being described as a habit, and a window is the only thing that lets it.
final mistakePatternProvider = FutureProvider<MistakePattern>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  ref.watch(mistakePatternRevisionProvider);
  return db.getMistakePattern(withinDays: 90);
});

/// The option pairs the user keeps swapping for each other.
///
/// Six months rather than three: a confusion is a slower thing than a habit,
/// and two mix-ups four months apart are still the same two words.
final confusablePairsProvider = FutureProvider<List<ConfusablePair>>((
  ref,
) async {
  final db = ref.watch(appDatabaseProvider);
  ref.watch(mistakePatternRevisionProvider);
  return db.getConfusablePairs(withinDays: 180);
});
