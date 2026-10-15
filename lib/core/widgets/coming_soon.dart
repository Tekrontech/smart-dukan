import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

/// Temporary helper for placeholder actions during early milestones.
void showComingSoon(BuildContext context) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(context.l10n.comingSoon), behavior: SnackBarBehavior.floating));
}
