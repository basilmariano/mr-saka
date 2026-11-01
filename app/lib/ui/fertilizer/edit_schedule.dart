import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../domain/model/decimal_text.dart';
import '../../domain/model/entities.dart';
import '../../domain/model/grams.dart';
import '../../l10n/app_localizations.dart';
import '../common/providers.dart';
import '../common/widgets/confirm.dart';
import '../common/widgets/button_label.dart';
import '../common/widgets/field_error.dart';

/// Add or change a step on ONE cropping's schedule. FR-023.
///
/// Deliberately separate from the template editor: FR-023 says a farmer may edit
/// an individual cropping's schedule "without affecting the template". A farmer
/// who applied something different this one season should not have that become
/// their standing recommendation.
class EditScheduleStepScreen extends ConsumerStatefulWidget {
  const EditScheduleStepScreen({
    required this.croppingId,
    this.existing,
    super.key,
  });

  final String croppingId;
  final ScheduledApplicationEntity? existing;

  @override
  ConsumerState<EditScheduleStepScreen> createState() =>
      _EditScheduleStepState();
}

class _EditScheduleStepState extends ConsumerState<EditScheduleStepScreen> {
  late final TextEditingController _stage =
      TextEditingController(text: widget.existing?.growthStage ?? '');
  late final TextEditingController _days = TextEditingController(
    text: widget.existing?.daysAfterPlanting.toString() ?? '',
  );
  late final TextEditingController _product =
      TextEditingController(text: widget.existing?.recommendedProduct ?? '');
  late final TextEditingController _rate = TextEditingController(
    text: widget.existing == null
        ? ''
        : formatScaled(rescale(widget.existing!.ratePerHectare.value, 3, 1), 1),
  );
  final _error = FieldError();
  bool _saving = false;

  @override
  void dispose() {
    _stage.dispose();
    _days.dispose();
    _product.dispose();
    _rate.dispose();
    _error.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _error.clear();
      _saving = true;
    });

    if (_stage.text.trim().isEmpty || _product.text.trim().isEmpty) {
      setState(() {
        _saving = false;
        _error.set(l10n.errorRequired);
      });
      return;
    }
    final days = int.tryParse(_days.text.trim());
    if (days == null || days < 0) {
      setState(() {
        _saving = false;
        _error.set(l10n.errorNotANumber);
      });
      return;
    }

    try {
      final rate = Grams.parseKg(_rate.text);
      final repository = ref.read(applicationRepositoryProvider);
      if (widget.existing == null) {
        final existing = await repository.forCropping(widget.croppingId);
        await repository.addStep(
          croppingId: widget.croppingId,
          daysAfterPlanting: days,
          growthStage: _stage.text.trim(),
          product: _product.text.trim(),
          ratePerHectare: rate,
          sortOrder: existing.length,
        );
      } else {
        await repository.update(
          ScheduledApplicationEntity(
            id: widget.existing!.id,
            croppingId: widget.existing!.croppingId,
            daysAfterPlanting: days,
            growthStage: _stage.text.trim(),
            recommendedProduct: _product.text.trim(),
            ratePerHectare: rate,
            sortOrder: widget.existing!.sortOrder,
            state: widget.existing!.state,
            actualDate: widget.existing!.actualDate,
            actualProduct: widget.existing!.actualProduct,
            actualQuantity: widget.existing!.actualQuantity,
            cost: widget.existing!.cost,
            skipReason: widget.existing!.skipReason,
            linkedExpenseId: widget.existing!.linkedExpenseId,
          ),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on DecimalFormatException {
      setState(() {
        _saving = false;
        _error.set(l10n.errorNotANumber);
      });
    }
  }

  Future<void> _remove() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await confirm(
      context: context,
      title: l10n.scheduleRemoveStep,
      body: l10n.scheduleRemoveConfirm(widget.existing!.growthStage),
      confirmLabel: l10n.actionDelete,
      destructive: true,
    );
    if (!confirmed) return;
    // The repository takes any linked expense with it, so a cost is never
    // orphaned on the cropping with nothing to explain it (FR-021).
    await ref.read(applicationRepositoryProvider).delete(widget.existing!.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return FScaffold(
      header: FHeader.nested(
        title: Text(l10n.scheduleEditTitle),
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
          FAlert(
            icon: const Icon(FIcons.info),
            title: Text(l10n.scheduleEditNote),
          ),
          const SizedBox(height: 16),
          FTextField(
            key: const Key('schedule-stage'),
            controller: _stage,
            label: Text(l10n.templateStepStage),
            statesController: _error.states,
            error: _error.widget,
          ),
          const SizedBox(height: 16),
          FTextField(
            key: const Key('schedule-days'),
            controller: _days,
            keyboardType: TextInputType.number,
            label: Text(l10n.templateStepDays),
          ),
          const SizedBox(height: 16),
          FTextField(
            key: const Key('schedule-product'),
            controller: _product,
            label: Text(l10n.templateStepProduct),
          ),
          const SizedBox(height: 16),
          FTextField(
            key: const Key('schedule-rate'),
            controller: _rate,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            label: Text(l10n.templateStepRate),
          ),
          if (widget.existing != null) ...[
            const SizedBox(height: 24),
            FButton(
              key: const Key('remove-schedule-step'),
              style: FButtonStyle.destructive(),
              onPress: _saving ? null : _remove,
              child: ButtonLabel(l10n.scheduleRemoveStep),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
