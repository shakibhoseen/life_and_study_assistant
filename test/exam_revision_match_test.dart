import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/features/dashboard/domain/exam_revision_match.dart';

RevisionCandidate c(String subject, String label) =>
    RevisionCandidate(subject: subject, label: label, source: 'দুর্বল টপিক');

void main() {
  group('revisionForExam', () {
    test('a literature exam picks out the literature topics', () {
      // Tomorrow's real exam, against the real weak-topic list.
      final picked = revisionForExam(
        examTitle: 'পরীক্ষা - ৭২',
        examTopics: 'বাংলা সাহিত্যের আধুনিক যুগের লেখকগণ, গুরুত্বপূর্ণ লেখকগণ: রবীন্দ্রনাথ',
        candidates: [
          c('বাংলা সাহিত্য', 'আধুনিক যুগের লেখকগণ'),
          c('গাণিতিক যুক্তি', 'বৃত্ত ও পরিধি'),
          c('সাধারণ বিজ্ঞান', 'রক্ত সংবহনতন্ত্র'),
        ],
      );

      expect(picked.length, 1);
      expect(picked.single.label, 'আধুনিক যুগের লেখকগণ');
    });

    test('the closest match comes first', () {
      final picked = revisionForExam(
        examTitle: 'গণিত',
        examTopics: 'রেখা, কোণ, ত্রিভুজ ও চতুর্ভুজ সংক্রান্ত উপপাদ্য',
        candidates: [
          c('গাণিতিক যুক্তি', 'ত্রিভুজ ও চতুর্ভুজ উপপাদ্য'),
          c('গাণিতিক যুক্তি', 'কোণ নির্ণয়'),
        ],
      );

      expect(picked.first.label, 'ত্রিভুজ ও চতুর্ভুজ উপপাদ্য');
    });

    test('one shared word is not a match', () {
      // "প্রশ্ন" and "ও" join every sentence; matching on them would put the
      // whole list under every exam.
      final picked = revisionForExam(
        examTitle: 'পরীক্ষা',
        examTopics: 'ত্রিভুজ ও চতুর্ভুজ',
        candidates: [c('সাধারণ বিজ্ঞান', 'রক্ত ও সংবহন')],
      );

      expect(picked, isEmpty);
    });

    test('an exam with nothing in common names nothing', () {
      final picked = revisionForExam(
        examTitle: 'কম্পিউটার',
        examTopics: 'ডাটাবেজ সিস্টেম, কম্পিউটার নেটওয়ার্ক',
        candidates: [c('বাংলা সাহিত্য', 'মধ্যযুগ মঙ্গলকাব্য')],
      );

      expect(picked, isEmpty);
    });

    test('an exam with no topics listed suggests nothing', () {
      expect(
        revisionForExam(
          examTitle: '',
          examTopics: '',
          candidates: [c('বাংলা সাহিত্য', 'মধ্যযুগ')],
        ),
        isEmpty,
      );
    });

    test('the list is capped so the night before stays doable', () {
      final picked = revisionForExam(
        examTitle: 'বাংলা সাহিত্য',
        examTopics: 'বাংলা সাহিত্যের আধুনিক যুগ',
        candidates: [
          for (var i = 0; i < 9; i++)
            c('বাংলা সাহিত্য', 'আধুনিক যুগের অধ্যায় $i'),
        ],
        limit: 5,
      );

      expect(picked.length, 5);
    });
  });
}
