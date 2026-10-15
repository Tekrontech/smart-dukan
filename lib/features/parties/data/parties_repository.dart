import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';

class PartyListItem {
  const PartyListItem({required this.party, required this.balance, this.lastActivity});

  final Party party;

  /// Positive = Lena, negative = Dena.
  final Money balance;
  final DateTime? lastActivity;
}

/// One ledger row with running balance (spec 5.6).
class LedgerRow {
  const LedgerRow({
    required this.date,
    required this.sourceType,
    required this.sourceId,
    required this.memo,
    required this.debit,
    required this.credit,
    required this.running,
    this.reversal = false,
  });

  final DateTime date;
  final String sourceType;
  final String sourceId;
  final String memo;
  final Money debit;
  final Money credit;
  final Money running;
  final bool reversal;
}

class PartiesRepository {
  PartiesRepository(this.db);

  final AppDatabase db;

  /// Parties of a kind (customers include "both"), sorted by balance.
  Selectable<PartyListItem> list({required PartyType kind, String search = '', int limit = 50}) {
    final types = kind == PartyType.supplier ? "('supplier','both')" : "('customer','both')";
    final vars = <Variable>[];
    var filter = '';
    if (search.trim().isNotEmpty) {
      filter = 'AND (p.name LIKE ? OR p.phone LIKE ?)';
      vars.addAll([Variable.withString('%${search.trim()}%'), Variable.withString('%${search.trim()}%')]);
    }
    return db.customSelect(
      'SELECT p.*, COALESCE(b.bal, 0) AS bal, b.last AS last FROM parties p LEFT JOIN ('
      '  SELECT jl.party_id pid, SUM(jl.debit - jl.credit) bal, MAX(je.date) last FROM journal_lines jl '
      '  JOIN accounts a ON a.id = jl.account_id JOIN journal_entries je ON je.id = jl.entry_id '
      "  WHERE a.system_key IN ('AR','AP') GROUP BY jl.party_id"
      ') b ON b.pid = p.id '
      'WHERE p.is_active = 1 AND p.type IN $types $filter '
      'ORDER BY ABS(COALESCE(b.bal, 0)) DESC, p.name COLLATE NOCASE LIMIT ?',
      variables: [...vars, Variable.withInt(limit)],
      readsFrom: {db.parties, db.journalLines, db.journalEntries, db.accounts},
    ).asyncMap((r) async => PartyListItem(
          party: await db.parties.mapFromRow(r),
          balance: Money(r.read<int>('bal')),
          lastActivity: r.readNullable<DateTime>('last'),
        ));
  }

  Stream<Party?> watchParty(String id) => (db.select(db.parties)..where((p) => p.id.equals(id))).watchSingleOrNull();

  Future<Party?> party(String id) => (db.select(db.parties)..where((p) => p.id.equals(id))).getSingleOrNull();

  Stream<Money> watchBalance(String partyId) => db
      .customSelect(
        'SELECT COALESCE(SUM(jl.debit - jl.credit), 0) b FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id '
        "WHERE a.system_key IN ('AR','AP') AND jl.party_id = ?",
        variables: [Variable.withString(partyId)],
        readsFrom: {db.journalLines, db.accounts},
      )
      .watchSingle()
      .map((r) => Money(r.read<int>('b')));

  /// Ledger lines between [from] and [to] (inclusive start, exclusive end)
  /// with a running balance that starts from everything before [from].
  Future<({Money opening, List<LedgerRow> rows})> ledger(String partyId, {DateTime? from, DateTime? to}) async {
    var opening = Money.zero;
    if (from != null) {
      final r = await db.customSelect(
        'SELECT COALESCE(SUM(jl.debit - jl.credit), 0) b FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id '
        'JOIN journal_entries je ON je.id = jl.entry_id '
        "WHERE a.system_key IN ('AR','AP') AND jl.party_id = ? AND je.date < ?",
        variables: [Variable.withString(partyId), Variable.withDateTime(from)],
      ).getSingle();
      opening = Money(r.read<int>('b'));
    }
    final rows = await db.customSelect(
      'SELECT je.date d, je.source_type t, je.source_id s, je.memo m, je.reverses_id rv, '
      'SUM(jl.debit) dr, SUM(jl.credit) cr FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id '
      'JOIN journal_entries je ON je.id = jl.entry_id '
      "WHERE a.system_key IN ('AR','AP') AND jl.party_id = ?"
      '${from != null ? ' AND je.date >= ?' : ''}${to != null ? ' AND je.date < ?' : ''} '
      'GROUP BY je.id ORDER BY je.date, je.id',
      variables: [
        Variable.withString(partyId),
        if (from != null) Variable.withDateTime(from),
        if (to != null) Variable.withDateTime(to),
      ],
    ).get();
    var running = opening;
    final out = <LedgerRow>[];
    for (final r in rows) {
      final dr = Money(r.read<int>('dr')), cr = Money(r.read<int>('cr'));
      running += dr - cr;
      out.add(LedgerRow(
        date: r.read<DateTime>('d'),
        sourceType: r.read<String>('t'),
        sourceId: r.read<String>('s'),
        memo: r.read<String>('m'),
        debit: dr,
        credit: cr,
        running: running,
        reversal: r.readNullable<String>('rv') != null,
      ));
    }
    return (opening: opening, rows: out);
  }
}
