import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/db/app_database.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/party_tile.dart';
import '../application/party_service.dart';
import '../data/parties_repository.dart';

/// Picks a customer or supplier, with quick-add (name + phone) — spec 5.3.
/// Returns null when dismissed; `(id: null)` means "walk-in".
Future<({String? id, String? name})?> pickParty(BuildContext context,
    {PartyType kind = PartyType.customer, bool allowWalkIn = true}) {
  return showModalBottomSheet<({String? id, String? name})>(
    context: context,
    isScrollControlled: true,
    builder: (_) => FractionallySizedBox(heightFactor: 0.85, child: _PartyPicker(kind: kind, allowWalkIn: allowWalkIn)),
  );
}

class _PartyPicker extends ConsumerStatefulWidget {
  const _PartyPicker({required this.kind, required this.allowWalkIn});

  final PartyType kind;
  final bool allowWalkIn;

  @override
  ConsumerState<_PartyPicker> createState() => _PartyPickerState();
}

class _PartyPickerState extends ConsumerState<_PartyPicker> {
  final _search = TextEditingController();
  late Stream<List<PartyListItem>> _stream = _make();

  Stream<List<PartyListItem>> _make() =>
      ref.read(partiesRepoProvider).list(kind: widget.kind, search: _search.text, limit: 100).watch();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _quickAdd() async {
    final l = context.l10n;
    final name = TextEditingController(text: _search.text.trim());
    final phone = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.kind == PartyType.supplier ? l.addSupplier : l.quickAddCustomer),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, autofocus: true, decoration: InputDecoration(labelText: l.name), textCapitalization: TextCapitalization.words),
          const SizedBox(height: AppSpacing.sm),
          TextField(controller: phone, decoration: InputDecoration(labelText: l.phone), keyboardType: TextInputType.phone),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.add)),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty || !mounted) return;
    final id = await guard(
        context,
        () => ref.read(partyServiceProvider).createParty(PartyInput(type: widget.kind, name: name.text, phone: phone.text)));
    if (id != null && mounted) Navigator.of(context).pop((id: id, name: name.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
          child: TextField(
            controller: _search,
            autofocus: true,
            decoration: InputDecoration(hintText: l.search, prefixIcon: const Icon(Icons.search)),
            onChanged: (_) => setState(() => _stream = _make()),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.person_add_alt_1_rounded),
          title: Text(widget.kind == PartyType.supplier ? l.addSupplier : l.quickAddCustomer),
          onTap: _quickAdd,
        ),
        if (widget.allowWalkIn)
          ListTile(
            leading: const Icon(Icons.directions_walk_rounded),
            title: Text(l.walkInCustomer),
            onTap: () => Navigator.of(context).pop((id: null, name: null)),
          ),
        const Divider(height: 1),
        Expanded(
          child: StreamBuilder<List<PartyListItem>>(
            stream: _stream,
            builder: (context, snap) {
              final items = snap.data ?? const <PartyListItem>[];
              return ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final it = items[i];
                  return PartyTile(
                    name: it.party.name,
                    phone: it.party.phone,
                    balance: it.balance,
                    lenaLabel: l.lenaLabel,
                    denaLabel: l.denaLabel,
                    onTap: () => Navigator.of(context).pop((id: it.party.id, name: it.party.name)),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
