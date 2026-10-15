import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../utils/ids.dart';
import 'system_accounts.dart';

/// Why a business operation was refused. The UI maps each code to a
/// localized message; nothing is saved when one is thrown.
enum PostingError {
  unbalanced,
  invalidAmount,
  invalidInput,
  emptyDocument,
  insufficientStock,
  imeiRequired,
  imeiNotAvailable,
  imeiDuplicate,
  partyRequired,
  overReturn,
  belowMinPrice,
  alreadyReversed,
  cannotReverse,
  overpayment,
  notFound,
  dayAlreadyClosed,
}

class PostingException implements Exception {
  const PostingException(this.code, [this.detail]);

  final PostingError code;
  final String? detail;

  @override
  String toString() => 'PostingException(${code.name}${detail == null ? '' : ': $detail'})';
}

/// Who is posting and when. One business per install in V1.
class BusinessCtx {
  const BusinessCtx({required this.businessId, this.userId, this.clock = DateTime.now});

  final String businessId;
  final String? userId;
  final DateTime Function() clock;

  BusinessCtx withUser(String? userId) => BusinessCtx(businessId: businessId, userId: userId, clock: clock);
}

/// A journal line waiting to be written.
class JLine {
  JLine(this.accountKey, {this.debit = Money.zero, this.credit = Money.zero, this.partyId, this.refType, this.refId});

  final String accountKey;
  final Money debit;
  final Money credit;
  final String? partyId;
  final String? refType;
  final String? refId;
}

/// Result of a stock movement.
class StockResult {
  const StockResult({required this.movementId, required this.value, required this.unitCost});

  final String movementId;

  /// Absolute inventory value moved.
  final Money value;
  final Money unitCost;
}

String stockKeyOf(String productId, String? variantId) => '$productId:${variantId ?? ''}';

/// The posting engine (spec Section 8).
///
/// Every business event runs inside [run], i.e. ONE database transaction:
/// the document, its stock movements, stock balances and a balanced journal
/// entry are written together, or nothing is written at all.
class PostingService {
  PostingService(this.db, this.ctx);

  final AppDatabase db;
  final BusinessCtx ctx;

  Future<T> run<T>(Future<T> Function(Posting p) body) {
    return db.transaction(() async {
      final p = Posting._(db, ctx, ctx.clock());
      final result = await body(p);
      if (p._lines.isNotEmpty) {
        throw StateError('Posting left ${p._lines.length} journal lines uncommitted');
      }
      return result;
    });
  }
}

/// Transaction-scoped posting helper. Only obtainable through
/// [PostingService.run].
class Posting {
  Posting._(this.db, this.ctx, this.now);

  final AppDatabase db;
  final BusinessCtx ctx;

  /// Wall-clock time of this transaction; documents default to it.
  final DateTime now;

  final List<JLine> _lines = [];
  final Map<String, String> _accountIds = {};

  String get businessId => ctx.businessId;
  String? get userId => ctx.userId;

  // ---------------------------------------------------------------------
  // Journal
  // ---------------------------------------------------------------------

  /// Debit [account]. Zero is ignored; a negative amount becomes a credit.
  void dr(SysAccount account, Money amount, {String? partyId, String? refType, String? refId}) =>
      drKey(account.key, amount, partyId: partyId, refType: refType, refId: refId);

  /// Credit [account]. Zero is ignored; a negative amount becomes a debit.
  void cr(SysAccount account, Money amount, {String? partyId, String? refType, String? refId}) =>
      crKey(account.key, amount, partyId: partyId, refType: refType, refId: refId);

  void drKey(String key, Money amount, {String? partyId, String? refType, String? refId}) {
    if (amount.isZero) return;
    if (amount.isNegative) return crKey(key, -amount, partyId: partyId, refType: refType, refId: refId);
    _lines.add(JLine(key, debit: amount, partyId: partyId, refType: refType, refId: refId));
  }

  void crKey(String key, Money amount, {String? partyId, String? refType, String? refId}) {
    if (amount.isZero) return;
    if (amount.isNegative) return drKey(key, -amount, partyId: partyId, refType: refType, refId: refId);
    _lines.add(JLine(key, credit: amount, partyId: partyId, refType: refType, refId: refId));
  }

