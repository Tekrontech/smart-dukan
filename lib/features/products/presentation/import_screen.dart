import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/files.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/primary_button.dart';
import '../application/import_service.dart';

/// Excel/CSV import with column mapping preview and error rows report
/// (spec 5.5).
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  List<List<String>>? _rows;
  Map<ImportField, int> _map = {};
  ImportPreview? _preview;
  List<ImportRowError>? _finalErrors;
  bool _busy = false;

  ProductImportService get _svc => ProductImportService(ref.read(databaseProvider), ref.read(ctxProvider));

  Future<void> _pick() async {
    final f = await pickNamedFile(extensions: ['csv', 'xlsx']);
    if (f == null || !mounted) return;
    final rows = await guard(context, () async => ProductImportService.parse(f.name, f.bytes));
    if (rows == null || rows.isEmpty) return;
    setState(() {
      _rows = rows;
      _map = ProductImportService.autoMap(rows.first);
      _finalErrors = null;
    });
    await _refreshPreview();
  }

  Future<void> _refreshPreview() async {
    final rows = _rows;
    if (rows == null) return;
    final p = await _svc.preview(rows.sublist(1), _map);
    if (mounted) setState(() => _preview = p);
  }

  String _fieldLabel(ImportField f) {
    final l = context.l10n;
    return switch (f) {
      ImportField.name => l.fieldName,
      ImportField.sku => l.sku,
      ImportField.barcode => l.barcodes,
      ImportField.category => l.category,
      ImportField.brand => l.brand,
      ImportField.salePrice => l.salePrice,
      ImportField.minSalePrice => l.minSalePrice,
      ImportField.cost => l.costPrice,
      ImportField.openingQty => l.fieldOpeningQty,
      ImportField.minStock => l.minStockAlert,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = AppColors.of(context);
    final rows = _rows;
    final preview = _preview;
    final errors = _finalErrors ?? preview?.errors ?? const [];
    return Scaffold(
      appBar: AppBar(title: Text(l.importProducts)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(l.importHint),
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(label: l.chooseFile, icon: Icons.upload_file_rounded, outlined: rows != null, onPressed: _pick),
          if (rows != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(l.mapColumns, style: Theme.of(context).textTheme.titleMedium),
            for (final f in ImportField.values)
              Row(children: [
                Expanded(child: Text(_fieldLabel(f))),
                Expanded(
                  child: DropdownButton<int?>(
                    isExpanded: true,
                    value: _map[f],
                    items: [
                      DropdownMenuItem(value: null, child: Text(l.notMapped)),
                      for (var i = 0; i < rows.first.length; i++) DropdownMenuItem(value: i, child: Text(rows.first[i])),
                    ],
                    onChanged: (v) {
                      setState(() => v == null ? _map.remove(f) : _map[f] = v);
                      _refreshPreview();
                    },
                  ),
                ),
              ]),
            if (preview != null) ...[
              const SizedBox(height: AppSpacing.md),
              Card(
                child: ListTile(
                  leading: Icon(Icons.fact_check_outlined, color: errors.isEmpty ? c.success : c.warning),
                  title: Text(l.previewRows(preview.valid.length, preview.errors.length)),
                ),
              ),
              for (final v in preview.valid.take(5))
                ListTile(dense: true, title: Text(v.input.name), trailing: Text('${v.qty}')),
              for (final e in errors.take(20))
                ListTile(
                  dense: true,
                  leading: Icon(Icons.error_outline, color: c.danger),
                  title: Text(l.rowError(e.row, e.message)),
                ),
              const SizedBox(height: AppSpacing.md),
              if (_finalErrors == null)
                PrimaryButton(
                  label: l.importNow(preview.valid.length),
                  icon: Icons.download_done_rounded,
                  loading: _busy,
                  onPressed: preview.valid.isEmpty
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          final r = await guard(context, () => _svc.run(preview));
                          if (!mounted) return;
                          setState(() {
                            _busy = false;
                            if (r != null) _finalErrors = r.errors;
                          });
                          if (r != null && context.mounted) showMessage(context, l.importDone(r.imported));
                        },
                ),
              if (errors.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                PrimaryButton(
                  label: l.shareErrorReport,
                  icon: Icons.share_rounded,
                  outlined: true,
                  onPressed: () => shareBytes(
                    'import_errors.csv',
                    Uint8List.fromList(utf8.encode(ProductImportService.errorReportCsv(rows.sublist(1), errors, rows.first))),
                    mimeType: 'text/csv',
                  ),
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }
}
