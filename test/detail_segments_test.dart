import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/data/detail_segments.dart';
import 'package:life_and_study_assistant/core/services/reference/reference_service.dart';

/// Figures inside a written explanation.
///
/// A triangle or a cube cannot be read as a sentence, and the detail field
/// could only hold words. A fenced svg block keeps it to one field, one
/// paste and no new column — which only works if a mangled paste degrades
/// into visible code rather than an error box or silence.
void main() {
  const svg = '<svg viewBox="0 0 10 10"><rect width="10" height="10"/></svg>';

  group('splitting', () {
    test('prose with no figure is one segment', () {
      final parts = splitDetail('## কোথা থেকে\n\nসাধারণ ব্যাখ্যা।');
      expect(parts.length, 1);
      expect(parts.single, isA<ProseSegment>());
    });

    test('a figure between two paragraphs keeps its place', () {
      final parts = splitDetail('''
আগের কথা।

```svg চিত্র: ত্রিভুজ
$svg
```

পরের কথা।
''');

      expect(parts.length, 3);
      expect((parts[0] as ProseSegment).markdown, 'আগের কথা।');
      expect((parts[1] as FigureSegment).caption, 'চিত্র: ত্রিভুজ');
      expect((parts[2] as ProseSegment).markdown, 'পরের কথা।');
    });

    test('a figure with no caption is still a figure', () {
      final parts = splitDetail('```svg\n$svg\n```');
      expect((parts.single as FigureSegment).caption, '');
    });

    test('two figures both come through, in order', () {
      final parts = splitDetail('''
```svg এক
$svg
```
মাঝের কথা।
```svg দুই
$svg
```
''');

      expect(parts.whereType<FigureSegment>().length, 2);
      expect(
        parts.whereType<FigureSegment>().map((f) => f.caption),
        ['এক', 'দুই'],
      );
    });

    test('nothing at all is nothing', () {
      expect(splitDetail(''), isEmpty);
      expect(splitDetail('   \n  '), isEmpty);
    });
  });

  group('what is not a figure', () {
    test('a fence holding prose stays prose', () {
      // A half-pasted answer must show up as the code it is, not vanish.
      final parts = splitDetail('```svg\nদুঃখিত, আমি আঁকতে পারিনি।\n```');
      expect(parts.single, isA<ProseSegment>());
      expect((parts.single as ProseSegment).markdown, contains('দুঃখিত'));
    });

    test('an unclosed svg is not drawn', () {
      expect(looksLikeSvg('<svg viewBox="0 0 10 10"><rect'), isFalse);
    });

    test('a script is refused outright', () {
      expect(
        looksLikeSvg('<svg><script>x()</script></svg>'),
        isFalse,
      );
    });

    test('anything reaching off the phone is refused', () {
      // A figure should draw and do nothing else.
      expect(
        looksLikeSvg('<svg><image href="https://x/y.png"/></svg>'),
        isFalse,
      );
      expect(
        looksLikeSvg('<svg><image xlink:href="//x/y.png"/></svg>'),
        isFalse,
      );
      expect(looksLikeSvg('<svg><foreignObject/></svg>'), isFalse);
    });

    test('a plain local drawing is accepted', () {
      expect(looksLikeSvg(svg), isTrue);
    });
  });

  group('the prompt that asks for all this', () {
    String prompt() => derivationPrompt(
      sheetTitle: 'পরিমিতি',
      columns: const ['আকৃতি', 'ক্ষেত্রফল'],
      cells: const ['ত্রিভুজ', '½ × ভূমি × উচ্চতা'],
    );

    test('carries the row and the table', () {
      expect(prompt(), contains('ত্রিভুজ'));
      expect(prompt(), contains('পরিমিতি'));
    });

    test('tells the model not to invent the sections it has not got', () {
      // The earlier version demanded a proof, a condition, a trap and a
      // mnemonic for every row, which for most rows means inventing three.
      expect(prompt(), contains('বানিয়ে লিখবেন না'));
      expect(prompt(), contains('শিরোনামটিই বাদ দিন'));
    });

    test('asks for a figure only where a shape is involved', () {
      expect(prompt(), contains('```svg'));
      expect(prompt(), contains('viewBox'));
      expect(prompt(), contains('আকৃতি না থাকলে ছবি দেবেন না'));
    });

    test('the example figure in the prompt is one this app would draw', () {
      // If the prompt's own example would be rejected, every answer
      // following it would be too.
      final example = splitDetail(prompt());
      expect(example.whereType<FigureSegment>(), isNotEmpty);
    });
  });
}
