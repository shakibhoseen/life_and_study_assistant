/// One topic's showing in a drill.
class TopicResult {
  final String subject;
  final String topic;
  final int asked;
  final int wrong;

  const TopicResult({
    required this.subject,
    required this.topic,
    required this.asked,
    required this.wrong,
  });

  double get wrongShare => asked == 0 ? 0 : wrong / asked;
}

/// Which topics a drill says the user is weak at.
///
/// The app has a weak-topics list and a healing drill built on top of it, but
/// nothing was feeding it from the richest signal there is: what the user
/// actually gets wrong. Topics arrived only from spoken mistakes, the chat,
/// a scanned sheet, or being typed in by hand.
///
/// A single slip is not weakness, so a topic has to be asked at least
/// [minAsked] times and be wrong at least [minWrong] times and in at least
/// [minShare] of them. That keeps a twenty-question drill from dumping every
/// topic it touched into the list.
List<TopicResult> weakTopicsFromDrill(
  List<TopicResult> results, {
  int minAsked = 2,
  int minWrong = 2,
  double minShare = 0.5,
}) {
  final weak = results
      .where(
        (r) =>
            r.asked >= minAsked &&
            r.wrong >= minWrong &&
            r.wrongShare >= minShare,
      )
      .toList();

  // Worst first, so the one worth starting on is at the top.
  weak.sort((a, b) {
    final byShare = b.wrongShare.compareTo(a.wrongShare);
    return byShare != 0 ? byShare : b.wrong.compareTo(a.wrong);
  });
  return weak;
}

/// Groups a drill's answers by topic.
List<TopicResult> tallyByTopic(
  List<({String subject, String topic, bool wasWrong})> answers,
) {
  final asked = <String, int>{};
  final wrong = <String, int>{};
  final labels = <String, (String, String)>{};

  for (final answer in answers) {
    final subject = answer.subject.trim();
    final topic = answer.topic.trim();
    if (topic.isEmpty) continue;
    final key = '${subject.toLowerCase()}|${topic.toLowerCase()}';
    labels[key] = (subject, topic);
    asked[key] = (asked[key] ?? 0) + 1;
    if (answer.wasWrong) wrong[key] = (wrong[key] ?? 0) + 1;
  }

  return [
    for (final entry in asked.entries)
      TopicResult(
        subject: labels[entry.key]!.$1,
        topic: labels[entry.key]!.$2,
        asked: entry.value,
        wrong: wrong[entry.key] ?? 0,
      ),
  ];
}
