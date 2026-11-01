import 'package:flutter/material.dart' show MaterialPageRoute;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../data/local/repositories/comparison_repository.dart';
import '../../domain/calc/yield_calc.dart';
import '../../domain/model/enums.dart';
import '../../l10n/app_localizations.dart';
import '../common/labels.dart';
import '../common/providers.dart';
import '../common/widgets/empty_state.dart';
import '../common/widgets/money_text.dart';
import '../croppings/cropping_detail.dart';
import 'comparison_filters.dart';

/// Compare croppings across seasons and fields. FR-043.
///
/// US4 is the long-term payoff for keeping records, and the reason a farmer keeps
/// using the app past the first season: "did direct-seeding beat transplanting on
/// Field 1?", "was the dry season better?", "which field actually makes money?".
///
/// Every figure here is on the same fresh-weight basis (FR-032a), which is the only
/// reason these rows can be set beside each other at all.
class ComparisonScreen extends ConsumerWidget {
  const ComparisonScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final rows = ref.watch(comparisonRowsProvider);
    final filter = ref.watch(comparisonFilterProvider);

    return FScaffold(
      header: FHeader.nested(
        title: Text(l10n.compareTitle),
        prefixes: [FHeaderAction.back(onPress: () => Navigator.of(context).pop())],
        suffixes: [
          if (!filter.isEmpty)
            FHeaderAction(
              icon: const Icon(FIcons.funnelX),
              onPress: () => ref
                  .read(comparisonFilterProvider.notifier)
                  .state = const ComparisonFilter(),
            ),
        ],
      ),
      childPad: false,
      child: rows.when(
        loading: () => const Center(child: FCircularProgress()),
        error: (error, _) => Center(child: Text('$error')),
        data: (all) {
          if (all.isEmpty) {
            return EmptyState(
              title: l10n.compareNone,
              body: l10n.homeEmptyBody,
              icon: FIcons.chartColumn,
            );
          }

          final visible = all.where(filter.matches).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: ComparisonFilters(rows: all),
              ),
              Expanded(
                child: visible.isEmpty
                    ? EmptyState(
                        title: l10n.compareNoneFiltered,
                        body: l10n.compareClearFilters,
                        actionLabel: l10n.compareClearFilters,
                        icon: FIcons.funnelX,
                        onAction: () => ref
                            .read(comparisonFilterProvider.notifier)
                            .state = const ComparisonFilter(),
                      )
                    : _Rows(rows: visible),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Rows extends ConsumerWidget {
  const _Rows({required this.rows});

  final List<ComparisonRow> rows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = context.theme;

    // Highlighting the best result is the point of comparing, but only once there
    // is something to compare and only among croppings that actually finished —
    // an in-progress cropping with no revenue would otherwise always look worst.
    final comparable =
        rows.where((r) => r.result.showsProfit).toList();
    final best = comparable.isEmpty
        ? null
        : comparable.reduce(
            (a, b) => a.netProfit >= b.netProfit ? a : b,
          );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Text(
          l10n.compareCount(rows.length),
          style: theme.typography.sm
              .copyWith(color: theme.colors.mutedForeground),
        ),
        const SizedBox(height: 12),
        for (final row in rows) ...[
          _ComparisonCard(row: row, isBest: best != null && row.croppingId == best.croppingId),
          const SizedBox(height: 12),
        ],
        // FR-043 / T109: say once, plainly, why these figures can be set beside
        // each other — rather than repeating "fresh weight" on every number.
        Text(
          l10n.compareFreshWeightNote,
          style: theme.typography.xs
              .copyWith(color: theme.colors.mutedForeground),
        ),
      ],
    );
  }
}

class _ComparisonCard extends ConsumerWidget {
  const _ComparisonCard({required this.row, required this.isBest});

  final ComparisonRow row;
  final bool isBest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = context.theme;
    final result = row.result;

    return GestureDetector(
      key: ValueKey('comparison-${row.croppingId}'),
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CroppingDetail(croppingId: row.croppingId),
          ),
        );
        ref.invalidate(comparisonRowsProvider);
      },
      behavior: HitTestBehavior.opaque,
      child: FCard(
        title: Row(
          children: [
            Expanded(child: Text(row.fieldName)),
            if (isBest)
              FBadge(
                style: FBadgeStyle.secondary(),
                child: Text(l10n.compareBestProfit),
              ),
          ],
        ),
        subtitle: Text(
          '${l10n.croppingDescriptor(
            cropValue: row.crop,
            season: row.growingSeason,
            plantingDate: row.plantingDate,
          )}'
          '${row.varietyName.isEmpty ? '' : ' · ${row.varietyName}'}'
          ' · ${l10n.plantingMethod(row.plantingMethod)}',
        ),
        child: Column(
          children: [
            _Figure(
              label: result.netProfit.isNegative
                  ? l10n.resultLoss
                  : l10n.resultProfit,
              // FR-042: before harvest the absence of revenue is not a loss, so
              // the headline figure is withheld rather than shown as negative.
              hidden: !result.showsProfit,
              child: MoneyText(
                result.netProfit,
                signed: true,
                style: theme.typography.lg,
              ),
            ),
            _Figure(
              label: l10n.resultExpenses,
              child: MoneyText(result.totalExpenses),
            ),
            if (result.showsProfit)
              _Figure(
                label: l10n.resultRevenue,
                child: MoneyText(result.revenue),
              ),
            if (result.harvested != null) ...[
              _Figure(
                label: l10n.resultYieldPerHectare,
                child: Text(
                  YieldCalc.formatTonsPerHectare(result.tonsPerHectareScaled2),
                ),
              ),
              _Figure(
                label: l10n.resultCostPerKg,
                child: result.costPerKg == null
                    ? Text(l10n.resultNotApplicable)
                    : MoneyText(result.costPerKg!),
              ),
            ],
            if (result.state != ResultState.isFinal)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FBadge(
                    style: FBadgeStyle.outline(),
                    child: Text(
                      result.state == ResultState.inProgress
                          ? l10n.resultInProgress
                          : l10n.resultProvisional,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.child,
    this.hidden = false,
  });

  final String label;
  final Widget child;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    if (hidden) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
}
