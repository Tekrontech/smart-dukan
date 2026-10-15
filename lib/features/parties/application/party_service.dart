import 'package:drift/drift.dart';

import '../../../core/accounting/ledger_queries.dart';
import '../../../core/accounting/posting.dart';
import '../../../core/accounting/system_accounts.dart';
import '../../../core/db/app_database.dart';
import '../../../core/utils/ids.dart';

class PartyInput {
  const PartyInput({
    required this.type,
    required this.name,
    this.phone,
    this.cnic,
    this.address,
    this.creditLimit = Money.zero,
    this.notes,
  });

  final PartyType type;
  final String name;
  final String? phone;
  final String? cnic;
  final String? address;
  final Money creditLimit;
  final String? notes;
}

/// Customers and suppliers (spec 5.6).
class PartyService {
  PartyService(this.db, this.ctx) : posting = PostingService(db, ctx);

  final AppDatabase db;
  final BusinessCtx ctx;
  final PostingService posting;

  /// Creates a party. [openingBalance] is signed: positive = they owe the
  /// shop, negative = the shop owes them. Posted at the go-live date
  /// against OPENING_EQUITY (spec 8.1).
  Future<String> createParty(PartyInput input, {Money openingBalance = Money.zero}) {
    if (input.name.trim().isEmpty) throw const PostingException(PostingError.invalidInput, 'name');
    return posting.run((p) async {
      final id = newId();
      await db.into(db.parties).insert(PartiesCompanion.insert(
            id: id,
            businessId: p.businessId,
            createdAt: p.now,
            updatedAt: p.now,
            createdBy: Value(p.userId),
            type: input.type,
            name: input.name.trim(),
            phone: Value(_clean(input.phone)),
            cnic: Value(_clean(input.cnic)),
            address: Value(_clean(input.address)),
            openingBalance: Value(openingBalance),
            creditLimit: Value(input.creditLimit),
            notes: Value(_clean(input.notes)),
          ));
      if (!openingBalance.isZero) {
        final acc = switch (input.type) {
          PartyType.customer => SysAccount.ar,
          PartyType.supplier => SysAccount.ap,
          PartyType.both => openingBalance.isPositive ? SysAccount.ar : SysAccount.ap,
        };
        p.dr(acc, openingBalance, partyId: id);
        p.cr(SysAccount.openingEquity, openingBalance);
        final business = await (db.select(db.businesses)..limit(1)).getSingle();
        await p.commit(date: business.goLiveDate, sourceType: 'party_opening', sourceId: id, memo: 'Opening balance');
      }
      await p.audit('party', id, 'create', after: {'name': input.name, 'opening': openingBalance.paisa});
      return id;
    });
  }

  Future<void> updateParty(String id, PartyInput input) => posting.run((p) async {
        await (db.update(db.parties)..where((x) => x.id.equals(id))).write(PartiesCompanion(
          type: Value(input.type),
          name: Value(input.name.trim()),
          phone: Value(_clean(input.phone)),
          cnic: Value(_clean(input.cnic)),
          address: Value(_clean(input.address)),
          creditLimit: Value(input.creditLimit),
          notes: Value(_clean(input.notes)),
          updatedAt: Value(p.now),
        ));
        await p.audit('party', id, 'update_master', after: {'name': input.name});
      });

  /// True when adding [extraDue] would push the customer past their credit
  /// limit (spec 5.6: warn at sale time). No limit set = never exceeded.
  Future<bool> exceedsCreditLimit(String partyId, Money extraDue) async {
    final party = await (db.select(db.parties)..where((x) => x.id.equals(partyId))).getSingle();
    if (!party.creditLimit.isPositive) return false;
    final bal = await LedgerQueries(db).partyBalance(partyId);
    return bal + extraDue > party.creditLimit;
  }

  static String? _clean(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
}
