import 'package:drift/drift.dart';

import '../../../../core/accounting/ledger_queries.dart';
import '../../../../core/accounting/posting.dart';
import '../../../../core/accounting/system_accounts.dart';
import '../../../../core/db/app_database.dart';
import '../../../../core/utils/ids.dart';
import '../../../payments/application/payment_service.dart';

/// Repair jobs (spec 5.9, posting table in 8.1).
///
/// The job's outstanding balance = the party's AR lines linked to the job
/// (`ref_type = 'repair'`, `ref_id = job id`).
class RepairService {
  RepairService(this.db, this.ctx) : posting = PostingService(db, ctx);

  final AppDatabase db;
  final BusinessCtx ctx;
  final PostingService posting;

  static const refType = 'repair';

  /// Allowed forward moves between working statuses.
  static const Map<RepairStatus, Set<RepairStatus>> transitions = {
    RepairStatus.received: {RepairStatus.diagnosing, RepairStatus.waitingParts, RepairStatus.ready},
    RepairStatus.diagnosing: {RepairStatus.waitingParts, RepairStatus.ready, RepairStatus.received},
    RepairStatus.waitingParts: {RepairStatus.diagnosing, RepairStatus.ready},
    RepairStatus.ready: {RepairStatus.diagnosing},
  };

  /// Job created: no journal entry. An advance is a payment linked to it
  /// (Dr Cash/Wallet, Cr AR party → credit balance on the job).
  Future<({String jobId, String jobNo})> createJob({
    required String partyId,
    required String deviceModel,
    String? imei,
    required String problem,
    Money estimate = Money.zero,
    Money advance = Money.zero,
    PaymentMethod advanceMethod = PaymentMethod.cash,
    String? technicianId,
    DateTime? expectedDate,
    String? note,
  }) {
    if (deviceModel.trim().isEmpty || problem.trim().isEmpty) {
      throw const PostingException(PostingError.invalidInput);
    }
    return posting.run((p) async {
      final seq = await p.nextSeq('repair');
      final jobNo = docNumber('RJ-', seq);
      final id = newId();
      await db.into(db.repairJobs).insert(RepairJobsCompanion.insert(
            id: id,
            businessId: p.businessId,
            createdAt: p.now,
            updatedAt: p.now,
            createdBy: Value(p.userId),
            jobSeq: seq,
            jobNo: jobNo,
            partyId: partyId,
            deviceModel: deviceModel.trim(),
            imei: Value(imei?.trim().isEmpty ?? true ? null : imei!.trim()),
            problem: problem.trim(),
            estimate: Value(estimate),
            status: RepairStatus.received,
            technicianId: Value(technicianId),
            expectedDate: Value(expectedDate),
            note: Value(note),
          ));
      await _log(p, id, null, RepairStatus.received, null);
      if (advance.isPositive) {
        await postPayment(p,
            direction: PaymentDirection.incoming,
            partyId: partyId,
            amount: advance,
            method: advanceMethod,
            refType: refType,
            refId: id,
            note: 'Advance $jobNo');
      }
      await p.audit('repair_job', id, 'create', after: {'job': jobNo});
      return (jobId: id, jobNo: jobNo);
    });
  }

  Future<void> changeStatus(String jobId, RepairStatus to, {String? note}) => posting.run((p) async {
        final job = await _job(jobId);
        if (!(transitions[job.status]?.contains(to) ?? false)) {
          throw PostingException(PostingError.invalidInput, '${job.status.name} → ${to.name}');
        }
        await (db.update(db.repairJobs)..where((j) => j.id.equals(jobId)))
            .write(RepairJobsCompanion(status: Value(to), updatedAt: Value(p.now)));
        await _log(p, jobId, job.status, to, note);
      });

  Future<String> addAdvance(String jobId, Money amount, {PaymentMethod method = PaymentMethod.cash}) =>
      posting.run((p) async {
        final job = await _openJob(jobId);
        return postPayment(p,
            direction: PaymentDirection.incoming,
            partyId: job.partyId,
            amount: amount,
            method: method,
            refType: refType,
            refId: jobId,
            note: 'Advance ${job.jobNo}');
      });

