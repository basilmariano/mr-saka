import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../l10n/app_localizations.dart';

/// The general-guidance statement shown wherever a fertilizer recommendation appears.
///
/// FR-026 requires this everywhere a recommendation is shown — not once in an about
/// screen. FR-026a adds the source, because "general guidance" only reads as honest
/// if the farmer can see where the figures came from.
class GuidanceNotice extends StatelessWidget {
  const GuidanceNotice({
    required this.sourceAttribution,
    required this.isPlaceholder,
    super.key,
  });

  final String? sourceAttribution;

  /// research.md R9: while the bundle carries stand-in figures, the app says the
  /// amounts are unavailable rather than presenting them as guidance.
  final bool isPlaceholder;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = context.theme;
    return FAlert(
      icon: const Icon(FIcons.info),
      title: Text(isPlaceholder ? l10n.guidanceUnverified : l10n.guidanceDisclaimer),
      subtitle: sourceAttribution != null && !isPlaceholder
          ? Text(
              l10n.guidanceSource(sourceAttribution!),
              style: theme.typography.xs,
            )
          : null,
    );
  }
}
