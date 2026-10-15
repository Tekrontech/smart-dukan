import 'package:flutter_test/flutter_test.dart';
import 'package:smart_dukan/core/widgets/amount_keypad.dart';

String type(List<String> keys) => keys.fold('', AmountKeypad.applyKey);

void main() {
  group('AmountKeypad input', () {
    test('digits and 000 key', () {
      expect(type(['1', '2', '000']), '12000');
    });

    test('leading zeros are dropped', () {
      expect(type(['0', '0', '5']), '5');
      expect(type(['000']), '0');
    });

    test('decimal point allows at most 2 paisa digits and only one dot', () {
      expect(type(['1', '.', '5', '0', '9']), '1.50');
      expect(type(['.', '5']), '0.5');
      expect(type(['1', '.', '.', '2']), '1.2');
    });

    test('backspace and clear', () {
      expect(type(['1', '2', '⌫']), '1');
      expect(type(['⌫']), '');
      expect(type(['9', '9', 'C']), '');
    });

    test('caps rupee digits', () {
      expect(type(List.filled(12, '9')).length, AmountKeypad.maxRupeeDigits);
    });
  });
}
