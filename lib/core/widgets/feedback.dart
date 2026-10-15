import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../accounting/posting.dart';
import '../l10n/l10n.dart';

/// Localized message for any error thrown by a use case.
String errorText(BuildContext context, Object error) {
  final l = context.l10n;
  if (error is PostingException) {
    if (error.detail == 'pin_in_use') return l.pinInUse;
    if (error.detail == 'last_owner') return l.lastOwner;
    return switch (error.code) {
      PostingError.unbalanced => l.errUnbalanced,
      PostingError.invalidAmount => l.errInvalidAmount,
      PostingError.invalidInput => l.errInvalidInput,
      PostingError.emptyDocument => l.errEmpty,
      PostingError.insufficientStock => l.errStock,
      PostingError.imeiRequired => l.errImeiRequired,
      PostingError.imeiNotAvailable => l.errImeiNotAvailable,
      PostingError.imeiDuplicate => l.errImeiDuplicate,
      PostingError.partyRequired => l.errPartyRequired,
      PostingError.overReturn => l.errOverReturn,
      PostingError.belowMinPrice => l.errBelowMin,
      PostingError.alreadyReversed => l.errAlreadyReversed,
      PostingError.cannotReverse => l.errCannotReverse,
      PostingError.overpayment => l.errOverpayment,
      PostingError.notFound => l.errNotFound,
      PostingError.dayAlreadyClosed => l.errDayClosed,
    };
  }
  return l.errGeneric;
}

void showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(errorText(context, error)),
      behavior: SnackBarBehavior.floating,
      backgroundColor: Theme.of(context).colorScheme.error,
    ));
}

void showMessage(BuildContext context, String message, {String? actionLabel, VoidCallback? onAction, Duration? duration}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      duration: duration ?? const Duration(seconds: 3),
      action: actionLabel == null ? null : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
    ));
}

/// Subtle haptic on money saved (spec Section 4, Motion and feel).
void savedHaptic() => HapticFeedback.mediumImpact();

/// Runs [action], showing a localized error on failure. Returns null when it
/// failed.
Future<T?> guard<T>(BuildContext context, Future<T> Function() action) async {
  try {
    return await action();
  } catch (e, st) {
    // Never log personal data (spec 9): only the error type.
    debugPrint('Action failed: ${e.runtimeType}');
    assert(() {
      debugPrintStack(stackTrace: st, maxFrames: 5);
      return true;
    }());
    if (context.mounted) showError(context, e);
    return null;
  }
}
