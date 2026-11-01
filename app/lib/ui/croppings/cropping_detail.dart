import 'package:flutter/material.dart' show MaterialPageRoute;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../domain/model/calendar_date.dart';
import '../../domain/model/enums.dart';
import '../../l10n/app_localizations.dart';
import '../common/labels.dart';
import '../common/providers.dart';
import '../common/widgets/button_label.dart';
import '../common/widgets/confirm.dart';
import '../common/widgets/money_text.dart';
import '../expenses/expense_form.dart';
import '../harvest/harvest_form.dart';
import '../harvest/sale_form.dart';
import '../fertilizer/schedule_screen.dart';
import '../results/cropping_result.dart';

/// One cropping: its expenses, harvest and sales, and its result.
class CroppingDetail extends ConsumerWidget {
  const CroppingDetail({required this.croppingId, super.key});

  final String croppingId;

  void _refresh(WidgetRef ref) {
    ref
      ..invalidate(croppingByIdProvider(croppingId))
      ..invalidate(croppingResultProvider(croppingId))
      ..invalidate(harvestForCroppingProvider(croppingId))
      ..invalidate(salesForCroppingProvider(croppingId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final cropping = ref.watch(croppingByIdProvider(croppingId));

    return cropping.when(
      loading: () => const FScaffold(child: Center(child: FCircularProgress())),
      error: (error, _) => FScaffold(child: Center(child: Text('$error'))),
      data: (c) {
        if (c == null) return const FScaffold(child: SizedBox.shrink());
        final editable = c.status.acceptsRecords;

        return FScaffold(
          header: FHeader.nested(
            title: Text(
              l10n.croppingDescriptor(
                cropValue: c.crop,
                season: c.growingSeason,
                plantingDate: c.plantingDate,
              ),
            ),
            prefixes: [
              FHeaderAction.back(onPress: () => Navigator.of(context).pop()),
            ],
            suffixes: [
              if (c.status == CroppingStatus.harvested)
                FHeaderAction(
                  icon: const Icon(FIcons.circleCheck),
                  onPress: () => _close(context, ref, l10n),
                ),
              if (c.status == CroppingStatus.closed)
                FHeaderAction(
                  icon: const Icon(FIcons.rotateCcw),
                  onPress: () async {
                    await ref.read(croppingRepositoryProvider).reopen(croppingId);
                    _refresh(ref);
                  },
                ),
            ],
          ),
          childPad: false,
          child: Column(
            children: [
              _StatusStrip(status: c.status, plantingDate: c.plantingDate),
              if (!editable)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FAlert(
                    style: FAlertStyle.destructive(),
                    icon: const Icon(FIcons.lock),
                    title: Text(l10n.croppingClosedNotice),
                  ),
                ),
              Expanded(
                child: _Tabs(
                  labels: [
                    l10n.scheduleTitle,
                    l10n.expensesTitle,
                    l10n.harvestTitle,
                    l10n.resultTitle,
                  ],
                  children: [
                    ScheduleTab(croppingId: croppingId, editable: editable),
                    _ExpensesTab(croppingId: croppingId, editable: editable),
                    _HarvestTab(croppingId: croppingId, editable: editable),
                    CroppingResultView(croppingId: croppingId),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// FR-012b, FR-012c: closing is deliberate, and warns when stock is still unsold.
  Future<void> _close(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final result = await ref.read(croppingResultProvider(croppingId).future);
    final remaining = result?.remaining;
    if (!context.mounted) return;

    final confirmed = await confirm(
      context: context,
      title: l10n.closeCroppingTitle,
      body: remaining != null && !remaining.quantity.isZero
          ? l10n.closeCroppingUnsold(remaining.quantity.formatKg())
          : l10n.closeCroppingBody,
      confirmLabel: l10n.closeCroppingConfirm,
    );
    if (confirmed) {
      await ref.read(croppingRepositoryProvider).close(croppingId);
      _refresh(ref);
    }
  }
}

/// A tab strip whose content fills the remaining height.
///
/// Forui's FTabs places the active child straight into a Column, so the child is
/// laid out unbounded. That is fine for short intrinsic content but breaks a
/// scrolling page: a ListView with no bounded height fails layout outright. Each
/// tab here is a full page, so the content sits in an Expanded instead.
class _Tabs extends StatefulWidget {
  const _Tabs({required this.labels, required this.children});

  final List<String> labels;
  final List<Widget> children;

  @override
  State<_Tabs> createState() => _TabsState();
}

class _TabsState extends State<_Tabs> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colors.muted,
              borderRadius: theme.style.borderRadius,
            ),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  for (var i = 0; i < widget.labels.length; i++)
                    Expanded(
                      child: _TabButton(
                        label: widget.labels[i],
                        selected: i == _index,
                        onPress: () => setState(() => _index = i),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        // IndexedStack keeps each tab's scroll position when switching away.
        Expanded(
          child: IndexedStack(
            index: _index,
            sizing: StackFit.expand,
            children: widget.children,
          ),
        ),
      ],
    );
  }
}

/// One tab.
///
/// Deliberately not an FButton: FButton lays its label out at natural size inside
/// its own Row, so four tabs on a phone overflow rather than shrink. Here the text
/// is constrained and ellipsised, which holds at any width and in any language —
/// the phase-2 translations will be longer than the English.
class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onPress,
  });

  final String label;
  final bool selected;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        key: ValueKey('tab-$label'),
        onTap: onPress,
        behavior: HitTestBehavior.opaque,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected ? theme.colors.primary : null,
            borderRadius: theme.style.borderRadius,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.typography.sm.copyWith(
                color: selected
                    ? theme.colors.primaryForeground
                    : theme.colors.mutedForeground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusStrip extends ConsumerWidget {
  const _StatusStrip({required this.status, required this.plantingDate});

  final CroppingStatus status;
  final CalendarDate plantingDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = context.theme;
    final today = ref.watch(todayProvider);
    final days = plantingDate.daysUntil(today);
    return ColoredBox(
      color: theme.colors.muted,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            '${l10n.croppingStatus(status)} · ${l10n.croppingDaysSincePlanting(days)}',
            style: theme.typography.sm
                .copyWith(color: theme.colors.mutedForeground),
          ),
        ),
      ),
    );
  }
}

class _ExpensesTab extends ConsumerWidget {
  const _ExpensesTab({required this.croppingId, required this.editable});

  final String croppingId;
  final bool editable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = context.theme;
    final expenses = ref.watch(expensesForCroppingProvider(croppingId));
    final result = ref.watch(croppingResultProvider(croppingId));

    return expenses.when(
      loading: () => const Center(child: FCircularProgress()),
      error: (error, _) => Center(child: Text('$error')),
      data: (list) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(child: Text(l10n.expenseTotal, style: theme.typography.base)),
              if (result.valueOrNull != null)
                MoneyText(
                  result.value!.totalExpenses,
                  style: theme.typography.xl,
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (editable)
            FButton(
              prefix: const Icon(FIcons.plus),
              onPress: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ExpenseForm(croppingId: croppingId),
                  ),
                );
                ref.invalidate(croppingResultProvider(croppingId));
              },
              child: ButtonLabel(l10n.expenseAdd),
            ),
          const SizedBox(height: 16),
          if (list.isEmpty)
            Text(
              l10n.expenseNone,
              textAlign: TextAlign.center,
              style: theme.typography.sm
                  .copyWith(color: theme.colors.mutedForeground),
            )
          else
            FTileGroup(
              children: [
                for (final expense in list)
                  FTile(
                    key: ValueKey(expense.id),
                    title: Text(l10n.categoryLabel(expense.category)),
                    subtitle: Text(l10n.formatDate(expense.date)),
                    details: MoneyText(expense.amount),
                    onPress: !editable
                        ? null
                        : () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => ExpenseForm(
                                  croppingId: croppingId,
                                  existing: expense,
                                ),
                              ),
                            );
                            ref.invalidate(croppingResultProvider(croppingId));
                          },
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _HarvestTab extends ConsumerWidget {
  const _HarvestTab({required this.croppingId, required this.editable});

  final String croppingId;
  final bool editable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = context.theme;
    final harvest = ref.watch(harvestForCroppingProvider(croppingId));
    final sales = ref.watch(salesForCroppingProvider(croppingId));
    final cropping = ref.watch(croppingByIdProvider(croppingId));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        harvest.when(
          loading: () => const FCircularProgress(),
          error: (error, _) => Text('$error'),
          data: (h) => h == null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.harvestNone,
                      style: theme.typography.sm
                          .copyWith(color: theme.colors.mutedForeground),
                    ),
                    const SizedBox(height: 12),
                    if (editable)
                      FButton(
                        prefix: const Icon(FIcons.wheat),
                        onPress: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => HarvestForm(croppingId: croppingId),
                            ),
                          );
                          ref
                            ..invalidate(harvestForCroppingProvider(croppingId))
                            ..invalidate(croppingByIdProvider(croppingId))
                            ..invalidate(croppingResultProvider(croppingId));
                        },
                        child: ButtonLabel(l10n.harvestRecord),
                      ),
                  ],
                )
              : FTileGroup(
                  children: [
                    FTile(
                      title: Text(
                        '${h.totalWet.formatTons()} ${l10n.tonsUnit} (${l10n.freshWeight})',
                      ),
                      subtitle: Text(l10n.formatDate(h.date)),
                    ),
                  ],
                ),
        ),
        const FDivider(),
        Text(l10n.salesTitle, style: theme.typography.sm),
        const SizedBox(height: 8),
        sales.when(
          loading: () => const FCircularProgress(),
          error: (error, _) => Text('$error'),
          data: (list) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (list.isEmpty)
                Text(
                  l10n.saleNone,
                  style: theme.typography.sm
                      .copyWith(color: theme.colors.mutedForeground),
                )
              else
                FTileGroup(
                  children: [
                    for (final sale in list)
                      FTile(
                        key: ValueKey(sale.id),
                        title: Text(
                          '${sale.quantity.formatKg()} ${l10n.kgUnit} · ${sale.buyer}',
                        ),
                        subtitle: Text(l10n.formatDate(sale.date)),
                        details: MoneyText(sale.pricePerKg),
                      ),
                  ],
                ),
              const SizedBox(height: 12),
              if (editable &&
                  harvest.valueOrNull != null &&
                  cropping.valueOrNull != null)
                FButton(
                  prefix: const Icon(FIcons.banknote),
                  onPress: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SaleForm(cropping: cropping.value!),
                      ),
                    );
                    ref
                      ..invalidate(salesForCroppingProvider(croppingId))
                      ..invalidate(croppingByIdProvider(croppingId))
                      ..invalidate(croppingResultProvider(croppingId));
                  },
                  child: ButtonLabel(l10n.saleAdd),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
