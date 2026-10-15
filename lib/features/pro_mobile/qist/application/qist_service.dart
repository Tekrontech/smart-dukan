import 'package:drift/drift.dart';

import '../../../../core/accounting/ledger_queries.dart';
import '../../../../core/accounting/posting.dart';
import '../../../../core/accounting/system_accounts.dart';
import '../../../../core/db/app_database.dart';
import '../../../../core/utils/ids.dart';
import '../../../payments/application/payment_service.dart';
import '../../../sales/application/sale_service.dart';
import 'qist_schedule_sync.dart';

/// Qist (instalment) plans after the sale (spec 5.9, 8.1). The plan itself
/// is created with the sale: `SaleService.createSale` with a `QistInput`.
class QistService {
  QistService(this.db, this.ctx) : posting = PostingService(db, ctx);

  final AppDatabase db;
  final BusinessCtx ctx;
  final PostingService posting;

  static const refType = 'qist';

  /// Collected so far including the down payment.
  Future<Money> collected(QistPlan plan) async => plan.downPayment + await LedgerQueries(db).allocatedTo(plan.id);

  /// Instalment received (amount A): Dr Cash, Cr AR (A); Dr DEFERRED_MARKUP
  /// (A × M / T), Cr MARKUP_INCOME. Applied to schedule rows oldest first.
  Future<String> collect(String planId, Money amount, {PaymentMethod method = PaymentMethod.cash}) =>
      posting.run((p) async {
        final plan = await _plan(planId);
        if (plan.status != QistPlanStatus.active) throw const PostingException(PostingError.invalidInput, 'plan closed');
        final outstanding = await LedgerQueries(db).refBalance(planId);
        if (!amount.isPositive || amount > outstanding) throw const PostingException(PostingError.overpayment);
        final before = await collected(plan);

        final paymentId = await postPayment(p,
            direction: PaymentDirection.incoming,
            partyId: plan.partyId,
            amount: amount,
            method: method,
            refType: refType,
            refId: planId,
            note: 'Qist',
            settle: false);
        // Markup recognition is its own balanced entry with the payment as
        // source, so reversing the payment mirrors it too.
        final earned = markupEarned(markup: plan.markup, total: plan.total, paidBefore: before, paidNow: amount);
        p.dr(SysAccount.deferredMarkup, earned);
        p.cr(SysAccount.markupIncome, earned);
        await p.commit(date: p.now, sourceType: 'payment', sourceId: paymentId, memo: 'Qist markup earned');

        await db.into(db.paymentAllocations).insert(PaymentAllocationsCompanion.insert(
              id: newId(),
              businessId: p.businessId,
              createdAt: p.now,
              updatedAt: p.now,
              createdBy: Value(p.userId),
              sourceType: AllocSource.payment,
              paymentId: paymentId,
              docType: AllocDocType.qist,
              docId: planId,
              amount: amount,
            ));
        await syncQistSchedule(p, planId);
        return paymentId;
      });

