import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/calc/date_calc.dart';
import '../../../domain/model/calendar_date.dart';
import '../../../domain/model/entities.dart';
import '../../../domain/model/enums.dart';
import '../../../domain/model/grams.dart';
import '../../../domain/rules/cropping_status.dart';
import '../../../domain/rules/field_occupancy.dart';
import '../database.dart';
import '../../reference/template_lookup.dart';
import '../mappers.dart';
import 'application_repository.dart';
import '../tables.dart';
import '../write_through.dart';

/// Why a cropping cannot be started on a field.
class FieldBusy implements Exception {
  const FieldBusy(this.occupyingCroppingId);
  final String occupyingCroppingId;
}

/// Croppings. FR-006 to FR-013.
class CroppingRepository {
  CroppingRepository(
    this._db, {
    ApplicationRepository? applications,
    TemplateLookup? templates,
    Uuid? uuid,
  })  : _applications = applications,
        _templates = templates,
        _uuid = uuid ?? const Uuid();

  final SakaDatabase _db;
  final Uuid _uuid;

  /// Optional so a bare repository still works for tests that do not care about
  /// schedules. When both are present, starting a cropping also generates its
  /// fertilizer schedule (FR-014).
  final ApplicationRepository? _applications;
  final TemplateLookup? _templates;

  Future<List<CroppingEntity>> forField(String fieldId) =>
      (_db.select(_db.croppings)
            ..where((c) => c.fieldId.equals(fieldId) & c.deleted.equals(false))
            ..orderBy([(c) => OrderingTerm.desc(c.plantingDate)]))
          .get()
          .then((rows) => rows.map(croppingFromRow).toList());

  Future<CroppingEntity?> byId(String id) =>
      (_db.select(_db.croppings)..where((c) => c.id.equals(id)))
          .getSingleOrNull()
          .then((row) => row == null ? null : croppingFromRow(row));

  /// Croppings still accepting records — planted, growing, or harvested.
  ///
  /// FR-031b: when this returns more than one for a field, the farmer must be asked
  /// which cropping an expense or sale belongs to.
  Future<List<CroppingEntity>> openForField(String fieldId) async {
    final all = await forField(fieldId);
    return all.where((c) => c.status.acceptsRecords).toList();
  }

  Future<List<CroppingEntity>> allOpen() => (_db.select(_db.croppings)
        ..where((c) =>
            c.deleted.equals(false) & c.status.isNotValue(StatusDb.closed.name))
        ..orderBy([(c) => OrderingTerm.desc(c.plantingDate)]))
      .get()
      .then((rows) => rows.map(croppingFromRow).toList());

  /// FR-006, FR-008, FR-009, FR-011c.
  ///
  /// Throws [FieldBusy] when a cropping is already in the ground on this field —
  /// the exception carries which one, so the refusal can name it (spec edge case
  /// "Field already busy").
  Future<CroppingEntity> start({
    required String fieldId,
    required Crop crop,
    required String varietyId,
    required int? varietyMaturityDays,
    required PlantingMethod plantingMethod,
    required GrowingSeason growingSeason,
    required CalendarDate plantingDate,
    required CalendarDate today,
    CalendarDate? expectedHarvestOverride,
  }) async {
    final existing = await forField(fieldId);
    final blocking = FieldOccupancyRules.occupyingCropping(
      existing,
      (c) => c.status,
    );
    if (blocking != null) throw FieldBusy(blocking.id);

    final derived = DateCalc.expectedHarvestDate(
      plantingDate: plantingDate,
      maturityDays: varietyMaturityDays,
    );

    final cropping = CroppingEntity(
      id: _uuid.v4(),
      fieldId: fieldId,
      crop: crop,
      varietyId: varietyId,
      plantingMethod: plantingMethod,
      growingSeason: growingSeason,
      plantingDate: plantingDate,
      expectedHarvestDate: expectedHarvestOverride ?? derived,
      expectedHarvestOverridden: expectedHarvestOverride != null,
      // FR-011c: a cropping backdated more than 10 days starts in growing.
      status: CroppingStatusRules.initialStatus(
        plantingDate: plantingDate,
        today: today,
      ),
    );
    await _write(cropping);

    // FR-014: generate the schedule from the matching template, snapshotting every
    // value. FR-025 then guarantees a later template edit cannot reach this
    // cropping — a farmer's running schedule does not shift under them.
    final templates = _templates;
    final applications = _applications;
    if (templates != null && applications != null) {
      final template = await templates.forCrop(crop, plantingMethod);
      if (template != null) {
        await applications.generate(
          croppingId: cropping.id,
          template: template,
        );
      }
    }

    return cropping;
  }

  /// FR-008b: whether starting a new cropping should prompt the farmer to close a
  /// harvested-but-open one. Never forces it.
  Future<CroppingEntity?> harvestedAwaitingClosure(String fieldId) async {
    final existing = await forField(fieldId);
    for (final cropping in existing) {
      if (cropping.status == CroppingStatus.harvested) return cropping;
    }
    return null;
  }

