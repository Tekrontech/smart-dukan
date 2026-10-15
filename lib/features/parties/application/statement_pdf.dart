import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../../../core/db/app_database.dart';
import '../../../core/pdf/pdf_kit.dart';
import '../../../core/utils/fmt.dart';
import '../data/parties_repository.dart';

/// Party statement PDF (spec 5.6). Contains only this party's own ledger.
Future<Uint8List> buildStatementPdf({
  required Business business,
  required Party party,
  required Money opening,
  required List<LedgerRow> rows,
  required String Function(LedgerRow) describe,
  DateTime? from,
  DateTime? to,
}) async {
  final k = await PdfKit.load();
  final money = PdfKit.money;
  final closing = rows.isEmpty ? opening : rows.last.running;
  final period = [if (from != null) Fmt.date(from), if (to != null) Fmt.date(to.subtract(const Duration(days: 1)))].join(' – ');
  return k.a4(business, 'Statement — ${party.name}', [party.phone ?? '', period].where((s) => s.isNotEmpty).join(' • '), [
    k.table(
      ['Date', 'Details', 'Debit', 'Credit', 'Balance'],
      [
        ['', 'Opening balance', '', '', money(opening)],
        for (final r in rows)
          [
            Fmt.date(r.date),
            describe(r),
            r.debit.isZero ? '' : money(r.debit),
            r.credit.isZero ? '' : money(r.credit),
            money(r.running),
          ],
      ],
      rightAligned: {2, 3, 4},
    ),
    pw.SizedBox(height: 12),
    k.kv(closing.isNegative ? 'Balance (shop owes)' : 'Balance due', money(closing.abs()), strong: true, size: 12),
  ]);
}
