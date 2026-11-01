import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../domain/model/centavos.dart';

/// Displays a peso amount.
///
/// Formatting happens here, at the display boundary, and nowhere else — the domain
/// layer works in exact integer centavos throughout (data-model.md rounding rule).
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.amount, {
    this.style,
    this.signed = false,
    super.key,
  });

  final Centavos amount;
  final TextStyle? style;

  /// Colours a loss and a profit differently. Used on result screens (FR-039).
  final bool signed;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final colour = !signed
        ? null
        : amount.isNegative
            ? theme.colors.destructive
            : theme.colors.primary;
    return Text(
      amount.formatWithSymbol(),
      style: (style ?? theme.typography.base).copyWith(color: colour),
    );
  }
}
