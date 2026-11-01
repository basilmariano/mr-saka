import '../model/enums.dart';

/// Which croppings may share a field. FR-008, FR-008a, FR-008b.
///
/// spec Assumptions, "Field occupancy ends at harvest, but the books stay open": a
/// field is free to replant once its cropping is marked harvested, so recording sales
/// never blocks the next planting. Freeing the field is not the same as finishing the
/// cropping.
///
/// The consequence is the sharpest correctness risk in the feature: a field can hold
/// one growing cropping and one harvested-but-open cropping at the same time, which
/// is why expenses and sales attach to a cropping and never to a field (FR-031b).
abstract final class FieldOccupancyRules {
  /// FR-008: a field may hold at most one cropping in the ground, where "in the
  /// ground" means planted or growing.
  static bool canStartNewCropping(Iterable<CroppingStatus> existingStatuses) =>
      !existingStatuses.any((status) => status.occupiesField);

  /// The cropping currently occupying the field, if any — named in the refusal so the
  /// farmer is told which one is in the way (spec edge case "Field already busy").
  static T? occupyingCropping<T>(
    Iterable<T> croppings,
    CroppingStatus Function(T) statusOf,
  ) {
    for (final cropping in croppings) {
      if (statusOf(cropping).occupiesField) return cropping;
    }
    return null;
  }

  /// FR-008b: when a field has a harvested-but-open cropping, starting a new one
  /// prompts the farmer to close it — but never forces them to.
  static bool shouldPromptToClosePrevious(
    Iterable<CroppingStatus> existingStatuses,
  ) =>
      existingStatuses.any((status) => status == CroppingStatus.harvested);

  /// FR-031b: whether an expense or sale needs the farmer to pick which cropping it
  /// belongs to, because the field has more than one open cropping.
  ///
  /// The system "MUST NOT silently default to either".
  static bool requiresCroppingChoice(Iterable<CroppingStatus> existingStatuses) =>
      existingStatuses.where((status) => status.acceptsRecords).length > 1;
}
