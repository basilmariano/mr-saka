import 'package:flutter/material.dart' show MaterialPageRoute;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../domain/model/entities.dart';
import '../../l10n/app_localizations.dart';
import '../account/guest_banner.dart';
import '../account/settings_screen.dart';
import '../account/sign_in_screen.dart';
import '../common/providers.dart';
import '../common/widgets/empty_state.dart';
import '../home/sync_status.dart';
import 'field_detail.dart';
import 'field_form.dart';

/// The field list. FR-001, FR-005.
class FieldsScreen extends ConsumerWidget {
  const FieldsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final fields = ref.watch(fieldsProvider);

    Future<void> openForm() async {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const FieldForm()),
      );
      ref.invalidate(syncStatusProvider);
    }

    return FScaffold(
      header: FHeader(
        title: Text(l10n.fieldsTitle),
        suffixes: [
          FHeaderAction(
            icon: const Icon(FIcons.circleUser),
            onPress: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SignInScreen()),
              );
              ref
                ..invalidate(isGuestProvider)
                ..invalidate(syncStatusProvider)
                ..invalidate(fieldsProvider);
            },
          ),
          FHeaderAction(
            icon: const Icon(FIcons.settings),
            onPress: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
              );
              ref.invalidate(remindersEnabledProvider);
            },
          ),
          FHeaderAction(icon: const Icon(FIcons.plus), onPress: openForm),
        ],
      ),
      childPad: false,
      child: Column(
        children: [
          // Backup state is visible without opening a settings screen (SC-015).
          // One line, so it stays pinned; the guest notice scrolls with the list
          // rather than eating a third of a short screen.
          const SyncStatusBar(),
          Expanded(child: _FieldList(fields: fields, onAdd: openForm)),
        ],
      ),
    );
  }
}

class _FieldList extends ConsumerWidget {
  const _FieldList({required this.fields, required this.onAdd});

  final AsyncValue<List<FieldEntity>> fields;
  final Future<void> Function() onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return fields.when(
      loading: () => const Center(child: FCircularProgress()),
      error: (error, _) => Center(child: Text('$error')),
      data: (list) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const GuestBanner(),
          if (list.isEmpty)
            EmptyState(
              title: l10n.fieldsTitle,
              body: l10n.homeEmptyBody,
              actionLabel: l10n.fieldAdd,
              onAction: onAdd,
            )
          else
            FTileGroup(
                  children: [
                    for (final field in list)
                      FTile(
                        key: ValueKey(field.id),
                        title: Text(field.name),
                        subtitle: Text(
                          '${field.area.formatHectares()} ${l10n.fieldAreaUnit}'
                          '${field.location == null ? '' : ' · ${field.location}'}',
                        ),
                        suffix: const Icon(FIcons.chevronRight),
                        onPress: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => FieldDetail(fieldId: field.id),
                          ),
                        ),
                      ),
              ],
            ),
        ],
      ),
    );
  }
}
