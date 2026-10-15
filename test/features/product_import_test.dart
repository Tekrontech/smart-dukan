import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_dukan/core/accounting/system_accounts.dart';
import 'package:smart_dukan/features/products/application/import_service.dart';

import '../helpers/test_shop.dart';

void main() {
  test('CSV import: auto mapping, preview with error rows, opening stock posted', () async {
    final shop = await TestShop.create();
    const csvText = 'Name,SKU,Barcode,Category,Sale Price,Cost,Qty,Min Stock\r\n'
        'Charger 20W,CH20,8901,Chargers,"1,200",700,10,2\r\n'
        ',X1,,Chargers,100,50,1,0\r\n'
        'Cable,CB1,8902,Cables,abc,50,1,0\r\n'
        'Cable C,CB2,8901,Cables,300,120,5,1\r\n'
        'Cover,CV1,,Covers,500,200,4,1\r\n';
    final rows = ProductImportService.parse('stock.csv', Uint8List.fromList(utf8.encode(csvText)));
    final map = ProductImportService.autoMap(rows.first);
    expect(map[ImportField.name], 0);
    expect(map[ImportField.salePrice], 4);
    expect(map[ImportField.openingQty], 6);

    final svc = ProductImportService(shop.db, shop.ctx);
    final preview = await svc.preview(rows.sublist(1), map);
    expect(preview.valid.map((v) => v.row), [2, 6]);
    expect(preview.errors.map((e) => e.row), [3, 4, 5]); // no name, bad price, duplicate barcode

    final result = await svc.run(preview);
    expect(result.imported, 2);
    expect(await shop.bal(SysAccount.inventory), rs(7000 + 800));
    expect((await shop.db.select(shop.db.categories).get()).map((c) => c.name).toSet(), {'Chargers', 'Covers'});
    final report = ProductImportService.errorReportCsv(rows.sublist(1), result.errors, rows.first);
    expect(report.split('\n').length, greaterThanOrEqualTo(4));
    await shop.expectHealthy();
  });

  test('XLSX import reads the first sheet', () async {
    final book = xl.Excel.createExcel();
    final sheet = book[book.getDefaultSheet()!];
    sheet.appendRow([xl.TextCellValue('Item'), xl.TextCellValue('Price'), xl.TextCellValue('Stock')]);
    sheet.appendRow([xl.TextCellValue('Earphones'), const xl.IntCellValue(450), const xl.IntCellValue(12)]);
    final bytes = Uint8List.fromList(book.encode()!);
    final rows = ProductImportService.parse('items.xlsx', bytes);
    expect(rows, [
      ['Item', 'Price', 'Stock'],
      ['Earphones', '450', '12'],
    ]);
    final map = ProductImportService.autoMap(rows.first);
    expect(map, {ImportField.name: 0, ImportField.salePrice: 1, ImportField.openingQty: 2});
  });
}
