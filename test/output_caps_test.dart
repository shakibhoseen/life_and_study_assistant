import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Holds the output ceilings up against what we know about the model.
///
/// A cap costs nothing on its own — billing is for tokens actually produced,
/// so a high ceiling on a short reply is free. All a low one can do is cut
/// the reply off. That was harmless until the model began reasoning before
/// writing: measured on this project, roughly a thousand tokens went before
/// the first visible word. Against that, the verification ceilings of 600 and
/// 900 left almost nothing for the answer, and a reply cut mid-JSON decodes
/// to nothing — so a question came back unverified rather than slowly
/// verified.
void main() {
  /// Enough that the reasoning does not eat the answer.
  const floor = 2048;

  final pattern = RegExp(r'maxOutputTokens:\s*(\d+)');

  test('no AI call is capped tight enough to cut its own reply', () {
    final tooTight = <String>[];

    for (final file in Directory(
      'lib/core/services/ai',
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      for (final match in pattern.allMatches(source)) {
        final cap = int.parse(match.group(1)!);
        if (cap < floor) {
          tooTight.add('${file.path.split('/').last}: $cap');
        }
      }
    }

    expect(
      tooTight,
      isEmpty,
      reason:
          'These would be cut by the reasoning that precedes the answer:\n'
          '${tooTight.join('\n')}',
    );
  });
}
