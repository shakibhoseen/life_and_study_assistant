import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/data/syllabus_coverage.dart';
import '../../../../core/theme/fluent_tokens.dart';
import '../providers/syllabus_map_provider.dart';

/// Adding a topic, or changing one that is already there.
///
/// One sheet for both because the fields are the same and the difference is
/// a single row: an existing topic can also be taken out of the syllabus.
///
/// Weight is offered as three words rather than a number. It decides how much
/// of a subject the topic is worth, and a spinner inviting "7" against a
/// neighbour's "2" would turn a rough sense of importance into false
/// precision that the coverage figure would then carry.
class TopicEditSheet extends ConsumerStatefulWidget {
  /// The subject the topic belongs to. Required when adding.
  final String subjectNodeKey;

  /// The topic being edited, or null to add a new one.
  final CoverageTopic? topic;

  const TopicEditSheet({
    super.key,
    required this.subjectNodeKey,
    this.topic,
  });

  static Future<void> show(
    BuildContext context, {
    required String subjectNodeKey,
    CoverageTopic? topic,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: TopicEditSheet(
          subjectNodeKey: subjectNodeKey,
          topic: topic,
        ),
      ),
    );
  }

  @override
  ConsumerState<TopicEditSheet> createState() => _TopicEditSheetState();
}

const Map<int, String> _weightLabels = {
  1: 'কম',
  2: 'সাধারণ',
  3: 'বেশি',
};

class _TopicEditSheetState extends ConsumerState<TopicEditSheet> {
  late final TextEditingController _title;
  late int _weight;
  String? _error;
  bool _busy = false;

  bool get _isEdit => widget.topic != null;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.topic?.title ?? '');
    // An existing weight outside the three offered is clamped for display
    // only; leaving the field alone will not rewrite it.
    _weight = (widget.topic?.weight ?? 2).clamp(1, 3);
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'টপিকের নাম লিখুন।');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final notifier = ref.read(syllabusMapNotifierProvider.notifier);
    final ok = _isEdit
        ? await notifier.editTopic(
            nodeKey: widget.topic!.nodeKey,
            title: title,
            weight: _weight,
          )
        : await notifier.addTopic(
            subjectNodeKey: widget.subjectNodeKey,
            title: title,
            weight: _weight,
          );

    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = 'এই নামে একটি টপিক আগে থেকেই আছে।';
      });
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _remove() async {
    final topic = widget.topic;
    if (topic == null) return;

    setState(() => _busy = true);
    await ref
        .read(syllabusMapNotifierProvider.notifier)
        .removeTopic(topic.nodeKey);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(FluentSpacing.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isEdit ? 'টপিক সম্পাদনা' : 'নতুন টপিক',
              style: FluentType.subtitle,
            ),
            const SizedBox(height: FluentSpacing.m),
            TextField(
              controller: _title,
              autofocus: !_isEdit,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _busy ? null : _save(),
              decoration: InputDecoration(
                labelText: 'টপিকের নাম',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: FluentSpacing.l),
            Text('কতটা গুরুত্বপূর্ণ', style: FluentType.bodyStrong),
            const SizedBox(height: FluentSpacing.xxs),
            Text(
              'বিষয়ের ভেতরে এই টপিক কত নম্বর ধরবে, সেটি ঠিক করে',
              style: FluentType.caption.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: FluentSpacing.s),
            Wrap(
              spacing: FluentSpacing.s,
              children: _weightLabels.entries.map((entry) {
                return ChoiceChip(
                  label: Text(entry.value),
                  selected: _weight == entry.key,
                  onSelected: _busy
                      ? null
                      : (_) => setState(() => _weight = entry.key),
                );
              }).toList(),
            ),
            const SizedBox(height: FluentSpacing.xl),
            Row(
              children: [
                if (_isEdit)
                  TextButton.icon(
                    onPressed: _busy ? null : _remove,
                    icon: const Icon(Icons.remove_circle_outline, size: 18),
                    label: const Text('সিলেবাস থেকে সরান'),
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.error,
                    ),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: const Text('বাতিল'),
                ),
                const SizedBox(width: FluentSpacing.s),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(_isEdit ? 'সংরক্ষণ' : 'যোগ করুন'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
