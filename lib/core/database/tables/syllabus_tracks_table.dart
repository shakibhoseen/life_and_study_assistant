import 'package:drift/drift.dart';

/// An exam whose syllabus the user is tracking.
///
/// Tracks used to exist only as a `trackKey` repeated on every node, with
/// their display names in a const map in the provider. That was workable
/// while every track shipped with the app; it stops being workable the
/// moment the user can add প্রধান শিক্ষক or NTRCA themselves, because a
/// track they made has no entry in anybody's const map.
///
/// So a track is a row. Bundled ones are seeded from
/// `assets/data/syllabus/*.json` and refreshed in place; [isCustom] marks the
/// ones the user made, which the seed never touches and the prune never
/// removes — the same bargain their topics already have.
/// The row class is named explicitly: drift would otherwise call it
/// `SyllabusTrack`, which is already the name of the parsed-asset model in
/// syllabus_service.dart. Two different shapes under one name, one of them
/// generated, is a confusion worth a line of configuration.
@DataClassName('SyllabusTrackRow')
class SyllabusTracks extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Stable identity, and what every node's `trackKey` points at. For a
  /// custom track this is generated once at creation and never derived from
  /// the name, so renaming an exam cannot orphan its syllabus.
  TextColumn get trackKey => text().withLength(min: 1, max: 100)();

  TextColumn get name => text().withLength(min: 1, max: 200)();

  /// Free text shown under the track: where the mark distribution came from,
  /// or a warning that a draft has not been checked.
  TextColumn get note => text().withDefault(const Constant(''))();

  BoolColumn get isCustom => boolean().withDefault(const Constant(false))();

  IntColumn get orderIndex => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {trackKey},
  ];
}
