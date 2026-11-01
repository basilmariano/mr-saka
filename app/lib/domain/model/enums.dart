/// Domain enumerations.
///
/// FR-057: behaviour must never branch on display text. Every value here is
/// identified by its constant, and the farmer-facing label is a separate localised
/// resource (FR-056) — which is what makes the phase-2 local-language work possible
/// without touching logic.
library;

enum Crop {
  rice,
  corn;

  /// FR-007: rice offers both planting methods; corn offers direct-seeded only
  /// (spec Assumptions, "Corn planting method").
  List<PlantingMethod> get plantingMethods => switch (this) {
        Crop.rice => const [PlantingMethod.transplanted, PlantingMethod.directSeeded],
        Crop.corn => const [PlantingMethod.directSeeded],
      };
}

enum PlantingMethod { transplanted, directSeeded }

/// When a cropping was planted. FR-006.
///
/// Deliberately distinct from [WeightBasis], which is also "wet or dry" but means
/// something entirely different. spec Assumptions: "Season has two meanings, kept
/// distinct." A dry-season cropping can be sold wet.
enum GrowingSeason { wet, dry }

/// How a cropping's produce was sold. FR-034a.
///
/// See the warning on [GrowingSeason]. These two are never stored in, or read from,
/// the same field.
enum WeightBasis { wet, dry }

/// FR-011. Advances in declaration order; see domain/rules/cropping_status.dart.
enum CroppingStatus {
  planted,
  growing,
  harvested,
  closed;

  /// FR-008: a cropping occupies its field from planting until it is marked
  /// harvested. FR-008a lets a harvested-but-open cropping share the field with a
  /// newly planted one.
  bool get occupiesField =>
      this == CroppingStatus.planted || this == CroppingStatus.growing;

  /// FR-012a: being harvested frees the field; it does not close the books.
  bool get acceptsRecords => this != CroppingStatus.closed;
}

enum ApplicationState { pending, done, skipped }

/// FR-028, verbatim. Post-harvest costs reuse these ten; no eleventh is introduced
/// (spec Assumptions, "Post-harvest costs use the existing categories").
enum ExpenseCategory {
  landPreparation,
  seeds,
  fertilizer,
  pesticideHerbicide,
  labor,
  irrigation,
  equipmentRental,
  harvestingThreshing,
  hauling,
  other,
}

/// Where a variety or fertilizer template came from. research.md R9.
///
/// The whole point: a published bundle update replaces [seed] and [published] rows
/// and never touches [farmer] ones, so a routine data refresh cannot discard the
/// advice a farmer's local agriculturist gave them (FR-026c).
enum ReferenceSource { seed, published, farmer }

/// FR-042, FR-042a, FR-042b.
enum ResultState {
  /// Before harvest: expenses to date, never presented as a loss.
  inProgress,

  /// Harvested but open: recalculates as post-harvest costs and sales land.
  provisional,

  /// Closed: the farmer has declared no further costs or sales are expected.
  isFinal,
}
