import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/features/quiz/domain/weak_topic_signal.dart';

({String subject, String topic, bool wasWrong}) answer(
  String topic,
  bool wasWrong, {
  String subject = 'বাংলা',
}) => (subject: subject, topic: topic, wasWrong: wasWrong);

void main() {
  group('tallyByTopic', () {
    test('counts each topic separately', () {
      final tally = tallyByTopic([
        answer('কারক', true),
        answer('কারক', false),
        answer('সমাস', true),
      ]);

      expect(tally.length, 2);
      final karak = tally.firstWhere((t) => t.topic == 'কারক');
      expect(karak.asked, 2);
      expect(karak.wrong, 1);
    });

    test('the same topic written with stray spacing is one topic', () {
      final tally = tallyByTopic([
        answer('কারক', true),
        answer('  কারক ', true),
      ]);

      expect(tally.length, 1);
      expect(tally.single.asked, 2);
    });

    test('an answer with no topic is left out', () {
      expect(tallyByTopic([answer('', true)]), isEmpty);
    });
  });

  group('weakTopicsFromDrill', () {
    test('a topic mostly got wrong counts as weak', () {
      final weak = weakTopicsFromDrill([
        const TopicResult(subject: 'বাংলা', topic: 'কারক', asked: 4, wrong: 3),
      ]);

      expect(weak.single.topic, 'কারক');
    });

    test('a single slip is not weakness', () {
      // One wrong out of four is a slip, and flooding the list with those
      // makes it useless.
      final weak = weakTopicsFromDrill([
        const TopicResult(subject: 'বাংলা', topic: 'কারক', asked: 4, wrong: 1),
      ]);

      expect(weak, isEmpty);
    });

    test('a topic asked once is not judged on it', () {
      final weak = weakTopicsFromDrill([
        const TopicResult(subject: 'বাংলা', topic: 'সমাস', asked: 1, wrong: 1),
      ]);

      expect(weak, isEmpty);
    });

    test('the worst topic comes first', () {
      final weak = weakTopicsFromDrill([
        const TopicResult(subject: 'ব', topic: 'অর্ধেক', asked: 4, wrong: 2),
        const TopicResult(subject: 'ব', topic: 'সবটাই', asked: 3, wrong: 3),
      ]);

      expect(weak.map((t) => t.topic), ['সবটাই', 'অর্ধেক']);
    });

    test('a clean drill names nobody', () {
      final weak = weakTopicsFromDrill([
        const TopicResult(subject: 'ব', topic: 'কারক', asked: 5, wrong: 0),
      ]);

      expect(weak, isEmpty);
    });
  });
}
