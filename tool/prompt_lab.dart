// A bench for trying prompts against the real model from a desktop shell.
//
// Installing a debug APK on the phone takes close to four minutes, nearly all
// of it transfer, which is far too slow a loop for tuning a prompt. This runs
// the same calls in a second or two.
//
// The key is read from the environment and never written down here. Pull it
// straight off the phone, where the app already keeps it, so it never has to
// be pasted anywhere:
//
//   GEMINI_API_KEY=$(tool/read_key_from_phone.sh) dart run tool/prompt_lab.dart text "..."
//
// Usage:
//   dart run tool/prompt_lab.dart text  "<prompt>"        a plain prompt
//   dart run tool/prompt_lab.dart image <file> "<prompt>" a prompt over an image
//   dart run tool/prompt_lab.dart pdf   <file> "<prompt>" a prompt over a PDF
import 'dart:convert';
import 'dart:io';

import 'package:google_generative_ai/google_generative_ai.dart';

const _defaultModel = 'gemini-flash-lite-latest';

Future<void> main(List<String> args) async {
  final key = Platform.environment['GEMINI_API_KEY'];
  if (key == null || key.isEmpty) {
    stderr.writeln('GEMINI_API_KEY is not set. See the header of this file.');
    exit(2);
  }

  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/prompt_lab.dart <text|image|pdf> ...');
    exit(2);
  }

  final mode = args.first;
  final modelName = Platform.environment['GEMINI_MODEL'] ?? _defaultModel;
  final json = Platform.environment['GEMINI_JSON'] == '1';

  final model = GenerativeModel(
    model: modelName,
    apiKey: key,
    generationConfig: GenerationConfig(
      temperature: double.tryParse(
        Platform.environment['GEMINI_TEMPERATURE'] ?? '0.1',
      ),
      responseMimeType: json ? 'application/json' : null,
    ),
  );

  late final List<Content> content;
  switch (mode) {
    case 'text':
      if (args.length < 2) _die('text needs a prompt');
      content = [Content.text(args[1])];
      break;

    case 'image':
    case 'pdf':
      if (args.length < 3) _die('$mode needs a file and a prompt');
      final file = File(args[1]);
      if (!file.existsSync()) _die('no such file: ${args[1]}');
      final bytes = await file.readAsBytes();
      final mime = mode == 'pdf'
          ? 'application/pdf'
          : (args[1].toLowerCase().endsWith('.png')
                ? 'image/png'
                : 'image/jpeg');
      stderr.writeln('${bytes.length ~/ 1024} KB as $mime');
      content = [
        Content.multi([TextPart(args[2]), DataPart(mime, bytes)]),
      ];
      break;

    default:
      _die('unknown mode: $mode');
  }

  final started = DateTime.now();
  try {
    final response = await model.generateContent(content);
    final elapsed = DateTime.now().difference(started);
    final usage = response.usageMetadata;
    final finish = response.candidates.isNotEmpty
        ? response.candidates.first.finishReason?.name
        : null;

    // Cost and truncation go to stderr so stdout stays pipeable into jq.
    stderr.writeln(
      '--- $modelName  ${elapsed.inMilliseconds}ms  '
      'in=${usage?.promptTokenCount ?? 0} out=${usage?.candidatesTokenCount ?? 0} '
      'total=${usage?.totalTokenCount ?? 0}  finish=${finish ?? "?"}'
      '${finish == 'maxTokens' ? '  *** TRUNCATED ***' : ''}',
    );

    final text = response.text ?? '';
    if (json) {
      try {
        stdout.writeln(
          const JsonEncoder.withIndent('  ').convert(jsonDecode(text)),
        );
        return;
      } catch (_) {
        stderr.writeln('(reply was not valid JSON, printing raw)');
      }
    }
    stdout.writeln(text);
  } catch (e) {
    stderr.writeln('FAILED: $e');
    exit(1);
  }
}

Never _die(String message) {
  stderr.writeln(message);
  exit(2);
}