  /// Part issued: Dr COGS at average cost, Cr Inventory; stock − qty.
  Future<String> issuePart(String jobId, {required String productId, String? variantId, int qty = 1, Money charge = Money.zero}) =>
      posting.run((p) async {
        await _openJob(jobId);
        if (qty <= 0) throw const PostingException(PostingError.invalidInput);
        final product = await (db.select(db.products)..where((x) => x.id.equals(productId))).getSingle();
        if (product.tracksImei) throw const PostingException(PostingError.invalidInput, 'IMEI items cannot be parts');
        final id = newId();
        final out = await p.stockOut(
          productId: productId,
          variantId: variantId,
          qty: qty,
          type: StockMoveType.repairPart,
          refType: 'repair_part',
          refId: id,
          allowNegative: false,
        );
        p.dr(SysAccount.cogs, out.value);
        await db.into(db.repairParts).insert(RepairPartsCompanion.insert(
              id: id,
              businessId: p.businessId,
              createdAt: p.now,
              updatedAt: p.now,
              createdBy: Value(p.userId),
              jobId: jobId,
              productId: productId,
              variantId: Value(variantId),
              action: RepairPartAction.issued,
              qty: qty,
              unitCost: out.unitCost,
              costTotal: out.value,
              charge: Value(charge),
            ));
        await p.commit(date: p.now, sourceType: 'repair_part', sourceId: id, memo: 'Part issued');
        return id;
      });

  /// Unused part returned to stock: Dr Inventory, Cr COGS at the cost it
  /// was issued at.
  Future<String> returnPart(String jobId, {required String productId, String? variantId, int qty = 1}) =>
      posting.run((p) async {
        await _openJob(jobId);
        final parts = await (db.select(db.repairParts)
              ..where((r) => r.jobId.equals(jobId) & r.productId.equals(productId)))
            .get();
        final issued = parts.where((r) => r.action == RepairPartAction.issued && r.variantId == variantId);
        final returned = parts.where((r) => r.action == RepairPartAction.returned && r.variantId == variantId);
        final issuedQty = issued.fold<int>(0, (a, r) => a + r.qty);
        final returnedQty = returned.fold<int>(0, (a, r) => a + r.qty);
        if (qty <= 0 || qty > issuedQty - returnedQty) throw const PostingException(PostingError.overReturn);
        final issuedCost = Money.sum(issued.map((r) => r.costTotal));
        final returnedCost = Money.sum(returned.map((r) => r.costTotal));
        final value = returnedQty + qty == issuedQty
            ? issuedCost - returnedCost
            : issuedCost.ratio(qty, issuedQty);
        final id = newId();
        await p.stockIn(
          productId: productId,
          variantId: variantId,
          qty: qty,
          value: value,
          type: StockMoveType.repairPart,
          refType: 'repair_part',
          refId: id,
        );
        p.cr(SysAccount.cogs, value);
        await db.into(db.repairParts).insert(RepairPartsCompanion.insert(
              id: id,
              businessId: p.businessId,
              createdAt: p.now,
              updatedAt: p.now,
              createdBy: Value(p.userId),
              jobId: jobId,
              productId: productId,
              variantId: Value(variantId),
              action: RepairPartAction.returned,
              qty: qty,
              unitCost: value.ratio(1, qty),
              costTotal: value,
            ));
        await p.commit(date: p.now, sourceType: 'repair_part', sourceId: id, memo: 'Part returned');
        return id;
      });

  /// Job delivered: Dr AR (party) final bill, Cr REPAIR_INCOME; optional
  /// payment at delivery (Dr Cash, Cr AR).
  Future<void> deliver(String jobId,
      {required Money finalAmount, Money paidNow = Money.zero, PaymentMethod method = PaymentMethod.cash}) {
    if (finalAmount.isNegative || paidNow.isNegative) throw const PostingException(PostingError.invalidAmount);
    return posting.run((p) async {
      final job = await _openJob(jobId);
      p.dr(SysAccount.ar, finalAmount, partyId: job.partyId, refType: refType, refId: jobId);
      p.cr(SysAccount.repairIncome, finalAmount);
      await p.commit(date: p.now, sourceType: 'repair_job', sourceId: jobId, memo: 'Repair ${job.jobNo} delivered');
      if (paidNow.isPositive) {
        final outstanding = await LedgerQueries(db).refBalance(jobId);
        if (paidNow > outstanding) throw const PostingException(PostingError.overpayment);
        await postPayment(p,
            direction: PaymentDirection.incoming,
            partyId: job.partyId,
            amount: paidNow,
            method: method,
            refType: refType,
            refId: jobId,
            note: 'Repair ${job.jobNo}');
      }
      await (db.update(db.repairJobs)..where((j) => j.id.equals(jobId))).write(RepairJobsCompanion(
        status: const Value(RepairStatus.delivered),
        finalAmount: Value(finalAmount),
        deliveredAt: Value(p.now),
        updatedAt: Value(p.now),
      ));
      await _log(p, jobId, job.status, RepairStatus.delivered, null);
    });
  }

