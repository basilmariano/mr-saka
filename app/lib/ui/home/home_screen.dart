import 'package:flutter/material.dart' show MaterialPageRoute;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../data/local/repositories/home_repository.dart';
import '../../l10n/app_localizations.dart';
import '../account/settings_screen.dart';
import '../account/sign_in_screen.dart';
import '../account/guest_banner.dart';
import '../common/labels.dart';
import '../common/providers.dart';
import '../common/widgets/empty_state.dart';
import '../croppings/cropping_detail.dart';
import '../fields/fields_screen.dart';
import '../results/comparison_screen.dart';
import 'sync_status.dart';

/// What needs attention right now. FR-044 to FR-046b.
///
/// US3's reason to exist: the schedule and reminders in US2 only change behaviour
/// if the farmer meets them without going looking. This is the surface that makes
/// the app worth opening daily — so the ordering is by urgency, not by entity.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final summary = ref.watch(homeSummaryProvider);

    return FScaffold(
      header: FHeader(
        title: Text(l10n.homeTitle),
        suffixes: [
          FHeaderAction(
            icon: const Icon(FIcons.sprout),
            onPress: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const FieldsScreen()),
              );
              ref.invalidate(homeSummaryProvider);
            },
          ),
          FHeaderAction(
            icon: const Icon(FIcons.chartColumn),
            onPress: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ComparisonScreen()),
            ),
          ),
          FHeaderAction(
            icon: const Icon(FIcons.settings),
            onPress: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
          FHeaderAction(
            icon: const Icon(FIcons.circleUser),
            onPress: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SignInScreen()),
              );
              ref
                ..invalidate(isGuestProvider)
                ..invalidate(syncStatusProvider);
            },
          ),
        ],
      ),
      childPad: false,
      child: Column(
        children: [
          // One line, so it stays pinned; the guest notice scrolls with the
          // content rather than eating a third of a short screen.
          const SyncStatusBar(),
          Expanded(
            child: summary.when(
              loading: () => const Center(child: FCircularProgress()),
              error: (error, _) => Center(child: Text('$error')),
              data: (data) => data.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        const GuestBanner(),
                        EmptyState(
                          title: l10n.homeEmptyTitle,
                          body: l10n.homeEmptyBody,
                          actionLabel: l10n.homeViewFields,
                          onAction: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const FieldsScreen(),
                              ),
                            );
                            ref.invalidate(homeSummaryProvider);
                          },
                        ),
                      ],
                    )
                  : _Summary(summary: data),
            ),
          ),
        ],
      ),
    );
  }
}

class _Summary extends ConsumerWidget {
  const _Summary({required this.summary});

  final HomeSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    Future<void> open(String croppingId) async {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CroppingDetail(croppingId: croppingId),
        ),
      );
      ref.invalidate(homeSummaryProvider);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const GuestBanner(),
        // FR-045 first: the next thing the farmer has to DO, not the next thing
        // to look at.
        if (summary.upcomingApplications.isNotEmpty)
          FTileGroup(
            label: Text(l10n.homeUpcomingApplications),
            children: [
              for (final item in summary.upcomingApplications)
                FTile(
                  key: ValueKey('due-${item.application.id}'),
                  title: Text('${item.fieldName} · ${item.application.recommendedProduct}'),
                  subtitle: Text(
                    '${l10n.scheduleBuy(item.quantityBags, item.quantityKg)}'
                    '\n${_dueLabel(l10n, item)}',
                  ),
                  details: item.isOverdue
                      ? FBadge(
                          style: FBadgeStyle.destructive(),
                          child: Text(l10n.scheduleOverdue),
                        )
                      : null,
                  suffix: const Icon(FIcons.chevronRight),
                  onPress: () => open(item.croppingId),
                ),
            ],
          ),
        if (summary.upcomingApplications.isNotEmpty) const SizedBox(height: 16),

        // FR-044.
        if (summary.active.isNotEmpty)
          FTileGroup(
            label: Text(l10n.homeActiveCroppings),
            children: [
              for (final item in summary.active)
                FTile(
                  key: ValueKey('active-${item.cropping.id}'),
                  title: Text(item.fieldName),
                  subtitle: Text(
                    '${l10n.croppingDescriptor(
                      cropValue: item.cropping.crop,
                      season: item.cropping.growingSeason,
                      plantingDate: item.cropping.plantingDate,
                    )}\n'
                    '${l10n.croppingStatus(item.cropping.status)} · '
                    '${l10n.croppingDaysSincePlanting(item.daysSincePlanting)}',
                  ),
                  suffix: const Icon(FIcons.chevronRight),
                  onPress: () => open(item.cropping.id),
                ),
            ],
          ),
        if (summary.active.isNotEmpty) const SizedBox(height: 16),

        // FR-046.
        if (summary.upcomingHarvests.isNotEmpty)
          FTileGroup(
            label: Text(l10n.homeUpcomingHarvests),
            children: [
              for (final item in summary.upcomingHarvests)
                FTile(
                  key: ValueKey('harvest-${item.cropping.id}'),
                  title: Text(item.fieldName),
                  subtitle: Text(
                    l10n.homeHarvestExpected(l10n.formatDate(item.expectedDate)),
                  ),
                  suffix: const Icon(FIcons.chevronRight),
                  onPress: () => open(item.cropping.id),
                ),
            ],
          ),
        if (summary.upcomingHarvests.isNotEmpty) const SizedBox(height: 16),

        // FR-046a: once a field is replanted it is easy to mentally move on while
        // sales and hauling costs are still outstanding. This is what prevents it.
        if (summary.awaitingClosure.isNotEmpty)
          FTileGroup(
            label: Text(l10n.homeAwaitingClosure),
            description: Text(l10n.homeAwaitingClosureHelp),
            children: [
              for (final item in summary.awaitingClosure)
                FTile(
                  key: ValueKey('awaiting-${item.cropping.id}'),
                  title: Text(item.fieldName),
                  subtitle: Text(
                    '${l10n.croppingDescriptor(
                      cropValue: item.cropping.crop,
                      season: item.cropping.growingSeason,
                      plantingDate: item.cropping.plantingDate,
                    )}'
                    '${item.remaining == null ? '' : '\n${l10n.homeUnsoldRemaining(
                        item.remaining!.quantity.formatKg(),
                        l10n.weightBasis(item.remaining!.basis),
                      )}'}',
                  ),
                  suffix: const Icon(FIcons.chevronRight),
                  onPress: () => open(item.cropping.id),
                ),
            ],
          ),
      ],
    );
  }

  String _dueLabel(AppLocalizations l10n, UpcomingApplication item) {
    if (item.daysUntilDue < 0) return l10n.homeDueOverdue(-item.daysUntilDue);
    if (item.daysUntilDue == 0) return l10n.homeDueToday;
    return l10n.homeDueIn(item.daysUntilDue);
  }
}
