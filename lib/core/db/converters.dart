import 'package:drift/drift.dart';

import '../money/money.dart';

/// Stores [Money] as INTEGER paisa (spec Section 6: never `double`).
class MoneyConverter extends TypeConverter<Money, int> with JsonTypeConverter<Money, int> {
  const MoneyConverter();

  @override
  Money fromSql(int fromDb) => Money(fromDb);

  @override
  int toSql(Money value) => value.paisa;
}
