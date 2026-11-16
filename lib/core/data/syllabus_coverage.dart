/// Turning a pile of ticks into a number that means something.
///
/// Two decisions are made here rather than in the UI, because both are easy
/// to get subtly wrong and neither should differ between the screen, the
/// widget and the mentor's answer.
///
/// **Marks, not topic counts.** A subject's share of the exam is its marks,
/// and a topic's share of its subject is its weight. Finishing twenty light
/// topics and finishing six heavy ones are not the same progress, and a
/// count would call them equal.
///
/// **"Reading" is never folded into "done".** It is reported alongside, so a
/// bar can show it as a lighter segment, but the headline figure counts only
/// what the user has said is finished. Half-credit for a half-read topic is
/// exactly the flattery that makes a coverage number worthless the week
/// before an exam.
library;

import '../database/tables/syllabus_progress_table.dart';

/// A topic as coverage sees it: its weight and where the user has put it.
class CoverageTopic {
  final String nodeKey;
  final String title;
  final int weight;
  final SyllabusStatus status;

  const CoverageTopic({
    required this.nodeKey,
    required this.title,
    required this.weight,
    this.status = SyllabusStatus.notStarted,
  });
}

/// A subject and its topics.
class CoverageSubject {
  final String nodeKey;
  final String name;
  final int marks;
  final List<CoverageTopic> topics;

  const CoverageSubject({
    required this.nodeKey,
    required this.name,
    required this.marks,
    required this.topics,
  });
}

/// What a subject or a whole track adds up to.
class CoverageTally {
  /// Weighted share of the topics marked done, 0..1.
  final double doneFraction;

  /// Weighted share marked as being read, 0..1. Never included in
  /// [doneFraction]; the two together cannot exceed 1.
  final double readingFraction;

  final int doneTopics;
  final int readingTopics;
  final int totalTopics;

  /// Exam marks this covers: the subject's marks scaled by [doneFraction],
  /// or the sum of that across a track.
  final double marksCovered;

  /// Marks in scope — the subject's marks, or the track's total.
  final int marksTotal;

  const CoverageTally({
    required this.doneFraction,
    required this.readingFraction,
    required this.doneTopics,
    required this.readingTopics,
    required this.totalTopics,
    required this.marksCovered,
    required this.marksTotal,
  });

  static const CoverageTally empty = CoverageTally(
    doneFraction: 0,
    readingFraction: 0,
    doneTopics: 0,
    readingTopics: 0,
    totalTopics: 0,
    marksCovered: 0,
    marksTotal: 0,
  );

  /// The headline percentage, rounded for display.
  int get donePercent => (doneFraction * 100).round();

  int get untouchedTopics => totalTopics - doneTopics - readingTopics;
}

/// Coverage of one subject.
///
/// A subject with no topics is 0%, not 100%: an empty map is an unknown
/// syllabus, not a finished one.
CoverageTally tallySubject(CoverageSubject subject) {
  var totalWeight = 0;
  var doneWeight = 0;
  var readingWeight = 0;
  var done = 0;
  var reading = 0;

  for (final topic in subject.topics) {
    // A weight of zero or less would silently drop the topic from the
    // denominator and make the subject look complete without it.
    final weight = topic.weight > 0 ? topic.weight : 1;
    totalWeight += weight;
    switch (topic.status) {
      case SyllabusStatus.done:
        doneWeight += weight;
        done++;
      case SyllabusStatus.reading:
        readingWeight += weight;
        reading++;
      case SyllabusStatus.notStarted:
        break;
    }
  }

  if (totalWeight == 0) {
    return CoverageTally(
      doneFraction: 0,
      readingFraction: 0,
      doneTopics: 0,
      readingTopics: 0,
      totalTopics: 0,
      marksCovered: 0,
      marksTotal: subject.marks,
    );
  }

  final doneFraction = doneWeight / totalWeight;
  return CoverageTally(
    doneFraction: doneFraction,
    readingFraction: readingWeight / totalWeight,
    doneTopics: done,
    readingTopics: reading,
    totalTopics: subject.topics.length,
    marksCovered: subject.marks * doneFraction,
    marksTotal: subject.marks,
  );
}

/// Coverage of a whole track, weighted by each subject's marks.
///
/// A subject carrying no marks still contributes its topics to the counts but
/// nothing to the percentage — which is right: an unweighted subject is not
/// part of the exam's score.
CoverageTally tallyTrack(List<CoverageSubject> subjects) {
  if (subjects.isEmpty) return CoverageTally.empty;

  var marksTotal = 0;
  var marksCovered = 0.0;
  var marksReading = 0.0;
  var done = 0;
  var reading = 0;
  var total = 0;

  for (final subject in subjects) {
    final tally = tallySubject(subject);
    marksTotal += subject.marks;
    marksCovered += tally.marksCovered;
    marksReading += subject.marks * tally.readingFraction;
    done += tally.doneTopics;
    reading += tally.readingTopics;
    total += tally.totalTopics;
  }

  return CoverageTally(
    doneFraction: marksTotal == 0 ? 0 : marksCovered / marksTotal,
    readingFraction: marksTotal == 0 ? 0 : marksReading / marksTotal,
    doneTopics: done,
    readingTopics: reading,
    totalTopics: total,
    marksCovered: marksCovered,
    marksTotal: marksTotal,
  );
}

/// Subjects ordered by how much exam weight is still uncovered.
///
/// This is the question the map exists to answer — not "what am I worst at"
/// but "where is the most of the exam still missing", which with marks in
/// hand is a different and more useful list.
List<CoverageSubject> subjectsByUncoveredMarks(List<CoverageSubject> subjects) {
  final scored = subjects
      .map((s) => (s, s.marks * (1 - tallySubject(s).doneFraction)))
      .toList()
    ..sort((a, b) => b.$2.compareTo(a.$2));
  return scored.map((e) => e.$1).toList();
}
