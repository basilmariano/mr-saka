import 'package:flutter/material.dart' show showDatePicker;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../domain/model/calendar_date.dart';
import '../../domain/model/decimal_text.dart';
import '../../domain/model/grams.dart';
import '../../l10n/app_localizations.dart';
import '../common/labels.dart';
import '../common/providers.dart';
import '../common/widgets/button_label.dart';
import '../common/widgets/field_error.dart';

/// Record the harvest. FR-032, FR-032a, FR-033.
///
/// Weight is ALWAYS fresh weight, straight from the field. That is what keeps yield
/// and cost per kilogram comparable across every cropping (FR-043).
class HarvestForm extends ConsumerStatefulWidget {
  const HarvestForm({required this.croppingId, super.key});

  final String croppingId;

  @override
  ConsumerState<HarvestForm> createState() => _HarvestFormState();
}

class _HarvestFormState extends ConsumerState<HarvestForm> {
  bool _bySacks = true;
  final _sacks = TextEditingController();
  final _avgPerSack = TextEditingController(text: '50');
  final _totalKg = TextEditingController();
  late CalendarDate _date = ref.read(todayProvider);
  final _error = FieldError();
  bool _saving = false;

  @override
  void dispose() {
    _sacks.dispose();
    _avgPerSack.dispose();
    _totalKg.dispose();
    _error.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    setState(_error.clear);
    try {
      setState(() => _saving = true);
      final harvests = ref.read(harvestRepositoryProvider);
      if (_bySacks) {
        final sacks = int.tryParse(_sacks.text.trim());
        if (sacks == null) throw const DecimalFormatException('', 'not a number');
        await harvests.record(
          croppingId: widget.croppingId,
          date: _date,
          sacks: sacks,
          avgWetPerSack: Grams.parseKg(_avgPerSack.text),
        );
      } else {
        await harvests.record(
          croppingId: widget.croppingId,
          date: _date,
          totalWet: Grams.parseKg(_totalKg.text),
        );
      }
      // FR-012: recording a harvest sets the status. It frees the field but does
      // NOT close the books — post-harvest costs and sales keep landing here.
      await ref.read(croppingRepositoryProvider).markHarvested(widget.croppingId);
      if (mounted) Navigator.of(context).pop(true);
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

    return FScaffold(
      header: FHeader.nested(
        title: Text(l10n.harvestRecord),
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
            title: Text(l10n.harvestFreshWeightNote),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FButton(
                  key: const Key('harvest-by-sacks'),
                  style: _bySacks
                      ? FButtonStyle.secondary()
                      : FButtonStyle.outline(),
                  onPress: () => setState(() => _bySacks = true),
                  child: ButtonLabel(l10n.harvestBySacks),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FButton(
                  style: _bySacks
                      ? FButtonStyle.outline()
                      : FButtonStyle.secondary(),
                  onPress: () => setState(() => _bySacks = false),
                  child: ButtonLabel(l10n.harvestByTotal),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_bySacks) ...[
            FTextField(
              key: const Key('harvest-sacks'),
              controller: _sacks,
              autofocus: true,
              keyboardType: TextInputType.number,
              label: Text(l10n.harvestSacks),
              statesController: _error.states,
              error: _error.widget,
            ),
            const SizedBox(height: 16),
            FTextField(
              key: const Key('harvest-avg-per-sack'),
              controller: _avgPerSack,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              label: Text(l10n.harvestAvgPerSack),
              hint: l10n.kgUnit,
            ),
          ] else
            FTextField(
              key: const Key('harvest-total-kg'),
              controller: _totalKg,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              label: Text(l10n.harvestTotalKg),
              hint: l10n.kgUnit,
              statesController: _error.states,
              error: _error.widget,
            ),
          const SizedBox(height: 16),
          FTileGroup(
            children: [
              FTile(
                title: Text(l10n.harvestDate),
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
