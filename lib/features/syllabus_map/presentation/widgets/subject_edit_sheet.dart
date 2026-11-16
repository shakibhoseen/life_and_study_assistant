import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/data/syllabus_coverage.dart';
import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/utils/bengali_math_sanitizer.dart';
import '../providers/syllabus_map_provider.dart';

String _bn(int value) => BengaliMathSanitizer.toBengaliDigits('$value');

/// Adding or changing a subject in a track the user made.
///
/// Marks are a plain number here, unlike a topic's weight, because they are
/// a real published figure — বাংলা is 35 in BCS Preliminary, not "বেশি" — and
/// the whole coverage calculation is built on getting them right.
///
/// The running total of the track's marks is shown while editing. It is not
/// enforced: an exam's marks are the user's to state, and refusing to save
/// until they add up would block them halfway through entering a syllabus.
/// Showing the sum lets them notice, which is the part that matters.
class SubjectEditSheet extends ConsumerStatefulWidget {
  final String trackKey;

  /// The subject being edited, or null to add one.
  final CoverageSubject? subject;

  /// Every subject in the track, for the running total.
  final List<CoverageSubject> siblings;

  const SubjectEditSheet({
    super.key,
    required this.trackKey,
    required this.siblings,
    this.subject,
  });

  static Future<void> show(
    BuildContext context, {
    required String trackKey,
    required List<CoverageSubject> siblings,
    CoverageSubject? subject,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SubjectEditSheet(
          trackKey: trackKey,
          siblings: siblings,
          subject: subject,
        ),
      ),
    );
  }

  @override
  ConsumerState<SubjectEditSheet> createState() => _SubjectEditSheetState();
}

class _SubjectEditSheetState extends ConsumerState<SubjectEditSheet> {
  late final TextEditingController _name;
  late final TextEditingController _marks;
  String? _error;
  bool _busy = false;

  bool get _isEdit => widget.subject != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.subject?.name ?? '');
    _marks = TextEditingController(
      text: widget.subject == null ? '' : '${widget.subject!.marks}',
    );
    _marks.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _marks.dispose();
    super.dispose();
  }

  int get _enteredMarks => int.tryParse(_marks.text.trim()) ?? 0;

  int get _trackTotal {
    var sum = 0;
    for (final s in widget.siblings) {
      if (_isEdit && s.nodeKey == widget.subject!.nodeKey) continue;
      sum += s.marks;
    }
    return sum + _enteredMarks;
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'বিষয়ের নাম লিখুন।');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final notifier = ref.read(syllabusMapNotifierProvider.notifier);
    final ok = _isEdit
        ? await notifier.editSubject(
            nodeKey: widget.subject!.nodeKey,
            name: name,
            marks: _enteredMarks,
          )
        : await notifier.addSubject(
            trackKey: widget.trackKey,
            name: name,
            marks: _enteredMarks,
          );

    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = 'এই নামে একটি বিষয় আগে থেকেই আছে।';
      });
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _remove() async {
    final subject = widget.subject;
    if (subject == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('বিষয়টি মুছবেন?'),
        content: Text(
          '"${subject.name}" ও এর ${_bn(subject.topics.length)}টি টপিক '
          'মুছে যাবে। এটি ফেরানো যাবে না।',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('না'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('মুছুন'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    await ref
        .read(syllabusMapNotifierProvider.notifier)
        .removeSubject(subject.nodeKey);
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
              _isEdit ? 'বিষয় সম্পাদনা' : 'নতুন বিষয়',
              style: FluentType.subtitle,
            ),
            const SizedBox(height: FluentSpacing.m),
            TextField(
              controller: _name,
              autofocus: !_isEdit,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: 'বিষয়ের নাম',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: FluentSpacing.m),
            TextField(
              controller: _marks,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'এই বিষয়ের নম্বর',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: FluentSpacing.s),
            Text(
              'এই পরীক্ষার মোট নম্বর দাঁড়াবে ${_bn(_trackTotal)}',
              style: FluentType.caption.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: FluentSpacing.xl),
            Row(
              children: [
                if (_isEdit)
                  TextButton.icon(
                    onPressed: _busy ? null : _remove,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('মুছুন'),
                    style: TextButton.styleFrom(foregroundColor: scheme.error),
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
