import 'package:drift/drift.dart';

/// Marks a row as a mistake dictated into the voice bubble rather than a
/// question answered here.
///
/// It is a prefix on [DrillQuestions.explanation], which is where it has
/// always been written; a column of its own would say it better, but this
/// project has no code generation set up and the tag already covers every row
/// ever saved this way, including the ones from before it had to be told
/// apart. Both the writer and [AppDatabase.getDrillStats] use this constant,
/// so the two cannot drift apart.
const String voiceMistakeSourceTag = '[উৎস: LiveMCQ 🎙️]';

/// What every one of those tags begins with.
///
/// There is more than one — dictating a mistake writes 🎙️ and photographing
/// one writes 📸 — and neither was answered here, so the statistics have to
/// recognise the whole family rather than the one spelling.
const String capturedMistakeTagPrefix = '[উৎস:';

@TableIndex(
  name: 'idx_drill_questions_correct_mastered',
  columns: {#isCorrect, #isMastered},
)
@TableIndex(name: 'idx_drill_questions_record_id', columns: {#drillRecordId})
class DrillQuestions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get drillRecordId => integer().nullable()();
  TextColumn get subject => text().withLength(min: 1, max: 100)();
  TextColumn get topic => text().withLength(min: 1, max: 200)();
  TextColumn get questionText => text()();
  TextColumn get optionsJson =>
      text()(); // JSON List of strings e.g. ["A","B","C","D"]
  IntColumn get correctIndex => integer()();
  IntColumn get selectedIndex => integer()();
  BoolColumn get isCorrect => boolean()();
  TextColumn get explanation => text().withDefault(const Constant(''))();
  BoolColumn get isMastered => boolean().withDefault(const Constant(false))();
  DateTimeColumn get attemptedAt =>
      dateTime().withDefault(currentDateAndTime)();

  /// What [correctIndex] and [explanation] held before a verification
  /// correction was accepted. Null until one is.
  ///
  /// [selectedIndex] and [isCorrect] are never rewritten: they record what
  /// the user answered and how it was scored at the time, and a later
  /// correction to the question does not change what happened in that
  /// attempt.
  IntColumn get originalCorrectIndex => integer().nullable()();
  TextColumn get originalExplanation => text().nullable()();
  TextColumn get originalQuestionText => text().nullable()();
  TextColumn get originalOptionsJson => text().nullable()();
  DateTimeColumn get correctedAt => dateTime().nullable()();

  /// The last verification's outcome, kept so reopening the sheet shows what
  /// was already found instead of paying for the same check again.
  TextColumn get verificationStatus => text().nullable()();
  TextColumn get verificationNote => text().nullable()();
  DateTimeColumn get verifiedAt => dateTime().nullable()();
}
