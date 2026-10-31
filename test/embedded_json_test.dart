import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/utils/embedded_json.dart';

void main() {
  group('extractFirstJson', () {
    test('pulls a fenced block out of a chat reply', () {
      const reply = '''
অবশ্যই! এই নিন আপনার ১০টি ফ্ল্যাশকার্ড:

```json
{"cards": [{"front": "কর্ণ", "back": "d = √2 × a"}]}
```

আরও কিছু লাগলে বলবেন।
''';
      expect(
        extractFirstJson(reply),
        '{"cards": [{"front": "কর্ণ", "back": "d = √2 × a"}]}',
      );
    });

    test('takes bare JSON unchanged', () {
      const bare = '[{"front": "ক", "back": "খ"}]';
      expect(extractFirstJson(bare), bare);
    });

    test('is not ended by a brace inside a string', () {
      const reply = 'ফল: {"front": "কোনটি {ক} নয়?", "back": "খ"} — শেষ।';
      expect(
        extractFirstJson(reply),
        '{"front": "কোনটি {ক} নয়?", "back": "খ"}',
      );
    });

    test('is not ended by an escaped quote', () {
      const reply = r'ok {"back": "say \"no\" here"} done';
      expect(extractFirstJson(reply), r'{"back": "say \"no\" here"}');
    });

    test('keeps nesting intact', () {
      const reply = 'x {"a": {"b": [1, 2]}, "c": "}"} y';
      expect(extractFirstJson(reply), '{"a": {"b": [1, 2]}, "c": "}"}');
    });

    test('skips an unbalanced opener and finds a later one', () {
      const reply = 'oops { broken ... now: ["ok"]';
      expect(extractFirstJson(reply), '["ok"]');
    });

    test('returns null when there is no JSON', () {
      expect(extractFirstJson('শুধু সাধারণ লেখা, কোনো JSON নেই।'), isNull);
    });
  });
}
