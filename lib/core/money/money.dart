import 'package:flutter/foundation.dart';

/// Money stored as an integer number of paisa (1 Rupee = 100 paisa).
///
/// Spec Section 6: never use `double` for money. All arithmetic stays in
/// integers so balances always reconcile to the paisa.
@immutable
class Money implements Comparable<Money> {
  const Money(this.paisa);

  /// Whole rupees, e.g. `Money.rupees(1250)` = Rs 1,250.
  const Money.rupees(int rupees) : paisa = rupees * 100;

  static const Money zero = Money(0);

  final int paisa;

  bool get isZero => paisa == 0;
  bool get isNegative => paisa < 0;
  bool get isPositive => paisa > 0;
  bool get hasPaisa => paisa % 100 != 0;

  /// Whole-rupee part (truncated toward zero).
  int get rupeePart => paisa ~/ 100;

  Money operator +(Money other) => Money(paisa + other.paisa);
  Money operator -(Money other) => Money(paisa - other.paisa);
  Money operator -() => Money(-paisa);

  /// Multiply by an integer quantity (e.g. qty × unit price).
  Money times(int qty) => Money(paisa * qty);

  /// Multiply by a ratio [numerator]/[denominator] with half-up rounding
  /// (away from zero), using integer maths only. Used for prorating
  /// discounts and markup (spec Section 8.1).
  Money ratio(int numerator, int denominator) {
    if (denominator == 0) throw ArgumentError('denominator must not be zero');
    final n = paisa * numerator;
    final sign = (n < 0) != (denominator < 0) ? -1 : 1;
    final a = n.abs();
    final d = denominator.abs();
    final q = a ~/ d;
    final r = a % d;
    return Money(sign * (r * 2 >= d ? q + 1 : q));
  }

  /// Splits this amount into [parts] instalments whose sum is exactly this
  /// amount. The remainder paisa go to the first instalments.
  List<Money> split(int parts) {
    if (parts <= 0) throw ArgumentError('parts must be positive');
    final base = paisa ~/ parts;
    var remainder = paisa - base * parts;
    final step = remainder >= 0 ? 1 : -1;
    return List.generate(parts, (_) {
      if (remainder != 0) {
        remainder -= step;
        return Money(base + step);
      }
      return Money(base);
    });
  }

  Money abs() => Money(paisa.abs());

  static Money sum(Iterable<Money> values) => values.fold(zero, (a, b) => a + b);

  bool operator >(Money other) => paisa > other.paisa;
  bool operator <(Money other) => paisa < other.paisa;
  bool operator >=(Money other) => paisa >= other.paisa;
  bool operator <=(Money other) => paisa <= other.paisa;

  @override
  int compareTo(Money other) => paisa.compareTo(other.paisa);

  @override
  bool operator ==(Object other) => other is Money && other.paisa == paisa;

  @override
  int get hashCode => paisa.hashCode;

  @override
  String toString() => 'Money($paisa paisa)';
}