  /// Returned unrepaired with an inspection fee: Dr AR, Cr REPAIR_INCOME
  /// (fee only). Parts issued stay as cost (spec 8.1).
  Future<void> returnUnrepaired(String jobId, {Money fee = Money.zero}) {
    if (fee.isNegative) throw const PostingException(PostingError.invalidAmount);
    return posting.run((p) async {
      final job = await _openJob(jobId);
      p.dr(SysAccount.ar, fee, partyId: job.partyId, refType: refType, refId: jobId);
      p.cr(SysAccount.repairIncome, fee);
      await p.commit(date: p.now, sourceType: 'repair_job', sourceId: jobId, memo: 'Repair ${job.jobNo} returned');
      await (db.update(db.repairJobs)..where((j) => j.id.equals(jobId))).write(RepairJobsCompanion(
        status: const Value(RepairStatus.returnedUnrepaired),
        finalAmount: Value(fee),
        deliveredAt: Value(p.now),
        updatedAt: Value(p.now),
      ));
      await _log(p, jobId, job.status, RepairStatus.returnedUnrepaired, null);
    });
  }

  /// Advance refunded: Dr AR (party), Cr Cash/Wallet. Limited to the
  /// job's credit balance.
  Future<String> refundAdvance(String jobId, Money amount, {PaymentMethod method = PaymentMethod.cash}) =>
      posting.run((p) async {
        final job = await _job(jobId);
        final outstanding = await LedgerQueries(db).refBalance(jobId);
        if (!amount.isPositive || amount > -outstanding) throw const PostingException(PostingError.overpayment);
        final id = newId();
        await db.into(db.payments).insert(PaymentsCompanion.insert(
              id: id,
              businessId: p.businessId,
              createdAt: p.now,
              updatedAt: p.now,
              createdBy: Value(p.userId),
              direction: PaymentDirection.outgoing,
              partyId: Value(job.partyId),
              date: p.now,
              amount: amount,
              method: method,
              accountId: await p.accountId(SysAccount.forMethod(method).key),
              refType: const Value(refType),
              refId: Value(jobId),
              status: DocStatus.posted,
              note: Value('Advance refund ${job.jobNo}'),
            ));
        p.dr(SysAccount.ar, amount, partyId: job.partyId, refType: refType, refId: jobId);
        p.cr(SysAccount.forMethod(method), amount);
        await p.commit(date: p.now, sourceType: 'payment', sourceId: id, memo: 'Advance refund');
        return id;
      });

  /// Collects money against a delivered job.
  Future<String> collect(String jobId, Money amount, {PaymentMethod method = PaymentMethod.cash}) =>
      posting.run((p) async {
        final job = await _job(jobId);
        final outstanding = await LedgerQueries(db).refBalance(jobId);
        if (amount > outstanding) throw const PostingException(PostingError.overpayment);
        return postPayment(p,
            direction: PaymentDirection.incoming,
            partyId: job.partyId,
            amount: amount,
            method: method,
            refType: refType,
            refId: jobId,
            note: 'Repair ${job.jobNo}');
      });

  Future<RepairJob> _job(String id) async {
    final job = await (db.select(db.repairJobs)..where((j) => j.id.equals(id))).getSingleOrNull();
    if (job == null) throw const PostingException(PostingError.notFound);
    return job;
  }

  Future<RepairJob> _openJob(String id) async {
    final job = await _job(id);
    if (job.status == RepairStatus.delivered || job.status == RepairStatus.returnedUnrepaired) {
      throw const PostingException(PostingError.invalidInput, 'job closed');
    }
    return job;
  }

  Future<void> _log(Posting p, String jobId, RepairStatus? from, RepairStatus to, String? note) async {
    await db.into(db.repairStatusLogs).insert(RepairStatusLogsCompanion.insert(
          id: newId(),
          businessId: p.businessId,
          createdAt: p.now,
          updatedAt: p.now,
          createdBy: Value(p.userId),
          jobId: jobId,
          fromStatus: Value(from),
          toStatus: to,
          note: Value(note),
        ));
  }
}
