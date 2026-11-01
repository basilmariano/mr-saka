import 'package:drift/drift.dart';

import '../../domain/model/enums.dart';
import '../../domain/model/grams.dart';
import '../../domain/model/reference.dart';
import '../local/database.dart';
import '../local/mappers.dart';

/// Finds the fertilizer template for a crop and planting method. FR-014.
class TemplateLookup {
  TemplateLookup(this._db);

  final SakaDatabase _db;

  /// Returns the template a new cropping should snapshot, or null when none has
  /// been published for this combination.
  ///
  /// A missing template is not an error: a cropping starts with an empty schedule
  /// and the farmer can add steps themselves (FR-023). Refusing to start the
  /// cropping would block the core journey over missing guidance.
  Future<TemplateRef?> forCrop(Crop crop, PlantingMethod method) async {
    final row = await (_db.select(_db.fertilizerTemplates)
          ..where((t) =>
              t.crop.equalsValue(cropToDb(crop)) &
              t.plantingMethod.equalsValue(methodToDb(method)) &
              t.deleted.equals(false))
          ..limit(1))
        .getSingleOrNull();
    if (row == null) return null;

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

  /// Whether the guidance currently held is still unverified stand-in data.
  ///
  /// research.md R9 / FR-026: the app must not present placeholder figures as
  /// agronomic guidance, so the schedule screen reads this to decide what to say.
  Future<bool> isPlaceholder() async {
    final rows = await (_db.select(_db.fertilizerTemplateSteps)
          ..where((s) => s.ratePerHectareGrams.isBiggerThanValue(0))
          ..limit(1))
        .get();
    return rows.isEmpty;
  }
}
