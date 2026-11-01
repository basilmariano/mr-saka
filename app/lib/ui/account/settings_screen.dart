import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../l10n/app_localizations.dart';
import 'package:flutter/material.dart' show MaterialPageRoute;

import '../common/providers.dart';
import '../fertilizer/template_editor.dart';

/// Settings. FR-019a.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = context.theme;
    final enabled = ref.watch(remindersEnabledProvider).valueOrNull ?? true;
    // Assume delivery works until the platform says otherwise, so a slow first
    // answer does not flash a warning at a farmer whose notifications are fine.
    final permitted =
        ref.watch(notificationsPermittedProvider).valueOrNull ?? true;

    return FScaffold(
      header: FHeader.nested(
        title: Text(l10n.settingsTitle),
        prefixes: [FHeaderAction.back(onPress: () => Navigator.of(context).pop())],
      ),
      child: ListView(
        children: [
          FSwitch(
            key: const Key('reminders-switch'),
            label: Text(l10n.settingsReminders),
            // FR-019a is explicit that turning reminders off must NOT hide the
            // upcoming and overdue lists — they are a different surface and keep
            // working. The farmer is told that here rather than discovering it.
            description: Text(l10n.settingsRemindersHelp),
            value: enabled,
            onChange: (value) async {
              final reconciliation =
                  ref.read(reminderReconciliationProvider);
              await reconciliation.setRemindersEnabled(value);
              if (value) {
                // Ask only when switching on, and only then — a permission
                // prompt on first launch, before the farmer knows what the app
                // does, is the surest way to get it declined.
                await ref.read(reminderSchedulerProvider).requestPermissions();
              }
              await reconciliation.reconcile(
                today: ref.read(todayProvider),
                remindersEnabled: value,
              );
              ref.invalidate(remindersEnabledProvider);
              ref.invalidate(notificationsPermittedProvider);
            },
          ),
          // FR-019a: the switch records what the farmer wants; it cannot make the
          // phone comply. When the OS is blocking delivery, saying so here is the
          // only place they would find out — a blocked notification produces no
          // error, no retry and no trace, so the switch alone would simply lie.
          if (enabled && !permitted) ...[
            const SizedBox(height: 12),
            FAlert(
              key: const Key('reminders-blocked'),
              icon: const Icon(FIcons.bellOff),
              title: Text(l10n.settingsRemindersDenied),
            ),
          ],
          const SizedBox(height: 20),
          FTileGroup(
            children: [
              FTile(
                key: const Key('open-templates'),
                title: Text(l10n.templatesTitle),
                subtitle: Text(l10n.templatesHelp),
                suffix: const Icon(FIcons.chevronRight),
                onPress: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const TemplateListScreen(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            l10n.guidanceDisclaimer,
            style: theme.typography.xs
                .copyWith(color: theme.colors.mutedForeground),
          ),
        ],
      ),
    );
  }
}
