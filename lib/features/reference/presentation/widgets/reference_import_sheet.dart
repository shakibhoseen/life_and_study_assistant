import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/services/media/photo_capture_service.dart';
import '../../../../core/services/reference/reference_import_service.dart';
import '../../../../core/services/reference/reference_service.dart';
import '../../../../core/theme/fluent_tokens.dart';
import '../../../../core/utils/bengali_math_sanitizer.dart';
import '../providers/reference_provider.dart';

String _bn(int value) => BengaliMathSanitizer.toBengaliDigits('$value');

/// Getting a table out of a book and into the app.
///
/// The whole flow ends in a preview rather than a save. A misread digit in a
/// conversion table is worse than no table: it is a wrong answer the user
/// will go on to trust, and they will have no reason to doubt it. So nothing
/// reaches the database until they have seen every row.
class ReferenceImportSheet extends ConsumerStatefulWidget {
  const ReferenceImportSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: const ReferenceImportSheet(),
      ),
    );
  }

  @override
  ConsumerState<ReferenceImportSheet> createState() =>
      _ReferenceImportSheetState();
}

class _ReferenceImportSheetState extends ConsumerState<ReferenceImportSheet> {
  final _text = TextEditingController();
  ReferenceSheetData? _draft;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _run(Future<ReferenceSheetData> Function() work) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final draft = await work();
      if (!mounted) return;
      setState(() {
        _draft = draft;
        _busy = false;
      });
    } on ReferenceImportException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'টেবিল তৈরি করা গেল না। আবার চেষ্টা করুন।';
      });
    }
  }

  Future<void> _fromCamera(ImageSource source) async {
    final file = await PhotoCaptureService.instance.captureAndCrop(
      source: source,
      context: context,
      title: 'টেবিলটুকু কেটে নিন',
    );
    if (file == null || !mounted) return;
    await _run(
      () => ref
          .read(referenceNotifierProvider.notifier)
          .draftFromImage(File(file.path)),
    );
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null) return;

    setState(() => _busy = true);
    final key = await ref
        .read(referenceNotifierProvider.notifier)
        .createSheet(
          title: draft.title,
          columns: draft.columns,
          category: draft.category,
          subject: draft.subject,
          note: draft.note,
          rows: draft.rows,
        );

    if (!mounted) return;
    if (key == null) {
      setState(() {
        _busy = false;
        _error = 'এই নামে একটি টেবিল আগে থেকেই আছে। নাম বদলে আবার দিন।';
      });
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"${draft.title}" যোগ হয়েছে।')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(FluentSpacing.l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _draft == null ? 'বই থেকে টেবিল' : 'দেখে নিন',
                style: FluentType.subtitle,
              ),
              const SizedBox(height: FluentSpacing.xs),
              Text(
                _draft == null
                    ? 'পাতার ছবি তুলুন, বা লেখা পেস্ট করুন'
                    : 'সংখ্যাগুলো বইয়ের সঙ্গে মিলিয়ে নিন — তারপর সংরক্ষণ',
                style: FluentType.caption.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: FluentSpacing.l),
              if (_busy) ...[
                Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: FluentSpacing.s),
                    Text('পড়া হচ্ছে…', style: FluentType.body),
                  ],
                ),
                const SizedBox(height: FluentSpacing.l),
              ],
              if (_error != null) ...[
                Text(
                  _error!,
                  style: FluentType.body.copyWith(color: scheme.error),
                ),
                const SizedBox(height: FluentSpacing.m),
              ],
              if (_draft == null) ..._sourceControls() else ..._preview(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _sourceControls() {
    return [
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : () => _fromCamera(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined, size: 18),
              label: const Text('ছবি তুলুন'),
            ),
          ),
          const SizedBox(width: FluentSpacing.s),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : () => _fromCamera(ImageSource.gallery),
              icon: const Icon(Icons.image_outlined, size: 18),
              label: const Text('গ্যালারি'),
            ),
          ),
        ],
      ),
      const SizedBox(height: FluentSpacing.l),
      // The app's own model is the cheap one, and a photographed conversion
      // table is what it is worst at. So this offers the way out: take the
      // exact prompt to whichever model the user already pays for, and paste
      // the answer back.
      Container(
        padding: const EdgeInsets.all(FluentSpacing.m),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(FluentRadius.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('বাইরের AI দিয়ে করাতে চান?', style: FluentType.bodyStrong),
            const SizedBox(height: FluentSpacing.xxs),
            Text(
              'প্রম্পটটি কপি করে ChatGPT বা Claude-এ পাতার ছবিসহ দিন, '
              'তারপর উত্তরের JSON নিচে পেস্ট করুন। ওটা হুবহু নেওয়া হবে — '
              'অ্যাপের নিজের AI আর ছোঁবে না।',
              style: FluentType.caption.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: FluentSpacing.s),
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(
                  ClipboardData(text: ReferenceImportService.externalPrompt),
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('প্রম্পট কপি হয়েছে।')),
                );
              },
              icon: const Icon(Icons.copy_all_outlined, size: 18),
              label: const Text('প্রম্পট কপি করুন'),
            ),
          ],
        ),
      ),
      const SizedBox(height: FluentSpacing.l),
      TextField(
        controller: _text,
        enabled: !_busy,
        maxLines: 6,
        minLines: 3,
        decoration: const InputDecoration(
          labelText: 'JSON বা লেখা পেস্ট করুন',
          helperText: 'JSON হলে সরাসরি নেওয়া হবে',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: FluentSpacing.m),
      Row(
        children: [
          const Spacer(),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('বাতিল'),
          ),
          const SizedBox(width: FluentSpacing.s),
          FilledButton(
            onPressed: _busy
                ? null
                : () => _run(
                    () => ref
                        .read(referenceNotifierProvider.notifier)
                        .draftFromText(_text.text),
                  ),
            child: const Text('টেবিল বানান'),
          ),
        ],
      ),
    ];
  }

  List<Widget> _preview() {
    final draft = _draft!;
    final scheme = Theme.of(context).colorScheme;

    return [
      Text(draft.title, style: FluentType.bodyStrong),
      Text(
        '${draft.category} · ${_bn(draft.rows.length)}টি সারি',
        style: FluentType.caption.copyWith(color: scheme.onSurfaceVariant),
      ),
      const SizedBox(height: FluentSpacing.m),
      ...draft.rows.take(30).map(
        (row) => Padding(
          padding: const EdgeInsets.only(bottom: FluentSpacing.s),
          child: Text(
            row.cells.where((c) => c.isNotEmpty).join('  →  '),
            style: FluentType.body,
          ),
        ),
      ),
      if (draft.rows.length > 30)
        Text(
          'আরও ${_bn(draft.rows.length - 30)}টি সারি',
          style: FluentType.caption.copyWith(color: scheme.onSurfaceVariant),
        ),
      const SizedBox(height: FluentSpacing.l),
      Row(
        children: [
          TextButton(
            onPressed: _busy ? null : () => setState(() => _draft = null),
            child: const Text('আবার তুলুন'),
          ),
          const Spacer(),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('বাতিল'),
          ),
          const SizedBox(width: FluentSpacing.s),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: const Text('সংরক্ষণ'),
          ),
        ],
      ),
    ];
  }
}
