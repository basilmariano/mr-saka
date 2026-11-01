import 'package:flutter/material.dart' show MaterialPageRoute;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../domain/model/calendar_date.dart';
import '../../domain/model/entities.dart';
import '../../domain/model/enums.dart';
import '../../domain/model/square_metres.dart';
import '../../l10n/app_localizations.dart';
import '../common/labels.dart';
import '../common/providers.dart';
import '../common/widgets/button_label.dart';
import '../common/widgets/guidance_notice.dart';
import 'edit_schedule.dart';
import 'mark_application.dart';

/// A cropping's fertilizer schedule. FR-015 to FR-018, FR-026, FR-026a.
///
/// The thing this screen exists to do is SC-004: let the farmer read off how many
/// 50 kg bags to buy for this specific field, without converting a per-hectare rate
/// themselves. The bag count is therefore the most prominent figure on each row.
class ScheduleTab extends ConsumerWidget {
  const ScheduleTab({
    required this.croppingId,
    required this.editable,
    super.key,
  });

  final String croppingId;
  final bool editable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = context.theme;
    final applications = ref.watch(applicationsForCroppingProvider(croppingId));
    final cropping = ref.watch(croppingByIdProvider(croppingId));
    final isPlaceholder =
        ref.watch(guidanceIsPlaceholderProvider).valueOrNull ?? true;
    final today = ref.watch(todayProvider);

    return applications.when(
      loading: () => const Center(child: FCircularProgress()),
      error: (error, _) => Center(child: Text('$error')),
      data: (list) {
        final c = cropping.valueOrNull;
        if (c == null) return const SizedBox.shrink();
        final area = ref.watch(fieldByIdProvider(c.fieldId)).valueOrNull?.area;
        if (area == null) return const Center(child: FCircularProgress());

        // spec edge case "Pending steps at harvest time": once the crop is off the
        // field, nothing is due any more — steps stay visible as not done, but the
        // app stops nagging about them.
        final stillGrowing = c.status == CroppingStatus.planted ||
            c.status == CroppingStatus.growing;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // FR-026 / FR-026a: shown wherever a recommendation appears, not once
            // in an about screen.
            GuidanceNotice(
              sourceAttribution: null,
              isPlaceholder: isPlaceholder,
            ),
            const SizedBox(height: 16),
            if (!stillGrowing) ...[
              Text(
                l10n.scheduleAfterHarvest,
                style: theme.typography.sm
                    .copyWith(color: theme.colors.mutedForeground),
              ),
              const SizedBox(height: 12),
            ],
            if (list.isEmpty)
              Text(
                l10n.scheduleNone,
                style: theme.typography.sm
                    .copyWith(color: theme.colors.mutedForeground),
              )
            else
              FTileGroup(
                children: [
                  for (final application in list)
                    _ApplicationTile(
                      application: application,
                      plantingDate: c.plantingDate,
                      area: area,
                      today: today,
                      showDue: stillGrowing,
                      editable: editable,
                    ),
                ],
              ),
            if (editable) ...[
              const SizedBox(height: 16),
              FButton(
                key: const Key('add-schedule-step'),
                style: FButtonStyle.outline(),
                prefix: const Icon(FIcons.plus),
                onPress: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          EditScheduleStepScreen(croppingId: croppingId),
                    ),
                  );
                  ref.invalidate(croppingResultProvider(croppingId));
                },
                child: ButtonLabel(l10n.scheduleAddStepHere),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ApplicationTile extends ConsumerWidget with FTileMixin {
  const _ApplicationTile({
    required this.application,
    required this.plantingDate,
    required this.area,
    required this.today,
    required this.showDue,
    required this.editable,
  });

  final ScheduledApplicationEntity application;
  final CalendarDate plantingDate;
  final SquareMetres area;
  final CalendarDate today;
  final bool showDue;
  final bool editable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = context.theme;
    final due = application.dueDate(plantingDate);
    final quantity = application.recommendedQuantity(area);

    // FR-018: flag an application whose due date has passed without being done.
    final overdue =
        showDue && application.isPending && due.isBefore(today);

    final (badgeLabel, badgeStyle) = switch (application.state) {
      ApplicationState.done => (l10n.scheduleDone, FBadgeStyle.secondary()),
      ApplicationState.skipped => (l10n.scheduleSkipped, FBadgeStyle.outline()),
      ApplicationState.pending => overdue
          ? (l10n.scheduleOverdue, FBadgeStyle.destructive())
          : (null, FBadgeStyle.outline()),
    };

    return FTile(
      key: ValueKey('application-${application.id}'),
      title: Text(application.growthStage),
      subtitle: Text(
        [
          // SC-004: bags first — it is the number the farmer acts on.
          l10n.scheduleBuy(quantity.formatBags(), quantity.formatKg()),
          application.recommendedProduct,
          if (showDue) l10n.scheduleDueOn(l10n.formatDate(due)),
        ].join('\n'),
        style: theme.typography.sm,
      ),
      details: badgeLabel == null
          ? null
          : FBadge(style: badgeStyle, child: Text(badgeLabel)),
      suffix: editable ? const Icon(FIcons.chevronRight) : null,
      // Tap marks it done — the common action. Editing the step itself is the
      // rarer one, so it sits behind a long press rather than competing for the
      // primary tap (FR-023).
      onLongPress: !editable
          ? null
          : () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => EditScheduleStepScreen(
                    croppingId: application.croppingId,
                    existing: application,
                  ),
                ),
              );
              ref.invalidate(croppingResultProvider(application.croppingId));
            },
      onPress: !editable
          ? null
          : () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => MarkApplicationScreen(
                    application: application,
                    area: area,
                  ),
                ),
              );
              ref
                ..invalidate(croppingByIdProvider(application.croppingId))
                ..invalidate(croppingResultProvider(application.croppingId));
            },
    );
  }
}
