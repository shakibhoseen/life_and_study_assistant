import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/services/syllabus/syllabus_draft_service.dart';
import '../../../../core/theme/fluent_tokens.dart';
import '../providers/syllabus_map_provider.dart';

/// How a new exam's syllabus gets filled in.
enum NewTrackSource { copy, draft, blank }

/// Adding an exam the app does not ship a map for.
///
/// Three ways in, in the order they are worth trying. Copying comes first
/// because these exams overlap heavily — প্রধান শিক্ষক and প্রাথমিক share most
/// of a syllabus — so a copy plus a few edits is usually both the fastest
/// route and the most accurate one. The AI draft is for an exam nothing here
/// resembles, and says plainly that it needs checking. Blank is for someone
/// who would rather type it than correct it.
class NewTrackSheet extends ConsumerStatefulWidget {
  final List<SyllabusTrackRow> existing;

  const NewTrackSheet({super.key, required this.existing});

  static Future<String?> show(
    BuildContext context, {
    required List<SyllabusTrackRow> existing,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: NewTrackSheet(existing: existing),
      ),
    );
  }

  @override
  ConsumerState<NewTrackSheet> createState() => _NewTrackSheetState();
}

class _NewTrackSheetState extends ConsumerState<NewTrackSheet> {
  final _name = TextEditingController();
  NewTrackSource _source = NewTrackSource.copy;
  String? _copyFrom;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _copyFrom = widget.existing.isEmpty ? null : widget.existing.first.trackKey;
    if (_copyFrom == null) _source = NewTrackSource.blank;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'পরীক্ষার নাম লিখুন।');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final notifier = ref.read(syllabusMapNotifierProvider.notifier);
    String? key;
    try {
      key = switch (_source) {
        NewTrackSource.copy when _copyFrom != null => await notifier.copyTrack(
          sourceTrackKey: _copyFrom!,
          name: name,
        ),
        NewTrackSource.draft => await notifier.draftTrack(name: name),
        _ => await notifier.createTrack(name: name),
      };
    } on SyllabusDraftException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
      return;
    }

    if (!mounted) return;
    if (key == null) {
      setState(() {
        _busy = false;
        _error = 'এই নামে একটি পরীক্ষা আগে থেকেই আছে।';
      });
      return;
    }
    Navigator.of(context).pop(key);
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
            Text('নতুন পরীক্ষা', style: FluentType.subtitle),
            const SizedBox(height: FluentSpacing.m),
            TextField(
              controller: _name,
              autofocus: true,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: 'পরীক্ষার নাম',
                hintText: 'যেমন: প্রধান শিক্ষক',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: FluentSpacing.l),
            Text('সিলেবাস কোথা থেকে আসবে', style: FluentType.bodyStrong),
            const SizedBox(height: FluentSpacing.s),
            if (widget.existing.isNotEmpty) ...[
              _SourceOption(
                value: NewTrackSource.copy,
                groupValue: _source,
                enabled: !_busy,
                title: 'আগের একটি পরীক্ষা থেকে কপি',
                subtitle: 'সব বিষয় ও টপিক চলে আসবে, টিক আসবে না',
                onChanged: (v) => setState(() => _source = v),
              ),
              // The picker gets its own full-width row. Beside the label it
              // squeezed the text column to about a third of the sheet, and
              // "আগের একটি পরীক্ষা থেকে কপি" broke across three lines.
              if (_source == NewTrackSource.copy)
                Padding(
                  padding: const EdgeInsets.only(
                    left: FluentSpacing.xxl + FluentSpacing.s,
                    bottom: FluentSpacing.xs,
                  ),
                  child: DropdownButton<String>(
                    value: _copyFrom,
                    isExpanded: true,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _copyFrom = v),
                    items: widget.existing
                        .map(
                          (t) => DropdownMenuItem(
                            value: t.trackKey,
                            child: Text(
                              t.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
            ],
            _SourceOption(
              value: NewTrackSource.draft,
              groupValue: _source,
              enabled: !_busy,
              title: 'AI দিয়ে খসড়া',
              subtitle: 'নিজে মিলিয়ে নিতে হবে — মানবণ্টন ভুল হতে পারে',
              onChanged: (v) => setState(() => _source = v),
            ),
            _SourceOption(
              value: NewTrackSource.blank,
              groupValue: _source,
              enabled: !_busy,
              title: 'খালি থেকে শুরু',
              subtitle: 'বিষয় ও টপিক নিজে যোগ করবেন',
              onChanged: (v) => setState(() => _source = v),
            ),
            if (_busy && _source == NewTrackSource.draft) ...[
              const SizedBox(height: FluentSpacing.m),
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: FluentSpacing.s),
                  Text(
                    'সিলেবাস তৈরি হচ্ছে…',
                    style: FluentType.caption.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: FluentSpacing.xl),
            Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: const Text('বাতিল'),
                ),
                const SizedBox(width: FluentSpacing.s),
                FilledButton(
                  onPressed: _busy ? null : _create,
                  child: const Text('তৈরি করুন'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceOption extends StatelessWidget {
  final NewTrackSource value;
  final NewTrackSource groupValue;
  final bool enabled;
  final String title;
  final String subtitle;
  final ValueChanged<NewTrackSource> onChanged;

  const _SourceOption({
    required this.value,
    required this.groupValue,
    required this.enabled,
    required this.title,
    required this.subtitle,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = value == groupValue;

    return InkWell(
      onTap: enabled ? () => onChanged(value) : null,
      borderRadius: BorderRadius.circular(FluentRadius.control),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: FluentSpacing.xs),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20,
              color: selected ? scheme.primary : scheme.outline,
            ),
            const SizedBox(width: FluentSpacing.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: FluentType.body),
                  Text(
                    subtitle,
                    style: FluentType.caption.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