  /// Writes the pending lines as one balanced journal entry. Returns null
  /// when there are no lines (e.g. a cash closing with zero difference).
  Future<String?> commit({
    required DateTime date,
    required String sourceType,
    required String sourceId,
    String memo = '',
    String? reversesId,
  }) async {
    if (_lines.isEmpty) return null;
    final lines = List<JLine>.of(_lines);
    _lines.clear();

    final dr = Money.sum(lines.map((l) => l.debit));
    final cr = Money.sum(lines.map((l) => l.credit));
    if (dr != cr) {
      throw PostingException(PostingError.unbalanced, '$sourceType $sourceId: Dr ${dr.paisa} != Cr ${cr.paisa}');
    }
    for (final l in lines) {
      if ((l.accountKey == SysAccount.ar.key || l.accountKey == SysAccount.ap.key) && l.partyId == null) {
        throw PostingException(PostingError.partyRequired, 'AR/AP line without party in $sourceType');
      }
    }

    final entryId = newId();
    await db.into(db.journalEntries).insert(JournalEntriesCompanion.insert(
          id: entryId,
          businessId: businessId,
          createdAt: now,
          updatedAt: now,
          createdBy: Value(userId),
          date: date,
          sourceType: sourceType,
          sourceId: sourceId,
          memo: Value(memo),
          reversesId: Value(reversesId),
        ));
    for (final l in lines) {
      await db.into(db.journalLines).insert(JournalLinesCompanion.insert(
            id: newId(),
            businessId: businessId,
            createdAt: now,
            updatedAt: now,
            createdBy: Value(userId),
            entryId: entryId,
            accountId: await accountId(l.accountKey),
            partyId: Value(l.partyId),
            debit: Value(l.debit),
            credit: Value(l.credit),
            refType: Value(l.refType),
            refId: Value(l.refId),
          ));
    }
    return entryId;
  }

  Future<String> accountId(String key) async {
    final cached = _accountIds[key];
    if (cached != null) return cached;
    final row = await (db.select(db.accounts)..where((a) => a.systemKey.equals(key))).getSingleOrNull();
    if (row == null) throw PostingException(PostingError.notFound, 'account $key');
    return _accountIds[key] = row.id;
  }

  /// Mirrors every journal entry and stock movement written for [sourceId]
  /// (spec Section 8: "Reversal of any document"). The mirror entries get
  /// [reversalId] as their source and point back via `reverses_id`.
  Future<void> mirrorSource({
    required String sourceId,
    required String reversalId,
    required String sourceType,
    String memo = 'Reversal',
  }) async {
    final entries = await (db.select(db.journalEntries)
          ..where((e) => e.sourceId.equals(sourceId) & e.reversesId.isNull()))
        .get();
    for (final e in entries) {
      final already = await (db.select(db.journalEntries)..where((x) => x.reversesId.equals(e.id))).get();
      if (already.isNotEmpty) throw const PostingException(PostingError.alreadyReversed);

      final lines = await (db.select(db.journalLines)..where((l) => l.entryId.equals(e.id))).get();
      final accounts = await db.select(db.accounts).get();
      final keyById = {for (final a in accounts) a.id: a.systemKey};
      for (final l in lines) {
        _lines.add(JLine(
          keyById[l.accountId]!,
          debit: l.credit,
          credit: l.debit,
          partyId: l.partyId,
          refType: l.refType,
          refId: l.refId,
        ));
      }
      await commit(date: now, sourceType: sourceType, sourceId: reversalId, memo: memo, reversesId: e.id);
    }

    final moves = await (db.select(db.stockMovements)..where((m) => m.refId.equals(sourceId))).get();
    final touched = <String>{};
    for (final m in moves.reversed) {
      await _applyMovement(
        productId: m.productId,
        variantId: m.variantId,
        qty: -m.qtyChange,
        value: -m.valueChange,
        unitCost: m.unitCost,
        type: m.type,
        refType: 'reversal',
        refId: reversalId,
        imeiUnitId: m.imeiUnitId,
        reason: 'reversal',
        date: now,
      );
      touched.add(m.stockKey);
    }
    for (final key in touched) {
      final bal = await (db.select(db.stockBalances)..where((b) => b.stockKey.equals(key))).getSingle();
      await _settleLeftover(bal, refType: 'reversal', refId: reversalId);
    }
    if (_lines.isNotEmpty) {
      await commit(date: now, sourceType: sourceType, sourceId: reversalId, memo: '$memo (stock adjustment)');
    }
  }

