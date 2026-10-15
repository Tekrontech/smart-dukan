import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../../../app/providers.dart';
import '../../../core/db/app_database.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/primary_button.dart';
import '../../onboarding/application/business_setup_service.dart';
import '../../onboarding/presentation/onboarding_screen.dart' show businessTypeLabel;

/// Shop profile, logo and invoice settings (spec 5.11).
class ShopProfileScreen extends ConsumerStatefulWidget {
  const ShopProfileScreen({super.key});

  @override
  ConsumerState<ShopProfileScreen> createState() => _ShopProfileScreenState();
}

class _ShopProfileScreenState extends ConsumerState<ShopProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final Business b = ref.read(sessionProvider).business!;
  late final _name = TextEditingController(text: b.name);
  late final _owner = TextEditingController(text: b.ownerName);
  late final _phone = TextEditingController(text: b.phone ?? '');
  late final _city = TextEditingController(text: b.city ?? '');
  late final _address = TextEditingController(text: b.address ?? '');
  late final _prefix = TextEditingController(text: b.invoicePrefix);
  late final _footer = TextEditingController(text: b.invoiceFooter ?? '');
  late final _terms = TextEditingController(text: b.invoiceTerms ?? '');
  late BusinessType _type = b.businessType;
  late String? _logo = b.logoPath;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _owner, _phone, _city, _address, _prefix, _footer, _terms]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 85);
    if (x == null) return;
    final dir = ref.read(appDirProvider);
    final dest = File(p.join(dir.path, 'logo${p.extension(x.path).isEmpty ? '.png' : p.extension(x.path)}'));
    await File(x.path).copy(dest.path);
    setState(() => _logo = dest.path);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final ok = await guard(context, () async {
      await BusinessSetupService(ref.read(databaseProvider)).updateProfile(
        b.id,
        name: _name.text,
        ownerName: _owner.text,
        phone: _phone.text,
        city: _city.text,
        address: _address.text,
        type: _type,
        logoPath: _logo ?? '',
        invoicePrefix: _prefix.text,
        invoiceFooter: _footer.text,
        invoiceTerms: _terms.text,
      );
      await ref.read(sessionProvider.notifier).reloadBusiness();
      return true;
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok == true) {
      showMessage(context, context.l10n.saved);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.shopProfile)),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Center(
              child: InkWell(
                onTap: _pickLogo,
                borderRadius: BorderRadius.circular(48),
                child: CircleAvatar(
                  radius: 44,
                  backgroundImage: _logo != null && File(_logo!).existsSync() ? FileImage(File(_logo!)) : null,
                  child: _logo == null ? const Icon(Icons.add_a_photo_outlined) : null,
                ),
              ),
            ),
            if (_logo != null)
              Center(child: TextButton(onPressed: () => setState(() => _logo = null), child: Text(l.removeLogo))),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _name,
              decoration: InputDecoration(labelText: l.shopName),
              validator: (v) => (v == null || v.trim().isEmpty) ? l.fieldRequired : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(controller: _owner, decoration: InputDecoration(labelText: l.ownerName)),
            const SizedBox(height: AppSpacing.md),
            TextFormField(controller: _phone, decoration: InputDecoration(labelText: l.phone), keyboardType: TextInputType.phone),
            const SizedBox(height: AppSpacing.md),
            TextFormField(controller: _city, decoration: InputDecoration(labelText: l.city)),
            const SizedBox(height: AppSpacing.md),
            TextFormField(controller: _address, decoration: InputDecoration(labelText: l.address), maxLines: 2),
            const SizedBox(height: AppSpacing.md),
            Text(l.businessType, style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final t in BusinessType.values)
                  ChoiceChip(
                      label: Text(businessTypeLabel(context, t)),
                      selected: _type == t,
                      onSelected: (_) => setState(() => _type = t)),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(l.invoiceSettings, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(controller: _prefix, decoration: InputDecoration(labelText: l.invoicePrefix)),
            const SizedBox(height: AppSpacing.md),
            TextFormField(controller: _footer, decoration: InputDecoration(labelText: l.invoiceFooter), maxLines: 2),
            const SizedBox(height: AppSpacing.md),
            TextFormField(controller: _terms, decoration: InputDecoration(labelText: l.invoiceTerms), maxLines: 3),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(label: l.save, icon: Icons.check_rounded, loading: _saving, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
