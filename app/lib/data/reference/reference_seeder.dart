import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/model/enums.dart';
import '../../domain/model/reference.dart';
import '../local/database.dart';
import '../local/mappers.dart';
import 'bundle_loader.dart';
import 'bundle_merge.dart';

/// Writes agronomic reference data into the local database.
///
/// research.md R9: varieties and fertilizer templates are published data with a
/// provenance trail, not hardcoded constants. This is the consumption side — it
/// applies a bundle, whether that bundle came from the shipped asset on first run
/// (FR-026e) or from `GET /v1/reference-data` later (FR-026b).
///
/// FR-026c is the rule that matters: a bundle NEVER overwrites a row the farmer
/// edited. A routine data refresh that silently discarded the advice a farmer's
/// local agriculturist gave them is the failure most likely to destroy trust in the
/// recommendations.
class ReferenceSeeder {
  ReferenceSeeder(this._db, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final SakaDatabase _db;
  final Uuid _uuid;

  /// Loads the bundle shipped inside the app, if the device has nothing newer.
  ///
  /// Called at startup. Without this the variety list is empty and no cropping can
  /// generate a schedule, because there is no template to generate it from.
  Future<int?> seedIfNeeded() async {
    final account = await _db.select(_db.accountState).getSingleOrNull();
    final current = account?.referenceBundleVersion ?? 0;
    final bundle = await BundleLoader.loadSeed();
    if (bundle.version <= current) return null;
    await apply(bundle);
    return bundle.version;
  }

  /// Applies [bundle] in ONE transaction.
  ///
  /// FR-026d: completely or not at all. A half-applied fertilizer template would
  /// produce wrong bag counts, which is worse than stale ones.
  Future<void> apply(ReferenceBundle bundle) => _db.transaction(() async {
        await _applyVarieties(bundle);
        await _applyTemplates(bundle);
        await _db.update(_db.accountState).write(
              AccountStateCompanion(referenceBundleVersion: Value(bundle.version)),
            );
      });

  Future<void> _applyVarieties(ReferenceBundle bundle) async {
    final existing = await _db.select(_db.varieties).get();
    final plan = BundleMerge.plan<_Row>(
      existing: existing.map((r) => _Row(r.id, sourceFromDb(r.source))),
      sourceOf: (r) => r.source,
      keyOf: (r) => r.id,
      incoming: bundle.varieties.map(
        (v) => _Row(v.id, v.source),
      ),
    );
    final allowed = plan.toApply.map((r) => r.id).toSet();

    for (final row in plan.toRemove) {
      await (_db.delete(_db.varieties)..where((v) => v.id.equals(row.id))).go();
    }
    for (final variety in bundle.varieties.where((v) => allowed.contains(v.id))) {
      await _db.into(_db.varieties).insertOnConflictUpdate(
            VarietiesCompanion.insert(
              id: variety.id,
              name: variety.name,
              crop: cropToDb(variety.crop),
              maturityDays: Value(variety.maturityDays),
              source: sourceToDb(variety.source),
              sourceAttribution: Value(variety.sourceAttribution),
              bundleVersion: Value(bundle.version),
              updatedAt: DateTime.now().toUtc(),
            ),
          );
    }
  }

  Future<void> _applyTemplates(ReferenceBundle bundle) async {
    final existing = await _db.select(_db.fertilizerTemplates).get();
    final plan = BundleMerge.plan<_Row>(
      existing: existing.map((r) => _Row(r.id, sourceFromDb(r.source))),
      sourceOf: (r) => r.source,
      keyOf: (r) => r.id,
      incoming: bundle.templates.map((t) => _Row(t.id, t.source)),
    );
    final allowed = plan.toApply.map((r) => r.id).toSet();

    for (final row in plan.toRemove) {
      // Steps go with their template, or they would be orphaned rows that no
      // schedule can ever reach.
      await (_db.delete(_db.fertilizerTemplateSteps)
            ..where((s) => s.templateId.equals(row.id)))
          .go();
      await (_db.delete(_db.fertilizerTemplates)
            ..where((t) => t.id.equals(row.id)))
          .go();
    }

    for (final template in bundle.templates.where((t) => allowed.contains(t.id))) {
      await _db.into(_db.fertilizerTemplates).insertOnConflictUpdate(
            FertilizerTemplatesCompanion.insert(
              id: template.id,
              crop: cropToDb(template.crop),
              plantingMethod: methodToDb(template.plantingMethod),
              source: sourceToDb(template.source),
              sourceAttribution: Value(template.sourceAttribution),
              bundleVersion: Value(bundle.version),
              updatedAt: DateTime.now().toUtc(),
            ),
          );
      await (_db.delete(_db.fertilizerTemplateSteps)
            ..where((s) => s.templateId.equals(template.id)))
          .go();
      for (final step in template.steps) {
        await _db.into(_db.fertilizerTemplateSteps).insertOnConflictUpdate(
              FertilizerTemplateStepsCompanion.insert(
                id: _uuid.v4(),
                templateId: template.id,
                daysAfterPlanting: step.daysAfterPlanting,
                growthStage: step.growthStage,
                product: step.product,
                ratePerHectareGrams: step.ratePerHectare.value,
                sortOrder: step.sortOrder,
                updatedAt: DateTime.now().toUtc(),
              ),
            );
      }
    }
  }
}

/// Minimal shape the provenance merge needs.
class _Row {
  const _Row(this.id, this.source);
  final String id;
  final ReferenceSource source;
}
