import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../domain/calc/yield_calc.dart';
import '../../domain/model/enums.dart';
import '../../l10n/app_localizations.dart';
import '../common/labels.dart';
import '../common/providers.dart';
import '../common/widgets/money_text.dart';

/// The result for one cropping. FR-039 to FR-042b.
///
/// Three states, and the distinction matters: before harvest the absence of revenue
/// is NOT a loss (FR-042); while harvested and open the figures are provisional and
/// will move as post-harvest costs land (FR-042a); only a closed cropping is final
/// (FR-042b).
class CroppingResultView extends ConsumerWidget {
  const CroppingResultView({required this.croppingId, super.key});

  final String croppingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = context.theme;
    final result = ref.watch(croppingResultProvider(croppingId));

    return result.when(
      loading: () => const Center(child: FCircularProgress()),
      error: (error, _) => Center(child: Text('$error')),
      data: (data) {
        if (data == null) return const SizedBox.shrink();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StateBanner(state: data.state),
            const SizedBox(height: 12),
            _Row(label: l10n.resultExpenses, child: MoneyText(data.totalExpenses)),
            if (data.showsProfit) ...[
              _Row(label: l10n.resultRevenue, child: MoneyText(data.revenue)),
              _Row(
                label: data.netProfit.isNegative
                    ? l10n.resultLoss
                    : l10n.resultProfit,
                child: MoneyText(
                  data.netProfit,
                  signed: true,
                  style: theme.typography.xl,
                ),
              ),
            ],
            const FDivider(),
            if (data.harvested != null) ...[
              _Row(
                label: '${l10n.resultYield} (${l10n.freshWeight})',
                child: Text('${data.harvested!.formatTons()} ${l10n.tonsUnit}'),
              ),
              _Row(
                label: l10n.resultYieldPerHectare,
                child: Text(
                  YieldCalc.formatTonsPerHectare(data.tonsPerHectareScaled2),
                ),
              ),
              _Row(
                label: l10n.resultCostPerKg,
                // FR-041: not applicable, never a division error.
                child: data.costPerKg == null
                    ? Text(l10n.resultNotApplicable)
                    : MoneyText(data.costPerKg!),
              ),
              if (data.remaining != null)
                _Row(
                  label: l10n.salesTitle,
                  child: Text(
                    l10n.saleRemaining(
                      data.remaining!.quantity.formatKg(),
                      l10n.weightBasis(data.remaining!.basis),
                    ),
                  ),
                ),
              const FDivider(),
            ],
            Text(l10n.resultBreakdown, style: theme.typography.sm),
            const SizedBox(height: 8),
            if (data.breakdown.isEmpty)
              Text(
                l10n.expenseNone,
                style: theme.typography.sm
                    .copyWith(color: theme.colors.mutedForeground),
              )
            else
              ...data.breakdown.map(
                (share) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(l10n.categoryLabel(share.category)),
                      ),
                      const SizedBox(width: 8),
                      Text(share.formatPercent()),
                      const SizedBox(width: 16),
                      Flexible(flex: 2, child: MoneyText(share.total)),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StateBanner extends StatelessWidget {
  const _StateBanner({required this.state});
  final ResultState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (label, note, icon) = switch (state) {
      ResultState.inProgress => (
          l10n.resultInProgress,
          l10n.resultInProgressNote,
          FIcons.sprout,
        ),
      ResultState.provisional => (
          l10n.resultProvisional,
          l10n.resultProvisionalNote,
          FIcons.hourglass,
        ),
      ResultState.isFinal => (l10n.resultFinal, null, FIcons.check),
    };
    return FAlert(
      icon: Icon(icon),
      title: Text(label),
      subtitle: note == null ? null : Text(note),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Both sides are bounded. An unbounded trailing value overflows as soon
            // as the label is Expanded, because Expanded takes every free pixel
            // first and leaves the value nowhere to go.
            Expanded(flex: 3, child: Text(label)),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: Align(alignment: Alignment.centerRight, child: child),
            ),
          ],
        ),
      );
}
