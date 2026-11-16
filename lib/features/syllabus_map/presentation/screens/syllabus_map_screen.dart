import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/data/syllabus_coverage.dart';
import '../../../../core/data/syllabus_proposals.dart';
import '../../../../core/database/tables/syllabus_progress_table.dart';
import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/utils/bengali_math_sanitizer.dart';
import '../providers/syllabus_map_provider.dart';
import '../widgets/coverage_bar.dart';
import '../widgets/topic_edit_sheet.dart';

String _bn(int value) => BengaliMathSanitizer.toBengaliDigits('$value');

/// The syllabus map: what the exam asks for, and how much of it is done.
class SyllabusMapScreen extends ConsumerWidget {
  const SyllabusMapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(syllabusTracksProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('সিলেবাস ম্যাপ')),
      body: tracks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Message('সিলেবাস খোলা গেল না।\n$e'),
        data: (keys) {
          if (keys.isEmpty) {
            return const _Message('কোনো সিলেবাস পাওয়া যায়নি।');
          }
          final selected =
              ref.watch(selectedSyllabusTrackProvider) ?? keys.first;
          return Column(
            children: [
              if (keys.length > 1)
                _TrackPicker(
                  keys: keys,
                  selected: selected,
                  onChanged: (key) => ref
                      .read(selectedSyllabusTrackProvider.notifier)
                      .select(key),
                ),
              Expanded(child: _TrackBody(trackKey: selected)),
            ],
          );
        },
      ),
    );
  }
}

class _TrackPicker extends StatelessWidget {
  final List<String> keys;
  final String selected;
  final ValueChanged<String> onChanged;

  const _TrackPicker({
    required this.keys,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        FluentSpacing.l,
        FluentSpacing.m,
        FluentSpacing.l,
        0,
      ),
      child: Row(
        children: keys.map((key) {
          return Padding(
            padding: const EdgeInsets.only(right: FluentSpacing.s),
            child: ChoiceChip(
              label: Text(syllabusTrackNames[key] ?? key),
              selected: key == selected,
              onSelected: (_) => onChanged(key),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _TrackBody extends ConsumerWidget {
  final String trackKey;

  const _TrackBody({required this.trackKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final map = ref.watch(syllabusMapProvider(trackKey));

    return map.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _Message('ম্যাপ পড়া গেল না।\n$e'),
      data: (state) {
        final ordered = subjectsByUncoveredMarks(state.subjects);
        return ListView(
          padding: const EdgeInsets.all(FluentSpacing.l),
          children: [
            _TrackHeader(state: state),
            if (state.proposals.isNotEmpty) ...[
              const SizedBox(height: FluentSpacing.l),
              _ProposalCard(proposals: state.proposals),
            ],
            const SizedBox(height: FluentSpacing.l),
            Text(
              'যে বিষয়ে সবচেয়ে বেশি নম্বর বাকি, সেটি উপরে',
              style: FluentType.caption.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: FluentSpacing.s),
            ...ordered.map((subject) => _SubjectTile(subject: subject)),
            const SizedBox(height: FluentSpacing.xxl),
          ],
        );
      },
    );
  }
}

class _TrackHeader extends StatelessWidget {
  final SyllabusMapState state;

  const _TrackHeader({required this.state});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tally = state.tally;

    return Container(
      padding: const EdgeInsets.all(FluentSpacing.l),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(FluentRadius.card),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(state.trackName, style: FluentType.subtitle),
          const SizedBox(height: FluentSpacing.xs),
          Text(
            '${_bn(tally.doneTopics)}টি টপিক শেষ, '
            '${_bn(tally.totalTopics)}টির মধ্যে',
            style: FluentType.caption.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: FluentSpacing.m),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${_bn(tally.donePercent)}%',
                style: FluentType.title.copyWith(color: scheme.primary),
              ),
              const SizedBox(width: FluentSpacing.s),
              Padding(
                padding: const EdgeInsets.only(bottom: FluentSpacing.xs),
                child: CoverageCaption(tally: tally, toBengali: _bn),
              ),
            ],
          ),
          const SizedBox(height: FluentSpacing.s),
          CoverageBar(tally: tally, height: 10),
        ],
      ),
    );
  }
}

/// The "ask me" half of the feature.
///
/// Shown only when there is evidence worth a question. Each card states the
/// reason as well as the suggestion, so the user is agreeing with something
/// they can check rather than waving through a number.
class _ProposalCard extends ConsumerWidget {
  final List<SyllabusProposal> proposals;

