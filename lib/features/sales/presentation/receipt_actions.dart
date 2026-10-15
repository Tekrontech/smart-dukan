import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../app/providers.dart';
import '../../../core/db/app_database.dart';
import '../../../core/utils/files.dart';
import '../../../core/widgets/feedback.dart';
import '../application/receipt_pdf.dart';

Future<Uint8List?> _receipt(WidgetRef ref, String saleId) async {
  final db = ref.read(databaseProvider);
  final v = await ref.read(salesRepoProvider).load(saleId);
  final b = ref.read(sessionProvider).business;
  if (v == null || b == null) return null;
  final unitIds = v.items.map((i) => i.imeiUnitId).whereType<String>().toList();
  final imeis = unitIds.isEmpty ? const <ImeiUnit>[] : await (db.select(db.imeiUnits)..where((u) => u.id.isIn(unitIds))).get();
  final plan = await (db.select(db.qistPlans)..where((q) => q.saleId.equals(saleId))).getSingleOrNull();
  return buildReceiptPdf(v, b, imeis: imeis, plan: plan);
}

/// Share the receipt PDF (WhatsApp via the share sheet — spec 5.3 step 8).
Future<void> shareReceipt(BuildContext context, WidgetRef ref, String saleId, String invoiceNo) =>
    guard(context, () async {
      final pdf = await _receipt(ref, saleId);
      if (pdf != null) await shareBytes('$invoiceNo.pdf', pdf, mimeType: 'application/pdf');
    });

/// Share the receipt as a PNG image.
Future<void> shareReceiptImage(BuildContext context, WidgetRef ref, String saleId, String invoiceNo) =>
    guard(context, () async {
      final pdf = await _receipt(ref, saleId);
      if (pdf == null) return;
      await for (final page in Printing.raster(pdf, dpi: 200)) {
        final png = await page.toPng();
        await shareBytes('$invoiceNo.png', png, mimeType: 'image/png');
        break;
      }
    });

/// System print dialog (Bluetooth thermal printing comes in V1.1).
Future<void> printReceipt(BuildContext context, WidgetRef ref, String saleId) => guard(context, () async {
      final pdf = await _receipt(ref, saleId);
      if (pdf != null) await Printing.layoutPdf(onLayout: (_) async => pdf);
    });
