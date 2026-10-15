import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart' as csvlib;
import 'package:excel/excel.dart' as xl;

import '../../../core/accounting/posting.dart';
import '../../../core/db/app_database.dart';
import '../../../core/money/money_format.dart';
import 'product_service.dart';

/// Columns that can be mapped from a spreadsheet (spec 5.5 import).
enum ImportField { name, sku, barcode, category, brand, salePrice, minSalePrice, cost, openingQty, minStock }

/// One row that failed validation or import.
class ImportRowError {
  const ImportRowError(this.row, this.message);

  /// 1-based row number as the user sees it in the sheet.
  final int row;
  final String message;
}

class ImportPreview {
  const ImportPreview({required this.valid, required this.errors});

  final List<({int row, ProductInput input, int qty, Money cost})> valid;
  final List<ImportRowError> errors;
}

/// Excel/CSV product import with column mapping preview and an error-rows
/// report. Opening stock goes through the posting engine like any other.
class ProductImportService {
  ProductImportService(this.db, this.ctx);

  final AppDatabase db;
  final BusinessCtx ctx;

  /// Reads `.csv` or `.xlsx` into rows of trimmed strings.
  static List<List<String>> parse(String fileName, Uint8List bytes) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.xlsx') || lower.endsWith('.xls')) {
      final book = xl.Excel.decodeBytes(bytes);
      final sheet = book.tables.values.firstOrNull;
      if (sheet == null) return const [];
      return [
        for (final r in sheet.rows) [for (final c in r) (c?.value?.toString() ?? '').trim()],
      ].where((r) => r.any((c) => c.isNotEmpty)).toList();
    }
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('﻿')) text = text.substring(1);
    final rows = csvlib.Csv().decode(text);
    return [
      for (final r in rows) [for (final c in r) '$c'.trim()],
    ].where((r) => r.any((c) => c.isNotEmpty)).toList();
  }

  static const Map<ImportField, List<String>> _synonyms = {
    ImportField.name: ['name', 'product', 'item', 'naam', 'product name', 'item name', 'maal'],
    ImportField.sku: ['sku', 'code', 'item code', 'product code'],
    ImportField.barcode: ['barcode', 'bar code', 'ean'],
    ImportField.category: ['category', 'qisam', 'group'],
    ImportField.brand: ['brand', 'company'],
    ImportField.salePrice: ['sale price', 'price', 'selling price', 'qeemat', 'rate', 'sale'],
    ImportField.minSalePrice: ['min sale price', 'minimum price', 'min price'],
    ImportField.cost: ['cost', 'cost price', 'purchase price', 'laagat', 'buy price'],
    ImportField.openingQty: ['qty', 'quantity', 'stock', 'opening stock', 'opening qty', 'tadaad'],
    ImportField.minStock: ['min stock', 'reorder', 'minimum stock', 'alert'],
  };

  /// Guesses which column holds which field from the header row.
  static Map<ImportField, int> autoMap(List<String> header) {
    final map = <ImportField, int>{};
    for (var i = 0; i < header.length; i++) {
      final h = header[i].toLowerCase().replaceAll(RegExp(r'[_\-\.]+'), ' ').trim();
      for (final e in _synonyms.entries) {
        if (map.containsKey(e.key)) continue;
        if (e.value.contains(h)) {
          map[e.key] = i;
          break;
        }
      }
    }
    return map;
  }

  static Money? _money(String s) => s.isEmpty ? Money.zero : MoneyFormat.parse(s.replaceAll(RegExp(r'rs\.?', caseSensitive: false), '').trim());

  /// Validates data rows (header excluded) against [mapping].
  Future<ImportPreview> preview(List<List<String>> dataRows, Map<ImportField, int> mapping) async {
    final valid = <({int row, ProductInput input, int qty, Money cost})>[];
    final errors = <ImportRowError>[];
    final existingSkus = (await db.select(db.products).get()).map((p) => p.sku.toLowerCase()).toSet();
    final existingCodes = (await db.select(db.barcodes).get()).map((b) => b.code).toSet();
    final seenSkus = <String>{};
    final seenCodes = <String>{};

    String cell(List<String> r, ImportField f) {
      final i = mapping[f];
      return i == null || i >= r.length ? '' : r[i].trim();
    }

    for (var i = 0; i < dataRows.length; i++) {
      final r = dataRows[i];
      final rowNo = i + 2; // +1 header, +1 for 1-based
      final name = cell(r, ImportField.name);
      if (name.isEmpty) {
        errors.add(ImportRowError(rowNo, 'name missing'));
        continue;
      }
      final price = _money(cell(r, ImportField.salePrice));
      final minPrice = _money(cell(r, ImportField.minSalePrice));
      final cost = _money(cell(r, ImportField.cost));
      final qtyText = cell(r, ImportField.openingQty);
      final qty = qtyText.isEmpty ? 0 : int.tryParse(qtyText.replaceAll(',', '').split('.').first);
      final minStockText = cell(r, ImportField.minStock);
      final minStock = minStockText.isEmpty ? 0 : int.tryParse(minStockText.split('.').first);
      if (price == null || price.isNegative) {
        errors.add(ImportRowError(rowNo, 'bad sale price'));
        continue;
      }
      if (cost == null || cost.isNegative || minPrice == null) {
        errors.add(ImportRowError(rowNo, 'bad cost'));
        continue;
      }
      if (qty == null || qty < 0 || minStock == null || minStock < 0) {
        errors.add(ImportRowError(rowNo, 'bad quantity'));
        continue;
      }
      final sku = cell(r, ImportField.sku);
      if (sku.isNotEmpty && (existingSkus.contains(sku.toLowerCase()) || !seenSkus.add(sku.toLowerCase()))) {
        errors.add(ImportRowError(rowNo, 'duplicate SKU $sku'));
        continue;
      }
      final code = cell(r, ImportField.barcode);
      if (code.isNotEmpty && (existingCodes.contains(code) || !seenCodes.add(code))) {
        errors.add(ImportRowError(rowNo, 'duplicate barcode $code'));
        continue;
      }
      valid.add((
        row: rowNo,
        input: ProductInput(
          name: name,
          sku: sku.isEmpty ? null : sku,
          salePrice: price,
          minSalePrice: minPrice,
          minStock: minStock,
          barcodes: code.isEmpty ? const [] : [code],
          // category/brand names are resolved to ids in [run]
          categoryId: cell(r, ImportField.category).isEmpty ? null : cell(r, ImportField.category),
          brandId: cell(r, ImportField.brand).isEmpty ? null : cell(r, ImportField.brand),
        ),
        qty: qty,
        cost: cost,
      ));
    }
    return ImportPreview(valid: valid, errors: errors);
  }

  /// Imports the valid rows. Each product (with its opening stock) is its own
  /// transaction; failures are added to the returned error list.
  Future<({int imported, List<ImportRowError> errors})> run(ImportPreview preview) async {
    final svc = ProductService(db, ctx);
    final cats = {for (final c in await db.select(db.categories).get()) c.name.toLowerCase(): c.id};
    final brands = {for (final b in await db.select(db.brands).get()) b.name.toLowerCase(): b.id};
    final errors = [...preview.errors];
    var imported = 0;
    for (final v in preview.valid) {
      try {
        final catName = v.input.categoryId;
        final brandName = v.input.brandId;
        final catId = catName == null ? null : cats[catName.toLowerCase()] ??= await svc.createCategory(catName);
        final brandId = brandName == null ? null : brands[brandName.toLowerCase()] ??= await svc.createBrand(brandName);
        final i = v.input;
        await svc.createProduct(
          ProductInput(
            name: i.name,
            sku: i.sku,
            categoryId: catId,
            brandId: brandId,
            salePrice: i.salePrice,
            minSalePrice: i.minSalePrice,
            minStock: i.minStock,
            barcodes: i.barcodes,
          ),
          openingQty: v.qty,
          openingCost: v.cost,
        );
        imported++;
      } catch (e) {
        errors.add(ImportRowError(v.row, e is PostingException ? e.code.name : 'error'));
      }
    }
    errors.sort((a, b) => a.row.compareTo(b.row));
    return (imported: imported, errors: errors);
  }

  /// CSV of the rows that failed, for the error report.
  static String errorReportCsv(List<List<String>> dataRows, List<ImportRowError> errors, List<String> header) {
    final rows = <List<String>>[
      ['row', 'error', ...header],
      for (final e in errors) ['${e.row}', e.message, ...dataRows[e.row - 2]],
    ];
    return csvlib.Csv(lineDelimiter: '\n').encode(rows);
  }
}
