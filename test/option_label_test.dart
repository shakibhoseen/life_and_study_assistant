import 'package:flutter_test/flutter_test.dart';
import 'package:life_and_study_assistant/core/utils/option_label.dart';

void main() {
  group('stripOptionLabel', () {
    test('drops a label the option was printed with', () {
      expect(stripOptionLabel('ক. চাকমা'), 'চাকমা');
      expect(stripOptionLabel('খ) তপন'), 'তপন');
      expect(stripOptionLabel('  গ। শশাঙ্ক'), 'শশাঙ্ক');
      expect(stripOptionLabel('a. Dhaka'), 'Dhaka');
      expect(stripOptionLabel('১. ঢাকা'), 'ঢাকা');
    });

    test('leaves an option that has no label', () {
      expect(stripOptionLabel('চাকমা'), 'চাকমা');
      expect(stripOptionLabel('১০ এপ্রিল ১৯৭১'), '১০ এপ্রিল ১৯৭১');
    });

    test('keeps an option that is only a letter', () {
      expect(stripOptionLabel('ক'), 'ক');
      expect(stripOptionLabel('ক.'), 'ক.');
    });
  });

  test('labelledOption never doubles the label', () {
    expect(labelledOption(0, 'ক. চাকমা'), 'ক. চাকমা');
    expect(labelledOption(0, 'চাকমা'), 'ক. চাকমা');
    expect(labelledOption(1, 'ক. চাকমা'), 'খ. চাকমা');
    expect(labelledOption(3, 'বিধু'), 'ঘ. বিধু');
  });
}
