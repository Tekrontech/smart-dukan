import '../money/money.dart';
import '../money/money_format.dart';

/// Display formatting for dates and numbers (Western digits by default,
/// Urdu digits when the setting is on — spec Section 4).
class Fmt {
  Fmt._();

  static String _d(String s) => MoneyFormat.useUrduDigits ? MoneyFormat.toUrduDigits(s) : s;

  static String two(int n) => n.toString().padLeft(2, '0');

  /// 15/10/2026
  static String date(DateTime d) => _d('${two(d.day)}/${two(d.month)}/${d.year}');

  /// 15/10/2026 14:05
  static String dateTime(DateTime d) => _d('${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}');

  static String time(DateTime d) => _d('${two(d.hour)}:${two(d.minute)}');

  /// yyyyMMdd_HHmm for file names (always Western digits).
  static String fileStamp(DateTime d) => '${d.year}${two(d.month)}${two(d.day)}_${two(d.hour)}${two(d.minute)}';

  static String qty(int q) => _d(MoneyFormat.group(q));

  static String money(Money m) => MoneyFormat.format(m);

  static String moneyPlain(Money m) => MoneyFormat.format(m, symbol: false);
}