  /// FR-011a, FR-011b: advance planted -> growing. Evaluated on the device with no
  /// network call, so a cropping advances on time while the farmer is offline.
  ///
  /// Run on app open and by the daily reconciliation.
  Future<int> refreshStatuses(CalendarDate today) async {
    final open = await allOpen();
    var changed = 0;
    for (final cropping in open) {
      if (cropping.status != CroppingStatus.planted) continue;
      final anyDone = await _anyApplicationDone(cropping.id);
      final next = CroppingStatusRules.derive(
        current: cropping.status,
        plantingDate: cropping.plantingDate,
        today: today,
        anyApplicationDone: anyDone,
      );
      if (next != cropping.status) {
        await _write(cropping.copyWith(status: next));
        changed++;
      }
    }
    return changed;
  }

  Future<bool> _anyApplicationDone(String croppingId) async {
    final rows = await (_db.select(_db.scheduledApplications)
          ..where((a) =>
              a.croppingId.equals(croppingId) & a.state.equalsValue(AppStateDb.done))
          ..limit(1))
        .get();
    return rows.isNotEmpty;
  }

  /// FR-012: recording a harvest sets the status.
  Future<void> markHarvested(String croppingId) async {
    final cropping = await byId(croppingId);
    if (cropping == null) return;
    await _write(cropping.copyWith(status: CroppingStatus.harvested));
  }

  /// FR-012b: closing is deliberate. There is no automatic path to this method —
  /// not on harvest, not on a date, not when the remaining quantity reaches zero.
  Future<void> close(String croppingId) async {
    final cropping = await byId(croppingId);
    if (cropping == null) return;
    if (!CroppingStatusRules.canClose(cropping.status)) return;
    await _write(cropping.copyWith(status: CroppingStatus.closed));
  }

  /// FR-013: reopening restores editing.
  Future<void> reopen(String croppingId) async {
    final cropping = await byId(croppingId);
    if (cropping == null) return;
    if (!CroppingStatusRules.canReopen(cropping.status)) return;
    await _write(cropping.copyWith(status: CroppingStatus.harvested));
  }

  /// FR-034a: declared once per cropping, changeable while it is open.
  Future<void> setWeightBasis(String croppingId, WeightBasis basis) async {
    final cropping = await byId(croppingId);
    if (cropping == null) return;
    await _write(cropping.copyWith(saleWeightBasis: basis));
  }

  /// FR-034b: required before any dry sale can be recorded.
  Future<void> setDriedWeight(String croppingId, Grams driedWeight) async {
    final cropping = await byId(croppingId);
    if (cropping == null) return;
    await _write(cropping.copyWith(driedWeight: driedWeight));
  }

  /// Changing the planting date shifts the due dates of every step not yet done, and
  /// the expected harvest date unless the farmer overrode it (spec edge case).
  /// Completed steps keep their recorded actual dates.
  Future<void> changePlantingDate({
    required String croppingId,
    required CalendarDate plantingDate,
    required int? varietyMaturityDays,
  }) async {
    final cropping = await byId(croppingId);
    if (cropping == null) return;
    final expected = cropping.expectedHarvestOverridden
        ? cropping.expectedHarvestDate
        : DateCalc.expectedHarvestDate(
            plantingDate: plantingDate,
            maturityDays: varietyMaturityDays,
          );
    await _write(
      cropping.copyWith(
        plantingDate: plantingDate,
        expectedHarvestDate: expected,
      ),
    );
    // Due dates are derived from plantingDate + daysAfterPlanting at read time, so
    // pending steps shift automatically and completed ones keep their actual dates.
  }

  Future<void> _write(CroppingEntity c) => _db.writeAndQueue(
        entityType: 'cropping',
        entityId: c.id,
        operation: OutboxOpDb.upsert,
        payload: {
          'id': c.id,
          'fieldId': c.fieldId,
          'crop': c.crop.name,
          'varietyId': c.varietyId,
          'plantingMethod': c.plantingMethod.name,
          'growingSeason': c.growingSeason.name,
          'plantingDate': c.plantingDate.toIso(),
          'expectedHarvestDate': c.expectedHarvestDate?.toIso(),
          'status': c.status.name,
          'saleWeightBasis': c.saleWeightBasis?.name,
          'driedWeightGrams': c.driedWeight?.value,
        },
        write: () => _db.into(_db.croppings).insertOnConflictUpdate(
              CroppingsCompanion.insert(
                id: c.id,
                fieldId: c.fieldId,
                crop: cropToDb(c.crop),
                varietyId: c.varietyId,
                plantingMethod: methodToDb(c.plantingMethod),
                growingSeason: seasonToDb(c.growingSeason),
                plantingDate: c.plantingDate.toIso(),
                expectedHarvestDate: Value(c.expectedHarvestDate?.toIso()),
                expectedHarvestOverridden: Value(c.expectedHarvestOverridden),
                status: statusToDb(c.status),
                saleWeightBasis: Value(
                  c.saleWeightBasis == null ? null : basisToDb(c.saleWeightBasis!),
                ),
                driedWeightGrams: Value(c.driedWeight?.value),
                updatedAt: DateTime.now().toUtc(),
              ),
            ),
      );
}
