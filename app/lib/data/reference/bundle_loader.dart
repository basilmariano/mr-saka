import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../../domain/model/enums.dart';
import '../../domain/model/grams.dart';
import '../../domain/model/reference.dart';

/// Loads a reference bundle from JSON.
///
/// FR-026e: built-in varieties and fertilizer recommendations are available to a
/// farmer using the app as a guest, with no account. research.md R10: the same shape
/// arrives from `GET /v1/reference-data`, so parsing lives here once.
abstract final class BundleLoader {
  static const String seedAssetPath = 'assets/reference/bundle-v1.json';

  /// Reads the bundle shipped inside the app, used on first run.
  static Future<ReferenceBundle> loadSeed() async =>
      parse(jsonDecode(await rootBundle.loadString(seedAssetPath)) as Map<String, Object?>);

  static ReferenceBundle parse(Map<String, Object?> json) {
    final version = json['version']! as int;
    // A bundle that does not say otherwise is treated as unverified. Defaulting to
    // true means a malformed or truncated bundle cannot quietly present itself as
    // real agronomy (research.md R9).
    final isPlaceholder = json['isPlaceholder'] as bool? ?? true;
    final source =
        isPlaceholder ? ReferenceSource.seed : ReferenceSource.published;

    final varieties = <VarietyRef>[
      for (final raw in (json['varieties']! as List).cast<Map<String, Object?>>())
        VarietyRef(
          id: raw['id']! as String,
          name: raw['name']! as String,
          crop: _crop(raw['crop']! as String),
          maturityDays: raw['maturityDays'] as int?,
          source: source,
          sourceAttribution: raw['sourceAttribution'] as String?,
          bundleVersion: version,
        ),
    ];

    final templates = <TemplateRef>[
      for (final raw in (json['templates']! as List).cast<Map<String, Object?>>())
        TemplateRef(
          id: raw['id']! as String,
          crop: _crop(raw['crop']! as String),
          plantingMethod: _method(raw['plantingMethod']! as String),
          source: source,
          sourceAttribution: raw['sourceAttribution'] as String?,
          bundleVersion: version,
          steps: [
            for (final step in (raw['steps']! as List).cast<Map<String, Object?>>())
              TemplateStepRef(
                daysAfterPlanting: step['daysAfterPlanting']! as int,
                growthStage: step['growthStage']! as String,
                product: step['product']! as String,
                ratePerHectare: Grams(step['ratePerHectareGrams']! as int),
                sortOrder: step['sortOrder']! as int,
              ),
          ],
        ),
    ];

    return ReferenceBundle(
      version: version,
      publishedAt: DateTime.parse(json['publishedAt']! as String),
      varieties: varieties,
      templates: templates,
      isPlaceholder: isPlaceholder,
    );
  }

  static Crop _crop(String value) => switch (value) {
        'rice' => Crop.rice,
        'corn' => Crop.corn,
        _ => throw FormatException('Unknown crop', value),
      };

  static PlantingMethod _method(String value) => switch (value) {
        'transplanted' => PlantingMethod.transplanted,
        'directSeeded' => PlantingMethod.directSeeded,
        _ => throw FormatException('Unknown planting method', value),
      };
}
