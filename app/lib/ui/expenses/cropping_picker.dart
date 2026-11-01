import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../domain/model/entities.dart';
import '../../l10n/app_localizations.dart';
import '../common/widgets/button_label.dart';
import '../common/labels.dart';

/// Asks which cropping a cost or sale belongs to. FR-031b, FR-031c, FR-038b.
///
/// This exists because a field can hold two open croppings at once — one in the
/// ground and one harvested but not yet closed (FR-008a). Logging "hauling on Field
/// 1" is therefore ambiguous, and FR-031b says the app "MUST NOT silently default to
/// either". Each option is identified by crop, season, and planting date, never by
/// field alone.
Future<CroppingEntity?> pickCropping({
  required BuildContext context,
  required List<CroppingEntity> open,
}) async {
  if (open.isEmpty) return null;
  if (open.length == 1) return open.single;

  final l10n = AppLocalizations.of(context);
  return showFDialog<CroppingEntity>(
    context: context,
    builder: (dialogContext, style, animation) => FDialog.adaptive(
      style: (_) => style,
      title: Text(l10n.whichCroppingTitle),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.whichCroppingBody),
          const SizedBox(height: 12),
          FTileGroup(
            children: [
              for (final cropping in open)
                FTile(
                  key: ValueKey('pick-${cropping.id}'),
                  title: Text(
                    l10n.croppingDescriptor(
                      cropValue: cropping.crop,
                      season: cropping.growingSeason,
                      plantingDate: cropping.plantingDate,
                    ),
                  ),
                  subtitle: Text(l10n.croppingStatus(cropping.status)),
                  onPress: () => Navigator.of(dialogContext).pop(cropping),
                ),
            ],
          ),
        ],
      ),
      actions: [
        FButton(
          style: FButtonStyle.outline(),
          onPress: () => Navigator.of(dialogContext).pop(),
          child: ButtonLabel(l10n.actionCancel),
        ),
      ],
    ),
  );
}
