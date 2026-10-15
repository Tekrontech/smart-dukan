import 'package:drift/drift.dart';

import '../../../core/accounting/allocation.dart';
import '../../../core/accounting/posting.dart';
import '../../../core/accounting/system_accounts.dart';
import '../../../core/db/app_database.dart';
import '../../../core/utils/ids.dart';
import '../../pro_mobile/qist/application/qist_schedule_sync.dart';

/// Payment In / Out (spec 5.7, posting rules in Section 8).
///
/// Received: Dr Cash/Bank/Wallet, Cr AR (party).
/// Made:     Dr AP (party), Cr Cash/Bank/Wallet.
class PaymentService {
  PaymentService(this.db, this.ctx) : posting = PostingService(db, ctx);

  final AppDatabase db;
  final BusinessCtx ctx;
  final PostingService posting;

  /// Money received from a customer. Without [allocations] the amount is
  /// applied to open invoices oldest-first; any remainder is an advance
  /// that the next sale uses up automatically.
  Future<String> receive({
    required String partyId,
    required Money amount,
    PaymentMethod method = PaymentMethod.cash,
    Map<String, Money>? allocations,
    String? reference,
    String? note,
  }) =>
      posting.run((p) => postPayment(p,
          direction: PaymentDirection.incoming,
          partyId: partyId,
          amount: amount,
          method: method,
          allocations: allocations,
          reference: reference,
          note: note));

  /// Money paid to a supplier (or refunded to a customer).
  Future<String> pay({
    required String partyId,
    required Money amount,
    PaymentMethod method = PaymentMethod.cash,
    Map<String, Money>? allocations,
    String? reference,
    String? note,
  }) =>
      posting.run((p) => postPayment(p,
          direction: PaymentDirection.outgoing,
          partyId: partyId,
          amount: amount,
          method: method,
          allocations: allocations,
          reference: reference,
          note: note));

  /// Opening cash / bank / wallet on the go-live date (spec 8.1):
  /// Dr Cash/Bank/Wallet, Cr OPENING_EQUITY.
  Future<String> openingBalance({required Money amount, PaymentMethod method = PaymentMethod.cash}) {
    if (!amount.isPositive) throw const PostingException(PostingError.invalidAmount);
    return posting.run((p) async {
      final id = newId();
      p.dr(SysAccount.forMethod(method), amount);
      p.cr(SysAccount.openingEquity, amount);
      final business = await (db.select(db.businesses)..limit(1)).getSingle();
      await p.commit(date: business.goLiveDate, sourceType: 'opening_cash', sourceId: id, memo: 'Opening ${method.name}');
      await p.audit('opening_cash', id, 'create', after: {'amount': amount.paisa, 'method': method.name});
      return id;
    });
  }

  /// Reverses a payment (owner PIN in the UI). Allocations are voided, so
  /// the invoices it paid become open again.
  Future<String> reverse(String paymentId) => posting.run((p) => reversePayment(p, paymentId));
}

/// Posts a payment inside an existing transaction. Shared with sales
/// (advance), repairs and qist collection.
Future<String> postPayment(
  Posting p, {
  required PaymentDirection direction,
  required String partyId,
  required Money amount,
  required PaymentMethod method,
  Map<String, Money>? allocations,
  String? reference,
  String? note,
  String? refType,
  String? refId,
  bool settle = true,
}) async {
  if (!amount.isPositive) throw const PostingException(PostingError.invalidAmount);
  final db = p.db;
  final party = await (db.select(db.parties)..where((x) => x.id.equals(partyId))).getSingleOrNull();
  if (party == null) throw const PostingException(PostingError.partyRequired);

  final id = newId();
  final cashAcc = SysAccount.forMethod(method);
  await db.into(db.payments).insert(PaymentsCompanion.insert(
        id: id,
        businessId: p.businessId,
        createdAt: p.now,
        updatedAt: p.now,
        createdBy: Value(p.userId),
        direction: direction,
        partyId: Value(partyId),
        date: p.now,
        amount: amount,
        method: method,
        accountId: await p.accountId(cashAcc.key),
        reference: Value(reference),
        refType: Value(refType),
        refId: Value(refId),
        status: DocStatus.posted,
        note: Value(note),
      ));

  if (direction == PaymentDirection.incoming) {
    p.dr(cashAcc, amount);
    p.cr(SysAccount.ar, amount, partyId: partyId, refType: refType, refId: refId);
  } else {
    // Supplier payments reduce AP; refunds to a pure customer reduce their
    // credit on AR. Party balance is the same either way.
    final acc = party.type == PartyType.customer ? SysAccount.ar : SysAccount.ap;
    p.dr(acc, amount, partyId: partyId, refType: refType, refId: refId);
    p.cr(cashAcc, amount);
  }
  await p.commit(
    date: p.now,
    sourceType: 'payment',
    sourceId: id,
    memo: direction == PaymentDirection.incoming ? 'Payment received' : 'Payment made',
  );

  if (refType == null) {
    final alloc = Allocator(p);
    if (allocations != null && allocations.isNotEmpty) {
      await alloc.allocateExplicit(
        source: AllocSource.payment,
        sourceId: id,
        available: amount,
        byDoc: allocations,
        sales: direction == PaymentDirection.incoming,
      );
    }
    if (settle) await alloc.settleParty(partyId);
  }
  await p.audit('payment', id, 'create', after: {'amount': amount.paisa, 'direction': direction.name});
  return id;
}

Future<String> reversePayment(Posting p, String paymentId) async {
  final db = p.db;
  final pay = await (db.select(db.payments)..where((x) => x.id.equals(paymentId))).getSingleOrNull();
  if (pay == null) throw const PostingException(PostingError.notFound);
  if (pay.status != DocStatus.posted) throw const PostingException(PostingError.alreadyReversed);

  final revId = newId();
  await db.into(db.payments).insert(PaymentsCompanion.insert(
        id: revId,
        businessId: p.businessId,
        createdAt: p.now,
        updatedAt: p.now,
        createdBy: Value(p.userId),
        direction: pay.direction,
        partyId: Value(pay.partyId),
        date: p.now,
        amount: pay.amount,
        method: pay.method,
        accountId: pay.accountId,
        refType: Value(pay.refType),
        refId: Value(pay.refId),
        status: DocStatus.reversal,
        reversesId: Value(pay.id),
        note: const Value('Reversal'),
      ));
  await p.mirrorSource(sourceId: pay.id, reversalId: revId, sourceType: 'payment');
  await (db.update(db.payments)..where((x) => x.id.equals(pay.id)))
      .write(PaymentsCompanion(status: const Value(DocStatus.reversed), updatedAt: Value(p.now)));
  await Allocator(p).voidFor(pay.id);
  if (pay.partyId != null && pay.refType == null) await Allocator(p).settleParty(pay.partyId!);
  if (pay.refType == 'qist' && pay.refId != null) {
    await syncQistSchedule(p, pay.refId!);
  }
  await p.audit('payment', pay.id, 'reverse');
  return revId;
}