  // ---------------------------------------------------------------------
  // Stock
  // ---------------------------------------------------------------------

  Future<bool> allowNegativeStock() async {
    final row = await (db.select(db.appSettings)..where((s) => s.key.equals('allow_negative_stock'))).getSingleOrNull();
    return row?.value == 'true';
  }

  Future<StockBalance> stockBalance(String productId, String? variantId) async {
    final key = stockKeyOf(productId, variantId);
    final existing = await (db.select(db.stockBalances)..where((b) => b.stockKey.equals(key))).getSingleOrNull();
    if (existing != null) return existing;
    final row = StockBalancesCompanion.insert(
      id: newId(),
      businessId: businessId,
      createdAt: now,
      updatedAt: now,
      createdBy: Value(userId),
      productId: productId,
      variantId: Value(variantId),
      stockKey: key,
    );
    await db.into(db.stockBalances).insert(row);
    return (db.select(db.stockBalances)..where((b) => b.stockKey.equals(key))).getSingle();
  }

  /// Adds stock worth [value] and debits INVENTORY by the same amount.
  /// The caller posts the matching credit (cash, AP, opening equity ...).
  Future<StockResult> stockIn({
    required String productId,
    String? variantId,
    required int qty,
    required Money value,
    required StockMoveType type,
    required String refType,
    required String refId,
    String? imeiUnitId,
    String? reason,
    DateTime? date,
  }) async {
    if (qty < 0) throw const PostingException(PostingError.invalidInput, 'stockIn qty must be >= 0');
    if (value.isNegative) throw const PostingException(PostingError.invalidAmount, 'negative stock value');
    final unitCost = qty == 0 ? value : value.ratio(1, qty);
    final id = await _applyMovement(
      productId: productId,
      variantId: variantId,
      qty: qty,
      value: value,
      unitCost: unitCost,
      type: type,
      refType: refType,
      refId: refId,
      imeiUnitId: imeiUnitId,
      reason: reason,
      date: date ?? now,
    );
    dr(SysAccount.inventory, value);
    final bal = await stockBalance(productId, variantId);
    await _settleLeftover(bal, refType: refType, refId: refId);
    return StockResult(movementId: id, value: value, unitCost: unitCost);
  }

  /// Removes stock and credits INVENTORY. Without [value] the weighted
  /// average cost is used; IMEI units and returns pass their exact value.
  Future<StockResult> stockOut({
    required String productId,
    String? variantId,
    required int qty,
    Money? value,
    required StockMoveType type,
    required String refType,
    required String refId,
    String? imeiUnitId,
    String? reason,
    DateTime? date,
    bool? allowNegative,
  }) async {
    if (qty <= 0) throw const PostingException(PostingError.invalidInput, 'stockOut qty must be > 0');
    final bal = await stockBalance(productId, variantId);
    final negativeOk = allowNegative ?? await allowNegativeStock();
    if (bal.qtyOnHand < qty && !negativeOk) {
      throw PostingException(PostingError.insufficientStock, '$productId has ${bal.qtyOnHand}, need $qty');
    }

    Money cost;
    if (value != null) {
      cost = value;
    } else if (bal.qtyOnHand == qty) {
      cost = bal.value; // selling the last units takes all remaining value
    } else if (bal.qtyOnHand > qty) {
      cost = bal.value.ratio(qty, bal.qtyOnHand);
    } else {
      // Negative stock allowed: fall back to the last known average cost.
      cost = (await _lastAvgCost(productId, variantId)).times(qty);
    }
    final unitCost = cost.ratio(1, qty);
    final id = await _applyMovement(
      productId: productId,
      variantId: variantId,
      qty: -qty,
      value: -cost,
      unitCost: unitCost,
      type: type,
      refType: refType,
      refId: refId,
      imeiUnitId: imeiUnitId,
      reason: reason,
      date: date ?? now,
    );
    cr(SysAccount.inventory, cost);
    final after = await stockBalance(productId, variantId);
    await _settleLeftover(after, refType: refType, refId: refId);
    return StockResult(movementId: id, value: cost, unitCost: unitCost);
  }

