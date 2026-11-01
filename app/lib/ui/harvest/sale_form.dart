import 'package:flutter/material.dart' show showDatePicker;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../data/local/repositories/sale_repository.dart';
import '../../domain/model/calendar_date.dart';
import '../../domain/model/centavos.dart';
import '../../domain/model/decimal_text.dart';
import '../../domain/model/entities.dart';
import '../../domain/model/enums.dart';
import '../../domain/model/grams.dart';
import '../../l10n/app_localizations.dart';
import '../common/labels.dart';
import '../common/providers.dart';
import '../common/widgets/button_label.dart';
import '../common/widgets/field_error.dart';

/// Record a sale. FR-034 to FR-038b.
///
/// Before the first sale the farmer declares whether the lot is being sold wet or
/// dry (FR-034a). That is a per-CROPPING decision, not per-sale, because farmers
/// sell a whole lot one way — which is what makes remaining quantity computable at
/// all (spec Assumptions, "One weight basis per cropping").
class SaleForm extends ConsumerStatefulWidget {
  const SaleForm({required this.cropping, super.key});

  final CroppingEntity cropping;

  @override
  ConsumerState<SaleForm> createState() => _SaleFormState();
}

class _SaleFormState extends ConsumerState<SaleForm> {
  final _quantity = TextEditingController();
  final _price = TextEditingController();
  final _buyer = TextEditingController();
  final _driedWeight = TextEditingController();
  late CalendarDate _date = ref.read(todayProvider);
  late WeightBasis? _basis = widget.cropping.saleWeightBasis;
  final _error = FieldError();
  bool _saving = false;

  @override
  void dispose() {
    _quantity.dispose();
    _price.dispose();
    _buyer.dispose();
    _driedWeight.dispose();
    _error.dispose();
    super.dispose();
  }

  bool get _needsDriedWeight =>
      _basis == WeightBasis.dry && widget.cropping.driedWeight == null;

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _error.clear();
      _saving = true;
    });

    final croppings = ref.read(croppingRepositoryProvider);
    try {
      if (_basis != null && widget.cropping.saleWeightBasis != _basis) {
        await croppings.setWeightBasis(widget.cropping.id, _basis!);
      }
      // FR-034b: a dry sale cannot be recorded until the lot's dried weight is
      // known. The app asks rather than guessing a wet-to-dry conversion.
      if (_needsDriedWeight) {
        await croppings.setDriedWeight(
          widget.cropping.id,
          Grams.parseKg(_driedWeight.text),
        );
      }

      final refreshed = (await croppings.byId(widget.cropping.id))!;
      await ref.read(saleRepositoryProvider).record(
            cropping: refreshed,
            quantity: Grams.parseKg(_quantity.text),
            pricePerKg: Centavos.parse(_price.text),
            buyer: _buyer.text,
            date: _date,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on SaleRejected catch (e) {
      setState(() {
        _saving = false;
        _error.set(l10n.saleRejection(
          e.reason,
          remaining: e.remaining?.quantity.formatKg(),
        ));
      });
    } on DecimalFormatException {
      setState(() {
        _saving = false;
        _error.set(l10n.errorNotANumber);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = context.theme;

    return FScaffold(
      header: FHeader.nested(
        title: Text(l10n.saleAdd),
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
          if (widget.cropping.saleWeightBasis == null) ...[
            Text(l10n.basisQuestion, style: theme.typography.sm),
            const SizedBox(height: 4),
            Text(
              l10n.basisQuestionHelp,
              style: theme.typography.xs
                  .copyWith(color: theme.colors.mutedForeground),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FButton(
                    key: const Key('basis-wet'),
                    style: (_basis ?? WeightBasis.wet) == WeightBasis.wet
                        ? FButtonStyle.secondary()
                        : FButtonStyle.outline(),
                    onPress: () => setState(() => _basis = WeightBasis.wet),
                    child: ButtonLabel(l10n.basisSellingWet),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FButton(
                    key: const Key('basis-dry'),
                    style: _basis == WeightBasis.dry
                        ? FButtonStyle.secondary()
                        : FButtonStyle.outline(),
                    onPress: () => setState(() => _basis = WeightBasis.dry),
                    child: ButtonLabel(l10n.basisSellingDry),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
          if (_needsDriedWeight) ...[
            Text(l10n.driedWeightTitle, style: theme.typography.sm),
            const SizedBox(height: 4),
            Text(
              l10n.driedWeightBody,
              style: theme.typography.xs
                  .copyWith(color: theme.colors.mutedForeground),
            ),
            const SizedBox(height: 8),
            FTextField(
              key: const Key('sale-dried-weight'),
              controller: _driedWeight,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              label: Text(l10n.driedWeightField),
              hint: l10n.kgUnit,
            ),
            const SizedBox(height: 20),
          ],
          FTextField(
            key: const Key('sale-quantity'),
            controller: _quantity,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            label: Text(l10n.saleQuantity),
            hint: l10n.kgUnit,
            statesController: _error.states,
            error: _error.widget,
          ),
          const SizedBox(height: 16),
          FTextField(
            key: const Key('sale-price'),
            controller: _price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            label: Text(l10n.salePricePerKg),
            hint: '₱',
          ),
          const SizedBox(height: 16),
          FTextField(
            key: const Key('sale-buyer'),
            controller: _buyer,
            label: Text(l10n.saleBuyer),
          ),
          const SizedBox(height: 16),
          FTileGroup(
            children: [
              FTile(
                title: Text(l10n.saleDate),
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
        ],
      ),
    );
  }
}
