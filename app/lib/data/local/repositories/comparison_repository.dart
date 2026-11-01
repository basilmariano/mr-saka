import 'package:drift/drift.dart';

import '../../../domain/model/calendar_date.dart';
import '../../../domain/model/centavos.dart';
import '../../../domain/model/enums.dart';
import '../database.dart';
import '../mappers.dart';
import 'cropping_repository.dart';
import 'field_repository.dart';
import 'result_repository.dart';

/// One cropping's line in the comparison. FR-043.
class ComparisonRow {
  const ComparisonRow({
    required this.croppingId,
    required this.fieldId,
    required this.fieldName,
    required this.crop,
    required this.varietyName,
    required this.growingSeason,
    required this.plantingMethod,
    required this.plantingDate,
    required this.result,
  });

  final String croppingId;
  final String fieldId;
  final String fieldName;
  final Crop crop;
  final String varietyName;
  final GrowingSeason growingSeason;
  final PlantingMethod plantingMethod;
  final CalendarDate plantingDate;
  final CroppingResult result;

  Centavos get netProfit => result.netProfit;
}

/// What the farmer can narrow the comparison to. FR-043.
class ComparisonFilter {
  const ComparisonFilter({this.fieldId, this.crop, this.growingSeason});

  final String? fieldId;
  final Crop? crop;
  final GrowingSeason? growingSeason;

  bool get isEmpty => fieldId == null && crop == null && growingSeason == null;

  ComparisonFilter copyWith({
    Object? fieldId = _unset,
    Object? crop = _unset,
    Object? growingSeason = _unset,
  }) =>
      ComparisonFilter(
        fieldId: fieldId == _unset ? this.fieldId : fieldId as String?,
        crop: crop == _unset ? this.crop : crop as Crop?,
        growingSeason: growingSeason == _unset
            ? this.growingSeason
            : growingSeason as GrowingSeason?,
      );

  static const Object _unset = Object();

  bool matches(ComparisonRow row) =>
      (fieldId == null || row.fieldId == fieldId) &&
      (crop == null || row.crop == crop) &&
      (growingSeason == null || row.growingSeason == growingSeason);
}

/// Comparing croppings across seasons and fields. FR-043.
///
/// Computed entirely from the local database (T110), so the comparison works
/// offline. The device already holds the farmer's whole history, so there is
/// nothing to fetch and nothing to pay for (research.md R7).
///
/// Every row's yield and cost per kilogram sit on the same fresh-weight basis,
/// because the harvest is always recorded wet (FR-032a). That is what makes these
/// numbers comparable at all — the whole reason US4 can exist.
class ComparisonRepository {
  ComparisonRepository({
    required SakaDatabase database,
    required this.croppings,
    required this.fields,
    required this.results,
  }) : _db = database;

  final SakaDatabase _db;
  final CroppingRepository croppings;
  final FieldRepository fields;
  final ResultRepository results;

  /// Every cropping the farmer has, newest first.
  ///
  /// Includes croppings still in progress. Their results are marked in progress or
  /// provisional (FR-042, FR-042a), and showing them lets a farmer compare a
  /// running season against finished ones — which is exactly when the comparison
  /// is most useful.
  Future<List<ComparisonRow>> load() async {
    final rows = await (_db.select(_db.croppings)
          ..where((c) => c.deleted.equals(false))
          ..orderBy([(c) => OrderingTerm.desc(c.plantingDate)]))
        .get();

    final varietyNames = {
      for (final variety in await _db.select(_db.varieties).get())
        variety.id: variety.name,
    };

    final out = <ComparisonRow>[];
    for (final row in rows) {
      final cropping = croppingFromRow(row);
      final field = await fields.byId(cropping.fieldId);
      if (field == null) continue;

      out.add(
        ComparisonRow(
          croppingId: cropping.id,
          fieldId: field.id,
          fieldName: field.name,
          crop: cropping.crop,
          varietyName: varietyNames[cropping.varietyId] ?? '',
          growingSeason: cropping.growingSeason,
          plantingMethod: cropping.plantingMethod,
          plantingDate: cropping.plantingDate,
          result: await results.forCropping(
            cropping: cropping,
            area: field.area,
          ),
        ),
      );
    }
    return out;
  }

  /// The fields that appear in [rows], for the filter chips.
  static List<({String id, String name})> fieldsIn(List<ComparisonRow> rows) {
    final seen = <String, String>{};
    for (final row in rows) {
      seen[row.fieldId] = row.fieldName;
    }
    return [
      for (final entry in seen.entries) (id: entry.key, name: entry.value),
    ]..sort((a, b) => a.name.compareTo(b.name));
  }
}
