import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/model/enums.dart';
import '../../../domain/model/grams.dart';
import '../../../domain/model/reference.dart';
import '../database.dart';
import '../mappers.dart';
import '../tables.dart';
import '../write_through.dart';

/// Editing fertilizer templates and varieties. FR-010, FR-024, FR-026c.
///
/// THE RULE THIS EXISTS TO HONOUR: every save here marks the record
/// `ReferenceSource.farmer`. A published bundle replaces `seed` and `published`
/// rows and never touches `farmer` ones (see BundleMerge), so a routine data
/// refresh cannot discard the advice a farmer's local agriculturist gave them —
/// the failure most likely to destroy trust in the recommendations.
///
/// FR-025 is the other half: a cropping's schedule is snapshotted when it starts,
/// so editing a template here never reaches a cropping already running.
class TemplateRepository {
  TemplateRepository(this._db, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final SakaDatabase _db;
  final Uuid _uuid;

  /// Every template, so the farmer can pick which to edit.
  Future<List<TemplateRef>> all() async {
    final rows = await (_db.select(_db.fertilizerTemplates)
          ..where((t) => t.deleted.equals(false)))
        .get();
    final out = <TemplateRef>[];
    for (final row in rows) {
      out.add(await _withSteps(row));
    }
    out.sort((a, b) {
      final byCrop = a.crop.index.compareTo(b.crop.index);
      return byCrop != 0
          ? byCrop
          : a.plantingMethod.index.compareTo(b.plantingMethod.index);
    });
    return out;
  }

  Future<TemplateRef?> byId(String id) async {
    final row = await (_db.select(_db.fertilizerTemplates)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _withSteps(row);
  }

  /// Adds a step to a template. FR-024.
  Future<void> addStep({
    required String templateId,
    required int daysAfterPlanting,
    required String growthStage,
    required String product,
    required Grams ratePerHectare,
  }) async {
    final existing = await byId(templateId);
    final sortOrder = existing == null || existing.steps.isEmpty
        ? 0
        : existing.steps.map((s) => s.sortOrder).reduce((a, b) => a > b ? a : b) + 1;

    final stepId = _uuid.v4();
    await _db.writeAndQueue(
      entityType: 'fertilizerTemplateStep',
      entityId: stepId,
      operation: OutboxOpDb.upsert,
      payload: {'id': stepId, 'templateId': templateId},
      write: () => _db.into(_db.fertilizerTemplateSteps).insert(
            FertilizerTemplateStepsCompanion.insert(
              id: stepId,
              templateId: templateId,
              daysAfterPlanting: daysAfterPlanting,
              growthStage: growthStage.trim(),
              product: product.trim(),
              ratePerHectareGrams: ratePerHectare.value,
              sortOrder: sortOrder,
              updatedAt: DateTime.now().toUtc(),
            ),
          ),
    );
    await _claimForFarmer(templateId);
  }

  /// Edits a step. FR-024.
  Future<void> updateStep({
    required String templateId,
    required String stepId,
    required int daysAfterPlanting,
    required String growthStage,
    required String product,
    required Grams ratePerHectare,
  }) async {
    await _db.writeAndQueue(
      entityType: 'fertilizerTemplateStep',
      entityId: stepId,
      operation: OutboxOpDb.upsert,
      payload: {'id': stepId, 'templateId': templateId},
      write: () =>
          (_db.update(_db.fertilizerTemplateSteps)..where((s) => s.id.equals(stepId)))
              .write(
        FertilizerTemplateStepsCompanion(
          daysAfterPlanting: Value(daysAfterPlanting),
          growthStage: Value(growthStage.trim()),
          product: Value(product.trim()),
          ratePerHectareGrams: Value(ratePerHectare.value),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      ),
    );
    await _claimForFarmer(templateId);
  }

  /// Removes a step. FR-024.
  Future<void> removeStep({
    required String templateId,
    required String stepId,
  }) async {
    await _db.writeAndQueue(
      entityType: 'fertilizerTemplateStep',
      entityId: stepId,
      operation: OutboxOpDb.delete,
      payload: {'id': stepId, 'templateId': templateId},
      write: () =>
          (_db.update(_db.fertilizerTemplateSteps)..where((s) => s.id.equals(stepId)))
              .write(const FertilizerTemplateStepsCompanion(deleted: Value(true))),
    );
    await _claimForFarmer(templateId);
  }

  /// Reorders steps. FR-024.
  ///
  /// Sort order is stored rather than derived from timing, because a farmer may
  /// want two steps on the same day listed in a particular order.
  Future<void> reorderSteps({
    required String templateId,
    required List<String> stepIdsInOrder,
  }) async {
    await _db.transaction(() async {
      for (var i = 0; i < stepIdsInOrder.length; i++) {
        await (_db.update(_db.fertilizerTemplateSteps)
              ..where((s) => s.id.equals(stepIdsInOrder[i])))
            .write(
          FertilizerTemplateStepsCompanion(
            sortOrder: Value(i),
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
      }
    });
    await _claimForFarmer(templateId);
  }

  /// FR-010: a custom variety with its own maturity in days.
  ///
  /// Marked `farmer` so an app update that ships a new variety list leaves it be.
  Future<String> createVariety({
    required String name,
    required Crop crop,
    required int? maturityDays,
  }) async {
    final id = _uuid.v4();
    await _db.writeAndQueue(
      entityType: 'variety',
      entityId: id,
      operation: OutboxOpDb.upsert,
      payload: {
        'id': id,
        'name': name.trim(),
        'crop': crop.name,
        'maturityDays': maturityDays,
        'source': ReferenceSource.farmer.name,
      },
      write: () => _db.into(_db.varieties).insert(
            VarietiesCompanion.insert(
              id: id,
              name: name.trim(),
              crop: cropToDb(crop),
              maturityDays: Value(maturityDays),
              source: SourceDb.farmer,
              updatedAt: DateTime.now().toUtc(),
            ),
          ),
    );
    return id;
  }

  /// Marks a template as the farmer's own.
  ///
  /// FR-026c: this is what protects the edit from the next published bundle. It
  /// runs on every mutation rather than only the first, so a template can never
  /// end up edited but still flagged as published.
  Future<void> _claimForFarmer(String templateId) =>
      (_db.update(_db.fertilizerTemplates)..where((t) => t.id.equals(templateId)))
          .write(
        FertilizerTemplatesCompanion(
          source: const Value(SourceDb.farmer),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );

  Future<TemplateRef> _withSteps(FertilizerTemplate row) async {
    final steps = await (_db.select(_db.fertilizerTemplateSteps)
          ..where((s) => s.templateId.equals(row.id) & s.deleted.equals(false))
          ..orderBy([(s) => OrderingTerm.asc(s.sortOrder)]))
        .get();
    return TemplateRef(
      id: row.id,
      crop: cropFromDb(row.crop),
      plantingMethod: methodFromDb(row.plantingMethod),
      source: sourceFromDb(row.source),
      sourceAttribution: row.sourceAttribution,
      bundleVersion: row.bundleVersion,
      steps: [
        for (final step in steps)
          TemplateStepRef(
            id: step.id,
            daysAfterPlanting: step.daysAfterPlanting,
            growthStage: step.growthStage,
            product: step.product,
            ratePerHectare: Grams(step.ratePerHectareGrams),
            sortOrder: step.sortOrder,
          ),
      ],
    );
  }
}
