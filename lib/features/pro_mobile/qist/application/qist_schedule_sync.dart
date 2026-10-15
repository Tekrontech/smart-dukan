import 'package:drift/drift.dart';

import '../../../../core/accounting/ledger_queries.dart';
import '../../../../core/accounting/posting.dart';
import '../../../../core/db/app_database.dart';

/// Re-applies everything collected on a plan to its schedule rows, oldest
/// first (spec 8.1). A row is `partial` when 0 < paid < due. Also updates
/// the plan status (completed when the plan's AR is zero).
Future<void> syncQistSchedule(Posting p, String planId) async {
  final db = p.db;
  final q = LedgerQueries(db);
  var collected = await q.allocatedTo(planId);
  final rows = await (db.select(db.qistSchedule)
        ..where((r) => r.planId.equals(planId))
        ..orderBy([(r) => OrderingTerm.asc(r.seq)]))
      .get();
  for (final r in rows) {
    final paid = Money.min(collected, r.amountDue);
    collected -= paid;
    final status = paid >= r.amountDue
        ? QistRowStatus.paid
        : paid.isPositive
            ? QistRowStatus.partial
            : QistRowStatus.due;
    if (paid != r.amountPaid || status != r.status) {
      await (db.update(db.qistSchedule)..where((x) => x.id.equals(r.id)))
          .write(QistScheduleCompanion(amountPaid: Value(paid), status: Value(status), updatedAt: Value(p.now)));
    }
  }
  final plan = await (db.select(db.qistPlans)..where((x) => x.id.equals(planId))).getSingle();
  if (plan.status == QistPlanStatus.cancelled) return;
  final outstanding = await q.refBalance(planId);
  final status = outstanding.isPositive ? QistPlanStatus.active : QistPlanStatus.completed;
  if (status != plan.status) {
    await (db.update(db.qistPlans)..where((x) => x.id.equals(planId)))
        .write(QistPlansCompanion(status: Value(status), updatedAt: Value(p.now)));
  }
}

/// Builds an instalment schedule: (T − D) split into [count] parts whose sum
/// is exact (remainder paisa on the first rows), due every week or month
/// from [start].
List<({int seq, DateTime due, Money amount})> buildQistSchedule({
  required Money financed,
  required int count,
  required QistFrequency frequency,
  required DateTime start,
}) {
  if (count <= 0) throw const PostingException(PostingError.invalidInput, 'installments');
  final parts = financed.split(count);
  return [
    for (var i = 0; i < count; i++)
      (
        seq: i + 1,
        due: frequency == QistFrequency.weekly
            ? DateTime(start.year, start.month, start.day + 7 * i)
            : _addMonths(start, i),
        amount: parts[i],
      ),
  ];
}

DateTime _addMonths(DateTime d, int months) {
  final y = d.year + (d.month - 1 + months) ~/ 12;
  final m = (d.month - 1 + months) % 12 + 1;
  final lastDay = DateTime(y, m + 1, 0).day;
  return DateTime(y, m, d.day > lastDay ? lastDay : d.day);
}
