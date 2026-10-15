import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/db/app_database.dart';
import '../../../core/pdf/pdf_kit.dart';
import '../../../core/utils/fmt.dart';
import '../data/sales_repository.dart';

/// Printable / shareable sale receipt (spec 5.3 step 8). 80 mm roll layout
/// that also reads well on a phone screen and in WhatsApp. Contains only
/// this customer's own invoice (spec 9: sharing).
Future<Uint8List> buildReceiptPdf(SaleView v, Business b, {List<ImeiUnit> imeis = const [], QistPlan? plan}) async {
  final k = await PdfKit.load();
  final s = v.sale;
  final doc = pw.Document(theme: k.theme(), title: s.invoiceNo, author: b.name);
  final imeiById = {for (final u in imeis) u.id: u};
  final money = PdfKit.money;

  doc.addPage(pw.Page(
    pageFormat: const PdfPageFormat(80 * PdfPageFormat.mm, double.infinity, marginAll: 4 * PdfPageFormat.mm),
    build: (ctx) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        k.header(b, compact: true),
        pw.Divider(color: PdfKit.line),
        k.kv('Invoice', s.invoiceNo, strong: true),
        k.kv('Date', Fmt.dateTime(s.date)),
        k.kv('Customer', v.party?.name ?? 'Walk-in'),
        if (v.party?.phone != null) k.kv('Phone', v.party!.phone!),
        if (s.status != DocStatus.posted) k.kv('Status', s.status.name.toUpperCase(), strong: true),
        pw.Divider(color: PdfKit.line),
        for (final i in v.items) ...[
          pw.Text(i.description, style: pw.TextStyle(font: k.bold, fontSize: 9)),
          k.kv('  ${i.unitQty} × ${money(i.unitPrice)}${i.discount.isZero ? '' : '  − ${money(i.discount)}'}', money(i.lineTotal)),
          if (i.imeiUnitId != null && imeiById[i.imeiUnitId] != null) ...[
            pw.Text('  IMEI ${imeiById[i.imeiUnitId]!.imei1}', style: k.small),
            if (imeiById[i.imeiUnitId]!.warrantyUntil != null)
              pw.Text('  Warranty until ${Fmt.date(imeiById[i.imeiUnitId]!.warrantyUntil!)}', style: k.small),
          ],
        ],
        pw.Divider(color: PdfKit.line),
        k.kv('Subtotal', money(s.subtotal)),
        if (!s.discount.isZero) k.kv('Discount', '− ${money(s.discount)}'),
        if (!s.tax.isZero) k.kv('Tax', money(s.tax)),
        if (!s.delivery.isZero) k.kv('Delivery', money(s.delivery)),
        if (!s.markup.isZero) k.kv('Qist markup', money(s.markup)),
        k.kv('TOTAL', money(s.total), strong: true, size: 12),
        k.kv('Paid', money(s.paid)),
        if (!s.due.isZero) k.kv('Udhaar / Due', money(s.due), strong: true),
        if (plan != null) ...[
          pw.SizedBox(height: 4),
          pw.Text('Qist: ${plan.installments} × ${plan.frequency.name}, from ${Fmt.date(plan.startDate)}', style: k.small),
          if (plan.guarantorName != null) pw.Text('Guarantor: ${plan.guarantorName}', style: k.small),
        ],
        if (v.returns.any((r) => r.status == DocStatus.posted)) ...[
          pw.SizedBox(height: 4),
          for (final r in v.returns.where((r) => r.status == DocStatus.posted))
            k.kv('Return ${r.returnNo}', '− ${money(r.amount)}'),
        ],
        pw.Divider(color: PdfKit.line),
        if (b.invoiceTerms != null) pw.Text(b.invoiceTerms!, style: k.small, textAlign: pw.TextAlign.center),
        k.footer(b.invoiceFooter ?? 'Shukriya! Dobara tashreef layein.'),
      ],
    ),
  ));
  return doc.save();
}
