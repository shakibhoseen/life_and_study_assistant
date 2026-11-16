import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/data/syllabus_coverage.dart';
import '../../../../core/data/syllabus_proposals.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/database/tables/syllabus_progress_table.dart';
import '../../../../core/services/syllabus/syllabus_evidence_service.dart';
import '../../../../core/services/syllabus/syllabus_draft_service.dart';
import '../../../../core/services/syllabus/syllabus_service.dart';

/// Which track the map is showing. Remembered only for the session; the
/// durable choice is which tracks exist, not which tab was open last.
class SelectedSyllabusTrackNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  /// Null goes back to whichever track the list shows first — what the
  /// screen needs after the selected track is deleted.
  void select(String? trackKey) => state = trackKey;
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

  /// Where the mark distribution came from, or that it is an unchecked draft.
  final String note;

  /// A track the user made: its subjects can be added to and removed, and the
  /// track itself renamed or deleted.
  final bool isCustom;

  final List<CoverageSubject> subjects;
  final CoverageTally tally;
  final List<SyllabusProposal> proposals;

  const SyllabusMapState({
    required this.trackKey,
    required this.trackName,
    required this.note,
    required this.isCustom,
    required this.subjects,
    required this.tally,
    required this.proposals,
  });
}

/// Every track, bundled and the user's own.
///
/// Names used to live in a const map here, which worked only while every
/// track shipped with the app. They come from the database now, so a track
/// the user adds is a track like any other.
final syllabusTracksProvider = FutureProvider<List<SyllabusTrackRow>>((
  ref,
) async {
  final db = ref.watch(appDatabaseProvider);
  ref.watch(syllabusRevisionProvider);
  // Seeding is an upsert keyed by nodeKey, so running it whenever the map is
  // opened costs a few writes and keeps a reinstalled or restored database in
  // step with whatever syllabus the installed build ships.
  await SyllabusService.instance.seed(db);
  return SyllabusService.instance.tracks(db);
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
  final row = await SyllabusService.instance.trackByKey(db, trackKey);

  return SyllabusMapState(
    trackKey: trackKey,
    trackName: row?.name ?? trackKey,
    note: row?.note ?? '',
    isCustom: row?.isCustom ?? false,
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

  /// Creates an exam of the user's own, empty.
  Future<String?> createTrack({required String name}) async {
    final key = await SyllabusService.instance.createTrack(
      ref.read(appDatabaseProvider),
      name: name,
    );
    if (key != null) ref.read(syllabusRevisionProvider.notifier).bump();
    return key;
  }

  /// Creates one from another track's subjects and topics, without its ticks.
  Future<String?> copyTrack({
    required String sourceTrackKey,
    required String name,
  }) async {
    final key = await SyllabusService.instance.copyTrack(
      ref.read(appDatabaseProvider),
      sourceTrackKey: sourceTrackKey,
      name: name,
    );
    if (key != null) ref.read(syllabusRevisionProvider.notifier).bump();
    return key;
  }

  /// Asks the model for a syllabus and creates the track from it.
  ///
  /// Throws [SyllabusDraftException] with something sayable when the draft
  /// cannot be produced. The track is created only once a usable draft is in
  /// hand, so a failure leaves nothing behind to clean up.
  Future<String?> draftTrack({required String name}) async {
    final draft = await SyllabusDraftService.instance.draft(name);
    final key = await SyllabusService.instance.createTrackFrom(
      ref.read(appDatabaseProvider),
      name: draft.trackName.trim().isEmpty ? name : draft.trackName,
      note: SyllabusDraftService.draftNote,
      subjects: draft.subjects,
    );
    if (key != null) ref.read(syllabusRevisionProvider.notifier).bump();
    return key;
  }

  Future<bool> renameTrack({
    required String trackKey,
    required String name,
  }) async {
    final ok = await SyllabusService.instance.renameTrack(
      ref.read(appDatabaseProvider),
      trackKey: trackKey,
      name: name,
    );
    if (ok) ref.read(syllabusRevisionProvider.notifier).bump();
    return ok;
  }

  Future<bool> deleteTrack(String trackKey) async {
    final ok = await SyllabusService.instance.deleteTrack(
      ref.read(appDatabaseProvider),
      trackKey: trackKey,
    );
    if (ok) {
      // The screen is showing a track that no longer exists.
      ref.read(selectedSyllabusTrackProvider.notifier).select(null);
      ref.read(syllabusRevisionProvider.notifier).bump();
    }
    return ok;
  }

  Future<bool> addSubject({
    required String trackKey,
    required String name,
    required int marks,
  }) async {
    final key = await SyllabusService.instance.addSubject(
      ref.read(appDatabaseProvider),
      trackKey: trackKey,
      name: name,
      marks: marks,
    );
    if (key != null) ref.read(syllabusRevisionProvider.notifier).bump();
    return key != null;
  }

  Future<bool> editSubject({
    required String nodeKey,
    String? name,
    int? marks,
  }) async {
    final ok = await SyllabusService.instance.editSubject(
      ref.read(appDatabaseProvider),
      nodeKey: nodeKey,
      name: name,
      marks: marks,
    );
    if (ok) ref.read(syllabusRevisionProvider.notifier).bump();
    return ok;
  }

  Future<bool> removeSubject(String nodeKey) async {
    final ok = await SyllabusService.instance.removeSubject(
      ref.read(appDatabaseProvider),
      nodeKey: nodeKey,
    );
    if (ok) ref.read(syllabusRevisionProvider.notifier).bump();
    return ok;
  }
}

final syllabusMapNotifierProvider =
    NotifierProvider<SyllabusMapNotifier, void>(SyllabusMapNotifier.new);
