import 'money.dart';

/// Formats money as in spec Section 4: `Rs 125,000`.
///
/// - Groups of three (never lakh grouping `1,25,000`).
/// - No decimals unless paisa exist (`Rs 1,250.50`).
/// - Western digits by default; [urduDigits] swaps to ۰–۹.
class MoneyFormat {
  MoneyFormat._();

  static const _urdu = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];

  static String format(Money m, {bool symbol = true, bool urduDigits = false, bool showSign = false}) {
    final negative = m.paisa < 0;
    final abs = m.paisa.abs();
    final rupees = abs ~/ 100;
    final paisa = abs % 100;

    var out = group(rupees);
    if (paisa != 0) out = '$out.${paisa.toString().padLeft(2, '0')}';
    if (urduDigits) out = toUrduDigits(out);

    final sign = negative ? '-' : (showSign && abs != 0 ? '+' : '');
    return symbol ? '${sign}Rs $out' : '$sign$out';
  }

  /// Groups an integer in threes: 1234567 -> "1,234,567".
  static String group(int value) {
    final s = value.abs().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return value < 0 ? '-$b' : b.toString();
  }

  static String toUrduDigits(String s) =>
      s.replaceAllMapped(RegExp(r'[0-9]'), (m) => _urdu[int.parse(m[0]!)]);

  /// Parses user keypad input like "1,250.5" into Money. Returns null if
  /// invalid. More than 2 decimal places is rejected (no silent rounding).
  static Money? parse(String input) {
    final t = input.replaceAll(',', '').replaceAll('Rs', '').trim();
    final m = RegExp(r'^(-?)(\d+)(?:\.(\d{1,2}))?$').firstMatch(t);
    if (m == null) return null;
    final rupees = int.parse(m[2]!);
    final paisa = int.parse((m[3] ?? '0').padRight(2, '0'));
    final total = rupees * 100 + paisa;
    return Money(m[1] == '-' ? -total : total);
  }
}

extension MoneyFormatX on Money {
  String get formatted => MoneyFormat.format(this);
}
