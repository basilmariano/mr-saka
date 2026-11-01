import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../data/sync/sync_worker.dart';
import '../../l10n/app_localizations.dart';
import '../common/providers.dart';
import '../common/widgets/confirm.dart';

/// What the farmer can see about backup state, without opening settings.
///
/// FR-053b, SC-015. FR-053c is the sharp one: a repeatedly failing sync must never
/// leave the app looking healthy while nothing reaches remote storage, so the
/// "not backed up" state is loud and persistent rather than a toast.
class SyncStatusBar extends ConsumerWidget {
  const SyncStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = context.theme;
    final status = ref.watch(syncStatusProvider);

    return status.maybeWhen(
      orElse: () => const SizedBox.shrink(),
      data: (state) {
        final (icon, label, background, foreground) = switch (state.health) {
          SyncHealth.upToDate => (
              FIcons.cloudCheck,
              l10n.syncUpToDate,
              theme.colors.muted,
              theme.colors.mutedForeground,
            ),
          SyncHealth.pending => (
              FIcons.refreshCw,
              l10n.syncPending(state.pendingCount),
              theme.colors.secondary,
              theme.colors.secondaryForeground,
            ),
          SyncHealth.notBackedUp => (
              FIcons.cloudOff,
              l10n.syncFailing,
              theme.colors.destructive,
              theme.colors.destructiveForeground,
            ),
          SyncHealth.guest => (
              FIcons.smartphone,
              l10n.syncGuest,
              theme.colors.secondary,
              theme.colors.secondaryForeground,
            ),
        };

        return GestureDetector(
          onTap: state.health == SyncHealth.notBackedUp
              ? () => confirm(
                    context: context,
                    title: l10n.syncNotBackedUpTitle,
                    body: l10n.syncNotBackedUpBody(state.lastError ?? '—'),
                    confirmLabel: l10n.actionCancel,
                  )
              : null,
          child: ColoredBox(
            color: background,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: foreground),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: theme.typography.sm.copyWith(color: foreground),
                    ),
                  ),
                  if (state.health == SyncHealth.notBackedUp)
                    Icon(FIcons.info, size: 18, color: foreground),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
