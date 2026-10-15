import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/providers.dart';
import '../../../core/db/app_database.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/security/license_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/ltr.dart';
import '../../../core/widgets/primary_button.dart';

String licenseErrorText(BuildContext context, LicenseError e) {
  final l = context.l10n;
  return switch (e) {
    LicenseError.malformed => l.licMalformed,
    LicenseError.badSignature => l.licBadSignature,
    LicenseError.wrongDevice => l.licWrongDevice,
    LicenseError.unknownPack => l.licUnknownPack,
  };
}

/// Opens WhatsApp with [text] (share intent, no API — spec Section 3).
Future<void> openWhatsApp(String text, {String? phone}) async {
  final digits = phone?.replaceAll(RegExp(r'[^0-9]'), '');
  final intl = digits == null || digits.isEmpty
      ? ''
      : (digits.startsWith('0') ? '92${digits.substring(1)}' : digits);
  final uri = Uri.parse('https://wa.me/$intl?text=${Uri.encodeComponent(text)}');
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

final _foreignProvider = FutureProvider.autoDispose<List<LicenseRow>>((ref) => ref.watch(licenseServiceProvider).foreignLicenses());

/// Licence and Pro packs (spec Section 2).
class LicenseScreen extends ConsumerStatefulWidget {
  const LicenseScreen({super.key, this.initialCode});

  /// From the `smartdukan://activate?c=` deep link.
  final String? initialCode;

  @override
  ConsumerState<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends ConsumerState<LicenseScreen> {
  late final _code = TextEditingController(text: widget.initialCode ?? '');
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialCode != null) WidgetsBinding.instance.addPostFrameCallback((_) => _activate());
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    if (_code.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref.read(licenseServiceProvider).activate(_code.text);
      ref.invalidate(proActiveProvider);
      ref.invalidate(_foreignProvider);
      if (mounted) {
        HapticFeedback.mediumImpact();
        showMessage(context, context.l10n.activated);
        _code.clear();
      }
    } on LicenseException catch (e) {
      if (mounted) showMessage(context, licenseErrorText(context, e.error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = AppColors.of(context);
    final theme = Theme.of(context);
    final svc = ref.watch(licenseServiceProvider);
    final grouped = LicenseService.group(svc.deviceCode);
    final active = ref.watch(proActiveProvider).value ?? false;
    final foreign = ref.watch(_foreignProvider).value ?? const [];
    final mismatch = ref.watch(startupInfoProvider).installIdMismatch;

    return Scaffold(
      appBar: AppBar(title: Text(l.licenseAndPro)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Card(
            color: active ? c.primaryContainer : null,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(active ? Icons.verified_rounded : Icons.workspace_premium_outlined,
                        color: active ? c.success : c.secondary, size: 32),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(active ? l.proActive : l.proInactive, style: theme.textTheme.titleLarge)),
                  ]),
                  const SizedBox(height: AppSpacing.sm),
                  Text(l.proFeatures),
                  if (!active) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(l.proPrice, style: theme.textTheme.titleSmall),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Text(l.proRecordsReadable, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ),
          if (mismatch && !active) ...[
            const SizedBox(height: AppSpacing.md),
            Card(child: ListTile(leading: Icon(Icons.info_outline, color: c.warning), title: Text(l.reactivateNeeded))),
          ],
          const SizedBox(height: AppSpacing.lg),
          Text(l.deviceCode, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(AppSpacing.buttonRadius), border: Border.all(color: c.outline)),
            child: Ltr(SelectableText(grouped,
                key: const Key('device_code'),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(fontFamily: 'monospace', letterSpacing: 1.5))),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: grouped));
                  if (context.mounted) showMessage(context, l.copied);
                },
                icon: const Icon(Icons.copy_rounded),
                label: Text(l.copy),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => openWhatsApp(l.deviceCodeMessage(grouped)),
                icon: const Icon(Icons.chat_rounded),
                label: Text(l.sendOnWhatsapp, overflow: TextOverflow.ellipsis),
              ),
            ),
          ]),
          if (!active) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(l.howToBuy, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(l.howToBuySteps),
          ],
          const SizedBox(height: AppSpacing.lg),
          TextField(
            key: const Key('activation_code'),
            controller: _code,
            decoration: InputDecoration(labelText: l.activationCode),
            minLines: 1,
            maxLines: 3,
          ),
          const SizedBox(height: AppSpacing.sm),
          PrimaryButton(label: l.activate, icon: Icons.lock_open_rounded, loading: _busy, onPressed: _activate),
          if (foreign.isNotEmpty && !active) ...[
            const SizedBox(height: AppSpacing.lg),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l.transferTitle, style: theme.textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Text(l.transferBody),
                    const SizedBox(height: AppSpacing.sm),
                    PrimaryButton(
                      label: l.sendTransfer,
                      icon: Icons.swap_horiz_rounded,
                      outlined: true,
                      onPressed: () => openWhatsApp(l.transferMessage(
                          foreign.first.licenseId, LicenseService.group(foreign.first.deviceCode), grouped)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
