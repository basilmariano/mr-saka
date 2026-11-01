import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart' show MaterialPageRoute, showDatePicker;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../data/local/mappers.dart';
import '../../data/local/repositories/cropping_repository.dart';
import '../../domain/calc/date_calc.dart';
import '../../domain/model/calendar_date.dart';
import '../../domain/model/enums.dart';
import '../../l10n/app_localizations.dart';
import '../common/labels.dart';
import '../common/providers.dart';
import '../common/widgets/button_label.dart';
import '../common/widgets/confirm.dart';
import 'variety_form.dart';

/// Variety choices for the selected crop.
final _varietiesProvider =
    FutureProvider.family<List<({String id, String name, int? maturityDays})>, Crop>(
        (ref, crop) async {
  final db = ref.watch(databaseProvider);
  final rows = await (db.select(db.varieties)
        ..where((v) =>
            v.crop.equalsValue(cropToDb(crop)) & v.deleted.equals(false)))
      .get();
  return rows
      .map((r) => (id: r.id, name: r.name, maturityDays: r.maturityDays))
      .toList();
});

/// Start a cropping. FR-006 to FR-009, FR-011c.
class StartCroppingScreen extends ConsumerStatefulWidget {
  const StartCroppingScreen({required this.fieldId, super.key});

  final String fieldId;

  @override
  ConsumerState<StartCroppingScreen> createState() => _StartCroppingState();
}

class _StartCroppingState extends ConsumerState<StartCroppingScreen> {
  Crop _crop = Crop.rice;
  PlantingMethod _method = PlantingMethod.transplanted;
  GrowingSeason _season = GrowingSeason.wet;
  String? _varietyId;
  int? _maturityDays;
  late CalendarDate _plantingDate = ref.read(todayProvider);
  CalendarDate? _expectedOverride;
  bool _saving = false;

  /// FR-009: derived from the variety. Null when the variety has no maturity, in
  /// which case the farmer must enter it (spec edge case).
  CalendarDate? get _derivedHarvest => DateCalc.expectedHarvestDate(
        plantingDate: _plantingDate,
        maturityDays: _maturityDays,
      );

