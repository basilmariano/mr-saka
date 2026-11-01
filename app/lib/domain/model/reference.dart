/// Agronomic reference data: varieties and fertilizer templates.
///
/// research.md R9: this is published data with a provenance trail, not hardcoded
/// constants. v1 consumes bundles; the CRM through which PhilRice and the Bureau of
/// Plant Industry would author them is feature 002.
library;

import 'enums.dart';
import 'grams.dart';

class VarietyRef {
  const VarietyRef({
    required this.id,
    required this.name,
    required this.crop,
    required this.maturityDays,
    required this.source,
    required this.sourceAttribution,
    this.bundleVersion,
  });

  final String id;
  final String name;
  final Crop crop;

  /// Null is meaningful: the farmer is then asked for the expected harvest date
  /// rather than the app guessing one (spec edge case).
  final int? maturityDays;

  final ReferenceSource source;

  /// FR-026a: where the figures came from. FR-026 only reads as honest guidance if
  /// its origin is recorded.
  final String? sourceAttribution;

  final int? bundleVersion;
}

class TemplateStepRef {
  const TemplateStepRef({
    required this.daysAfterPlanting,
    this.id,
    required this.growthStage,
    required this.product,
    required this.ratePerHectare,
    required this.sortOrder,
  });

  /// The local row's id. Null for a step parsed from a published bundle that has
  /// not been written to the database yet.
  final String? id;

  final int daysAfterPlanting;
  final String growthStage;
  final String product;
  final Grams ratePerHectare;
  final int sortOrder;
}

class TemplateRef {
  const TemplateRef({
    required this.id,
    required this.crop,
    required this.plantingMethod,
    required this.steps,
    required this.source,
    required this.sourceAttribution,
    this.bundleVersion,
  });

  final String id;
  final Crop crop;
  final PlantingMethod plantingMethod;
  final List<TemplateStepRef> steps;
  final ReferenceSource source;
  final String? sourceAttribution;
  final int? bundleVersion;
}

/// An immutable, monotonically versioned set of published guidance. research.md R10.
class ReferenceBundle {
  const ReferenceBundle({
    required this.version,
    required this.publishedAt,
    required this.varieties,
    required this.templates,
    required this.isPlaceholder,
  });

  final int version;
  final DateTime publishedAt;
  final List<VarietyRef> varieties;
  final List<TemplateRef> templates;

  /// True while the bundle carries stand-in figures rather than verified agronomy.
  ///
  /// research.md R9 and task T151: placeholder agronomy must not reach a real farmer.
  /// Carrying this on the bundle means the app can refuse to present it as guidance,
  /// rather than relying on someone remembering.
  final bool isPlaceholder;
}
