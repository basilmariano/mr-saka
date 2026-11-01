import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../l10n/app_localizations.dart';

/// A confirm/cancel dialog.
///
/// Used wherever the farmer is about to do something they cannot casually undo —
/// archiving a field, closing a cropping (FR-012c). Returns true only on an
/// explicit confirm, never on a dismiss.
Future<bool> confirm({
  required BuildContext context,
  required String title,
  required String body,
  required String confirmLabel,
  /// Overrides the dismiss label. "Cancel" is ambiguous whenever the dialog
  /// interrupts another action — cancelling the dialog is not the same as
  /// cancelling what the farmer was doing — so callers can name the decline.
  String? cancelLabel,
  bool destructive = false,
}) async {
  final l10n = AppLocalizations.of(context);
  final result = await showFDialog<bool>(
    context: context,
    builder: (dialogContext, style, animation) => FDialog.adaptive(
      style: (_) => style,
      title: Text(title),
      body: Text(body),
      actions: [
        FButton(
          style: FButtonStyle.outline(),
          onPress: () => Navigator.of(dialogContext).pop(false),
          child: Text(cancelLabel ?? l10n.actionCancel),
        ),
        FButton(
          style: destructive ? FButtonStyle.destructive() : FButtonStyle.primary(),
          onPress: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