  const _ProposalCard({required this.proposals});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final shown = proposals.take(3).toList();

    return Container(
      padding: const EdgeInsets.all(FluentSpacing.l),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(FluentRadius.card),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.help_outline, size: 18, color: scheme.primary),
              const SizedBox(width: FluentSpacing.s),
              Expanded(
                child: Text('একটু জিজ্ঞেস করি', style: FluentType.bodyStrong),
              ),
              if (proposals.length > shown.length)
                Text(
                  '+${_bn(proposals.length - shown.length)}',
                  style: FluentType.caption.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: FluentSpacing.m),
          ...shown.map(
            (proposal) => Padding(
              padding: const EdgeInsets.only(bottom: FluentSpacing.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    proposal.suggested == SyllabusStatus.done
                        ? '"${proposal.title}" কি শেষ?'
                        : '"${proposal.title}" কি পড়ছেন?',
                    style: FluentType.body,
                  ),
                  const SizedBox(height: FluentSpacing.xxs),
                  Text(
                    proposal.reason,
                    style: FluentType.caption.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: FluentSpacing.xs),
                  Row(
                    children: [
                      FilledButton.tonal(
                        onPressed: () => ref
                            .read(syllabusMapNotifierProvider.notifier)
                            .acceptProposal(proposal),
                        child: const Text('হ্যাঁ'),
                      ),
                      const SizedBox(width: FluentSpacing.s),
                      TextButton(
                        // Dismissal is not stored: the proposal simply
                        // reappears next time, which is the honest behaviour
                        // when the evidence has not changed.
                        onPressed: () => ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(
                          const SnackBar(
                            content: Text('ঠিক আছে, পরে আবার জিজ্ঞেস করব।'),
                          ),
                        ),
                        child: const Text('এখনো না'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubjectTile extends ConsumerWidget {
  final CoverageSubject subject;

  const _SubjectTile({required this.subject});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final tally = tallySubject(subject);
    final visible = subject.topics
        .where((t) => t.status != SyllabusStatus.hidden)
        .toList();
    final hidden = subject.topics
        .where((t) => t.status == SyllabusStatus.hidden)
        .toList();

    return Card(
      margin: const EdgeInsets.only(bottom: FluentSpacing.s),
      child: ExpansionTile(
        // Every tick refetches the provider and rebuilds this list, which
        // without a stable key closed the subject the user was working in —
        // most obviously after removing a topic, where the sheet closing and
        // the rebuild landed together.
        key: PageStorageKey<String>(subject.nodeKey),
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(subject.name, style: FluentType.bodyStrong),
        // Hidden topics are listed apart rather than dropped from the widget
        // tree: a removal the user cannot see is a removal they cannot undo.
        subtitle: Padding(
          padding: const EdgeInsets.only(top: FluentSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CoverageBar(tally: tally),
              const SizedBox(height: FluentSpacing.xs),
              CoverageCaption(tally: tally, toBengali: _bn),
            ],
          ),
        ),
        children: [
          ...visible.map(
            (topic) => _TopicRow(topic: topic, subjectNodeKey: subject.nodeKey),
          ),
          ListTile(
            dense: true,
            leading: Icon(Icons.add, size: 20, color: scheme.primary),
            title: Text(
              'টপিক যোগ করুন',
              style: FluentType.body.copyWith(color: scheme.primary),
            ),
            onTap: () => TopicEditSheet.show(
              context,
              subjectNodeKey: subject.nodeKey,
            ),
          ),
          if (hidden.isNotEmpty)
            _HiddenTopics(topics: hidden),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FluentSpacing.l,
              0,
              FluentSpacing.l,
              FluentSpacing.m,
            ),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => ref
                      .read(syllabusMapNotifierProvider.notifier)
                      .setSubject(
                        subject: subject,
                        status: SyllabusStatus.done,
                      ),
                  child: const Text('পুরো বিষয় শেষ'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => ref
                      .read(syllabusMapNotifierProvider.notifier)
                      .setSubject(
                        subject: subject,
                        status: SyllabusStatus.notStarted,
                      ),
                  style: TextButton.styleFrom(foregroundColor: scheme.error),
                  child: const Text('সব মুছুন'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One topic, cycling notStarted → reading → done → notStarted on tap.
class _TopicRow extends ConsumerWidget {
  final CoverageTopic topic;
  final String subjectNodeKey;

  const _TopicRow({required this.topic, required this.subjectNodeKey});

  /// Tapping cycles a topic. Hidden is not in the cycle — it is reached and
  /// left from the edit sheet, so a stray tap cannot drop a topic out of the
  /// syllabus, and a hidden row is not drawn here anyway.
  static SyllabusStatus _next(SyllabusStatus current) => switch (current) {
    SyllabusStatus.notStarted => SyllabusStatus.reading,
    SyllabusStatus.reading => SyllabusStatus.done,
    SyllabusStatus.done => SyllabusStatus.notStarted,
    SyllabusStatus.hidden => SyllabusStatus.notStarted,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, label) = switch (topic.status) {
      SyllabusStatus.done => (
        Icons.check_circle,
        scheme.primary,
        'শেষ',
      ),
      SyllabusStatus.reading => (
        Icons.timelapse,
        scheme.tertiary,
        'পড়ছি',
      ),
      SyllabusStatus.notStarted || SyllabusStatus.hidden => (
        Icons.circle_outlined,
        scheme.outline,
        '',
      ),
    };

    return ListTile(
      dense: true,
      leading: Icon(icon, color: color, size: 20),
      title: Text(
        topic.title,
        style: FluentType.body.copyWith(
          color: topic.status == SyllabusStatus.done
              ? scheme.onSurfaceVariant
              : scheme.onSurface,
        ),
      ),
      // Editing gets its own control rather than a long press: tapping the
      // row is the common action and has to stay instant, and a gesture
      // nobody discovers is the same as no way to rename a topic at all.
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label.isNotEmpty)
            Text(label, style: FluentType.caption.copyWith(color: color)),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            color: scheme.onSurfaceVariant,
            tooltip: 'সম্পাদনা',
            onPressed: () => TopicEditSheet.show(
              context,
              subjectNodeKey: subjectNodeKey,
              topic: topic,
            ),
          ),
        ],
      ),
      onTap: () => ref
          .read(syllabusMapNotifierProvider.notifier)
          .setStatus(nodeKey: topic.nodeKey, status: _next(topic.status)),
    );
  }
}

/// Topics the user has taken out, kept within reach.
///
/// Collapsed by default so a removed topic does not go on competing for
/// attention with the syllabus the user kept, but present, because a removal
/// with no way back is a trap rather than a setting.
class _HiddenTopics extends ConsumerWidget {
  final List<CoverageTopic> topics;

  const _HiddenTopics({required this.topics});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return ExpansionTile(
      // Its own storage key, or it inherits the context-derived path of the
      // subject tile it sits inside and opens itself because that tile is
      // open. Two unkeyed ExpansionTiles in a rebuilt list is exactly the
      // collision PageStorageKey exists to prevent.
      key: PageStorageKey<String>('hidden/${topics.first.nodeKey}'),
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding: const EdgeInsets.symmetric(horizontal: FluentSpacing.l),
      leading: Icon(
        Icons.visibility_off_outlined,
        size: 20,
        color: scheme.onSurfaceVariant,
      ),
      title: Text(
        'সরানো হয়েছে — ${_bn(topics.length)}টি',
        style: FluentType.caption.copyWith(color: scheme.onSurfaceVariant),
      ),
      children: topics
          .map(
            (topic) => ListTile(
              dense: true,
              contentPadding: const EdgeInsets.only(
                left: FluentSpacing.xxl + FluentSpacing.l,
                right: FluentSpacing.l,
              ),
              title: Text(
                topic.title,
                style: FluentType.body.copyWith(
                  color: scheme.onSurfaceVariant,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
              trailing: TextButton(
                onPressed: () => ref
                    .read(syllabusMapNotifierProvider.notifier)
                    .restoreTopic(topic.nodeKey),
                child: const Text('ফেরত আনুন'),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _Message extends StatelessWidget {
  final String text;

  const _Message(this.text);

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(FluentSpacing.xxl),
      child: Text(text, textAlign: TextAlign.center, style: FluentType.body),
    ),
  );
}
