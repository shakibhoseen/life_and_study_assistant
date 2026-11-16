/// Deciding what to *ask* the user about a topic — never what to tick.
///
/// Coverage is a claim about the user's own knowledge, so the app does not
/// get to make it on their behalf. What it can do is notice evidence and put
/// a question in front of them: you have answered nine questions on সমাস and
/// got eight right — shall I mark it done?
///
/// Everything here returns a proposal. Writing one in is a separate, explicit
/// act in the service, triggered by the user's answer. That split is the
/// whole point: a number the app talked itself into is worse than no number,
/// because it is believed.
library;

import '../database/tables/syllabus_progress_table.dart';
import '../utils/bengali_math_sanitizer.dart';

String _bn(int value) => BengaliMathSanitizer.toBengaliDigits('$value');

/// Evidence gathered for one topic from what the user has actually done.
class TopicEvidence {
  final String nodeKey;
  final String title;

  /// Distinct questions attempted whose topic matches this node.
  final int attempted;

  /// How many of those were answered correctly.
  final int correct;

  /// The topic is on the user's weak list.
  final bool isWeakTopic;

  /// An exam in this track covering this topic has been marked complete.
  final bool examCompleted;

  const TopicEvidence({
    required this.nodeKey,
    required this.title,
    this.attempted = 0,
    this.correct = 0,
    this.isWeakTopic = false,
    this.examCompleted = false,
  });

  double get accuracy => attempted == 0 ? 0 : correct / attempted;
}

/// A question to put to the user, with the reason that prompted it.
class SyllabusProposal {
  final String nodeKey;
  final String title;
  final SyllabusStatus suggested;

  /// Why, in the app's language, ready to show. The user should be able to
  /// disagree with the reason, not just the conclusion.
  final String reason;

  const SyllabusProposal({
    required this.nodeKey,
    required this.title,
    required this.suggested,
    required this.reason,
  });
}

/// Questions attempted before performance is worth reading at all.
///
/// Two right out of two is not evidence of anything; it is the number of
/// questions a single lucky screen can produce.
const int proposeDoneMinAttempts = 6;

/// Accuracy at or above which a topic is worth asking about.
const double proposeDoneMinAccuracy = 0.75;

/// Attempts that suggest the user has at least opened the topic.
const int proposeReadingMinAttempts = 3;

/// What, if anything, to ask about one topic.
///
/// Returns null when there is nothing worth interrupting the user for: no
/// evidence, or evidence that only confirms where the topic already sits.
SyllabusProposal? proposeForTopic({
  required TopicEvidence evidence,
  required SyllabusStatus current,
}) {
  // A topic the user has called done stays done. Getting a later question
  // wrong is a reason to revise it, which the weak-topic and review machinery
  // already handles — it is not a reason to tell someone they have un-read a
  // chapter.
  if (current == SyllabusStatus.done) return null;

  // A topic the user is struggling with should not be proposed as finished
  // however many questions they have seen.
  if (evidence.isWeakTopic) return null;

  if (evidence.attempted >= proposeDoneMinAttempts &&
      evidence.accuracy >= proposeDoneMinAccuracy) {
    final percent = (evidence.accuracy * 100).round();
    return SyllabusProposal(
      nodeKey: evidence.nodeKey,
      title: evidence.title,
      suggested: SyllabusStatus.done,
      reason:
          'এই টপিকে ${_bn(evidence.attempted)}টি প্রশ্নের মধ্যে '
          '${_bn(evidence.correct)}টি সঠিক (${_bn(percent)}%)।',
    );
  }

  if (current == SyllabusStatus.notStarted) {
    if (evidence.examCompleted) {
      return SyllabusProposal(
        nodeKey: evidence.nodeKey,
        title: evidence.title,
        suggested: SyllabusStatus.reading,
        reason: 'এই টপিকের একটি পরীক্ষা আপনি সম্পন্ন করেছেন।',
      );
    }
    if (evidence.attempted >= proposeReadingMinAttempts) {
      return SyllabusProposal(
        nodeKey: evidence.nodeKey,
        title: evidence.title,
        suggested: SyllabusStatus.reading,
        reason:
          'এই টপিকে ইতিমধ্যে ${_bn(evidence.attempted)}টি প্রশ্ন দিয়েছেন।',
      );
    }
  }

  return null;
}

/// Proposals for a batch, strongest evidence first.
///
/// Ordered so that a user who answers only the first few gets the questions
/// that move the coverage figure most — a "done" proposal backed by many
/// attempts before a "reading" one backed by three.
List<SyllabusProposal> proposeForTopics({
  required List<TopicEvidence> evidence,
  required Map<String, SyllabusStatus> current,
}) {
  final out = <(SyllabusProposal, double)>[];
  for (final e in evidence) {
    final proposal = proposeForTopic(
      evidence: e,
      current: current[e.nodeKey] ?? SyllabusStatus.notStarted,
    );
    if (proposal == null) continue;
    final rank = proposal.suggested == SyllabusStatus.done
        ? 1000.0 + e.attempted
        : e.attempted.toDouble();
    out.add((proposal, rank));
  }
  out.sort((a, b) => b.$2.compareTo(a.$2));
  return out.map((e) => e.$1).toList();
}
