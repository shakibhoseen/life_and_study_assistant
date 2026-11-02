import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/data/study_data_cleanup.dart';

void main() {
  group('canonicalSubject', () {
    test('an English name becomes the Bengali one', () {
      // Ten questions were saved under one and six under the other, so the
      // figures for a single subject were split in two.
      expect(canonicalSubject('Bangladesh Affairs'), 'বাংলাদেশ বিষয়াবলী');
      expect(canonicalSubject('Mathematics'), 'গাণিতিক যুক্তি');
      expect(canonicalSubject('General Science'), 'সাধারণ বিজ্ঞান');
    });

    test('case and spacing do not hide a match', () {
      expect(canonicalSubject('  bangladesh affairs  '), 'বাংলাদেশ বিষয়াবলী');
    });

    test('a subject already in Bengali is left alone', () {
      expect(canonicalSubject('বাংলাদেশ বিষয়াবলী'), 'বাংলাদেশ বিষয়াবলী');
    });

    test('an unknown subject is left alone rather than guessed at', () {
      // Merging two subjects that should have stayed apart is worse than
      // leaving them split.
      expect(
        canonicalSubject('সাম্প্রতিক তথ্য প্র্যাকটিস টেস্ট'),
        'সাম্প্রতিক তথ্য প্র্যাকটিস টেস্ট',
      );
    });
  });

  group('topicMergeKey', () {
    test('two writings of the same topic share a key', () {
      expect(
        topicMergeKey('মধ্যযুগ - মঙ্গলকাব্য (অন্নদামঙ্গল)'),
        topicMergeKey('মধ্যযুগ (মঙ্গলকাব্য ও ভারতচন্দ্র রায়গুণাকর)'),
      );
    });

    test('different topics keep different keys', () {
      expect(
        topicMergeKey('বৃত্ত ও পরিধি'),
        isNot(topicMergeKey('সামান্তরিক ও রম্বস')),
      );
    });

    test('spacing and punctuation do not matter', () {
      expect(
        topicMergeKey('  কারক  ও  বিভক্তি '),
        topicMergeKey('কারক ও বিভক্তি'),
      );
    });
  });

  group('planTopicCleanup', () {
    test('a near-duplicate is merged into the first of its kind', () {
      final plan = planTopicCleanup(const [
        TopicRow(
          id: 1,
          subject: 'Bangla Literature',
          topicName: 'মধ্যযুগ - মঙ্গলকাব্য (অন্নদামঙ্গল)',
        ),
        TopicRow(
          id: 2,
          subject: 'Bangla Literature',
          topicName: 'মধ্যযুগ (মঙ্গলকাব্য ও ভারতচন্দ্র)',
        ),
      ]);

      expect(plan.mergeInto, {2: 1});
      // The one kept still gets its subject corrected.
      expect(plan.renameSubject[1], 'বাংলা সাহিত্য');
    });

    test('an exam title saved as its own topic is dropped', () {
      final plan = planTopicCleanup(const [
        TopicRow(
          id: 3,
          subject: 'বাংলা ১ম পত্র - নির্বাচনী পরীক্ষা ২০২৬',
          topicName: 'বাংলা ১ম পত্র - নির্বাচনী পরীক্ষা ২০২৬',
        ),
      ]);

      expect(plan.drop, [3]);
      // A row being deleted is not also renamed.
      expect(plan.renameSubject.containsKey(3), isFalse);
    });

    test('the same topic under two names for one subject is one topic', () {
      final plan = planTopicCleanup(const [
        TopicRow(
          id: 1,
          subject: 'Bangladesh Affairs',
          topicName: 'বাংলাদেশের নদ-নদী',
        ),
        TopicRow(
          id: 2,
          subject: 'বাংলাদেশ বিষয়াবলী',
          topicName: 'বাংলাদেশের নদ নদী',
        ),
      ]);

      expect(plan.mergeInto, {2: 1});
    });

    test('genuinely different topics are left alone', () {
      final plan = planTopicCleanup(const [
        TopicRow(id: 1, subject: 'গাণিতিক যুক্তি', topicName: 'বৃত্ত ও পরিধি'),
        TopicRow(id: 2, subject: 'গাণিতিক যুক্তি', topicName: 'সামান্তরিক'),
      ]);

      expect(plan.isEmpty, isTrue);
    });

    test('a tidy list needs no changes', () {
      final plan = planTopicCleanup(const [
        TopicRow(id: 1, subject: 'বাংলাদেশ বিষয়াবলী', topicName: 'নদ-নদী'),
      ]);

      expect(plan.isEmpty, isTrue);
      expect(plan.changeCount, 0);
    });
  });
}
