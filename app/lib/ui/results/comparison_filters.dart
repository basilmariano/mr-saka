import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../data/local/repositories/comparison_repository.dart';
import '../../domain/model/enums.dart';
import '../../l10n/app_localizations.dart';
import '../common/labels.dart';
import '../common/providers.dart';

/// Filters for field, crop, and season. FR-043.
///
/// Each is a single row of chips rather than a dropdown: the farmer is comparing
/// a handful of fields and two seasons, and a tap is faster than a picker.
class ComparisonFilters extends ConsumerWidget {
  const ComparisonFilters({required this.rows, super.key});

  final List<ComparisonRow> rows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final filter = ref.watch(comparisonFilterProvider);
    final fields = ComparisonRepository.fieldsIn(rows);

    void update(ComparisonFilter next) =>
        ref.read(comparisonFilterProvider.notifier).state = next;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (fields.length > 1)
          _ChipRow(
            allLabel: l10n.compareAllFields,
            allSelected: filter.fieldId == null,
            onAll: () => update(filter.copyWith(fieldId: null)),
            options: [
              for (final field in fields)
                (
                  key: 'filter-field-${field.id}',
                  label: field.name,
                  selected: filter.fieldId == field.id,
                  onSelect: () => update(filter.copyWith(fieldId: field.id)),
                ),
            ],
          ),
        _ChipRow(
          allLabel: l10n.compareAllCrops,
          allSelected: filter.crop == null,
          onAll: () => update(filter.copyWith(crop: null)),
          options: [
            for (final crop in Crop.values)
              (
                key: 'filter-crop-${crop.name}',
                label: l10n.crop(crop),
                selected: filter.crop == crop,
                onSelect: () => update(filter.copyWith(crop: crop)),
              ),
          ],
        ),
        _ChipRow(
          allLabel: l10n.compareAllSeasons,
          allSelected: filter.growingSeason == null,
          onAll: () => update(filter.copyWith(growingSeason: null)),
          options: [
            for (final season in GrowingSeason.values)
              (
                key: 'filter-season-${season.name}',
                label: l10n.growingSeason(season),
                selected: filter.growingSeason == season,
                onSelect: () =>
                    update(filter.copyWith(growingSeason: season)),
              ),
          ],
        ),
      ],
    );
  }
}

typedef _Option = ({
  String key,
  String label,
  bool selected,
  VoidCallback onSelect,
});

class _ChipRow extends StatelessWidget {
  const _ChipRow({
    required this.allLabel,
    required this.allSelected,
    required this.onAll,
    required this.options,
  });

  final String allLabel;
  final bool allSelected;
  final VoidCallback onAll;
  final List<_Option> options;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SingleChildScrollView(
          // Horizontal scroll rather than wrapping: a farmer with several fields
          // would otherwise push the actual comparison off the screen.
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _Chip(
                chipKey: 'filter-all-$allLabel',
                label: allLabel,
                selected: allSelected,
                onSelect: onAll,
              ),
              for (final option in options) ...[
                const SizedBox(width: 8),
                _Chip(
                  chipKey: option.key,
                  label: option.label,
                  selected: option.selected,
                  onSelect: option.onSelect,
                ),
              ],
            ],
          ),
        ),
      );
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.chipKey,
    required this.label,
    required this.selected,
    required this.onSelect,
  });

  final String chipKey;
  final String label;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return GestureDetector(
      key: ValueKey(chipKey),
      onTap: onSelect,
      behavior: HitTestBehavior.opaque,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? theme.colors.primary : theme.colors.muted,
          borderRadius: theme.style.borderRadius,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.typography.sm.copyWith(
              color: selected
                  ? theme.colors.primaryForeground
                  : theme.colors.mutedForeground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
