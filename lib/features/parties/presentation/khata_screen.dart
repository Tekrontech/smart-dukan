import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../core/db/app_database.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/fmt.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/party_tile.dart';
import '../data/parties_repository.dart';

/// Khata — customers and suppliers sorted by balance, with search (5.6).
class KhataScreen extends ConsumerWidget {
  const KhataScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return DefaultTabController(
      length: 2,
      child: Builder(builder: (context) {
        return Scaffold(
          appBar: AppBar(
            title: Text(l.tabKhata),
            bottom: TabBar(tabs: [Tab(text: l.customers), Tab(text: l.suppliers)]),
          ),
          body: const TabBarView(children: [
            _PartyList(kind: PartyType.customer),
            _PartyList(kind: PartyType.supplier),
          ]),
          floatingActionButton: ref.watch(permissionsProvider).editParties
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 72),
                  child: FloatingActionButton(
                    heroTag: 'add_party',
                    tooltip: l.addCustomer,
                    onPressed: () {
                      final tab = DefaultTabController.of(context).index;
                      context.push(Routes.partyNew(tab == 0 ? PartyType.customer : PartyType.supplier));
                    },
                    child: const Icon(Icons.person_add_alt_1_rounded),
                  ),
                )
              : null,
        );
      }),
    );
  }
}

class _PartyList extends ConsumerStatefulWidget {
  const _PartyList({required this.kind});

  final PartyType kind;

  @override
  ConsumerState<_PartyList> createState() => _PartyListState();
}

class _PartyListState extends ConsumerState<_PartyList> with AutomaticKeepAliveClientMixin {
  final _search = TextEditingController();
  int _limit = 50;
  late Stream<List<PartyListItem>> _stream = _make();

  Stream<List<PartyListItem>> _make() =>
      ref.read(partiesRepoProvider).list(kind: widget.kind, search: _search.text, limit: _limit).watch();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l = context.l10n;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: TextField(
          controller: _search,
          decoration: InputDecoration(hintText: l.search, prefixIcon: const Icon(Icons.search)),
          onChanged: (_) => setState(() => _stream = _make()),
        ),
      ),
      Expanded(
        child: StreamBuilder<List<PartyListItem>>(
          stream: _stream,
          builder: (context, snap) {
            final rows = snap.data;
            if (rows == null) return const Center(child: CircularProgressIndicator());
            if (rows.isEmpty) {
              return EmptyState(
                icon: widget.kind == PartyType.customer ? Icons.people_outline_rounded : Icons.local_shipping_outlined,
                title: _search.text.isEmpty ? l.khataEmptyTitle : l.nothingFound,
                message: _search.text.isEmpty ? l.khataEmptyBody : '',
                actionLabel: _search.text.isEmpty ? (widget.kind == PartyType.customer ? l.addCustomer : l.addSupplier) : null,
                actionIcon: Icons.person_add_alt_1_rounded,
                onAction: () => context.push(Routes.partyNew(widget.kind)),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.only(bottom: 160),
              itemCount: rows.length + (rows.length >= _limit ? 1 : 0),
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
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
                final it = rows[i];
                return PartyTile(
                  name: it.party.name,
                  phone: it.party.phone,
                  subtitle: it.lastActivity == null ? null : l.lastActivity(Fmt.date(it.lastActivity!)),
                  balance: it.balance,
                  lenaLabel: l.lenaLabel,
                  denaLabel: it.party.type == PartyType.customer ? l.advanceLabel : l.denaLabel,
                  onTap: () => context.push(Routes.party(it.party.id)),
                );
              },
            );
          },
        ),
      ),
    ]);
  }
}
