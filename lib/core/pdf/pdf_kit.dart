import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../db/app_database.dart';
import '../money/money_format.dart';
import '../utils/fmt.dart';

/// Shared PDF building blocks: bundled fonts (Inter + Noto Naskh Arabic
/// fallback so Urdu names render), brand colour and the shop header.
class PdfKit {
  PdfKit._(this.regular, this.bold, this.urdu);

  final pw.Font regular;
  final pw.Font bold;
  final pw.Font urdu;

  static PdfKit? _cache;

  static Future<PdfKit> load() async {
    if (_cache != null) return _cache!;
    Future<pw.Font> f(String name) async => pw.Font.ttf(await rootBundle.load('assets/fonts/$name'));
    return _cache = PdfKit._(await f('Inter-Regular.ttf'), await f('Inter-Bold.ttf'), await f('NotoNaskhArabic-Regular.ttf'));
  }

  static const brand = PdfColor.fromInt(0xFF0F6E56);
  static const grey = PdfColor.fromInt(0xFF5B6B65);
  static const line = PdfColor.fromInt(0xFFDCE3E0);

  pw.ThemeData theme() => pw.ThemeData.withFont(base: regular, bold: bold, fontFallback: [urdu]);

  pw.TextStyle get small => const pw.TextStyle(fontSize: 8, color: grey);

  static String money(Money m) => MoneyFormat.format(m, urduDigits: false);

  /// Shop name, logo, address and phone.
  pw.Widget header(Business b, {String? title, String? subtitle, bool compact = false}) {
    pw.ImageProvider? logo;
    if (b.logoPath != null) {
      final f = File(b.logoPath!);
      if (f.existsSync()) logo = pw.MemoryImage(f.readAsBytesSync());
    }
    final info = [b.address, b.city, b.phone].whereType<String>().where((s) => s.isNotEmpty).join(' • ');
    return pw.Column(
      crossAxisAlignment: compact ? pw.CrossAxisAlignment.center : pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: compact ? pw.MainAxisAlignment.center : pw.MainAxisAlignment.start,
          children: [
            if (logo != null) pw.Container(width: compact ? 28 : 40, height: compact ? 28 : 40, child: pw.Image(logo)),
            if (logo != null) pw.SizedBox(width: 8),
            pw.Text(b.name, style: pw.TextStyle(font: bold, fontSize: compact ? 13 : 18, color: brand)),
          ],
        ),
        if (info.isNotEmpty) pw.Text(info, style: small, textAlign: compact ? pw.TextAlign.center : pw.TextAlign.left),
        if (title != null) ...[
          pw.SizedBox(height: 6),
          pw.Text(title, style: pw.TextStyle(font: bold, fontSize: compact ? 11 : 14)),
        ],
        if (subtitle != null) pw.Text(subtitle, style: small),
      ],
    );
  }

  pw.Widget kv(String k, String v, {bool strong = false, double size = 9}) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(k, style: pw.TextStyle(fontSize: size, font: strong ? bold : regular)),
          pw.Text(v, style: pw.TextStyle(fontSize: size, font: strong ? bold : regular)),
        ],
      );

  /// A simple table for reports and statements.
  pw.Widget table(List<String> headers, List<List<String>> rows, {Set<int> rightAligned = const {}}) {
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      headerStyle: pw.TextStyle(font: bold, fontSize: 8, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: brand),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellAlignments: {for (final i in rightAligned) i: pw.Alignment.centerRight},
      border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: line, width: 0.5)),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    );
  }

  pw.Widget footer(String text) => pw.Container(
        alignment: pw.Alignment.center,
        margin: const pw.EdgeInsets.only(top: 8),
        child: pw.Text(text, style: small),
      );

  static String stamp(DateTime d) => Fmt.dateTime(d);

  /// Multi-page A4 document (statements, reports).
  Future<Uint8List> a4(Business b, String title, String subtitle, List<pw.Widget> body) async {
    final doc = pw.Document(theme: theme(), title: title, author: b.name);
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      header: (ctx) => ctx.pageNumber == 1 ? header(b, title: title, subtitle: subtitle) : pw.SizedBox(),
      footer: (ctx) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('Smart Dukan', style: small),
        pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}', style: small),
      ]),
      build: (ctx) => [pw.SizedBox(height: 10), ...body],
    ));
    return doc.save();
  }
}
