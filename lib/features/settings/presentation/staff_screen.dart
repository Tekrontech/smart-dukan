import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/db/app_database.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/feedback.dart';
import 'more_screen.dart' show roleLabel;
import 'security_screen.dart' show askNewPin;

final _usersProvider = StreamProvider.autoDispose<List<AppUser>>((ref) => ref.watch(userServiceProvider).watchUsers());

/// Staff and roles (spec Section 9). Owner only.
class StaffScreen extends ConsumerWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final users = ref.watch(_usersProvider).value ?? const [];
    return Scaffold(
      appBar: AppBar(title: Text(l.staffAndRoles)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: Text(l.addStaff),
      ),
      body: ListView(
        children: [
          for (final u in users)
            ListTile(
              leading: CircleAvatar(child: Text(u.name.characters.first.toUpperCase())),
              title: Text(u.name),
              subtitle: Text('${roleLabel(context, u.role)} • ${u.isActive ? l.active : l.inactive}'),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _edit(context, ref, u),
            ),
          const SizedBox(height: 96),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, AppUser? user) async {
    final l = context.l10n;
    final name = TextEditingController(text: user?.name ?? '');
    var role = user?.role ?? UserRole.cashier;
    var active = user?.isActive ?? true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(user == null ? l.addStaff : l.edit),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: InputDecoration(labelText: l.name), autofocus: user == null),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<UserRole>(
                initialValue: role,
                decoration: InputDecoration(labelText: l.role),
                items: [for (final r in UserRole.values) DropdownMenuItem(value: r, child: Text(roleLabel(context, r)))],
                onChanged: (v) => set(() => role = v ?? role),
              ),
              if (user != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.active),
                  value: active,
                  onChanged: (v) => set(() => active = v),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(user == null ? l.next : l.save)),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted || name.text.trim().isEmpty) return;
    final svc = ref.read(userServiceProvider);
    if (user == null) {
      final pin = await askNewPin(context);
      if (pin == null || !context.mounted) return;
      await guard(context, () => svc.createUser(name: name.text, role: role, pin: pin));
    } else {
      await guard(context, () => svc.update(user.id, name: name.text, role: role, active: active));
    }
  }
}
