import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/data/syllabus_coverage.dart';
import '../../../../core/data/syllabus_proposals.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/database/tables/syllabus_progress_table.dart';
import '../../../../core/services/syllabus/syllabus_evidence_service.dart';
import '../../../../core/services/syllabus/syllabus_service.dart';

/// Which track the map is showing. Remembered only for the session; the
/// durable choice is which tracks exist, not which tab was open last.
class SelectedSyllabusTrackNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String trackKey) => state = trackKey;
}

final selectedSyllabusTrackProvider =
    NotifierProvider<SelectedSyllabusTrackNotifier, String?>(
      SelectedSyllabusTrackNotifier.new,
    );

/// Everything the map screen needs for one track.
@immutable
class SyllabusMapState {
  final String trackKey;
  final String trackName;
  final List<CoverageSubject> subjects;
  final CoverageTally tally;
  final List<SyllabusProposal> proposals;

  const SyllabusMapState({
    required this.trackKey,
    required this.trackName,
    required this.subjects,
    required this.tally,
    required this.proposals,
  });
}

/// Display names, kept beside the keys so a track with no bundled asset
/// still reads as something.
const Map<String, String> syllabusTrackNames = {
  'primary': 'প্রাথমিক সহকারী শিক্ষক',
  'bcs_preliminary': 'বিসিএস প্রিলিমিনারি',
};

/// The track keys present in the map, seeded on first read.
final syllabusTracksProvider = FutureProvider<List<String>>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  // Seeding is an upsert keyed by nodeKey, so running it whenever the map is
  // opened costs a few writes and keeps a reinstalled or restored database in
  // step with whatever syllabus the installed build ships.
  await SyllabusService.instance.seed(db);
  return SyllabusService.instance.trackKeys(db);
});

/// One track's map, its coverage and the questions worth asking about it.
final syllabusMapProvider = FutureProvider.family<SyllabusMapState, String>((
  ref,
  trackKey,
) async {
  final db = ref.watch(appDatabaseProvider);
  // Re-read whenever a topic is ticked.
  ref.watch(syllabusRevisionProvider);

  final subjects = await SyllabusService.instance.loadCoverage(db, trackKey);
  final statuses = await SyllabusService.instance.statusMap(db);
  final evidence = await SyllabusEvidenceService.instance.gather(db, trackKey);

  return SyllabusMapState(
    trackKey: trackKey,
    trackName: syllabusTrackNames[trackKey] ?? trackKey,
    subjects: subjects,
    tally: tallyTrack(subjects),
    proposals: proposeForTopics(evidence: evidence, current: statuses),
  );
});

/// Bumped on every write so the family provider above refetches.
///
/// A plain counter rather than invalidating the family directly, because the
/// dashboard tile watches a different track than the screen may be showing
/// and both have to move together.
class SyllabusRevisionNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final syllabusRevisionProvider =
    NotifierProvider<SyllabusRevisionNotifier, int>(
      SyllabusRevisionNotifier.new,
    );

class SyllabusMapNotifier extends Notifier<void> {
  @override
  void build() {}

  Future<void> setStatus({
    required String nodeKey,
    required SyllabusStatus status,
    SyllabusProgressSource source = SyllabusProgressSource.self,
  }) async {
    await SyllabusService.instance.setStatus(
      ref.read(appDatabaseProvider),
      nodeKey: nodeKey,
      status: status,
      source: source,
    );
    ref.read(syllabusRevisionProvider.notifier).bump();
  }

  /// Accepts a proposal the user has agreed with.
  ///
  /// Recorded as [SyllabusProgressSource.self] rather than `drill`: the
  /// evidence suggested it, but the claim is the user's once they have said
  /// yes, and the coverage figure should be traceable to a person.
  Future<void> acceptProposal(SyllabusProposal proposal) =>
      setStatus(nodeKey: proposal.nodeKey, status: proposal.suggested);

  /// Marks every topic in a subject at once.
  ///
  /// Topics the user has hidden are left out: "পুরো বিষয় শেষ" is a claim
  /// about the syllabus they kept, and sweeping a removed topic back in would
  /// undo a decision they made deliberately.
  Future<void> setSubject({
    required CoverageSubject subject,
    required SyllabusStatus status,
  }) async {
    final db = ref.read(appDatabaseProvider);
    for (final topic in subject.topics) {
      if (topic.status == SyllabusStatus.hidden) continue;
      await SyllabusService.instance.setStatus(
        db,
        nodeKey: topic.nodeKey,
        status: status,
      );
    }
    ref.read(syllabusRevisionProvider.notifier).bump();
  }

  /// Adds a topic of the user's own. False if the name is empty or already
  /// used in that subject.
  Future<bool> addTopic({
    required String subjectNodeKey,
    required String title,
    int weight = 2,
  }) async {
    final key = await SyllabusService.instance.addCustomTopic(
      ref.read(appDatabaseProvider),
      subjectNodeKey: subjectNodeKey,
      title: title,
      weight: weight,
    );
    if (key != null) ref.read(syllabusRevisionProvider.notifier).bump();
    return key != null;
  }

  Future<bool> editTopic({
    required String nodeKey,
    String? title,
    int? weight,
  }) async {
    final ok = await SyllabusService.instance.editTopic(
      ref.read(appDatabaseProvider),
      nodeKey: nodeKey,
      title: title,
      weight: weight,
    );
    if (ok) ref.read(syllabusRevisionProvider.notifier).bump();
    return ok;
  }

  Future<void> removeTopic(String nodeKey) async {
    await SyllabusService.instance.removeTopic(
      ref.read(appDatabaseProvider),
      nodeKey: nodeKey,
    );
    ref.read(syllabusRevisionProvider.notifier).bump();
  }

  Future<void> restoreTopic(String nodeKey) async {
    await SyllabusService.instance.restoreTopic(
      ref.read(appDatabaseProvider),
      nodeKey: nodeKey,
    );
    ref.read(syllabusRevisionProvider.notifier).bump();
  }
}

final syllabusMapNotifierProvider =
    NotifierProvider<SyllabusMapNotifier, void>(SyllabusMapNotifier.new);
