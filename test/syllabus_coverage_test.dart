import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/data/syllabus_coverage.dart';
import 'package:life_and_study_assistant/core/data/syllabus_proposals.dart';
import 'package:life_and_study_assistant/core/database/tables/syllabus_progress_table.dart';

/// The arithmetic behind "আপনি কতটা শেষ করেছেন".
///
/// Worth its own tests because every reader of this feature — the screen, the
/// dashboard tile, the widget, eventually the mentor — has to agree on the
/// number, and because the two ways of getting it wrong (counting topics
/// instead of marks, and quietly crediting half-read topics) both produce a
/// figure that looks plausible and flatters the user.
void main() {
  CoverageTopic topic(String title, int weight, SyllabusStatus status) =>
      CoverageTopic(
        nodeKey: 'track/subject/$title',
        title: title,
        weight: weight,
        status: status,
      );

  group('subject coverage', () {
    test('weights topics rather than counting them', () {
      final subject = CoverageSubject(
        nodeKey: 'k',
        name: 'গণিত',
        marks: 20,
        topics: [
          topic('ভারী', 6, SyllabusStatus.done),
          topic('হালকা ১', 1, SyllabusStatus.notStarted),
          topic('হালকা ২', 1, SyllabusStatus.notStarted),
          topic('হালকা ৩', 2, SyllabusStatus.notStarted),
        ],
      );

      final tally = tallySubject(subject);

      // One topic of four is done, but it carries six of the ten weight.
      expect(tally.doneTopics, 1);
      expect(tally.doneFraction, closeTo(0.6, 1e-9));
      expect(tally.marksCovered, closeTo(12.0, 1e-9));
    });

    test('reading is reported apart and never counted as done', () {
      final subject = CoverageSubject(
        nodeKey: 'k',
        name: 'বাংলা',
        marks: 10,
        topics: [
          topic('ক', 1, SyllabusStatus.done),
          topic('খ', 1, SyllabusStatus.reading),
          topic('গ', 1, SyllabusStatus.reading),
          topic('ঘ', 1, SyllabusStatus.notStarted),
        ],
      );

      final tally = tallySubject(subject);

      expect(tally.doneFraction, closeTo(0.25, 1e-9));
      expect(tally.readingFraction, closeTo(0.5, 1e-9));
      expect(tally.doneTopics, 1);
      expect(tally.readingTopics, 2);
      expect(tally.untouchedTopics, 1);
      // The headline must not borrow from the lighter segment.
      expect(tally.donePercent, 25);
    });

    test('a subject with no topics is zero, not complete', () {
      final tally = tallySubject(
        const CoverageSubject(nodeKey: 'k', name: 'খালি', marks: 15, topics: []),
      );

      expect(tally.doneFraction, 0);
      expect(tally.marksCovered, 0);
      expect(tally.marksTotal, 15);
    });

    test('a zero weight is treated as one rather than vanishing', () {
      final subject = CoverageSubject(
        nodeKey: 'k',
        name: 'বিজ্ঞান',
        marks: 10,
        topics: [
          topic('ভালো', 1, SyllabusStatus.done),
          topic('ওজনহীন', 0, SyllabusStatus.notStarted),
        ],
      );

      // If the zero-weight topic dropped out of the denominator this would
      // read 100% while half the subject is untouched.
      expect(tallySubject(subject).doneFraction, closeTo(0.5, 1e-9));
    });
  });

  group('track coverage', () {
    List<CoverageSubject> track() => [
      CoverageSubject(
        nodeKey: 'a',
        name: 'ভারী বিষয়',
        marks: 35,
        topics: [topic('ক', 1, SyllabusStatus.done)],
      ),
      CoverageSubject(
        nodeKey: 'b',
        name: 'হালকা বিষয়',
        marks: 5,
        topics: [topic('খ', 1, SyllabusStatus.notStarted)],
      ),
    ];

    test('weights subjects by their exam marks', () {
      final tally = tallyTrack(track());

      // One subject of two is finished, but it is 35 of the 40 marks.
      expect(tally.doneFraction, closeTo(35 / 40, 1e-9));
      expect(tally.marksCovered, closeTo(35.0, 1e-9));
      expect(tally.marksTotal, 40);
      expect(tally.totalTopics, 2);
    });

    test('an empty track is empty rather than throwing', () {
      expect(tallyTrack(const []).doneFraction, 0);
      expect(tallyTrack(const []).marksTotal, 0);
    });

    test('orders subjects by the marks still uncovered', () {
      final ordered = subjectsByUncoveredMarks(track());

      // The heavy subject is finished, so the light one has more missing.
      expect(ordered.first.name, 'হালকা বিষয়');
    });
  });

  group('proposals', () {
    TopicEvidence evidence({
      int attempted = 0,
      int correct = 0,
      bool weak = false,
      bool exam = false,
    }) => TopicEvidence(
      nodeKey: 'track/subject/সমাস',
      title: 'সমাস',
      attempted: attempted,
      correct: correct,
      isWeakTopic: weak,
      examCompleted: exam,
    );

    test('suggests done on sustained accuracy', () {
      final proposal = proposeForTopic(
        evidence: evidence(attempted: 9, correct: 8),
        current: SyllabusStatus.notStarted,
      );

      expect(proposal, isNotNull);
      expect(proposal!.suggested, SyllabusStatus.done);
      expect(proposal.reason, contains('৯'));
    });

    test('a short lucky run is not evidence', () {
      expect(
        proposeForTopic(
          evidence: evidence(attempted: 2, correct: 2),
          current: SyllabusStatus.notStarted,
        ),
        isNull,
      );
    });

    test('never proposes done for a topic on the weak list', () {
      expect(
        proposeForTopic(
          evidence: evidence(attempted: 20, correct: 19, weak: true),
          current: SyllabusStatus.notStarted,
        ),
        isNull,
      );
    });

    test('leaves a finished topic alone however it is answered later', () {
      expect(
        proposeForTopic(
          evidence: evidence(attempted: 10, correct: 1),
          current: SyllabusStatus.done,
        ),
        isNull,
      );
    });

    test('a few attempts suggest reading, not done', () {
      final proposal = proposeForTopic(
        evidence: evidence(attempted: 4, correct: 1),
        current: SyllabusStatus.notStarted,
      );

      expect(proposal!.suggested, SyllabusStatus.reading);
    });

    test('a completed exam suggests reading with no questions at all', () {
      final proposal = proposeForTopic(
        evidence: evidence(exam: true),
        current: SyllabusStatus.notStarted,
      );

      expect(proposal!.suggested, SyllabusStatus.reading);
      expect(proposal.reason, contains('পরীক্ষা'));
    });

    test('does not re-suggest reading for a topic already being read', () {
      expect(
        proposeForTopic(
          evidence: evidence(attempted: 4, correct: 1),
          current: SyllabusStatus.reading,
        ),
        isNull,
      );
    });

    test('batches put the strongest evidence first', () {
      final proposals = proposeForTopics(
        evidence: [
          const TopicEvidence(nodeKey: 'a', title: 'ক', attempted: 4),
          const TopicEvidence(
            nodeKey: 'b',
            title: 'খ',
            attempted: 8,
            correct: 7,
          ),
          const TopicEvidence(nodeKey: 'c', title: 'গ', attempted: 3),
        ],
        current: const {},
      );

      expect(proposals.map((p) => p.nodeKey), ['b', 'a', 'c']);
      expect(proposals.first.suggested, SyllabusStatus.done);
    });
  });
}