  Future<void> _pickDate({
    required CalendarDate initial,
    required ValueChanged<CalendarDate> onPicked,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.toDateTime(),
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (picked != null) onPicked(CalendarDate.fromDateTime(picked));
  }

  Future<void> _start() async {
    final l10n = AppLocalizations.of(context);
    if (_varietyId == null) return;
    setState(() => _saving = true);

    final croppings = ref.read(croppingRepositoryProvider);
    try {
      await croppings.start(
        fieldId: widget.fieldId,
        crop: _crop,
        varietyId: _varietyId!,
        varietyMaturityDays: _maturityDays,
        plantingMethod: _method,
        growingSeason: _season,
        plantingDate: _plantingDate,
        today: ref.read(todayProvider),
        expectedHarvestOverride: _expectedOverride,
      );
    } on FieldBusy catch (e) {
      // spec edge case "Field already busy": name the cropping in the way.
      if (!mounted) return;
      setState(() => _saving = false);
      final blocking = await croppings.byId(e.occupyingCroppingId);
      if (!mounted || blocking == null) return;
      await confirm(
        context: context,
        title: l10n.fieldBusyTitle,
        body: l10n.fieldBusyBody(
          l10n.crop(blocking.crop),
          l10n.formatDate(blocking.plantingDate),
        ),
        confirmLabel: l10n.actionCancel,
      );
      return;
    }

    // FR-008b: prompt to close a harvested-but-open cropping — never force it.
    final awaiting = await croppings.harvestedAwaitingClosure(widget.fieldId);
    if (mounted && awaiting != null) {
      final close = await confirm(
        context: context,
        title: l10n.closePreviousTitle,
        body: l10n.closePreviousBody(
          l10n.crop(awaiting.crop),
          l10n.formatDate(awaiting.plantingDate),
        ),
        confirmLabel: l10n.closePreviousClose,
        // FR-008b: declining must read as "leave the previous cropping open",
        // not as cancelling the cropping the farmer is starting.
        cancelLabel: l10n.closePreviousLeaveOpen,
      );
      if (close) await croppings.close(awaiting.id);
    }

    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = context.theme;
    final varieties = ref.watch(_varietiesProvider(_crop));
    final expected = _expectedOverride ?? _derivedHarvest;

    Widget choices<T>({
      required String label,
      required List<T> options,
      required T selected,
      required String Function(T) describe,
      required ValueChanged<T> onSelect,
    }) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.typography.sm),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final option in options) ...[
                  Expanded(
                    child: FButton(
                      key: ValueKey('option-${describe(option)}'),
                      style: option == selected
                          ? FButtonStyle.secondary()
                          : FButtonStyle.outline(),
                      onPress: () => onSelect(option),
                      child: ButtonLabel(describe(option)),
                    ),
                  ),
                  if (option != options.last) const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 20),
          ],
        );

    return FScaffold(
      header: FHeader.nested(
        title: Text(l10n.croppingStart),
        prefixes: [FHeaderAction.back(onPress: () => Navigator.of(context).pop())],
      ),
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FButton(
          key: const Key('start-cropping-button'),
          onPress: (_saving || _varietyId == null) ? null : _start,
          child: ButtonLabel(l10n.croppingStart),
        ),
      ),
      child: ListView(
        children: [
          choices<Crop>(
            label: l10n.croppingCrop,
            options: Crop.values,
            selected: _crop,
            describe: l10n.crop,
            onSelect: (crop) => setState(() {
              _crop = crop;
              // FR-007: rice offers both methods; corn offers direct-seeded only.
              _method = crop.plantingMethods.first;
              _varietyId = null;
              _maturityDays = null;
            }),
          ),
          choices<PlantingMethod>(
            label: l10n.croppingMethod,
            options: _crop.plantingMethods,
            selected: _method,
            describe: l10n.plantingMethod,
            onSelect: (method) => setState(() => _method = method),
          ),
          Row(
            children: [
              Expanded(
                child: Text(l10n.croppingVariety, style: theme.typography.sm),
              ),
              GestureDetector(
                key: const Key('add-variety'),
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  // FR-010: a farmer planting a local variety the bundle has
                  // never heard of should not be stuck.
                  final id = await Navigator.of(context).push<String>(
                    MaterialPageRoute<String>(
                      builder: (_) => VarietyForm(crop: _crop),
                    ),
                  );
                  if (id == null) return;
                  ref.invalidate(_varietiesProvider(_crop));
                  setState(() {
                    _varietyId = id;
                    _maturityDays = null;
                    _expectedOverride = null;
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    l10n.varietyAdd,
                    style: theme.typography.sm
                        .copyWith(color: theme.colors.primary),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          varieties.when(
            loading: () => const FCircularProgress(),
            error: (error, _) => Text('$error'),
            data: (list) => FSelect<String>(
              key: const Key('variety-select'),
              items: {for (final v in list) v.name: v.id},
              initialValue: _varietyId,
              onChange: (id) => setState(() {
                _varietyId = id;
                _maturityDays =
                    list.firstWhere((v) => v.id == id).maturityDays;
                _expectedOverride = null;
              }),
            ),
          ),
          const SizedBox(height: 20),
          choices<GrowingSeason>(
            label: l10n.croppingSeason,
            options: GrowingSeason.values,
            selected: _season,
            describe: l10n.growingSeason,
            onSelect: (season) => setState(() => _season = season),
          ),
          FTileGroup(
            children: [
              FTile(
                title: Text(l10n.croppingPlantingDate),
                subtitle: Text(l10n.formatDate(_plantingDate)),
                suffix: const Icon(FIcons.calendar),
                onPress: () => _pickDate(
                  initial: _plantingDate,
                  onPicked: (date) => setState(() => _plantingDate = date),
                ),
              ),
              FTile(
                title: Text(l10n.croppingExpectedHarvest),
                subtitle: Text(
                  expected == null
                      ? l10n.croppingExpectedHarvestHelp
                      : l10n.formatDate(expected),
                ),
                suffix: const Icon(FIcons.calendar),
                onPress: () => _pickDate(
                  initial: expected ?? _plantingDate.addDays(110),
                  onPicked: (date) => setState(() => _expectedOverride = date),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
