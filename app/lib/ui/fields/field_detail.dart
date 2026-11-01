import 'package:flutter/material.dart' show MaterialPageRoute;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../domain/model/entities.dart';
import '../../l10n/app_localizations.dart';
import '../common/labels.dart';
import '../common/providers.dart';
import '../common/widgets/button_label.dart';
import '../common/widgets/confirm.dart';
import '../croppings/cropping_detail.dart';
import '../croppings/start_cropping.dart';
import 'field_form.dart';

/// A field with its full cropping history. FR-004, FR-005.
class FieldDetail extends ConsumerWidget {
  const FieldDetail({required this.fieldId, super.key});

  final String fieldId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = context.theme;
    final field = ref.watch(fieldByIdProvider(fieldId));
    final croppings = ref.watch(croppingsForFieldProvider(fieldId));

    return FScaffold(
      header: FHeader.nested(
        title: Text(field.valueOrNull?.name ?? ''),
        prefixes: [FHeaderAction.back(onPress: () => Navigator.of(context).pop())],
        suffixes: [
          FHeaderAction(
            icon: const Icon(FIcons.pencil),
            onPress: () async {
              final existing = field.valueOrNull;
              if (existing == null) return;
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => FieldForm(existing: existing),
                ),
              );
              ref.invalidate(fieldByIdProvider(fieldId));
            },
          ),
          FHeaderAction(
            icon: const Icon(FIcons.archive),
            onPress: () => _archive(context, ref, l10n),
          ),
        ],
      ),
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FButton(
          key: const Key('open-start-cropping'),
          prefix: const Icon(FIcons.plus),
          onPress: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => StartCroppingScreen(fieldId: fieldId),
              ),
            );
            ref.invalidate(croppingsForFieldProvider(fieldId));
          },
          child: ButtonLabel(l10n.croppingStart),
        ),
      ),
      child: croppings.when(
        loading: () => const Center(child: FCircularProgress()),
        error: (error, _) => Center(child: Text('$error')),
        data: (list) => ListView(
          children: [
            if (field.valueOrNull != null)
              Text(
                '${field.value!.area.formatHectares()} ${l10n.fieldAreaUnit}',
                style: theme.typography.lg,
              ),
            const SizedBox(height: 16),
            Text(l10n.fieldCroppingHistory, style: theme.typography.sm),
            const SizedBox(height: 8),
            if (list.isEmpty)
              Text(
                l10n.fieldNoCroppings,
                style: theme.typography.sm
                    .copyWith(color: theme.colors.mutedForeground),
              )
            else
              FTileGroup(
                children: [
                  for (final cropping in list)
                    _CroppingTile(cropping: cropping),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// FR-004: a field with croppings is archived, never deleted — so its history
  /// survives.
  Future<void> _archive(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final repository = ref.read(fieldRepositoryProvider);
    final deleted = await repository.deleteIfUnused(fieldId);
    if (!context.mounted) return;
    if (deleted) {
      Navigator.of(context).pop();
      return;
    }
    final confirmed = await confirm(
      context: context,
      title: l10n.fieldArchive,
      body: l10n.fieldArchiveExplain,
      confirmLabel: l10n.fieldArchive,
    );
    if (confirmed) {
      await repository.archive(fieldId);
      if (context.mounted) Navigator.of(context).pop();
    }
  }
}

class _CroppingTile extends ConsumerWidget with FTileMixin {
  const _CroppingTile({required this.cropping});

  final CroppingEntity cropping;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final result = ref.watch(croppingResultProvider(cropping.id));

    return FTile(
      key: ValueKey(cropping.id),
      title: Text(
        l10n.croppingDescriptor(
          cropValue: cropping.crop,
          season: cropping.growingSeason,
          plantingDate: cropping.plantingDate,
        ),
      ),
      subtitle: Text(
        '${l10n.croppingStatus(cropping.status)}'
        '${result.valueOrNull == null ? '' : ' · ${result.value!.netProfit.formatWithSymbol()}'}',
      ),
      suffix: const Icon(FIcons.chevronRight),
      onPress: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CroppingDetail(croppingId: cropping.id),
        ),
      ),
    );
  }
}