  Future<Money> _lastAvgCost(String productId, String? variantId) async {
    if (variantId != null) {
      final v = await (db.select(db.productVariants)..where((x) => x.id.equals(variantId))).getSingleOrNull();
      if (v != null) return v.avgCost;
    }
    final p = await (db.select(db.products)..where((x) => x.id.equals(productId))).getSingleOrNull();
    return p?.avgCost ?? Money.zero;
  }

  Future<String> _applyMovement({
    required String productId,
    required String? variantId,
    required int qty,
    required Money value,
    required Money unitCost,
    required StockMoveType type,
    required String refType,
    required String refId,
    String? imeiUnitId,
    String? reason,
    required DateTime date,
  }) async {
    final bal = await stockBalance(productId, variantId);
    final id = newId();
    await db.into(db.stockMovements).insert(StockMovementsCompanion.insert(
          id: id,
          businessId: businessId,
          createdAt: now,
          updatedAt: now,
          createdBy: Value(userId),
          productId: productId,
          variantId: Value(variantId),
          stockKey: bal.stockKey,
          qtyChange: qty,
          unitCost: unitCost,
          valueChange: value,
          type: type,
          refType: refType,
          refId: refId,
          imeiUnitId: Value(imeiUnitId),
          reason: Value(reason),
          date: date,
        ));
    final newQty = bal.qtyOnHand + qty;
    final newValue = bal.value + value;
    await (db.update(db.stockBalances)..where((b) => b.id.equals(bal.id))).write(StockBalancesCompanion(
      qtyOnHand: Value(newQty),
      value: Value(newValue),
      updatedAt: Value(now),
    ));
    if (newQty > 0) {
      final avg = newValue.ratio(1, newQty);
      if (variantId != null) {
        await (db.update(db.productVariants)..where((v) => v.id.equals(variantId)))
            .write(ProductVariantsCompanion(avgCost: Value(avg), updatedAt: Value(now)));
      }
      await (db.update(db.products)..where((p) => p.id.equals(productId)))
          .write(ProductsCompanion(avgCost: Value(avg), updatedAt: Value(now)));
    }
    return id;
  }

  /// Spec 8.1: when quantity reaches zero but value does not, post the
  /// leftover to INVENTORY_ADJUSTMENT so stock value is exactly zero.
  Future<void> _settleLeftover(StockBalance bal, {required String refType, required String refId}) async {
    if (bal.qtyOnHand != 0 || bal.value.isZero) return;
    final leftover = bal.value;
    await _applyMovement(
      productId: bal.productId,
      variantId: bal.variantId,
      qty: 0,
      value: -leftover,
      unitCost: Money.zero,
      type: StockMoveType.adjustment,
      refType: refType,
      refId: refId,
      reason: 'zero_qty_leftover',
      date: now,
    );
    dr(SysAccount.inventoryAdjustment, leftover);
    cr(SysAccount.inventory, leftover);
  }

  // ---------------------------------------------------------------------
  // Numbering and audit
  // ---------------------------------------------------------------------

  /// Next gap-free number for [key] (e.g. `sale`). Runs inside the posting
  /// transaction, so a failed save never consumes a number.
  Future<int> nextSeq(String key) async {
    final row = await (db.select(db.docCounters)..where((c) => c.key.equals(key))).getSingleOrNull();
    if (row == null) {
      await db.into(db.docCounters).insert(DocCountersCompanion.insert(
            id: newId(),
            businessId: businessId,
            createdAt: now,
            updatedAt: now,
            key: key,
            lastValue: const Value(1),
          ));
      return 1;
    }
    final next = row.lastValue + 1;
    await (db.update(db.docCounters)..where((c) => c.id.equals(row.id)))
        .write(DocCountersCompanion(lastValue: Value(next), updatedAt: Value(now)));
    return next;
  }

  Future<void> audit(String entity, String entityId, String action, {Object? before, Object? after}) async {
    await db.into(db.auditLogs).insert(AuditLogsCompanion.insert(
          id: newId(),
          businessId: businessId,
          createdAt: now,
          updatedAt: now,
          createdBy: Value(userId),
          entity: entity,
          entityId: entityId,
          action: action,
          beforeJson: Value(before == null ? null : jsonEncode(before)),
          afterJson: Value(after == null ? null : jsonEncode(after)),
          userId: Value(userId),
        ));
  }
}

/// Formats a document number: `INV-00042`.
String docNumber(String prefix, int seq) => '$prefix${seq.toString().padLeft(5, '0')}';
