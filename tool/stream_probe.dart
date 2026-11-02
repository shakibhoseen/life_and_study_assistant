// Asks the API, rather than the documentation, whether a streaming call
// reports its token usage as it goes.
//
// The app's image reads use generateContent, which says nothing until it
// returns, so a wait can only show an estimate. If the streaming variant
// reports usage per chunk, the real figure could climb during the wait.
//
//   GEMINI_API_KEY=$(tool/read_key_from_phone.sh) \
//     dart run tool/stream_probe.dart [image-file]
import 'dart:io';

import 'package:google_generative_ai/google_generative_ai.dart';

Future<void> main(List<String> args) async {
  final key = Platform.environment['GEMINI_API_KEY'];
  if (key == null || key.isEmpty) {
    stderr.writeln('GEMINI_API_KEY is not set.');
    exit(2);
  }

  final model = GenerativeModel(
    model: Platform.environment['GEMINI_MODEL'] ?? 'gemini-flash-latest',
    apiKey: key,
    generationConfig: GenerationConfig(maxOutputTokens: 2048),
  );

  final Content content;
  if (args.isNotEmpty && File(args.first).existsSync()) {
    content = Content.multi([
      TextPart(
        'এই পাতার গুরুত্বপূর্ণ তথ্যগুলো বাংলায় সংক্ষেপে লেখো, অন্তত ৮টি পয়েন্টে।',
      ),
      DataPart('image/jpeg', File(args.first).readAsBytesSync()),
    ]);
  } else {
    content = Content.text(
      'বাংলাদেশের মুক্তিযুদ্ধ নিয়ে ১৫টি গুরুত্বপূর্ণ তথ্য বাংলায় লেখো।',
    );
  }

  final watch = Stopwatch()..start();
  var chunkNo = 0;
  await for (final chunk in model.generateContentStream([content])) {
    chunkNo++;
    final u = chunk.usageMetadata;
    final chars = chunk.text?.length ?? 0;
    stdout.writeln(
      '#$chunkNo  ${watch.elapsedMilliseconds}ms  chars=$chars  '
      'prompt=${u?.promptTokenCount}  out=${u?.candidatesTokenCount}  '
      'total=${u?.totalTokenCount}',
    );
  }
  stdout.writeln('done in ${watch.elapsedMilliseconds}ms, $chunkNo chunks');
}