  /// Cancellation, device taken back: Dr Inventory (agreed recovery value)
  /// + DEFERRED_MARKUP (unearned remainder), Cr AR (party). Whatever the
  /// customer still owes stays on their khata until paid or written off.
  Future<void> cancelWithRecovery(String planId, {required Money recoveryValue}) => posting.run((p) async {
        final plan = await _plan(planId);
        if (plan.status != QistPlanStatus.active) throw const PostingException(PostingError.invalidInput, 'plan closed');
        final q = LedgerQueries(db);
        final outstanding = await q.refBalance(planId);
        final unearned = plan.markup - await _earned(plan);
        if (recoveryValue.isNegative || recoveryValue + unearned > outstanding) {
          throw const PostingException(PostingError.invalidAmount, 'recovery value too high');
        }

        final items = await (db.select(db.saleItems)..where((i) => i.saleId.equals(plan.saleId))).get();
        if (items.isEmpty) throw const PostingException(PostingError.notFound);
        final item = items.first; // qist sales are one device in V1 (D-014)
        if (item.imeiUnitId != null) {
          await (db.update(db.imeiUnits)..where((u) => u.id.equals(item.imeiUnitId!))).write(ImeiUnitsCompanion(
            status: const Value(ImeiStatus.inStock),
            cost: Value(recoveryValue),
            saleRefId: const Value(null),
            warrantyUntil: const Value(null),
            updatedAt: Value(p.now),
          ));
        }
        await p.stockIn(
          productId: item.productId,
          variantId: item.variantId,
          qty: item.qty,
          value: recoveryValue,
          type: StockMoveType.qistRecovery,
          refType: 'qist_cancel',
          refId: planId,
          imeiUnitId: item.imeiUnitId,
        );
        p.dr(SysAccount.deferredMarkup, unearned);
        p.cr(SysAccount.ar, recoveryValue + unearned, partyId: plan.partyId, refType: refType, refId: planId);
        await p.commit(date: p.now, sourceType: 'qist_cancel', sourceId: planId, memo: 'Qist cancelled, device back');
        await (db.update(db.qistPlans)..where((x) => x.id.equals(planId)))
            .write(QistPlansCompanion(status: const Value(QistPlanStatus.cancelled), updatedAt: Value(p.now)));
        await p.audit('qist_plan', planId, 'cancel', after: {'recovery': recoveryValue.paisa});
      });

  /// Remaining amount written off (owner PIN): Dr BAD_DEBT, Cr AR. On an
  /// active plan the unearned markup is cleared first (Dr DEFERRED_MARKUP).
  Future<void> writeOff(String planId) => posting.run((p) async {
        final plan = await _plan(planId);
        final outstanding = await LedgerQueries(db).refBalance(planId);
        if (!outstanding.isPositive) throw const PostingException(PostingError.invalidAmount, 'nothing owed');
        final unearned = plan.status == QistPlanStatus.active ? plan.markup - await _earned(plan) : Money.zero;
        p.dr(SysAccount.deferredMarkup, unearned);
        p.dr(SysAccount.badDebt, outstanding - unearned);
        p.cr(SysAccount.ar, outstanding, partyId: plan.partyId, refType: refType, refId: planId);
        await p.commit(date: p.now, sourceType: 'qist_writeoff', sourceId: planId, memo: 'Qist written off');
        await (db.update(db.qistPlans)..where((x) => x.id.equals(planId)))
            .write(QistPlansCompanion(status: const Value(QistPlanStatus.cancelled), updatedAt: Value(p.now)));
        await p.audit('qist_plan', planId, 'write_off', after: {'amount': outstanding.paisa});
      });

  Future<Money> _earned(QistPlan plan) async {
    final row = await db.customSelect(
      'SELECT COALESCE(SUM(jl.credit - jl.debit), 0) AS e FROM journal_lines jl '
      'JOIN accounts a ON a.id = jl.account_id JOIN journal_entries je ON je.id = jl.entry_id '
      "WHERE a.system_key = 'MARKUP_INCOME' AND (je.source_id = ? OR je.source_id IN "
      "(SELECT id FROM payments WHERE ref_type = 'qist' AND ref_id = ?) OR je.source_id IN "
      "(SELECT id FROM payments WHERE reverses_id IN (SELECT id FROM payments WHERE ref_type = 'qist' AND ref_id = ?)))",
      variables: [Variable.withString(plan.saleId), Variable.withString(plan.id), Variable.withString(plan.id)],
      readsFrom: {db.journalLines, db.accounts, db.journalEntries, db.payments},
    ).getSingle();
    return Money(row.read<int>('e'));
  }

  /// Markup recognised so far on a plan.
  Future<Money> earnedMarkup(QistPlan plan) => _earned(plan);

  Future<QistPlan> _plan(String id) async {
    final plan = await (db.select(db.qistPlans)..where((x) => x.id.equals(id))).getSingleOrNull();
    if (plan == null) throw const PostingException(PostingError.notFound);
    return plan;
  }
}
