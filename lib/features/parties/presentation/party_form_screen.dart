import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/db/app_database.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/ltr.dart';
import '../../../core/widgets/money_field.dart';
import '../../../core/widgets/primary_button.dart';
import '../application/party_service.dart';

/// Create / edit a customer or supplier with opening balance and credit
/// limit (spec 5.6).
class PartyFormScreen extends ConsumerStatefulWidget {
  const PartyFormScreen({super.key, this.partyId, this.type = PartyType.customer});

  final String? partyId;
  final PartyType type;

  @override
  ConsumerState<PartyFormScreen> createState() => _PartyFormScreenState();
}

class _PartyFormScreenState extends ConsumerState<PartyFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _cnic = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();
  final _opening = TextEditingController();
  final _limit = TextEditingController();
  late PartyType _type = widget.type;
  bool _theyOwe = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.partyId != null) {
      ref.read(partiesRepoProvider).party(widget.partyId!).then((p) {
        if (p == null || !mounted) return;
        setState(() {
          _type = p.type;
          _name.text = p.name;
          _phone.text = p.phone ?? '';
          _cnic.text = p.cnic ?? '';
          _address.text = p.address ?? '';
          _notes.text = p.notes ?? '';
          _limit.text = MoneyField.text(p.creditLimit);
        });
      });
    } else {
      _theyOwe = widget.type != PartyType.supplier;
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _cnic, _address, _notes, _opening, _limit]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final input = PartyInput(
      type: _type,
      name: _name.text,
      phone: _phone.text,
      cnic: _cnic.text,
      address: _address.text,
      notes: _notes.text,
      creditLimit: MoneyField.read(_limit) ?? Money.zero,
    );
    setState(() => _busy = true);
    final svc = ref.read(partyServiceProvider);
    final ok = await guard(context, () async {
      if (widget.partyId == null) {
        final opening = MoneyField.read(_opening) ?? Money.zero;
        await svc.createParty(input, openingBalance: _theyOwe ? opening : -opening);
      } else {
        await svc.updateParty(widget.partyId!, input);
      }
      return true;
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok == true) {
      showMessage(context, context.l10n.partySaved);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final creating = widget.partyId == null;
    return Scaffold(
      appBar: AppBar(title: Text(creating ? (_type == PartyType.supplier ? l.addSupplier : l.addCustomer) : l.editParty)),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            SegmentedButton<PartyType>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: PartyType.customer, label: Text(l.typeCustomer)),
                ButtonSegment(value: PartyType.supplier, label: Text(l.typeSupplier)),
                ButtonSegment(value: PartyType.both, label: Text(l.typeBoth)),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              key: const Key('party_name'),
              controller: _name,
              autofocus: creating,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: l.name),
              validator: (v) => (v == null || v.trim().isEmpty) ? l.fieldRequired : null,
            ),
            const SizedBox(height: AppSpacing.md),
            Ltr(TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: l.phone))),
            const SizedBox(height: AppSpacing.md),
            TextFormField(controller: _address, decoration: InputDecoration(labelText: l.address)),
            const SizedBox(height: AppSpacing.md),
            if (ref.watch(permissionsProvider).viewCnic) ...[
              Ltr(TextFormField(controller: _cnic, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: '${l.cnic} (${l.optional})'))),
              const SizedBox(height: AppSpacing.md),
            ],
            if (_type != PartyType.supplier) ...[
              MoneyField(controller: _limit, label: l.creditLimit),
              const SizedBox(height: AppSpacing.md),
            ],
            if (creating) ...[
              MoneyField(key: const Key('party_opening'), controller: _opening, label: l.openingBalance),
              RadioGroup<bool>(
                groupValue: _theyOwe,
                onChanged: (v) => setState(() => _theyOwe = v ?? true),
                child: Column(children: [
                  RadioListTile<bool>(value: true, title: Text(l.openingTheyOwe)),
                  RadioListTile<bool>(value: false, title: Text(l.openingIOwe)),
                ]),
              ),
            ],
            TextFormField(controller: _notes, decoration: InputDecoration(labelText: l.note), maxLines: 2),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(key: const Key('party_save'), label: l.save, icon: Icons.check_rounded, loading: _busy, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
