import 'package:flutter_test/flutter_test.dart';
import 'package:smart_dukan/core/money/money.dart';
import 'package:smart_dukan/core/money/money_format.dart';

void main() {
  group('Money arithmetic', () {
    test('rupees constructor stores paisa', () {
      expect(const Money.rupees(125).paisa, 12500);
    });

    test('add, subtract, negate, times', () {
      const a = Money.rupees(300);
      const b = Money(5050);
      expect((a + b).paisa, 35050);
      expect((a - b).paisa, -20950);
      expect((-a).paisa, -30000);
      expect(a.times(10), const Money.rupees(3000));
    });

    test('sum of a list', () {
      expect(Money.sum([const Money.rupees(1), const Money(50), const Money(-25)]), const Money(125));
      expect(Money.sum(const []), Money.zero);
    });

    test('ratio rounds half away from zero, integer only', () {
      // Spec 8 worked example: avg cost (3,000 + 3,600) / 20 = 330
      expect(const Money.rupees(6600).ratio(1, 20), const Money.rupees(330));
      expect(const Money(100).ratio(1, 3), const Money(33));
      expect(const Money(100).ratio(2, 3), const Money(67));
      expect(const Money(5).ratio(1, 2), const Money(3));
      expect(const Money(-5).ratio(1, 2), const Money(-3));
      expect(() => const Money(1).ratio(1, 0), throwsArgumentError);
    });

    test('split always sums back to the original amount', () {
      final parts = const Money(10000).split(3);
      expect(parts, [const Money(3334), const Money(3333), const Money(3333)]);
      expect(Money.sum(parts), const Money(10000));

      final neg = const Money(-10).split(3);
      expect(Money.sum(neg), const Money(-10));
    });

    test('equality and comparison', () {
      expect(const Money(100) == const Money.rupees(1), isTrue);
      expect(const Money(1) > Money.zero, isTrue);
      expect(const Money(-1).isNegative, isTrue);
      expect(const Money(150).hasPaisa, isTrue);
      expect(const Money(200).hasPaisa, isFalse);
    });
  });

  group('MoneyFormat', () {
    test('groups of three, no lakh grouping', () {
      expect(MoneyFormat.format(const Money.rupees(125000)), 'Rs 125,000');
      expect(MoneyFormat.format(const Money.rupees(1234567)), 'Rs 1,234,567');
      expect(MoneyFormat.format(const Money.rupees(999)), 'Rs 999');
      expect(MoneyFormat.format(Money.zero), 'Rs 0');
    });

    test('decimals only when paisa exist', () {
      expect(MoneyFormat.format(const Money(125050)), 'Rs 1,250.50');
      expect(MoneyFormat.format(const Money(105)), 'Rs 1.05');
    });

    test('negatives, sign and no symbol', () {
      expect(MoneyFormat.format(const Money.rupees(-1600)), '-Rs 1,600');
      expect(MoneyFormat.format(const Money.rupees(500), showSign: true), '+Rs 500');
      expect(MoneyFormat.format(const Money.rupees(2000), symbol: false), '2,000');
    });

    test('urdu digits', () {
      expect(MoneyFormat.format(const Money.rupees(1250), urduDigits: true), 'Rs ۱,۲۵۰');
    });

    test('parse', () {
      expect(MoneyFormat.parse('1,250'), const Money.rupees(1250));
      expect(MoneyFormat.parse('1250.5'), const Money(125050));
      expect(MoneyFormat.parse('Rs 99.05'), const Money(9905));
      expect(MoneyFormat.parse('-20'), const Money.rupees(-20));
      expect(MoneyFormat.parse('1.234'), isNull);
      expect(MoneyFormat.parse('abc'), isNull);
      expect(MoneyFormat.parse(''), isNull);
    });
  });
}
