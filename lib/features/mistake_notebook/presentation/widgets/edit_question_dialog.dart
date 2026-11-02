import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/utils/option_label.dart';

/// Lets a question be corrected by hand.
///
/// Until now the only way to fix one was to ask the model, which costs tokens
/// and a wait for what is often a typo or an option the scan misread. The
/// AI correction stays for the cases where the answer itself is in doubt;
/// this is for the ones the user can already see.
class EditQuestionDialog extends StatefulWidget {
  final DrillQuestion question;

  const EditQuestionDialog({super.key, required this.question});

  /// Returns the edit to apply, or null if the user backs out.
  static Future<QuestionEdit?> show(
    BuildContext context,
    DrillQuestion question,
  ) {
    return showDialog<QuestionEdit>(
      context: context,
      builder: (_) => EditQuestionDialog(question: question),
    );
  }

  @override
  State<EditQuestionDialog> createState() => _EditQuestionDialogState();
}

/// What the user changed.
class QuestionEdit {
  final String questionText;
  final List<String> options;
  final int correctIndex;
  final String explanation;

  const QuestionEdit({
    required this.questionText,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });
}

class _EditQuestionDialogState extends State<EditQuestionDialog> {
  late final TextEditingController _question;
  late final TextEditingController _explanation;
  late final List<TextEditingController> _options;
  late int _correct;

  @override
  void initState() {
    super.initState();
    _question = TextEditingController(text: widget.question.questionText);
    _explanation = TextEditingController(text: widget.question.explanation);

    final decoded = _decodeOptions(widget.question.optionsJson);
    _options = [
      for (final option in decoded) TextEditingController(text: option),
    ];
    _correct = widget.question.correctIndex.clamp(0, _options.length - 1);
  }

  static List<String> _decodeOptions(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is List && decoded.isNotEmpty) {
        return decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {}
    return ['', '', '', ''];
  }

  @override
  void dispose() {
    _question.dispose();
    _explanation.dispose();
    for (final option in _options) {
      option.dispose();
    }
    super.dispose();
  }

  void _save() {
    final text = _question.text.trim();
    final options = _options.map((c) => c.text.trim()).toList();
    // A question with no text, or an option left blank, would be unanswerable.
    if (text.isEmpty || options.any((o) => o.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('প্রশ্ন ও সব অপশন পূরণ করুন')),
      );
      return;
    }
    Navigator.of(context).pop(
      QuestionEdit(
        questionText: text,
        options: options,
        correctIndex: _correct,
        explanation: _explanation.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('প্রশ্ন সম্পাদনা', style: TextStyle(fontSize: 16)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _question,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'প্রশ্ন',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'সঠিক উত্তরটি বেছে নিন',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            RadioGroup<int>(
              groupValue: _correct,
              onChanged: (v) => setState(() => _correct = v ?? _correct),
              child: Column(
                children: [
                  for (var i = 0; i < _options.length; i++)
                    Row(
                      children: [
                        Radio<int>(value: i),
                        Text(
                          '${optionLabelChar(i)}.',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: TextField(
                            controller: _options[i],
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _explanation,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'ব্যাখ্যা',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('বাতিল'),
        ),
        FilledButton(onPressed: _save, child: const Text('সেভ করুন')),
      ],
    );
  }
}
