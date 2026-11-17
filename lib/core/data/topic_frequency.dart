/// How often a topic has actually been asked in past papers.
///
/// "High-yield" is a word every guide uses and almost nobody counts. Once
/// the source exam is kept with each imported question, it becomes a count:
/// this topic appeared in these papers, that many times.
class TopicFrequency {
  final String topic;

  /// The distinct exams it has appeared in, sorted so the list reads the
  /// same way each time.
  final List<String> exams;

  /// Questions seen from this topic across those exams.
  final int questions;

  const TopicFrequency({
    required this.topic,
    required this.exams,
    required this.questions,
  });
}
