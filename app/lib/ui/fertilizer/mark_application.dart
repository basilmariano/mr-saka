import 'package:flutter/material.dart' show showDatePicker;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../domain/model/calendar_date.dart';
import '../../domain/model/centavos.dart';
import '../../domain/model/decimal_text.dart';
import '../../domain/model/entities.dart';
import '../../domain/model/grams.dart';
import '../../domain/model/square_metres.dart';
import '../../l10n/app_localizations.dart';
import '../common/labels.dart';
import '../common/providers.dart';
import '../common/widgets/confirm.dart';
import '../common/widgets/button_label.dart';
import '../common/widgets/field_error.dart';

/// Record what was actually applied. FR-020, FR-021, FR-022.
///
/// Pre-filled with the recommendation, because the common case is that the farmer
/// applied what was suggested — SC-002's speed target applies here too.
///
/// Entering a cost creates exactly one fertilizer expense on the cropping, and
/// editing it later updates that same expense (FR-021). The form says so plainly
/// rather than leaving the farmer to discover an expense appearing elsewhere.
class MarkApplicationScreen extends ConsumerStatefulWidget {
  const MarkApplicationScreen({
    required this.application,
    required this.area,
    super.key,
  });

  final ScheduledApplicationEntity application;
  final SquareMetres area;

  @override
  ConsumerState<MarkApplicationScreen> createState() =>
      _MarkApplicationState();
}

class _MarkApplicationState extends ConsumerState<MarkApplicationScreen> {
  late final TextEditingController _product = TextEditingController(
    text: widget.application.actualProduct ??
        widget.application.recommendedProduct,
  );
  late final TextEditingController _quantity = TextEditingController(
    text: formatScaled(
      rescale(
        (widget.application.actualQuantity ??
                widget.application.recommendedQuantity(widget.area))
            .value,
        3,
        1,
      ),
      1,
    ),
  );
  late final TextEditingController _cost = TextEditingController(
    text: widget.application.cost == null
        ? ''
        : formatScaled(widget.application.cost!.value, 2),
  );
  late CalendarDate _date =
      widget.application.actualDate ?? ref.read(todayProvider);
  final _error = FieldError();
  bool _saving = false;

  @override
  void dispose() {
    _product.dispose();
    _quantity.dispose();
    _cost.dispose();
    _error.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _error.clear();
      _saving = true;
    });
    try {
      await ref.read(applicationRepositoryProvider).markDone(
            applicationId: widget.application.id,
            actualDate: _date,
            actualProduct: _product.text.trim(),
            actualQuantity: Grams.parseKg(_quantity.text),
            // Empty means the farmer is not recording a cost; no expense is
            // created, and any previous one is removed.
            cost: _cost.text.trim().isEmpty ? null : Centavos.parse(_cost.text),
          );
      if (mounted) Navigator.of(context).pop(true);
    } on DecimalFormatException {
      setState(() {
        _saving = false;
        _error.set(l10n.errorNotANumber);
      });
    }
  }

  Future<void> _skip() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await confirm(
      context: context,
      title: l10n.markSkipTitle,
      body: l10n.markSkipReason,
      confirmLabel: l10n.markSkipConfirm,
    );
    if (!confirmed) return;
    await ref
        .read(applicationRepositoryProvider)
        .markSkipped(applicationId: widget.application.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = context.theme;

    return FScaffold(
      header: FHeader.nested(
        title: Text(l10n.markDoneTitle),
        prefixes: [FHeaderAction.back(onPress: () => Navigator.of(context).pop())],
      ),
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FButton(
          key: const Key('save-button'),
          onPress: _saving ? null : _save,
          child: ButtonLabel(l10n.actionSave),
        ),
      ),
      child: ListView(
        children: [
          Text(
            widget.application.growthStage,
            style: theme.typography.lg,
          ),
          const SizedBox(height: 16),
          FTextField(
            key: const Key('application-product'),
            controller: _product,
            label: Text(l10n.markDoneProduct),
          ),
          const SizedBox(height: 16),
          FTextField(
            key: const Key('application-quantity'),
            controller: _quantity,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            label: Text(l10n.markDoneQuantity),
            hint: l10n.kgUnit,
            statesController: _error.states,
            error: _error.widget,
          ),
          const SizedBox(height: 16),
          FTextField(
            key: const Key('application-cost'),
            controller: _cost,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            label: Text(l10n.markDoneCost),
            hint: '₱',
            description: Text(l10n.markDoneCostHelp),
          ),
          const SizedBox(height: 16),
          FTileGroup(
            children: [
              FTile(
                title: Text(l10n.markDoneDate),
                subtitle: Text(l10n.formatDate(_date)),
                suffix: const Icon(FIcons.calendar),
                onPress: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date.toDateTime(),
                    firstDate: DateTime(2015),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setState(() => _date = CalendarDate.fromDateTime(picked));
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
          FButton(
            key: const Key('skip-button'),
            style: FButtonStyle.outline(),
            onPress: _saving ? null : _skip,
            child: ButtonLabel(l10n.markDoneSkip),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
