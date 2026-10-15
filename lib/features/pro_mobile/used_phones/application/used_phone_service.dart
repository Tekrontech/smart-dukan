import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../../core/accounting/posting.dart';
import '../../../../core/accounting/system_accounts.dart';
import '../../../../core/db/app_database.dart';
import '../../../../core/utils/ids.dart';
import '../../../products/application/product_service.dart';

/// Used-phone purchase from a walk-in seller (spec 5.9).
///
/// Dr Inventory (price), Cr Cash/Bank/Wallet; the phone becomes an
/// in-stock IMEI unit costing the price paid.
class UsedPhoneService {
  UsedPhoneService(this.db, this.ctx) : posting = PostingService(db, ctx);

  final AppDatabase db;
  final BusinessCtx ctx;
  final PostingService posting;

  Future<({String id, String docNo, String imeiUnitId})> purchase({
    required String sellerPartyId,
    required String productId,
    required String model,
    required String imei1,
    String? imei2,
    required ConditionGrade grade,
    required Money price,
    PaymentMethod method = PaymentMethod.cash,
    String? sellerCnic,
    String? cnicFrontPath,
    String? cnicBackPath,
    List<String> devicePhotoPaths = const [],
  }) {
    if (!price.isPositive) throw const PostingException(PostingError.invalidAmount);
    return posting.run((p) async {
      final product = await (db.select(db.products)..where((x) => x.id.equals(productId))).getSingleOrNull();
      if (product == null || !product.tracksImei) {
        throw const PostingException(PostingError.invalidInput, 'product must track IMEI');
      }
      final id = newId();
      final seq = await p.nextSeq('used_phone');
      final docNo = docNumber('UP-', seq);
      final unitId = await insertImeiUnit(
          p, productId, null, ImeiInput(imei1: imei1, imei2: imei2, grade: grade), price, 'used_phone', id);
      await p.stockIn(
        productId: productId,
        qty: 1,
        value: price,
        type: StockMoveType.usedPurchase,
        refType: 'used_phone',
        refId: id,
        imeiUnitId: unitId,
      );
      p.cr(SysAccount.forMethod(method), price);
      await db.into(db.usedPhonePurchases).insert(UsedPhonePurchasesCompanion.insert(
            id: id,
            businessId: p.businessId,
            createdAt: p.now,
            updatedAt: p.now,
            createdBy: Value(p.userId),
            docSeq: seq,
            docNo: docNo,
            sellerPartyId: sellerPartyId,
            date: p.now,
            sellerCnic: Value(sellerCnic),
            cnicFrontPath: Value(cnicFrontPath),
            cnicBackPath: Value(cnicBackPath),
            devicePhotosJson: Value(jsonEncode(devicePhotoPaths)),
            model: model,
            productId: productId,
            imeiUnitId: unitId,
            grade: grade,
            price: price,
            method: method,
            status: DocStatus.posted,
          ));
      await p.commit(date: p.now, sourceType: 'used_phone', sourceId: id, memo: 'Used phone $docNo');
      // CNIC never goes into logs (spec 9).
      await p.audit('used_phone', id, 'create', after: {'doc': docNo, 'price': price.paisa});
      return (id: id, docNo: docNo, imeiUnitId: unitId);
    });
  }

  /// Deletes the seller's identity data (CNIC number and photos) on request
  /// or at the end of retention. The financial record stays (spec 9).
  /// [shred] overwrites and removes each encrypted photo file.
  Future<void> deleteIdentity(String id, Future<void> Function(String name) shred, {String reason = 'request'}) async {
    final doc = await (db.select(db.usedPhonePurchases)..where((x) => x.id.equals(id))).getSingleOrNull();
    if (doc == null) return;
    for (final f in [doc.cnicFrontPath, doc.cnicBackPath]) {
      if (f != null) await shred(f);
    }
    await posting.run((p) async {
      await (db.update(db.usedPhonePurchases)..where((x) => x.id.equals(id))).write(UsedPhonePurchasesCompanion(
        sellerCnic: const Value(null),
        cnicFrontPath: const Value(null),
        cnicBackPath: const Value(null),
        identityPurgedAt: Value(p.now),
        updatedAt: Value(p.now),
      ));
      await (db.update(db.parties)..where((x) => x.id.equals(doc.sellerPartyId)))
          .write(PartiesCompanion(cnic: const Value(null), updatedAt: Value(p.now)));
      await p.audit('used_phone', id, 'delete_identity', after: {'reason': reason});
    });
  }

  /// Retention (default 12 months after the device was sold): purges
  /// identity data of phones sold more than [months] ago. Returns how many
  /// records were purged.
  Future<int> purgeExpiredIdentity({required int months, required Future<void> Function(String name) shred}) async {
    final now = ctx.clock();
    final cutoff = DateTime(now.year, now.month - months, now.day);
    final rows = await db.customSelect(
      'SELECT up.id i FROM used_phone_purchases up JOIN imei_units u ON u.id = up.imei_unit_id '
      'JOIN sales s ON s.id = u.sale_ref_id '
      "WHERE up.identity_purged_at IS NULL AND u.status = 'sold' AND s.date < ? "
      'AND (up.seller_cnic IS NOT NULL OR up.cnic_front_path IS NOT NULL OR up.cnic_back_path IS NOT NULL)',
      variables: [Variable.withDateTime(cutoff)],
    ).get();
    for (final r in rows) {
      await deleteIdentity(r.read<String>('i'), shred, reason: 'retention');
    }
    return rows.length;
  }

  /// Logs every view of CNIC data (spec 9).
  Future<void> logCnicView(String id) => posting.run((p) => p.audit('used_phone', id, 'view_cnic'));

  /// Reverses a used-phone purchase while the phone is still in stock.
  Future<String> reverse(String id) => posting.run((p) async {
        final doc = await (db.select(db.usedPhonePurchases)..where((x) => x.id.equals(id))).getSingleOrNull();
        if (doc == null) throw const PostingException(PostingError.notFound);
        if (doc.status != DocStatus.posted) throw const PostingException(PostingError.alreadyReversed);
        final unit = await (db.select(db.imeiUnits)..where((u) => u.id.equals(doc.imeiUnitId))).getSingle();
        if (unit.status != ImeiStatus.inStock) throw const PostingException(PostingError.cannotReverse, 'sold');
        final revId = newId();
        await db.into(db.usedPhonePurchases).insert(UsedPhonePurchasesCompanion.insert(
              id: revId,
              businessId: p.businessId,
              createdAt: p.now,
              updatedAt: p.now,
              createdBy: Value(p.userId),
              docSeq: doc.docSeq,
              docNo: doc.docNo,
              sellerPartyId: doc.sellerPartyId,
              date: p.now,
              model: doc.model,
              productId: doc.productId,
              imeiUnitId: doc.imeiUnitId,
              grade: doc.grade,
              price: doc.price,
              method: doc.method,
              status: DocStatus.reversal,
              reversesId: Value(doc.id),
            ));
        await p.mirrorSource(sourceId: id, reversalId: revId, sourceType: 'used_phone');
        await (db.update(db.imeiUnits)..where((u) => u.id.equals(unit.id)))
            .write(ImeiUnitsCompanion(status: const Value(ImeiStatus.returned), updatedAt: Value(p.now)));
        await (db.update(db.usedPhonePurchases)..where((x) => x.id.equals(id)))
            .write(UsedPhonePurchasesCompanion(status: const Value(DocStatus.reversed), updatedAt: Value(p.now)));
        await p.audit('used_phone', id, 'reverse');
        return revId;
      });
}
