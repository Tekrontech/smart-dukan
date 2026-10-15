import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../core/db/app_database.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/fmt.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/ltr.dart';
import '../data/sales_repository.dart';
import 'sale_detail_screen.dart' show docStatusLabel;

class SalesListScreen extends ConsumerStatefulWidget {
  const SalesListScreen({super.key});

  @override
  ConsumerState<SalesListScreen> createState() => _SalesListScreenState();
}

class _SalesListScreenState extends ConsumerState<SalesListScreen> {
  final _search = TextEditingController();
  int _limit = 50;
  late Stream<List<SaleListItem>> _stream = _make();

  Stream<List<SaleListItem>> _make() => ref.read(salesRepoProvider).list(search: _search.text, limit: _limit).watch();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.salesList)),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(hintText: l.searchInvoice, prefixIcon: const Icon(Icons.search)),
            onChanged: (_) => setState(() => _stream = _make()),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<SaleListItem>>(
            stream: _stream,
            builder: (context, snap) {
              final rows = snap.data;
              if (rows == null) return const Center(child: CircularProgressIndicator());
              if (rows.isEmpty) return EmptyState(icon: Icons.receipt_long_outlined, title: l.noSales, message: '');
              return ListView.separated(
                itemCount: rows.length + (rows.length >= _limit ? 1 : 0),
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  if (i == rows.length) {
                    return TextButton(
                      onPressed: () => setState(() {
                        _limit += 50;
                        _stream = _make();
                      }),
                      child: Text(l.loadMore),
                    );
                  }
                  final s = rows[i].sale;
                  final reversed = s.status != DocStatus.posted;
                  return ListTile(
                    onTap: () => context.push(Routes.saleDetail(s.id)),
                    title: Ltr(Text(s.invoiceNo, style: TextStyle(decoration: reversed ? TextDecoration.lineThrough : null))),
                    subtitle: Text('${rows[i].partyName ?? l.walkInCustomer} • ${Fmt.dateTime(s.date)}'
                        '${reversed ? ' • ${docStatusLabel(context, s.status)}' : ''}'),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Ltr(Text(Fmt.money(s.total), style: Theme.of(context).textTheme.titleSmall)),
                        if (!s.due.isZero && !reversed)
                          Ltr(Text(Fmt.money(s.due), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c.danger))),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}
